// Mode-tagged dual-context wrapper around the 12-stage GS-MDC pipeline.
// Transform frames may enter every N/2 valid cycles; frame_id[0] selects the
// per-stage reorder context while the full frame_id and mode travel end-to-end.
module gs_mdc_core_dualctx #(
    parameter int N = 4096,
    parameter int LOGN = 12,
    parameter int QW = 64,
    parameter int MUL_LAT = 14,
    parameter bit USE_WL_MONT = 1'b1,
    parameter bit USE_STAGE_LOCAL_TWIDDLE = 1'b1,
    parameter int TWIDDLE_BRAM_STAGES = 4,
    parameter int FRAME_W = 2
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    output logic               in_ready,
    input  logic [QW-1:0]      in0,
    input  logic [QW-1:0]      in1,
    input  logic [1:0]         in_mode,
    input  logic [FRAME_W-1:0] in_frame,
    output logic               out_valid,
    input  logic               out_ready,
    output logic [QW-1:0]      out0,
    output logic [QW-1:0]      out1,
    output logic [1:0]         out_mode,
    output logic [FRAME_W-1:0] out_frame,
    output logic               frame_done,
    output logic [FRAME_W-1:0] done_frame
);
  import params_pkg::*;
  localparam int META_W = FRAME_W + 2;

  logic [LOGN:0] stage_valid;
  logic [QW-1:0] stage_data0 [0:LOGN];
  logic [QW-1:0] stage_data1 [0:LOGN];
  logic [1:0] stage_mode [0:LOGN];
  logic [FRAME_W-1:0] stage_frame [0:LOGN];
  logic [LOGN-2:0] output_count;
  logic scale_valid0, scale_valid1;
  logic [QW-1:0] scaled0, scaled1;
  logic delay_valid;
  logic [2*QW-1:0] delayed_pair;
  logic meta_valid;
  logic [META_W-1:0] delayed_meta;
  genvar s;

  function automatic integer stage_depth(input integer sid);
    if (sid == LOGN-1) stage_depth = 0;
    else stage_depth = 1 << (LOGN-sid-2);
  endfunction

  always_comb begin
    stage_valid[0] = in_valid;
    stage_data0[0] = in0;
    stage_data1[0] = in1;
    stage_mode[0] = in_mode;
    stage_frame[0] = in_frame;
    in_ready = 1'b1;
  end

  generate
    for (s = 0; s < LOGN; s = s + 1) begin : g_stage
      mdc_stage_dualctx #(
          .STAGE_ID(s), .QW(QW), .DEPTH(stage_depth(s)),
          .MUL_LAT(MUL_LAT), .USE_WL_MONT(USE_WL_MONT),
          .USE_STAGE_LOCAL_TWIDDLE(USE_STAGE_LOCAL_TWIDDLE),
          .TWIDDLE_BRAM_STAGES(TWIDDLE_BRAM_STAGES),
          .LOGN(LOGN), .N(N), .FRAME_W(FRAME_W)
      ) u_stage (
          .clk(clk), .rst_n(rst_n),
          .in_valid(stage_valid[s]),
          .in0(stage_data0[s]), .in1(stage_data1[s]),
          .in_mode(stage_mode[s]), .in_frame(stage_frame[s]),
          .twiddle(R_MOD_Q),
          .out_valid(stage_valid[s+1]),
          .out0(stage_data0[s+1]), .out1(stage_data1[s+1]),
          .out_mode(stage_mode[s+1]), .out_frame(stage_frame[s+1])
      );
    end
  endgenerate

  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_MONT)) u_intt_scale0 (
      .clk(clk), .rst_n(rst_n), .in_valid(stage_valid[LOGN]),
      .a(stage_data0[LOGN]), .b(N_INV_MONT),
      .out_valid(scale_valid0), .y(scaled0)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_MONT)) u_intt_scale1 (
      .clk(clk), .rst_n(rst_n), .in_valid(stage_valid[LOGN]),
      .a(stage_data1[LOGN]), .b(N_INV_MONT),
      .out_valid(scale_valid1), .y(scaled1)
  );
  delay_line #(.DW(2*QW), .DEPTH(MUL_LAT)) u_ntt_output_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(stage_valid[LOGN]),
      .din({stage_data1[LOGN], stage_data0[LOGN]}),
      .out_valid(delay_valid), .dout(delayed_pair)
  );
  delay_line #(.DW(META_W), .DEPTH(MUL_LAT)) u_output_meta_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(stage_valid[LOGN]),
      .din({stage_mode[LOGN], stage_frame[LOGN]}),
      .out_valid(meta_valid), .dout(delayed_meta)
  );

  always_comb begin
    out_mode = delayed_meta[META_W-1 -: 2];
    out_frame = delayed_meta[FRAME_W-1:0];
    if (out_mode == MODE_INTT) begin
      out_valid = meta_valid & scale_valid0 & scale_valid1;
      out0 = scaled0;
      out1 = scaled1;
    end else begin
      out_valid = meta_valid & delay_valid;
      out0 = delayed_pair[QW-1:0];
      out1 = delayed_pair[2*QW-1:QW];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      output_count <= '0;
      frame_done <= 1'b0;
      done_frame <= '0;
    end else begin
      frame_done <= 1'b0;
      if (out_valid) begin
        if (output_count == N/2-1) begin
          output_count <= '0;
          frame_done <= 1'b1;
          done_frame <= out_frame;
        end else begin
          output_count <= output_count + 1'b1;
        end
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && stage_valid[LOGN] && (scale_valid0 != scale_valid1))
      $fatal(1, "INTT scale lanes lost valid alignment");
    if (rst_n && (meta_valid != delay_valid))
      $fatal(1, "final metadata and NTT delay are misaligned");
  end
`endif

  logic unused_out_ready;
  always_comb unused_out_ready = out_ready;
endmodule
