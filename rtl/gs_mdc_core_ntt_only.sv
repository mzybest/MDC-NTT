// Forward-only 12-stage, two-lane GS-MDC core.
//
// This is the second transform engine in the asymmetric dual-forward top. It
// deliberately omits the two final N^-1 Montgomery multipliers and uses an
// independent NTT-only stage-local twiddle image.
module gs_mdc_core_ntt_only #(
    parameter int N       = 4096,
    parameter int LOGN    = 12,
    parameter int QW      = 64,
    parameter int MUL_LAT = 14,
    parameter bit USE_WL_MONT = 1'b1,
    parameter bit BYPASS_FINAL_UNIT_TWIDDLE = 1'b0,
    parameter logic [LOGN-1:0] BFU_BOUNDARY_PIPE_MASK = '0,
    parameter int TWIDDLE_BRAM_STAGES = 4
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          start,
    input  logic          in_valid,
    output logic          in_ready,
    input  logic [QW-1:0] in0,
    input  logic [QW-1:0] in1,
    output logic          out_valid,
    input  logic          out_ready,
    output logic [QW-1:0] out0,
    output logic [QW-1:0] out1,
    output logic          done
);
  import params_pkg::*;

  logic [LOGN:0] stage_valid;
  logic [QW-1:0] stage_data0 [0:LOGN];
  logic [QW-1:0] stage_data1 [0:LOGN];
  logic [LOGN-2:0] output_count;
  logic delay_valid;
  logic [2*QW-1:0] delayed_pair;
  genvar s;

  function automatic integer stage_depth(input integer sid);
    if (sid == LOGN-1) stage_depth = 0;
    else stage_depth = 1 << (LOGN-sid-2);
  endfunction

  always_comb begin
    stage_valid[0] = in_valid;
    stage_data0[0] = in0;
    stage_data1[0] = in1;
    in_ready = 1'b1;
  end

  generate
    for (s = 0; s < LOGN; s = s + 1) begin : g_stage
      mdc_stage #(
          .STAGE_ID(s), .QW(QW), .DEPTH(stage_depth(s)),
          .MUL_LAT(MUL_LAT), .USE_WL_MONT(USE_WL_MONT),
          .USE_BFU_BOUNDARY_PIPE(BFU_BOUNDARY_PIPE_MASK[s]),
          .BYPASS_TWIDDLE_MUL(BYPASS_FINAL_UNIT_TWIDDLE && (s == LOGN-1)),
          .USE_STAGE_LOCAL_TWIDDLE(1'b1),
          .USE_NTT_ONLY_TWIDDLE(1'b1),
          .TWIDDLE_BRAM_STAGES(TWIDDLE_BRAM_STAGES),
          .LOGN(LOGN), .N(N)
      ) u_stage (
          .clk(clk), .rst_n(rst_n), .mode(MODE_NTT),
          .in_valid(stage_valid[s]), .in0(stage_data0[s]), .in1(stage_data1[s]),
          .twiddle(R_MOD_Q), .out_valid(stage_valid[s+1]),
          .out0(stage_data0[s+1]), .out1(stage_data1[s+1])
      );
    end
  endgenerate

  delay_line #(.DW(2*QW), .DEPTH(MUL_LAT)) u_ntt_output_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(stage_valid[LOGN]),
      .din({stage_data1[LOGN], stage_data0[LOGN]}),
      .out_valid(delay_valid), .dout(delayed_pair)
  );

  always_comb begin
    out_valid = delay_valid;
    out0 = delayed_pair[QW-1:0];
    out1 = delayed_pair[2*QW-1:QW];
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      output_count <= '0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start)
        output_count <= '0;
      if (out_valid) begin
        if (output_count == N/2-1) begin
          output_count <= '0;
          done <= 1'b1;
        end else begin
          output_count <= output_count + 1'b1;
        end
      end
    end
  end

  logic unused_out_ready;
  always_comb unused_out_ready = out_ready;
endmodule
