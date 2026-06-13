// Negacyclic polynomial multiplier modulo x^N+1.
//
// The reusable GS-MDC core remains an ordinary cyclic NTT/INTT engine.
// Explicit Montgomery-domain psi pre/post multipliers implement negacyclic:
//   Pre_NTT : a[i] <- a[i] * psi^i
//   Post_INTT: c[i] <- c[i] * psi^-i
module poly_mul_top #(
    parameter int N = 4096,
    parameter int LOGN = 12,
    parameter int QW = 64
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
  typedef enum logic [3:0] {
    IDLE, NTT_A, WAIT_NTT_A, NTT_B_MUL, WAIT_NTT_B,
    INTT_C, WAIT_INTT_C, DONE
  } ctrl_state_t;

  ctrl_state_t state;

  // Lower/upper-half banks directly provide the two stage-0 operands.
  logic [QW-1:0] a_bank0 [0:N/2-1];
  logic [QW-1:0] a_bank1 [0:N/2-1];
  logic [QW-1:0] b_bank0 [0:N/2-1];
  logic [QW-1:0] b_bank1 [0:N/2-1];
  // Transform-domain streams always read/write adjacent even/odd addresses.
  // Splitting them into even/odd banks turns each array into a single-write
  // memory pattern that Vivado can infer instead of dissolving into registers.
  logic [QW-1:0] a_ntt_even [0:N/2-1];
  logic [QW-1:0] a_ntt_odd  [0:N/2-1];
  logic [QW-1:0] c_ntt_even [0:N/2-1];
  logic [QW-1:0] c_ntt_odd  [0:N/2-1];

  // Post-INTT writes use one address in each polynomial half, so result storage
  // is banked by the address MSB.
  logic [QW-1:0] result_bank0 [0:N/2-1];
  logic [QW-1:0] result_bank1 [0:N/2-1];

  logic [LOGN-2:0] feed_count, recv_count, mul_count, post_count;
  logic core_start, core_in_valid, core_out_valid, core_done;
  logic [1:0] core_mode;
  logic [QW-1:0] core_in0, core_in1, core_out0, core_out1;

  logic pre_issue_valid, pre_valid0, pre_valid1;
  logic [LOGN-1:0] pre_index0, pre_index1;
  logic [QW-1:0] pre_data0, pre_data1, psi_fwd0, psi_fwd1;
  logic [QW-1:0] pre_out0, pre_out1;

  logic mul_valid0, mul_valid1, mul_addr_valid;
  logic [QW-1:0] mul_out0, mul_out1;
  logic [LOGN-2:0] mul_addr;

  logic [LOGN-1:0] post_addr0, post_addr1;
  logic [LOGN-1:0] intt_addr0, intt_addr1;
  logic [QW-1:0] psi_inv0, psi_inv1, post_out0, post_out1;
  logic post_valid0, post_valid1, post_addr_valid;
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

  // Explicit Pre_NTT: both lanes multiply their natural-index coefficient by
  // psi^i. The Montgomery multipliers preserve the Montgomery data domain.
  always_comb begin
    pre_issue_valid = (state == NTT_A) || (state == NTT_B_MUL);
    pre_index0 = {1'b0, feed_count};
    pre_index1 = {1'b1, feed_count};
    if (state == NTT_B_MUL) begin
      pre_data0 = b_bank0[feed_count];
      pre_data1 = b_bank1[feed_count];
    end else begin
      pre_data0 = a_bank0[feed_count];
      pre_data1 = a_bank1[feed_count];
    end
  end

  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_fwd0 (
      .table_sel(PSI_FWD), .index(pre_index0), .factor(psi_fwd0)
  );
  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_fwd1 (
      .table_sel(PSI_FWD), .index(pre_index1), .factor(psi_fwd1)
  );
  mont_mul #(.QW(QW)) u_pre_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
      .a(pre_data0), .b(psi_fwd0), .out_valid(pre_valid0), .y(pre_out0)
  );
  mont_mul #(.QW(QW)) u_pre_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
      .a(pre_data1), .b(psi_fwd1), .out_valid(pre_valid1), .y(pre_out1)
  );

  // Core input is driven by completed Pre_NTT products for forward transforms.
  // INTT input keeps the existing external bit-reversal scheme unchanged.
  always_comb begin
    core_in_valid = pre_valid0 & pre_valid1;
    core_in0 = pre_out0;
    core_in1 = pre_out1;
    if (state == INTT_C) begin
      intt_addr0 = bit_reverse({1'b0, feed_count});
      intt_addr1 = bit_reverse({1'b1, feed_count});
      core_in_valid = 1'b1;
      core_in0 = c_ntt_even[intt_addr0[LOGN-1:1]];
      core_in1 = c_ntt_odd[intt_addr1[LOGN-1:1]];
    end else begin
      intt_addr0 = '0;
      intt_addr1 = '0;
    end
    core_mode = ((state == INTT_C) || (state == WAIT_INTT_C))
              ? MODE_INTT : MODE_NTT;
  end

  gs_mdc_core #(.N(N), .LOGN(LOGN), .QW(QW), .MUL_LAT(MUL_LAT)) u_core (
      .clk(clk), .rst_n(rst_n), .start(core_start), .mode(core_mode),
      .in_valid(core_in_valid), .in_ready(), .in0(core_in0), .in1(core_in1),
      .out_valid(core_out_valid), .out_ready(1'b1),
      .out0(core_out0), .out1(core_out1), .done(core_done)
  );

  pointwise_mul #(.QW(QW)) u_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(core_out_valid && state == WAIT_NTT_B),
      .a_ntt(a_ntt_even[recv_count]), .b_ntt(core_out0),
      .out_valid(mul_valid0), .c_ntt(mul_out0)
  );
  pointwise_mul #(.QW(QW)) u_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(core_out_valid && state == WAIT_NTT_B),
      .a_ntt(a_ntt_odd[recv_count]), .b_ntt(core_out1),
      .out_valid(mul_valid1), .c_ntt(mul_out1)
  );
  delay_line #(.DW(LOGN-1), .DEPTH(MUL_LAT)) u_mul_addr_delay (
      .clk(clk), .rst_n(rst_n),
      .in_valid(core_out_valid && state == WAIT_NTT_B), .din(recv_count),
      .out_valid(mul_addr_valid), .dout(mul_addr)
  );

  // Explicit Post_INTT. The core already applies N^-1, so only psi^-i is
  // applied here. Factors use the final bit-reversed result write addresses.
  always_comb begin
    post_addr0 = bit_reverse({recv_count, 1'b0});
    post_addr1 = bit_reverse({recv_count, 1'b1});
  end
  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_inv0 (
      .table_sel(PSI_INV), .index(post_addr0), .factor(psi_inv0)
  );
  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_inv1 (
      .table_sel(PSI_INV), .index(post_addr1), .factor(psi_inv1)
  );
  mont_mul #(.QW(QW)) u_post_mul0 (
      .clk(clk), .rst_n(rst_n),
      .in_valid(core_out_valid && state == WAIT_INTT_C),
      .a(core_out0), .b(psi_inv0), .out_valid(post_valid0), .y(post_out0)
  );
  mont_mul #(.QW(QW)) u_post_mul1 (
      .clk(clk), .rst_n(rst_n),
      .in_valid(core_out_valid && state == WAIT_INTT_C),
      .a(core_out1), .b(psi_inv1), .out_valid(post_valid1), .y(post_out1)
  );
  delay_line #(.DW(2*LOGN), .DEPTH(MUL_LAT)) u_post_addr_delay (
      .clk(clk), .rst_n(rst_n),
      .in_valid(core_out_valid && state == WAIT_INTT_C),
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
      recv_count <= '0;
      mul_count <= '0;
      post_count <= '0;
      core_start <= 1'b0;
    end else begin
      core_start <= 1'b0;
      case (state)
        IDLE: if (start) begin
          feed_count <= '0;
          recv_count <= '0;
          core_start <= 1'b1;
          state <= NTT_A;
        end
        NTT_A: begin
          if (feed_count == N/2-1) begin
            feed_count <= '0;
            recv_count <= '0;
            state <= WAIT_NTT_A;
          end else feed_count <= feed_count + 1'b1;
        end
        WAIT_NTT_A: begin
          if (core_out_valid) begin
            a_ntt_even[recv_count] <= core_out0;
            a_ntt_odd[recv_count] <= core_out1;
            recv_count <= recv_count + 1'b1;
          end
          if (core_done) begin
            feed_count <= '0;
            recv_count <= '0;
            mul_count <= '0;
            core_start <= 1'b1;
            state <= NTT_B_MUL;
          end
        end
        NTT_B_MUL: begin
          if (feed_count == N/2-1) begin
            feed_count <= '0;
            recv_count <= '0;
            state <= WAIT_NTT_B;
          end else feed_count <= feed_count + 1'b1;
        end
        WAIT_NTT_B: begin
          if (core_out_valid)
            recv_count <= recv_count + 1'b1;
          if (mul_valid0 && mul_valid1 && mul_addr_valid) begin
            c_ntt_even[mul_addr] <= mul_out0;
            c_ntt_odd[mul_addr] <= mul_out1;
            if (mul_count == N/2-1) begin
              feed_count <= '0;
              recv_count <= '0;
              post_count <= '0;
              core_start <= 1'b1;
              state <= INTT_C;
            end else mul_count <= mul_count + 1'b1;
          end
        end
        INTT_C: begin
          if (feed_count == N/2-1) begin
            feed_count <= '0;
            recv_count <= '0;
            state <= WAIT_INTT_C;
          end else feed_count <= feed_count + 1'b1;
        end
        WAIT_INTT_C: begin
          if (core_out_valid)
            recv_count <= recv_count + 1'b1;
          if (post_valid0 && post_valid1 && post_addr_valid) begin
            result_bank0[delayed_post_addrs[LOGN-2:0]] <= post_out0;
            result_bank1[delayed_post_addrs[2*LOGN-2:LOGN]] <= post_out1;
            if (post_count == N/2-1)
              state <= DONE;
            else
              post_count <= post_count + 1'b1;
          end
        end
        DONE: if (!start) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end
endmodule
