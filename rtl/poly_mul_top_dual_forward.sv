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
    parameter bit USE_LOAD_PREPROCESS = 1'b0,
    parameter bit USE_WL_POINTWISE = USE_WL_MONT,
    parameter bit USE_WL_POST_INTT = USE_WL_MONT,
    parameter bit USE_SHARED_PERIPH_MONT = 1'b0,
    parameter bit FUSE_INTT_SCALE_IN_POST = 1'b0,
    parameter bit USE_FINAL_UNIT_TWIDDLE_BYPASS = 1'b0,
    parameter bit USE_TOP_DATA_BRAM = 1'b0,
    parameter bit USE_NATURAL_AB_LOADER = 1'b0,
    parameter bit USE_BFU_BOUNDARY_PIPE = 1'b1,
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
    input  logic             ab_load_start,
    input  logic             ab_in_valid,
    output logic             ab_in_ready,
    input  logic [QW-1:0]    a_coeff_in,
    input  logic [QW-1:0]    b_coeff_in,
    output logic             ab_load_done,
    input  logic [LOGN-1:0]  result_addr,
    output logic [QW-1:0]    result_data,
    output logic             busy,
    output logic             done
);
  import params_pkg::*;

  localparam int OLD_MONT_LAT = 12;
  localparam int WL_MONT_LAT = 14;
  localparam int PRE_MUL_LAT =
      USE_WL_PRE_NTT ? WL_MONT_LAT : OLD_MONT_LAT;
  localparam int POINTWISE_MUL_LAT =
      USE_WL_POINTWISE ? WL_MONT_LAT : OLD_MONT_LAT;
  localparam int POST_MUL_LAT =
      USE_WL_POST_INTT ? WL_MONT_LAT : OLD_MONT_LAT;
  localparam bit SHARED_POOL_ACTIVE =
      USE_SHARED_PERIPH_MONT && !USE_LOAD_PREPROCESS;
  localparam logic [LOGN-1:0] CORE_A_BFU_PIPE_MASK =
      USE_BFU_BOUNDARY_PIPE ? {1'b1, {(LOGN-1){1'b0}}} : '0;
  localparam logic [LOGN-1:0] CORE_B_BFU_PIPE_MASK =
      USE_BFU_BOUNDARY_PIPE ? {{(LOGN-1){1'b0}}, 1'b1} : '0;
  localparam logic [LOGN-2:0] BRAM_FIRST_STREAM_ADDR =
      {{(LOGN-2){1'b0}}, 1'b1};

  typedef enum logic [2:0] {
    IDLE,
    WAIT_LOAD_DRAIN,
    FEED_FORWARD,
    WAIT_POINTWISE,
    FEED_INTT_C,
    WAIT_INTT_C,
    DONE
  } ctrl_state_t;
  ctrl_state_t state;

  localparam int LOAD_PENDING_W = $clog2(PRE_MUL_LAT + 2);
  logic load_accept;
  logic [LOAD_PENDING_W-1:0] load_pending_count;
  logic [LOGN-1:0] load_index;
  logic ab_load_active, ab_loaded, ab_fire;
  logic compute_start;

  logic [QW-1:0] result_bank0 [0:N/2-1];

  logic input_bank_wr_valid;
  logic input_bank_wr_sel;
  logic [LOGN-1:0] input_bank_wr_addr;
  logic [QW-1:0] input_bank_wr_data;
  logic c_write_valid;
  logic forward_mem_valid;
  logic intt_mem_valid, intt_mem_first;
  logic [LOGN-2:0] forward_mem_index;
  logic [QW-1:0] forward_mem_a0, forward_mem_a1;
  logic [QW-1:0] forward_mem_b0, forward_mem_b1;
  logic [QW-1:0] intt_mem0, intt_mem1;
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

  // Natural input is A[k]/B[k] in raw Montgomery representation. The address
  // MSB selects the physical half-bank; only a successful handshake advances k.
  always_comb begin
    load_accept = !USE_NATURAL_AB_LOADER && load_we && (state == IDLE);
    ab_in_ready = USE_NATURAL_AB_LOADER && ab_load_active &&
                  (state == IDLE);
    ab_fire = ab_in_valid && ab_in_ready;
    compute_start = start && (!USE_NATURAL_AB_LOADER || ab_loaded);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      load_index <= '0;
      ab_load_active <= 1'b0;
      ab_loaded <= 1'b0;
      ab_load_done <= 1'b0;
    end else begin
      ab_load_done <= 1'b0;
      if (USE_NATURAL_AB_LOADER) begin
        if (ab_load_start && (state == IDLE)) begin
          load_index <= '0;
          ab_load_active <= 1'b1;
          ab_loaded <= 1'b0;
        end else if (ab_fire) begin
          if (load_index == N-1) begin
            ab_load_active <= 1'b0;
            ab_loaded <= 1'b1;
            ab_load_done <= 1'b1;
          end else begin
            load_index <= load_index + 1'b1;
          end
        end
      end else begin
        load_index <= '0;
        ab_load_active <= 1'b0;
        ab_loaded <= 1'b0;
      end
    end
  end

  generate
    if (USE_LOAD_PREPROCESS) begin : g_load_preprocess
      logic [QW-1:0] load_psi_factor;
      logic load_pre_valid;
      logic [QW-1:0] load_pre_out;
      logic load_meta_valid;
      logic [LOGN:0] delayed_load_meta;

      psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_load (
          .table_sel(PSI_FWD), .index(load_addr), .factor(load_psi_factor)
      );
      mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_load_pre_mul (
          .clk(clk), .rst_n(rst_n), .in_valid(load_accept),
          .a(load_data), .b(load_psi_factor),
          .out_valid(load_pre_valid), .y(load_pre_out)
      );
      delay_line #(.DW(LOGN+1), .DEPTH(PRE_MUL_LAT)) u_load_meta_delay (
          .clk(clk), .rst_n(rst_n), .in_valid(load_accept),
          .din({load_sel, load_addr}),
          .out_valid(load_meta_valid), .dout(delayed_load_meta)
      );

      always_ff @(posedge clk) begin
        if (!rst_n) begin
          load_pending_count <= '0;
        end else begin
          case ({load_accept, load_pre_valid})
            2'b10: load_pending_count <= load_pending_count + 1'b1;
            2'b01: load_pending_count <= load_pending_count - 1'b1;
            default: load_pending_count <= load_pending_count;
          endcase

        end
      end

      always_comb begin
        input_bank_wr_valid = load_pre_valid && load_meta_valid;
        input_bank_wr_sel = delayed_load_meta[LOGN];
        input_bank_wr_addr = delayed_load_meta[LOGN-1:0];
        input_bank_wr_data = load_pre_out;
      end

`ifndef SYNTHESIS
      always_ff @(posedge clk) begin
        if (rst_n && (load_pre_valid != load_meta_valid))
          $fatal(1, "load preprocess address/data latency mismatch");
        if (rst_n && load_pre_valid && (load_pending_count == '0))
          $fatal(1, "load preprocess pending counter underflow");
      end
`endif
    end else begin : g_direct_load
      always_comb load_pending_count = '0;

      always_comb begin
        input_bank_wr_valid = load_accept;
        input_bank_wr_sel = load_sel;
        input_bank_wr_addr = load_addr;
        input_bank_wr_data = load_data;
      end
    end
  endgenerate

  always_comb c_write_valid = mul_valid0 && mul_valid1 && mul_addr_valid;

  generate
    if (USE_TOP_DATA_BRAM) begin : g_top_bram
      logic forward_prefetch, forward_stream, forward_rd_en;
      logic intt_prefetch, intt_stream, intt_rd_en;
      logic [LOGN-2:0] forward_rd_addr, intt_pair_index;
      logic [LOGN-1:0] intt_rd_addr0, intt_rd_addr1;
      logic ac0_rd_valid, ac1_rd_valid, b0_rd_valid, b1_rd_valid;
      logic forward_tag_r, intt_tag_r, intt_first_r;
      logic [LOGN-2:0] forward_index_r;
      logic [QW-1:0] ac0_rd_data, ac1_rd_data;
      logic [QW-1:0] b0_rd_data, b1_rd_data;
      logic ac0_wr_en, ac1_wr_en, b0_wr_en, b1_wr_en;
      logic [LOGN-2:0] ac0_wr_addr, ac1_wr_addr;
      logic [LOGN-2:0] b0_wr_addr, b1_wr_addr;
      logic [QW-1:0] ac0_wr_data, ac1_wr_data;
      logic [QW-1:0] b0_wr_data, b1_wr_data;

      always_comb begin
        forward_prefetch =
            ((state == IDLE) && compute_start && (load_pending_count == '0)) ||
            ((state == WAIT_LOAD_DRAIN) && (load_pending_count == '0));
        forward_stream = (state == FEED_FORWARD);
        forward_rd_en = forward_prefetch || forward_stream;
        forward_rd_addr = forward_prefetch ? '0 : feed_count;

        intt_prefetch = c_write_valid && (mul_count == N/2-1);
        intt_stream = (state == FEED_INTT_C);
        intt_rd_en = intt_prefetch || intt_stream;
        intt_pair_index = intt_prefetch ? '0 : feed_count;
        intt_rd_addr0 = bit_reverse({1'b0, intt_pair_index});
        intt_rd_addr1 = bit_reverse({1'b1, intt_pair_index});

        if (USE_NATURAL_AB_LOADER) begin
          ac0_wr_en = c_write_valid || (ab_fire && !load_index[LOGN-1]);
          ac1_wr_en = c_write_valid || (ab_fire && load_index[LOGN-1]);
          ac0_wr_addr = c_write_valid ? mul_addr : load_index[LOGN-2:0];
          ac1_wr_addr = c_write_valid ? mul_addr : load_index[LOGN-2:0];
          ac0_wr_data = c_write_valid ? mul_out0 : a_coeff_in;
          ac1_wr_data = c_write_valid ? mul_out1 : a_coeff_in;

          b0_wr_en = ab_fire && !load_index[LOGN-1];
          b1_wr_en = ab_fire && load_index[LOGN-1];
          b0_wr_addr = load_index[LOGN-2:0];
          b1_wr_addr = load_index[LOGN-2:0];
          b0_wr_data = b_coeff_in;
          b1_wr_data = b_coeff_in;
        end else begin
          ac0_wr_en = c_write_valid ||
                      (input_bank_wr_valid && !input_bank_wr_sel &&
                       !input_bank_wr_addr[LOGN-1]);
          ac1_wr_en = c_write_valid ||
                      (input_bank_wr_valid && !input_bank_wr_sel &&
                       input_bank_wr_addr[LOGN-1]);
          ac0_wr_addr = c_write_valid ? mul_addr :
                        input_bank_wr_addr[LOGN-2:0];
          ac1_wr_addr = c_write_valid ? mul_addr :
                        input_bank_wr_addr[LOGN-2:0];
          ac0_wr_data = c_write_valid ? mul_out0 : input_bank_wr_data;
          ac1_wr_data = c_write_valid ? mul_out1 : input_bank_wr_data;

          b0_wr_en = input_bank_wr_valid && input_bank_wr_sel &&
                     !input_bank_wr_addr[LOGN-1];
          b1_wr_en = input_bank_wr_valid && input_bank_wr_sel &&
                     input_bank_wr_addr[LOGN-1];
          b0_wr_addr = input_bank_wr_addr[LOGN-2:0];
          b1_wr_addr = input_bank_wr_addr[LOGN-2:0];
          b0_wr_data = input_bank_wr_data;
          b1_wr_data = input_bank_wr_data;
        end

        forward_mem_valid = ac0_rd_valid && ac1_rd_valid &&
                            b0_rd_valid && b1_rd_valid && forward_tag_r;
        forward_mem_index = forward_index_r;
        forward_mem_a0 = ac0_rd_data;
        forward_mem_a1 = ac1_rd_data;
        forward_mem_b0 = b0_rd_data;
        forward_mem_b1 = b1_rd_data;
        intt_mem_valid = ac0_rd_valid && ac1_rd_valid && intt_tag_r;
        intt_mem_first = intt_first_r;
        intt_mem0 = ac0_rd_data;
        intt_mem1 = ac1_rd_data;
      end

      always_ff @(posedge clk) begin
        if (!rst_n) begin
          forward_tag_r <= 1'b0;
          intt_tag_r <= 1'b0;
          intt_first_r <= 1'b0;
          forward_index_r <= '0;
        end else begin
          forward_tag_r <= forward_rd_en;
          intt_tag_r <= intt_rd_en;
          intt_first_r <= intt_prefetch;
          if (forward_rd_en)
            forward_index_r <= forward_rd_addr;
        end
      end

      top_data_bram #(.DW(QW), .DEPTH(N/2), .AW(LOGN-1)) u_ac_bank0 (
          .clk(clk), .rst_n(rst_n),
          .wr_en(ac0_wr_en), .wr_addr(ac0_wr_addr), .wr_data(ac0_wr_data),
          .rd_en(forward_rd_en || intt_rd_en),
          .rd_addr(intt_rd_en ? intt_rd_addr0[LOGN-1:1] : forward_rd_addr),
          .rd_valid(ac0_rd_valid), .rd_data(ac0_rd_data)
      );
      top_data_bram #(.DW(QW), .DEPTH(N/2), .AW(LOGN-1)) u_ac_bank1 (
          .clk(clk), .rst_n(rst_n),
          .wr_en(ac1_wr_en), .wr_addr(ac1_wr_addr), .wr_data(ac1_wr_data),
          .rd_en(forward_rd_en || intt_rd_en),
          .rd_addr(intt_rd_en ? intt_rd_addr1[LOGN-1:1] : forward_rd_addr),
          .rd_valid(ac1_rd_valid), .rd_data(ac1_rd_data)
      );
      top_data_bram #(.DW(QW), .DEPTH(N/2), .AW(LOGN-1)) u_b_bank0 (
          .clk(clk), .rst_n(rst_n),
          .wr_en(b0_wr_en), .wr_addr(b0_wr_addr), .wr_data(b0_wr_data),
          .rd_en(forward_rd_en), .rd_addr(forward_rd_addr),
          .rd_valid(b0_rd_valid), .rd_data(b0_rd_data)
      );
      top_data_bram #(.DW(QW), .DEPTH(N/2), .AW(LOGN-1)) u_b_bank1 (
          .clk(clk), .rst_n(rst_n),
          .wr_en(b1_wr_en), .wr_addr(b1_wr_addr), .wr_data(b1_wr_data),
          .rd_en(forward_rd_en), .rd_addr(forward_rd_addr),
          .rd_valid(b1_rd_valid), .rd_data(b1_rd_data)
      );

`ifndef SYNTHESIS
      always_ff @(posedge clk) begin
        if (rst_n && input_bank_wr_valid && c_write_valid)
          $fatal(1, "top BRAM input/C_NTT write ownership overlap");
        if (rst_n && ab_fire && c_write_valid)
          $fatal(1, "natural A/B load and C_NTT write ownership overlap");
        if (rst_n && forward_rd_en && c_write_valid)
          $fatal(1, "A forward read and C_NTT write ownership overlap");
        if (rst_n && ab_fire && (forward_rd_en || intt_rd_en))
          $fatal(1, "natural A/B load and transform read ownership overlap");
        if (rst_n && forward_rd_en && intt_rd_en)
          $fatal(1, "top BRAM forward/INTT read ownership overlap");
        if (rst_n && ((ac0_rd_valid != ac1_rd_valid) ||
                      (ac0_rd_valid != b0_rd_valid && forward_tag_r) ||
                      (ac0_rd_valid != b1_rd_valid && forward_tag_r)))
          $fatal(1, "top BRAM lane read-valid mismatch");
      end
`endif
    end else begin : g_top_lutram
      logic [QW-1:0] a_bank0 [0:N/2-1];
      logic [QW-1:0] a_bank1 [0:N/2-1];
      logic [QW-1:0] b_bank0 [0:N/2-1];
      logic [QW-1:0] b_bank1 [0:N/2-1];
      logic [QW-1:0] c_ntt_even [0:N/2-1];
      logic [QW-1:0] c_ntt_odd  [0:N/2-1];
      logic [LOGN-1:0] lut_intt_addr0, lut_intt_addr1;

      always_ff @(posedge clk) begin
        if (input_bank_wr_valid) begin
          if (input_bank_wr_sel) begin
            if (input_bank_wr_addr[LOGN-1])
              b_bank1[input_bank_wr_addr[LOGN-2:0]] <= input_bank_wr_data;
            else
              b_bank0[input_bank_wr_addr[LOGN-2:0]] <= input_bank_wr_data;
          end else begin
            if (input_bank_wr_addr[LOGN-1])
              a_bank1[input_bank_wr_addr[LOGN-2:0]] <= input_bank_wr_data;
            else
              a_bank0[input_bank_wr_addr[LOGN-2:0]] <= input_bank_wr_data;
          end
        end
        if (c_write_valid) begin
          c_ntt_even[mul_addr] <= mul_out0;
          c_ntt_odd[mul_addr] <= mul_out1;
        end
      end

      always_comb begin
        lut_intt_addr0 = bit_reverse({1'b0, feed_count});
        lut_intt_addr1 = bit_reverse({1'b1, feed_count});
        forward_mem_valid = (state == FEED_FORWARD);
        forward_mem_index = feed_count;
        forward_mem_a0 = a_bank0[feed_count];
        forward_mem_a1 = a_bank1[feed_count];
        forward_mem_b0 = b_bank0[feed_count];
        forward_mem_b1 = b_bank1[feed_count];
        intt_mem_valid = (state == FEED_INTT_C);
        intt_mem_first = intt_mem_valid && (feed_count == '0);
        intt_mem0 = c_ntt_even[lut_intt_addr0[LOGN-1:1]];
        intt_mem1 = c_ntt_odd[lut_intt_addr1[LOGN-1:1]];
      end
    end
  endgenerate
  always_comb begin
    if (result_addr[LOGN-1])
      result_data = result_bank1[result_addr[LOGN-2:0]];
    else
      result_data = result_bank0[result_addr[LOGN-2:0]];
  end

  always_comb begin
    pre_issue_valid = forward_mem_valid;
    pre_index0 = {1'b0, forward_mem_index};
    pre_index1 = {1'b1, forward_mem_index};
  end

  generate
    if (USE_LOAD_PREPROCESS) begin : g_preloaded_forward
      always_comb begin
        pre_a_valid0 = pre_issue_valid;
        pre_a_valid1 = pre_issue_valid;
        pre_b_valid0 = pre_issue_valid;
        pre_b_valid1 = pre_issue_valid;
        pre_a_out0 = forward_mem_a0;
        pre_a_out1 = forward_mem_a1;
        pre_b_out0 = forward_mem_b0;
        pre_b_out1 = forward_mem_b1;
      end
    end else begin : g_forward_pre
      psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_fwd0 (
          .table_sel(PSI_FWD), .index(pre_index0), .factor(psi_fwd0)
      );
      psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_fwd1 (
          .table_sel(PSI_FWD), .index(pre_index1), .factor(psi_fwd1)
      );

      if (!SHARED_POOL_ACTIVE) begin : g_direct_pre
      mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_pre_a_mul0 (
          .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
          .a(forward_mem_a0), .b(psi_fwd0),
          .out_valid(pre_a_valid0), .y(pre_a_out0)
      );
      mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_pre_a_mul1 (
          .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
          .a(forward_mem_a1), .b(psi_fwd1),
          .out_valid(pre_a_valid1), .y(pre_a_out1)
      );
      mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_pre_b_mul0 (
          .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
          .a(forward_mem_b0), .b(psi_fwd0),
          .out_valid(pre_b_valid0), .y(pre_b_out0)
      );
      mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_pre_b_mul1 (
          .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
          .a(forward_mem_b1), .b(psi_fwd1),
          .out_valid(pre_b_valid1), .y(pre_b_out1)
      );
      end
    end
  endgenerate
  always_comb begin
    pre_pair_valid = pre_a_valid0 & pre_a_valid1 & pre_b_valid0 & pre_b_valid1;

    core_a_start = pre_pair_valid & !forward_started;
    core_a_in_valid = pre_pair_valid;
    core_a_mode = MODE_NTT;
    core_a_in0 = pre_a_out0;
    core_a_in1 = pre_a_out1;
    if (intt_mem_valid) begin
      core_a_start = intt_mem_first;
      core_a_in_valid = 1'b1;
      core_a_mode = MODE_INTT;
      core_a_in0 = intt_mem0;
      core_a_in1 = intt_mem1;
    end

    core_b_start = pre_pair_valid & !forward_started;
  end

  // Keep the two transform engines as independent synthesis domains. This
  // prevents equivalent valid pipelines from being merged into a long
  // cross-core control net after placement.
  (* keep_hierarchy = "yes" *)
  gs_mdc_core #(
      .N(N), .LOGN(LOGN), .QW(QW), .MUL_LAT(MUL_LAT),
      .USE_WL_MONT(USE_WL_CORE),
      .BYPASS_INTT_SCALE(FUSE_INTT_SCALE_IN_POST),
      .BYPASS_FINAL_UNIT_TWIDDLE(USE_FINAL_UNIT_TWIDDLE_BYPASS),
      .BFU_BOUNDARY_PIPE_MASK(CORE_A_BFU_PIPE_MASK),
      .USE_STAGE_LOCAL_TWIDDLE(USE_STAGE_LOCAL_TWIDDLE),
      .TWIDDLE_BRAM_STAGES(TWIDDLE_BRAM_STAGES)
  ) u_core_a (
      .clk(clk), .rst_n(rst_n), .start(core_a_start), .mode(core_a_mode),
      .in_valid(core_a_in_valid), .in_ready(core_a_in_ready),
      .in0(core_a_in0), .in1(core_a_in1),
      .out_valid(core_a_out_valid), .out_ready(1'b1),
      .out0(core_a_out0), .out1(core_a_out1), .done(core_a_done)
  );

  (* keep_hierarchy = "yes" *)
  gs_mdc_core_ntt_only #(
      .N(N), .LOGN(LOGN), .QW(QW), .MUL_LAT(MUL_LAT),
      .USE_WL_MONT(USE_WL_CORE),
      .BYPASS_FINAL_UNIT_TWIDDLE(USE_FINAL_UNIT_TWIDDLE_BYPASS),
      .BFU_BOUNDARY_PIPE_MASK(CORE_B_BFU_PIPE_MASK),
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

  generate
    if (!SHARED_POOL_ACTIVE) begin : g_direct_pointwise
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
    end
  endgenerate
  delay_line #(.DW(LOGN-1), .DEPTH(POINTWISE_MUL_LAT)) u_mul_addr_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(forward_pair_valid),
      .din(forward_recv_count), .out_valid(mul_addr_valid), .dout(mul_addr)
  );

  always_comb begin
    intt_pair_valid = (state == WAIT_INTT_C) & core_a_out_valid;
    post_addr0 = bit_reverse({post_recv_count, 1'b0});
    post_addr1 = bit_reverse({post_recv_count, 1'b1});
  end

  psi_post_rom #(
      .QW(QW), .LOGN(LOGN), .N(N),
      .FUSE_N_INV(FUSE_INTT_SCALE_IN_POST)
  ) u_psi_inv0 (
      .index(post_addr0), .factor(psi_inv0)
  );
  psi_post_rom #(
      .QW(QW), .LOGN(LOGN), .N(N),
      .FUSE_N_INV(FUSE_INTT_SCALE_IN_POST)
  ) u_psi_inv1 (
      .index(post_addr1), .factor(psi_inv1)
  );
  generate
    if (!SHARED_POOL_ACTIVE) begin : g_direct_post
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
    end
  endgenerate

  generate
    if (SHARED_POOL_ACTIVE) begin : g_shared_periph_pool
      peripheral_mont_pool #(
          .QW(QW), .MONT_LAT(PRE_MUL_LAT),
          .USE_WL_MONT(USE_WL_PRE_NTT)
      ) u_pool (
          .clk(clk), .rst_n(rst_n),
          .pre_valid(pre_issue_valid),
          .pre_a0(forward_mem_a0), .pre_a1(forward_mem_a1),
          .pre_b0(forward_mem_b0), .pre_b1(forward_mem_b1),
          .pre_factor0(psi_fwd0), .pre_factor1(psi_fwd1),
          .pre_out_valid0(pre_a_valid0), .pre_out_valid1(pre_a_valid1),
          .pre_out_valid2(pre_b_valid0), .pre_out_valid3(pre_b_valid1),
          .pre_out0(pre_a_out0), .pre_out1(pre_a_out1),
          .pre_out2(pre_b_out0), .pre_out3(pre_b_out1),
          .point_valid(forward_pair_valid),
          .point_a0(core_a_out0), .point_a1(core_a_out1),
          .point_b0(core_b_out0), .point_b1(core_b_out1),
          .point_out_valid0(mul_valid0), .point_out_valid1(mul_valid1),
          .point_out0(mul_out0), .point_out1(mul_out1),
          .post_valid(intt_pair_valid),
          .post_a0(core_a_out0), .post_a1(core_a_out1),
          .post_factor0(psi_inv0), .post_factor1(psi_inv1),
          .post_out_valid0(post_valid0), .post_out_valid1(post_valid1),
          .post_out0(post_out0), .post_out1(post_out1)
      );
    end
  endgenerate
  delay_line #(.DW(2*LOGN), .DEPTH(POST_MUL_LAT)) u_post_addr_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(intt_pair_valid),
      .din({post_addr1, post_addr0}),
      .out_valid(post_addr_valid), .dout(delayed_post_addrs)
  );

  always_comb begin
    busy = ((state != IDLE) && (state != DONE)) ||
           (USE_NATURAL_AB_LOADER && ab_load_active);
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

      if (c_write_valid) begin
        if (mul_count == N/2-1) begin
          mul_count <= '0;
          feed_count <= USE_TOP_DATA_BRAM ? BRAM_FIRST_STREAM_ADDR : '0;
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
        IDLE: if (compute_start) begin
          feed_count <= '0;
          forward_recv_count <= '0;
          mul_count <= '0;
          post_recv_count <= '0;
          post_count <= '0;
          forward_started <= 1'b0;
          if (USE_LOAD_PREPROCESS && (load_pending_count != '0))
            state <= WAIT_LOAD_DRAIN;
          else begin
            if (USE_TOP_DATA_BRAM)
              feed_count <= BRAM_FIRST_STREAM_ADDR;
            state <= FEED_FORWARD;
          end
        end
        WAIT_LOAD_DRAIN: begin
          if (load_pending_count == '0) begin
            if (USE_TOP_DATA_BRAM)
              feed_count <= BRAM_FIRST_STREAM_ADDR;
            state <= FEED_FORWARD;
        end
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
  initial begin
    if (USE_NATURAL_AB_LOADER && !USE_TOP_DATA_BRAM)
      $fatal(1, "natural A/B loader requires top-level BRAM banks");
    if (USE_NATURAL_AB_LOADER && USE_LOAD_PREPROCESS)
      $fatal(1, "natural A/B loader writes raw coefficients; load preprocessing must be disabled");
    if (USE_SHARED_PERIPH_MONT && USE_LOAD_PREPROCESS)
      $fatal(1, "shared peripheral Montgomery pool requires raw Pre_NTT mode");
    if (USE_SHARED_PERIPH_MONT &&
        ((USE_WL_PRE_NTT != USE_WL_POINTWISE) ||
         (USE_WL_PRE_NTT != USE_WL_POST_INTT) ||
         (PRE_MUL_LAT != POINTWISE_MUL_LAT) ||
         (PRE_MUL_LAT != POST_MUL_LAT)))
      $fatal(1, "shared peripheral Montgomery pool requires equal multiplier implementations");
  end

  always_ff @(posedge clk) begin
    if (rst_n && USE_NATURAL_AB_LOADER && start && !ab_loaded)
      $fatal(1, "compute start asserted before natural A/B load completed");
    if (rst_n && USE_NATURAL_AB_LOADER && ab_load_start && (state != IDLE))
      $fatal(1, "natural A/B load started while compute state is active");
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
