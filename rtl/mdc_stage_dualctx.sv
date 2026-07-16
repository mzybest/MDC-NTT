// Mode-tagged, dual-context two-path radix-2 GS-MDC stage.
//
// The BFU and twiddle ROM are shared. Only the post-BFU C2/delay state is
// duplicated, allowing frame k to flush while frame k+1 enters the BFU.
module mdc_stage_dualctx #(
    parameter int STAGE_ID = 0,
    parameter int QW = 64,
    parameter int DEPTH = 1024,
    parameter int MUL_LAT = 14,
    parameter bit USE_WL_MONT = 1'b1,
    parameter bit USE_STAGE_LOCAL_TWIDDLE = 1'b1,
    parameter int TWIDDLE_BRAM_STAGES = 4,
    parameter int LOGN = 12,
    parameter int N = 4096,
    parameter int FRAME_W = 2
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic [QW-1:0]      in0,
    input  logic [QW-1:0]      in1,
    input  logic [1:0]         in_mode,
    input  logic [FRAME_W-1:0] in_frame,
    input  logic [QW-1:0]      twiddle,
    output logic               out_valid,
    output logic [QW-1:0]      out0,
    output logic [QW-1:0]      out1,
    output logic [1:0]         out_mode,
    output logic [FRAME_W-1:0] out_frame
);
  localparam int PAIRS = N / 2;
  localparam int BF_DISTANCE = 1 << (LOGN - STAGE_ID - 1);
  localparam int BF_LAT = MUL_LAT + 1;
  localparam int META_W = FRAME_W + 2;

  logic [LOGN-2:0] bf_count;
  logic [LOGN-1:0] twiddle_index;
  logic [LOGN-1:0] twiddle_prefetch_index;
  logic [QW-1:0] stage_twiddle;
  logic bf_valid;
  logic [QW-1:0] bf_u;
  logic [QW-1:0] bf_v;
  logic meta_valid;
  logic [META_W-1:0] bf_meta;
  logic [1:0] bf_mode;
  logic [FRAME_W-1:0] bf_frame;

  always_ff @(posedge clk) begin
    if (!rst_n)
      bf_count <= '0;
    else if (in_valid) begin
      if (bf_count == PAIRS-1)
        bf_count <= '0;
      else
        bf_count <= bf_count + 1'b1;
    end
  end

  always_comb begin
    twiddle_index = bf_count % BF_DISTANCE;
    if (!in_valid)
      twiddle_prefetch_index = twiddle_index;
    else if (bf_count == PAIRS-1)
      twiddle_prefetch_index = '0;
    else
      twiddle_prefetch_index = (bf_count + 1'b1) % BF_DISTANCE;
  end

  generate
    if (USE_STAGE_LOCAL_TWIDDLE) begin : g_stage_local_twiddle
      twiddle_rom_stage #(
          .STAGE_ID(STAGE_ID), .QW(QW), .LOGN(LOGN),
          .BRAM_STAGES(TWIDDLE_BRAM_STAGES)
      ) u_twiddle_rom (
          .clk(clk), .rst_n(rst_n), .mode(in_mode),
          .index(twiddle_index[LOGN-2:0]),
          .prefetch_index(twiddle_prefetch_index[LOGN-2:0]),
          .twiddle(stage_twiddle)
      );
    end else begin : g_legacy_twiddle
      twiddle_rom #(.QW(QW), .LOGN(LOGN)) u_twiddle_rom (
          .clk(clk), .mode(in_mode), .stage_id(STAGE_ID[3:0]),
          .index(twiddle_index), .twiddle(stage_twiddle)
      );
    end
  endgenerate

  gs_butterfly #(
      .QW(QW), .MUL_LAT(MUL_LAT), .USE_WL_MONT(USE_WL_MONT)
  ) u_butterfly (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
      .a(in0), .b(in1), .twiddle(stage_twiddle),
      .out_valid(bf_valid), .y0(bf_u), .y1(bf_v)
  );

  delay_line #(.DW(META_W), .DEPTH(BF_LAT)) u_bf_meta_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
      .din({in_mode, in_frame}), .out_valid(meta_valid), .dout(bf_meta)
  );
  always_comb begin
    bf_mode = bf_meta[META_W-1 -: 2];
    bf_frame = bf_meta[FRAME_W-1:0];
  end

  generate
    if (DEPTH == 0) begin : g_no_reorder
      always_comb begin
        out_valid = bf_valid & meta_valid;
        out0 = bf_u;
        out1 = bf_v;
        out_mode = bf_mode;
        out_frame = bf_frame;
      end
    end else begin : g_output_reorder
      logic ctx0_valid, ctx1_valid;
      logic [QW-1:0] ctx0_out0, ctx0_out1;
      logic [QW-1:0] ctx1_out0, ctx1_out1;
      logic [1:0] ctx0_mode, ctx1_mode;
      logic [FRAME_W-1:0] ctx0_frame, ctx1_frame;

      mdc_reorder_context #(
          .QW(QW), .DEPTH(DEPTH), .PAIRS(PAIRS), .FRAME_W(FRAME_W)
      ) u_context0 (
          .clk(clk), .rst_n(rst_n),
          .in_valid(bf_valid && meta_valid && !bf_frame[0]),
          .bf_u(bf_u), .bf_v(bf_v), .in_mode(bf_mode), .in_frame(bf_frame),
          .out_valid(ctx0_valid), .out0(ctx0_out0), .out1(ctx0_out1),
          .out_mode(ctx0_mode), .out_frame(ctx0_frame)
      );
      mdc_reorder_context #(
          .QW(QW), .DEPTH(DEPTH), .PAIRS(PAIRS), .FRAME_W(FRAME_W)
      ) u_context1 (
          .clk(clk), .rst_n(rst_n),
          .in_valid(bf_valid && meta_valid && bf_frame[0]),
          .bf_u(bf_u), .bf_v(bf_v), .in_mode(bf_mode), .in_frame(bf_frame),
          .out_valid(ctx1_valid), .out0(ctx1_out0), .out1(ctx1_out1),
          .out_mode(ctx1_mode), .out_frame(ctx1_frame)
      );

      always_comb begin
        out_valid = ctx0_valid | ctx1_valid;
        out0 = '0;
        out1 = '0;
        out_mode = '0;
        out_frame = '0;
        if (ctx0_valid) begin
          out0 = ctx0_out0;
          out1 = ctx0_out1;
          out_mode = ctx0_mode;
          out_frame = ctx0_frame;
        end else if (ctx1_valid) begin
          out0 = ctx1_out0;
          out1 = ctx1_out1;
          out_mode = ctx1_mode;
          out_frame = ctx1_frame;
        end
      end

`ifndef SYNTHESIS
      always_ff @(posedge clk) begin
        if (rst_n && ctx0_valid && ctx1_valid)
          $fatal(1, "dual-context stage %0d has two outputs in one cycle", STAGE_ID);
      end
`endif
    end
  endgenerate

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && (bf_valid != meta_valid))
      $fatal(1, "BFU metadata latency mismatch at stage %0d", STAGE_ID);
  end
`endif

  logic [QW-1:0] unused_twiddle;
  always_comb unused_twiddle = twiddle;
endmodule
