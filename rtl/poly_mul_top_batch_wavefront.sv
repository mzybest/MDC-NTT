// Experimental batched polynomial multiplier with frame-level job interleaving.
//
// The arithmetic datapath is unchanged. A/B_NTT and C_INTT frames from several
// independent jobs share one mode-tagged dual-context GS-MDC core. Source,
// transform, pointwise, and result storage use synchronous BRAM-friendly banks.
module poly_mul_top_batch_wavefront #(
    parameter int N = 4096,
    parameter int LOGN = 12,
    parameter int QW = 64,
    parameter int JOB_COUNT = 6,
    parameter int JOB_BUFFERS = 3,
    parameter int JOB_W = (JOB_COUNT <= 1) ? 1 : $clog2(JOB_COUNT),
    parameter int BANK_W = (JOB_BUFFERS <= 1) ? 1 : $clog2(JOB_BUFFERS),
    parameter int MUL_LAT = params_pkg::MUL_LAT,
    parameter bit USE_WL_MONT = 1'b1,
    parameter bit USE_WL_CORE = USE_WL_MONT,
    parameter bit USE_WL_PRE_NTT = USE_WL_MONT,
    parameter bit USE_WL_POINTWISE = USE_WL_MONT,
    parameter bit USE_WL_POST_INTT = USE_WL_MONT,
    parameter bit USE_STAGE_LOCAL_TWIDDLE = 1'b1,
    parameter int TWIDDLE_BRAM_STAGES = 4
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 start,
    input  logic                 load_we,
    input  logic [JOB_W-1:0]     load_job,
    input  logic                 load_sel,
    input  logic [LOGN-1:0]      load_addr,
    input  logic [QW-1:0]        load_data,
    input  logic                 result_rd_en,
    input  logic [JOB_W-1:0]     result_job,
    input  logic [LOGN-1:0]      result_addr,
    output logic                 result_rd_valid,
    output logic [QW-1:0]        result_data,
    output logic                 busy,
    output logic                 done
);
  import params_pkg::*;

  localparam int PAIRS = N / 2;
  localparam int OLD_MONT_LAT = 12;
  localparam int WL_MONT_LAT = 14;
  localparam int PRE_MUL_LAT =
      USE_WL_PRE_NTT ? WL_MONT_LAT : OLD_MONT_LAT;
  localparam int POINTWISE_MUL_LAT =
      USE_WL_POINTWISE ? WL_MONT_LAT : OLD_MONT_LAT;
  localparam int POST_MUL_LAT =
      USE_WL_POST_INTT ? WL_MONT_LAT : OLD_MONT_LAT;

  localparam logic [1:0] ROLE_A_NTT = 2'd0;
  localparam logic [1:0] ROLE_B_NTT = 2'd1;
  localparam logic [1:0] ROLE_C_INTT = 2'd2;

  // LSB remains the reorder-context selector required by mdc_stage_dualctx.
  localparam int FRAME_W = JOB_W + BANK_W + 3;
  localparam int SRC_DEPTH = JOB_COUNT * PAIRS;
  localparam int SRC_AW = (SRC_DEPTH <= 1) ? 1 : $clog2(SRC_DEPTH);
  localparam int CTX_DEPTH = JOB_BUFFERS * PAIRS;
  localparam int CTX_AW = (CTX_DEPTH <= 1) ? 1 : $clog2(CTX_DEPTH);
  localparam int RES_DEPTH = JOB_COUNT * PAIRS;
  localparam int RES_AW = (RES_DEPTH <= 1) ? 1 : $clog2(RES_DEPTH);
  localparam int MUL_META_W = FRAME_W + LOGN - 1;
  localparam int POST_META_W = FRAME_W + 3*LOGN - 1;

  function automatic logic [FRAME_W-1:0] pack_frame(
      input logic [JOB_W-1:0] job,
      input logic [BANK_W-1:0] bank,
      input logic [1:0] role,
      input logic context_select
  );
    pack_frame = {job, bank, role, context_select};
  endfunction

  function automatic logic [SRC_AW-1:0] source_address(
      input logic [JOB_W-1:0] job,
      input logic [LOGN-2:0] pair
  );
    source_address = job * PAIRS + pair;
  endfunction

  function automatic logic [CTX_AW-1:0] context_address(
      input logic [BANK_W-1:0] bank,
      input logic [LOGN-2:0] pair
  );
    context_address = bank * PAIRS + pair;
  endfunction

  function automatic logic [RES_AW-1:0] result_address(
      input logic [JOB_W-1:0] job,
      input logic [LOGN-2:0] pair
  );
    result_address = job * PAIRS + pair;
  endfunction

  function automatic logic [LOGN-2:0] bit_reverse_pair(
      input logic [LOGN-2:0] value
  );
    integer k;
    for (k = 0; k < LOGN-1; k = k + 1)
      bit_reverse_pair[k] = value[LOGN-2-k];
  endfunction

  function automatic logic [LOGN-1:0] bit_reverse(
      input logic [LOGN-1:0] value
  );
    integer k;
    for (k = 0; k < LOGN; k = k + 1)
      bit_reverse[k] = value[LOGN-1-k];
  endfunction

  logic sched_frame_valid, sched_frame_sof, sched_frame_eof;
  logic [LOGN-2:0] sched_frame_pair;
  logic [1:0] sched_frame_role;
  logic [JOB_W-1:0] sched_frame_job;
  logic [BANK_W-1:0] sched_frame_bank;
  logic sched_frame_context;
  logic pointwise_done_valid, result_done_valid;
  logic [JOB_W-1:0] pointwise_done_job, result_done_job;
  logic [BANK_W-1:0] pointwise_done_bank, result_done_bank;

  logic src_a0_we, src_a1_we, src_b0_we, src_b1_we;
  logic [SRC_AW-1:0] source_wr_addr, source_rd_addr;
  logic src_a_rd_en, src_b_rd_en;
  logic src_a0_rd_valid, src_a1_rd_valid;
  logic src_b0_rd_valid, src_b1_rd_valid;
  logic [QW-1:0] src_a0_rd_data, src_a1_rd_data;
  logic [QW-1:0] src_b0_rd_data, src_b1_rd_data;

  logic [CTX_AW-1:0] a_ntt_wr_addr, a_ntt_rd_addr;
  logic a_ntt_wr_en, a_ntt_rd_en;
  logic a_ntt0_rd_valid, a_ntt1_rd_valid;
  logic [QW-1:0] a_ntt0_rd_data, a_ntt1_rd_data;
  logic [CTX_AW-1:0] c_ntt_wr_addr, c_ntt_rd_addr;
  logic c_ntt_wr_en, c_ntt_rd_en;
  logic c_ntt0_rd_valid, c_ntt1_rd_valid;
  logic [QW-1:0] c_ntt0_rd_data, c_ntt1_rd_data;

  logic [RES_AW-1:0] result_wr_addr0, result_wr_addr1;
  logic result_wr_en;
  logic [RES_AW-1:0] result_rd_addr_flat;
  logic result0_rd_valid, result1_rd_valid, result_lane_q;
  logic [QW-1:0] result0_rd_data, result1_rd_data;

  logic read_desc_valid_q;
  logic [LOGN-2:0] read_pair_q;
  logic [1:0] read_role_q;
  logic [JOB_W-1:0] read_job_q;
  logic [BANK_W-1:0] read_bank_q;
  logic read_context_q;
  logic [FRAME_W-1:0] read_frame_q;

  logic pre_issue_valid, pre_valid0, pre_valid1, pre_tag_valid;
  logic [QW-1:0] pre_data0, pre_data1;
  logic [QW-1:0] psi_fwd0, psi_fwd1, pre_out0, pre_out1;
  logic [LOGN-1:0] pre_index0, pre_index1;
  logic [FRAME_W-1:0] pre_output_frame;

  logic c_front_valid, c_front_tag_valid;
  logic [2*QW-1:0] c_front_pair;
  logic [FRAME_W-1:0] c_front_frame;

  logic core_in_valid, core_out_valid;
  logic [QW-1:0] core_in0, core_in1, core_out0, core_out1;
  logic [1:0] core_in_mode, core_out_mode;
  logic [FRAME_W-1:0] core_in_frame, core_out_frame;
  logic core_frame_done;
  logic [FRAME_W-1:0] core_done_frame;
  logic [LOGN-2:0] core_out_count;
  logic [1:0] core_out_role;
  logic [JOB_W-1:0] core_out_job;
  logic [BANK_W-1:0] core_out_bank;

  logic b_pipe_valid;
  logic [QW-1:0] b_pipe0, b_pipe1;
  logic [FRAME_W-1:0] b_pipe_frame;
  logic [LOGN-2:0] b_pipe_pair;
  logic pointwise_issue_valid;
  logic mul_valid0, mul_valid1, mul_meta_valid;
  logic [QW-1:0] mul_out0, mul_out1;
  logic [MUL_META_W-1:0] delayed_mul_meta;
  logic [FRAME_W-1:0] mul_frame;
  logic [LOGN-2:0] mul_pair;
  logic [JOB_W-1:0] mul_job;
  logic [BANK_W-1:0] mul_bank;

  logic post_issue_valid, post_valid0, post_valid1, post_meta_valid;
  logic [LOGN-1:0] post_addr0, post_addr1;
  logic [QW-1:0] psi_inv0, psi_inv1, post_out0, post_out1;
  logic [POST_META_W-1:0] delayed_post_meta;
  logic [FRAME_W-1:0] post_frame;
  logic [LOGN-2:0] post_pair;
  logic [LOGN-1:0] delayed_post_addr0, delayed_post_addr1;
  logic [JOB_W-1:0] post_job;
  logic [BANK_W-1:0] post_bank;

  batch_frame_scheduler #(
      .N(N), .LOGN(LOGN), .JOB_COUNT(JOB_COUNT),
      .JOB_BUFFERS(JOB_BUFFERS), .JOB_W(JOB_W), .BANK_W(BANK_W)
  ) u_scheduler (
      .clk(clk), .rst_n(rst_n), .start(start),
      .pointwise_done_valid(pointwise_done_valid),
      .pointwise_done_job(pointwise_done_job),
      .pointwise_done_bank(pointwise_done_bank),
      .result_done_valid(result_done_valid),
      .result_done_job(result_done_job),
      .result_done_bank(result_done_bank),
      .frame_valid(sched_frame_valid), .frame_sof(sched_frame_sof),
      .frame_eof(sched_frame_eof), .frame_pair(sched_frame_pair),
      .frame_role(sched_frame_role), .frame_job(sched_frame_job),
      .frame_bank(sched_frame_bank), .frame_context(sched_frame_context),
      .busy(busy), .done(done)
  );

  always_comb begin
    source_wr_addr = source_address(load_job, load_addr[LOGN-2:0]);
    src_a0_we = load_we && !busy && !load_sel && !load_addr[LOGN-1];
    src_a1_we = load_we && !busy && !load_sel && load_addr[LOGN-1];
    src_b0_we = load_we && !busy && load_sel && !load_addr[LOGN-1];
    src_b1_we = load_we && !busy && load_sel && load_addr[LOGN-1];

    source_rd_addr = source_address(sched_frame_job, sched_frame_pair);
    src_a_rd_en = sched_frame_valid && (sched_frame_role == ROLE_A_NTT);
    src_b_rd_en = sched_frame_valid && (sched_frame_role == ROLE_B_NTT);
    c_ntt_rd_en = sched_frame_valid && (sched_frame_role == ROLE_C_INTT);
    c_ntt_rd_addr = context_address(
        sched_frame_bank, bit_reverse_pair(sched_frame_pair)
    );
  end

  batch_sdp_ram #(.DW(QW), .DEPTH(SRC_DEPTH), .AW(SRC_AW)) u_src_a0 (
      .clk(clk), .wr_en(src_a0_we), .wr_addr(source_wr_addr), .wr_data(load_data),
      .rd_en(src_a_rd_en), .rd_addr(source_rd_addr),
      .rd_valid(src_a0_rd_valid), .rd_data(src_a0_rd_data)
  );
  batch_sdp_ram #(.DW(QW), .DEPTH(SRC_DEPTH), .AW(SRC_AW)) u_src_a1 (
      .clk(clk), .wr_en(src_a1_we), .wr_addr(source_wr_addr), .wr_data(load_data),
      .rd_en(src_a_rd_en), .rd_addr(source_rd_addr),
      .rd_valid(src_a1_rd_valid), .rd_data(src_a1_rd_data)
  );
  batch_sdp_ram #(.DW(QW), .DEPTH(SRC_DEPTH), .AW(SRC_AW)) u_src_b0 (
      .clk(clk), .wr_en(src_b0_we), .wr_addr(source_wr_addr), .wr_data(load_data),
      .rd_en(src_b_rd_en), .rd_addr(source_rd_addr),
      .rd_valid(src_b0_rd_valid), .rd_data(src_b0_rd_data)
  );
  batch_sdp_ram #(.DW(QW), .DEPTH(SRC_DEPTH), .AW(SRC_AW)) u_src_b1 (
      .clk(clk), .wr_en(src_b1_we), .wr_addr(source_wr_addr), .wr_data(load_data),
      .rd_en(src_b_rd_en), .rd_addr(source_rd_addr),
      .rd_valid(src_b1_rd_valid), .rd_data(src_b1_rd_data)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      read_desc_valid_q <= 1'b0;
      read_pair_q <= '0;
      read_role_q <= ROLE_A_NTT;
      read_job_q <= '0;
      read_bank_q <= '0;
      read_context_q <= 1'b0;
      result_lane_q <= 1'b0;
    end else begin
      read_desc_valid_q <= sched_frame_valid;
      if (sched_frame_valid) begin
        read_pair_q <= sched_frame_pair;
        read_role_q <= sched_frame_role;
        read_job_q <= sched_frame_job;
        read_bank_q <= sched_frame_bank;
        read_context_q <= sched_frame_context;
      end
      if (result_rd_en)
        result_lane_q <= result_addr[LOGN-1];
    end
  end

  always_comb begin
    read_frame_q = pack_frame(
        read_job_q, read_bank_q, read_role_q, read_context_q
    );
    pre_issue_valid = (src_a0_rd_valid && src_a1_rd_valid) ||
                      (src_b0_rd_valid && src_b1_rd_valid);
    if (read_role_q == ROLE_B_NTT) begin
      pre_data0 = src_b0_rd_data;
      pre_data1 = src_b1_rd_data;
    end else begin
      pre_data0 = src_a0_rd_data;
      pre_data1 = src_a1_rd_data;
    end
    pre_index0 = {1'b0, read_pair_q};
    pre_index1 = {1'b1, read_pair_q};
  end

  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_fwd0 (
      .table_sel(PSI_FWD), .index(pre_index0), .factor(psi_fwd0)
  );
  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_fwd1 (
      .table_sel(PSI_FWD), .index(pre_index1), .factor(psi_fwd1)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_pre_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
      .a(pre_data0), .b(psi_fwd0), .out_valid(pre_valid0), .y(pre_out0)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_PRE_NTT)) u_pre_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
      .a(pre_data1), .b(psi_fwd1), .out_valid(pre_valid1), .y(pre_out1)
  );
  delay_line #(.DW(FRAME_W), .DEPTH(PRE_MUL_LAT)) u_pre_tag_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(pre_issue_valid),
      .din(read_frame_q), .out_valid(pre_tag_valid), .dout(pre_output_frame)
  );

  delay_line #(.DW(2*QW), .DEPTH(PRE_MUL_LAT)) u_c_front_data_delay (
      .clk(clk), .rst_n(rst_n),
      .in_valid(c_ntt0_rd_valid && c_ntt1_rd_valid),
      .din({c_ntt1_rd_data, c_ntt0_rd_data}),
      .out_valid(c_front_valid), .dout(c_front_pair)
  );
  delay_line #(.DW(FRAME_W), .DEPTH(PRE_MUL_LAT)) u_c_front_tag_delay (
      .clk(clk), .rst_n(rst_n),
      .in_valid(c_ntt0_rd_valid && c_ntt1_rd_valid),
      .din(read_frame_q),
      .out_valid(c_front_tag_valid), .dout(c_front_frame)
  );

  always_comb begin
    core_in_valid = 1'b0;
    core_in0 = '0;
    core_in1 = '0;
    core_in_mode = MODE_NTT;
    core_in_frame = '0;
    if (pre_valid0 && pre_valid1 && pre_tag_valid) begin
      core_in_valid = 1'b1;
      core_in0 = pre_out0;
      core_in1 = pre_out1;
      core_in_mode = MODE_NTT;
      core_in_frame = pre_output_frame;
    end else if (c_front_valid && c_front_tag_valid) begin
      core_in_valid = 1'b1;
      core_in0 = c_front_pair[QW-1:0];
      core_in1 = c_front_pair[2*QW-1:QW];
      core_in_mode = MODE_INTT;
      core_in_frame = c_front_frame;
    end
  end

  gs_mdc_core_dualctx #(
      .N(N), .LOGN(LOGN), .QW(QW), .MUL_LAT(MUL_LAT),
      .USE_WL_MONT(USE_WL_CORE),
      .USE_STAGE_LOCAL_TWIDDLE(USE_STAGE_LOCAL_TWIDDLE),
      .TWIDDLE_BRAM_STAGES(TWIDDLE_BRAM_STAGES), .FRAME_W(FRAME_W)
  ) u_core (
      .clk(clk), .rst_n(rst_n),
      .in_valid(core_in_valid), .in_ready(),
      .in0(core_in0), .in1(core_in1),
      .in_mode(core_in_mode), .in_frame(core_in_frame),
      .out_valid(core_out_valid), .out_ready(1'b1),
      .out0(core_out0), .out1(core_out1),
      .out_mode(core_out_mode), .out_frame(core_out_frame),
      .frame_done(core_frame_done), .done_frame(core_done_frame)
  );

  always_comb begin
    core_out_role = core_out_frame[2:1];
    core_out_bank = core_out_frame[2+BANK_W:3];
    core_out_job = core_out_frame[FRAME_W-1:3+BANK_W];
    a_ntt_wr_en = core_out_valid && (core_out_role == ROLE_A_NTT);
    a_ntt_rd_en = core_out_valid && (core_out_role == ROLE_B_NTT);
    a_ntt_wr_addr = context_address(core_out_bank, core_out_count);
    a_ntt_rd_addr = context_address(core_out_bank, core_out_count);
  end

  batch_sdp_ram #(.DW(QW), .DEPTH(CTX_DEPTH), .AW(CTX_AW)) u_a_ntt0 (
      .clk(clk), .wr_en(a_ntt_wr_en), .wr_addr(a_ntt_wr_addr), .wr_data(core_out0),
      .rd_en(a_ntt_rd_en), .rd_addr(a_ntt_rd_addr),
      .rd_valid(a_ntt0_rd_valid), .rd_data(a_ntt0_rd_data)
  );
  batch_sdp_ram #(.DW(QW), .DEPTH(CTX_DEPTH), .AW(CTX_AW)) u_a_ntt1 (
      .clk(clk), .wr_en(a_ntt_wr_en), .wr_addr(a_ntt_wr_addr), .wr_data(core_out1),
      .rd_en(a_ntt_rd_en), .rd_addr(a_ntt_rd_addr),
      .rd_valid(a_ntt1_rd_valid), .rd_data(a_ntt1_rd_data)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      core_out_count <= '0;
      b_pipe_valid <= 1'b0;
      b_pipe0 <= '0;
      b_pipe1 <= '0;
      b_pipe_frame <= '0;
      b_pipe_pair <= '0;
    end else begin
      b_pipe_valid <= a_ntt_rd_en;
      if (a_ntt_rd_en) begin
        b_pipe0 <= core_out0;
        b_pipe1 <= core_out1;
        b_pipe_frame <= core_out_frame;
        b_pipe_pair <= core_out_count;
      end

      if (core_out_valid) begin
        if (core_out_count == PAIRS-1)
          core_out_count <= '0;
        else
          core_out_count <= core_out_count + 1'b1;
      end
    end
  end

  always_comb pointwise_issue_valid =
      b_pipe_valid && a_ntt0_rd_valid && a_ntt1_rd_valid;

  pointwise_mul #(.QW(QW), .USE_WL_POINTWISE(USE_WL_POINTWISE)) u_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(pointwise_issue_valid),
      .a_ntt(a_ntt0_rd_data), .b_ntt(b_pipe0),
      .out_valid(mul_valid0), .c_ntt(mul_out0)
  );
  pointwise_mul #(.QW(QW), .USE_WL_POINTWISE(USE_WL_POINTWISE)) u_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(pointwise_issue_valid),
      .a_ntt(a_ntt1_rd_data), .b_ntt(b_pipe1),
      .out_valid(mul_valid1), .c_ntt(mul_out1)
  );
  delay_line #(.DW(MUL_META_W), .DEPTH(POINTWISE_MUL_LAT)) u_mul_meta_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(pointwise_issue_valid),
      .din({b_pipe_frame, b_pipe_pair}),
      .out_valid(mul_meta_valid), .dout(delayed_mul_meta)
  );

  always_comb begin
    mul_frame = delayed_mul_meta[MUL_META_W-1 -: FRAME_W];
    mul_pair = delayed_mul_meta[LOGN-2:0];
    mul_bank = mul_frame[2+BANK_W:3];
    mul_job = mul_frame[FRAME_W-1:3+BANK_W];
    c_ntt_wr_en = mul_valid0 && mul_valid1 && mul_meta_valid;
    c_ntt_wr_addr = context_address(mul_bank, mul_pair);
    pointwise_done_valid = c_ntt_wr_en && (mul_pair == PAIRS-1);
    pointwise_done_job = mul_job;
    pointwise_done_bank = mul_bank;
  end

  batch_sdp_ram #(.DW(QW), .DEPTH(CTX_DEPTH), .AW(CTX_AW)) u_c_ntt0 (
      .clk(clk), .wr_en(c_ntt_wr_en), .wr_addr(c_ntt_wr_addr), .wr_data(mul_out0),
      .rd_en(c_ntt_rd_en), .rd_addr(c_ntt_rd_addr),
      .rd_valid(c_ntt0_rd_valid), .rd_data(c_ntt0_rd_data)
  );
  batch_sdp_ram #(.DW(QW), .DEPTH(CTX_DEPTH), .AW(CTX_AW)) u_c_ntt1 (
      .clk(clk), .wr_en(c_ntt_wr_en), .wr_addr(c_ntt_wr_addr), .wr_data(mul_out1),
      .rd_en(c_ntt_rd_en), .rd_addr(c_ntt_rd_addr),
      .rd_valid(c_ntt1_rd_valid), .rd_data(c_ntt1_rd_data)
  );

  always_comb begin
    post_issue_valid = core_out_valid && (core_out_role == ROLE_C_INTT);
    post_addr0 = bit_reverse({core_out_count, 1'b0});
    post_addr1 = bit_reverse({core_out_count, 1'b1});
  end

  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_inv0 (
      .table_sel(PSI_INV), .index(post_addr0), .factor(psi_inv0)
  );
  psi_rom #(.QW(QW), .LOGN(LOGN), .N(N)) u_psi_inv1 (
      .table_sel(PSI_INV), .index(post_addr1), .factor(psi_inv1)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_POST_INTT)) u_post_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(post_issue_valid),
      .a(core_out0), .b(psi_inv0), .out_valid(post_valid0), .y(post_out0)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_POST_INTT)) u_post_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(post_issue_valid),
      .a(core_out1), .b(psi_inv1), .out_valid(post_valid1), .y(post_out1)
  );
  delay_line #(.DW(POST_META_W), .DEPTH(POST_MUL_LAT)) u_post_meta_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(post_issue_valid),
      .din({core_out_frame, core_out_count, post_addr1, post_addr0}),
      .out_valid(post_meta_valid), .dout(delayed_post_meta)
  );

  always_comb begin
    post_frame = delayed_post_meta[POST_META_W-1 -: FRAME_W];
    post_pair = delayed_post_meta[3*LOGN-2 -: LOGN-1];
    delayed_post_addr1 = delayed_post_meta[2*LOGN-1 -: LOGN];
    delayed_post_addr0 = delayed_post_meta[LOGN-1:0];
    post_bank = post_frame[2+BANK_W:3];
    post_job = post_frame[FRAME_W-1:3+BANK_W];
    result_wr_en = post_valid0 && post_valid1 && post_meta_valid;
    result_wr_addr0 = result_address(
        post_job, delayed_post_addr0[LOGN-2:0]
    );
    result_wr_addr1 = result_address(
        post_job, delayed_post_addr1[LOGN-2:0]
    );
    result_done_valid = result_wr_en && (post_pair == PAIRS-1);
    result_done_job = post_job;
    result_done_bank = post_bank;
  end

  always_comb begin
    result_rd_addr_flat = result_address(
        result_job, result_addr[LOGN-2:0]
    );
    result_rd_valid = result0_rd_valid || result1_rd_valid;
    result_data = result_lane_q ? result1_rd_data : result0_rd_data;
  end

  batch_sdp_ram #(.DW(QW), .DEPTH(RES_DEPTH), .AW(RES_AW)) u_result0 (
      .clk(clk), .wr_en(result_wr_en), .wr_addr(result_wr_addr0),
      .wr_data(post_out0),
      .rd_en(result_rd_en && !result_addr[LOGN-1]),
      .rd_addr(result_rd_addr_flat),
      .rd_valid(result0_rd_valid), .rd_data(result0_rd_data)
  );
  batch_sdp_ram #(.DW(QW), .DEPTH(RES_DEPTH), .AW(RES_AW)) u_result1 (
      .clk(clk), .wr_en(result_wr_en), .wr_addr(result_wr_addr1),
      .wr_data(post_out1),
      .rd_en(result_rd_en && result_addr[LOGN-1]),
      .rd_addr(result_rd_addr_flat),
      .rd_valid(result1_rd_valid), .rd_data(result1_rd_data)
  );

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && load_we && busy)
      $fatal(1, "batch source memory cannot be loaded while busy");
    if (rst_n && load_we && (load_job >= JOB_COUNT))
      $fatal(1, "batch load job index out of range");
    if (rst_n && ((src_a0_rd_valid != src_a1_rd_valid) ||
                  (src_b0_rd_valid != src_b1_rd_valid)))
      $fatal(1, "source BRAM lane valid mismatch");
    if (rst_n && pre_issue_valid && !read_desc_valid_q)
      $fatal(1, "source data lost its frame descriptor");
    if (rst_n && ((pre_valid0 != pre_valid1) ||
                  (pre_valid0 != pre_tag_valid)))
      $fatal(1, "Pre_NTT data/tag latency mismatch");
    if (rst_n && ((c_front_valid != c_front_tag_valid) ||
                  (c_ntt0_rd_valid != c_ntt1_rd_valid)))
      $fatal(1, "C_INTT BRAM data/tag latency mismatch");
    if (rst_n && pre_valid0 && c_front_valid)
      $fatal(1, "two scheduled frames overlap at the core input");
    if (rst_n && ((a_ntt0_rd_valid != a_ntt1_rd_valid) ||
                  (a_ntt0_rd_valid != b_pipe_valid)))
      $fatal(1, "A_NTT BRAM read and B output lost alignment");
    if (rst_n && ((mul_valid0 != mul_valid1) ||
                  (mul_valid0 != mul_meta_valid)))
      $fatal(1, "pointwise data/tag latency mismatch");
    if (rst_n && ((post_valid0 != post_valid1) ||
                  (post_valid0 != post_meta_valid)))
      $fatal(1, "Post_INTT data/tag latency mismatch");
  end
`endif

  logic unused_sched_sof, unused_sched_eof, unused_core_frame_done;
  logic [FRAME_W-1:0] unused_core_done_frame;
  always_comb begin
    unused_sched_sof = sched_frame_sof;
    unused_sched_eof = sched_frame_eof;
    unused_core_frame_done = core_frame_done;
    unused_core_done_frame = core_done_frame;
  end
endmodule