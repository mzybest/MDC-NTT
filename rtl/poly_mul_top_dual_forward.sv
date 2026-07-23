// Experimental asymmetric dual-forward polynomial multiplier.
//
// CoreA and the NTT-only CoreB transform A/B concurrently. Their lockstep
// outputs feed the existing two-lane Pointwise multipliers directly, removing
// the A_NTT cache. CoreA is then reused for C_INTT.
module poly_mul_top_dual_forward #(
    parameter int N = 4096,
    parameter int LOGN = 12,
    parameter int QW = 64,
    parameter int MUL_LAT = params_pkg::MUL_LAT,
    parameter bit USE_WL_MONT = 1'b1,
    parameter bit USE_WL_CORE = USE_WL_MONT,
    parameter bit USE_WL_PRE_NTT = USE_WL_MONT,
    parameter bit USE_WL_POINTWISE = USE_WL_MONT,
    parameter bit USE_WL_POST_INTT = USE_WL_MONT,
    parameter bit USE_STAGE_LOCAL_TWIDDLE = 1'b1,
    parameter int TWIDDLE_BRAM_STAGES = 4
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             start,
    input  logic             load_we,
    input  logic             load_sel,
    input  logic [LOGN-1:0]  load_addr,
    input  logic [QW-1:0]    load_data,
    input  logic [LOGN-1:0]  result_addr,
    output logic [QW-1:0]    result_data,
    output logic             busy,
    output logic             done
);
  import params_pkg::*;

  localparam int OLD_MONT_LAT = 12;
  localparam int WL_MONT_LAT = 14;
  localparam int POINTWISE_MUL_LAT =
      USE_WL_POINTWISE ? WL_MONT_LAT : OLD_MONT_LAT;
  localparam int POST_MUL_LAT =
      USE_WL_POST_INTT ? WL_MONT_LAT : OLD_MONT_LAT;

  typedef enum logic [2:0] {
    IDLE,
    FEED_FORWARD,
    WAIT_POINTWISE,
    FEED_INTT_C,
    WAIT_INTT_C,
    DONE
  } ctrl_state_t;
  ctrl_state_t state;

  logic [QW-1:0] a_bank0 [0:N/2-1];
  logic [QW-1:0] a_bank1 [0:N/2-1];
  logic [QW-1:0] b_bank0 [0:N/2-1];
  logic [QW-1:0] b_bank1 [0:N/2-1];
  logic [QW-1:0] c_ntt_even [0:N/2-1];
  logic [QW-1:0] c_ntt_odd  [0:N/2-1];
  logic [QW-1:0] result_bank0 [0:N/2-1];
  logic [QW-1:0] result_bank1 [0:N/2-1];

  logic [LOGN-2:0] feed_count;
  logic [LOGN-2:0] forward_recv_count;
  logic [LOGN-2:0] mul_count;
  logic [LOGN-2:0] post_recv_count;
  logic [LOGN-2:0] post_count;
  logic forward_started;

  logic pre_issue_valid;
  logic [LOGN-1:0] pre_index0, pre_index1;
  logic [QW-1:0] psi_fwd0, psi_fwd1;
  logic pre_a_valid0, pre_a_valid1, pre_b_valid0, pre_b_valid1;
  logic pre_pair_valid;
  logic [QW-1:0] pre_a_out0, pre_a_out1, pre_b_out0, pre_b_out1;

  logic core_a_start, core_a_in_valid, core_a_in_ready;
  logic [1:0] core_a_mode;
  logic [QW-1:0] core_a_in0, core_a_in1;
  logic core_a_out_valid, core_a_done;
  logic [QW-1:0] core_a_out0, core_a_out1;

  logic core_b_start, core_b_in_ready;
  logic core_b_out_valid, core_b_done;
  logic [QW-1:0] core_b_out0, core_b_out1;

  logic forward_pair_valid;
  logic mul_valid0, mul_valid1, mul_addr_valid;
  logic [QW-1:0] mul_out0, mul_out1;
  logic [LOGN-2:0] mul_addr;

  logic [LOGN-1:0] intt_addr0, intt_addr1;
  logic intt_pair_valid;
  logic [LOGN-1:0] post_addr0, post_addr1;
  logic [QW-1:0] psi_inv0, psi_inv1;
  logic post_valid0, post_valid1, post_addr_valid;
  logic [QW-1:0] post_out0, post_out1;
  logic [2*LOGN-1:0] delayed_post_addrs;

  function automatic logic [LOGN-1:0] bit_reverse(input logic [LOGN-1:0] v);
    integer i;
    for (i = 0; i < LOGN; i = i + 1)
      bit_reverse[i] = v[LOGN-1-i];
  endfunction

  always_ff @(posedge clk) begin
    if (load_we && state == IDLE) begin
      if (load_sel) begin
        if (load_addr[LOGN-1])
          b_bank1[load_addr[LOGN-2:0]] <= load_data;
        else
          b_bank0[load_addr[LOGN-2:0]] <= load_data;
      end else begin
        if (load_addr[LOGN-1])
          a_bank1[load_addr[LOGN-2:0]] <= load_data;
        else
          a_bank0[load_addr[LOGN-2:0]] <= load_data;
      end
    end
  end

  always_comb begin
    if (result_addr[LOGN-1])
      result_data = result_bank1[result_addr[LOGN-2:0]];
    else
      result_data = result_bank0[result_addr[LOGN-2:0]];
  end

  always_comb begin
    pre_issue_valid = (state == FEED_FORWARD);
    pre_index0 = {1'b0, feed_count};
    pre_index1 = {1'b1, feed_count};
  end

  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_fwd0 (
      .table_sel(PSI_FWD), .index(pre_index0), .factor(psi_fwd0)
  );
  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_fwd1 (
      .table_sel(PSI_FWD), .index(pre_index1), .factor(psi_fwd1)
  );

  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_pre_a_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
      .a(a_bank0[feed_count]), .b(psi_fwd0),
      .out_valid(pre_a_valid0), .y(pre_a_out0)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_pre_a_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
      .a(a_bank1[feed_count]), .b(psi_fwd1),
      .out_valid(pre_a_valid1), .y(pre_a_out1)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_pre_b_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
      .a(b_bank0[feed_count]), .b(psi_fwd0),
      .out_valid(pre_b_valid0), .y(pre_b_out0)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_pre_b_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
      .a(b_bank1[feed_count]), .b(psi_fwd1),
      .out_valid(pre_b_valid1), .y(pre_b_out1)
  );

  always_comb begin
    pre_pair_valid = pre_a_valid0 & pre_a_valid1 & pre_b_valid0 & pre_b_valid1;

    core_a_start = pre_pair_valid & !forward_started;
    core_a_in_valid = pre_pair_valid;
    core_a_mode = MODE_NTT;
    core_a_in0 = pre_a_out0;
    core_a_in1 = pre_a_out1;
    intt_addr0 = '0;
    intt_addr1 = '0;

    if (state == FEED_INTT_C) begin
      intt_addr0 = bit_reverse({1'b0, feed_count});
      intt_addr1 = bit_reverse({1'b1, feed_count});
      core_a_start = (feed_count == '0);
      core_a_in_valid = 1'b1;
      core_a_mode = MODE_INTT;
      core_a_in0 = c_ntt_even[intt_addr0[LOGN-1:1]];
      core_a_in1 = c_ntt_odd[intt_addr1[LOGN-1:1]];
    end

    core_b_start = pre_pair_valid & !forward_started;
  end

  gs_mdc_core #(
      .N(N), .LOGN(LOGN), .QW(QW), .MUL_LAT(MUL_LAT),
      .USE_WL_MONT(USE_WL_CORE),
      .USE_STAGE_LOCAL_TWIDDLE(USE_STAGE_LOCAL_TWIDDLE),
      .TWIDDLE_BRAM_STAGES(TWIDDLE_BRAM_STAGES)
  ) u_core_a (
      .clk(clk), .rst_n(rst_n), .start(core_a_start), .mode(core_a_mode),
      .in_valid(core_a_in_valid), .in_ready(core_a_in_ready),
      .in0(core_a_in0), .in1(core_a_in1),
      .out_valid(core_a_out_valid), .out_ready(1'b1),
      .out0(core_a_out0), .out1(core_a_out1), .done(core_a_done)
  );

  gs_mdc_core_ntt_only #(
      .N(N), .LOGN(LOGN), .QW(QW), .MUL_LAT(MUL_LAT),
      .USE_WL_MONT(USE_WL_CORE),
      .TWIDDLE_BRAM_STAGES(TWIDDLE_BRAM_STAGES)
  ) u_core_b (
      .clk(clk), .rst_n(rst_n), .start(core_b_start),
      .in_valid(pre_pair_valid), .in_ready(core_b_in_ready),
      .in0(pre_b_out0), .in1(pre_b_out1),
      .out_valid(core_b_out_valid), .out_ready(1'b1),
      .out0(core_b_out0), .out1(core_b_out1), .done(core_b_done)
  );

  always_comb begin
    forward_pair_valid =
        (state == WAIT_POINTWISE) & core_a_out_valid & core_b_out_valid;
  end

  pointwise_mul #(
      .QW(QW), .USE_WL_POINTWISE(USE_WL_POINTWISE)
  ) u_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(forward_pair_valid),
      .a_ntt(core_a_out0), .b_ntt(core_b_out0),
      .out_valid(mul_valid0), .c_ntt(mul_out0)
  );
  pointwise_mul #(
      .QW(QW), .USE_WL_POINTWISE(USE_WL_POINTWISE)
  ) u_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(forward_pair_valid),
      .a_ntt(core_a_out1), .b_ntt(core_b_out1),
      .out_valid(mul_valid1), .c_ntt(mul_out1)
  );
  delay_line #(.DW(LOGN-1), .DEPTH(POINTWISE_MUL_LAT)) u_mul_addr_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(forward_pair_valid),
      .din(forward_recv_count), .out_valid(mul_addr_valid), .dout(mul_addr)
  );

  always_comb begin
    intt_pair_valid = (state == WAIT_INTT_C) & core_a_out_valid;
    post_addr0 = bit_reverse({post_recv_count, 1'b0});
    post_addr1 = bit_reverse({post_recv_count, 1'b1});
  end

  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_inv0 (
      .table_sel(PSI_INV), .index(post_addr0), .factor(psi_inv0)
  );
  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_inv1 (
      .table_sel(PSI_INV), .index(post_addr1), .factor(psi_inv1)
  );
  mont_mul_select #(
      .QW(QW), .USE_WL_MONT(USE_WL_POST_INTT)
  ) u_post_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(intt_pair_valid),
      .a(core_a_out0), .b(psi_inv0), .out_valid(post_valid0), .y(post_out0)
  );
  mont_mul_select #(
      .QW(QW), .USE_WL_MONT(USE_WL_POST_INTT)
  ) u_post_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(intt_pair_valid),
      .a(core_a_out1), .b(psi_inv1), .out_valid(post_valid1), .y(post_out1)
  );
  delay_line #(.DW(2*LOGN), .DEPTH(POST_MUL_LAT)) u_post_addr_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(intt_pair_valid),
      .din({post_addr1, post_addr0}),
      .out_valid(post_addr_valid), .dout(delayed_post_addrs)
  );

  always_comb begin
    busy = (state != IDLE) && (state != DONE);
    done = (state == DONE);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE;
      feed_count <= '0;
      forward_recv_count <= '0;
      mul_count <= '0;
      post_recv_count <= '0;
      post_count <= '0;
      forward_started <= 1'b0;
    end else begin
      if (pre_pair_valid)
        forward_started <= 1'b1;

      if (forward_pair_valid)
        forward_recv_count <= forward_recv_count + 1'b1;

      if (mul_valid0 && mul_valid1 && mul_addr_valid) begin
        c_ntt_even[mul_addr] <= mul_out0;
        c_ntt_odd[mul_addr] <= mul_out1;
        if (mul_count == N/2-1) begin
          mul_count <= '0;
          feed_count <= '0;
          post_recv_count <= '0;
          post_count <= '0;
          state <= FEED_INTT_C;
        end else begin
          mul_count <= mul_count + 1'b1;
        end
      end

      if (intt_pair_valid)
        post_recv_count <= post_recv_count + 1'b1;

      if (post_valid0 && post_valid1 && post_addr_valid) begin
        result_bank0[delayed_post_addrs[LOGN-2:0]] <= post_out0;
        result_bank1[delayed_post_addrs[2*LOGN-2:LOGN]] <= post_out1;
        if (post_count == N/2-1) begin
          post_count <= '0;
          state <= DONE;
        end else begin
          post_count <= post_count + 1'b1;
        end
      end

      case (state)
        IDLE: if (start) begin
          feed_count <= '0;
          forward_recv_count <= '0;
          mul_count <= '0;
          post_recv_count <= '0;
          post_count <= '0;
          forward_started <= 1'b0;
          state <= FEED_FORWARD;
        end
        FEED_FORWARD: begin
          if (feed_count == N/2-1) begin
            feed_count <= '0;
            state <= WAIT_POINTWISE;
          end else begin
            feed_count <= feed_count + 1'b1;
          end
        end
        WAIT_POINTWISE: begin end
        FEED_INTT_C: begin
          if (feed_count == N/2-1) begin
            feed_count <= '0;
            post_recv_count <= '0;
            state <= WAIT_INTT_C;
          end else begin
            feed_count <= feed_count + 1'b1;
          end
        end
        WAIT_INTT_C: begin end
        DONE: if (!start) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && ((pre_a_valid0 != pre_a_valid1) ||
                  (pre_a_valid0 != pre_b_valid0) ||
                  (pre_a_valid0 != pre_b_valid1)))
      $fatal(1, "dual-forward Pre_NTT lane latency mismatch");
    if (rst_n && (state == WAIT_POINTWISE) &&
        (core_a_out_valid != core_b_out_valid))
      $fatal(1, "dual-forward core output valid mismatch");
    if (rst_n && ((mul_valid0 != mul_valid1) ||
                  (mul_valid0 != mul_addr_valid)))
      $fatal(1, "dual-forward Pointwise address/data latency mismatch");
    if (rst_n && ((post_valid0 != post_valid1) ||
                  (post_valid0 != post_addr_valid)))
      $fatal(1, "dual-forward Post_INTT address/data latency mismatch");
  end
`endif

  logic unused_ready;
  logic unused_done;
  always_comb begin
    unused_ready = core_a_in_ready ^ core_b_in_ready;
    unused_done = core_a_done ^ core_b_done;
  end
endmodule
