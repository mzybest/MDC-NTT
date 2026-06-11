// Reusable 12-stage, 2-lane GS NTT/INTT core.
// Data at this interface is Montgomery-domain. Backpressure is intentionally
// not implemented in this first version; keep out_ready asserted.
module gs_mdc_core #(
    parameter int N       = 4096,
    parameter int LOGN    = 12,
    parameter int QW      = 64,
    parameter int MUL_LAT = 3
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          start,
    input  logic [1:0]    mode,
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
  logic [1:0] active_mode;
  logic [LOGN-2:0] output_count;
  logic scale_valid0, scale_valid1;
  logic [QW-1:0] scaled0, scaled1;
  logic delay_valid;
  logic [2*QW-1:0] delayed_pair;
  genvar s;

  function automatic integer stage_depth(input integer sid);
    // DEPTH belongs to the reorder network after the current stage BFU.
    // Stage 0 input is delay-free, but its output still needs D=N/4 to form
    // stage 1 pairs. The final stage has no following reorder requirement.
    if (sid == LOGN-1) stage_depth = 0;
    else stage_depth = 1 << (LOGN-sid-2);
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) active_mode <= '0;
    else if (start) active_mode <= mode;
  end

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
          .MUL_LAT(MUL_LAT), .LOGN(LOGN), .N(N)
      ) u_stage (
          .clk(clk), .rst_n(rst_n), .mode(active_mode),
          .in_valid(stage_valid[s]), .in0(stage_data0[s]), .in1(stage_data1[s]),
          .twiddle(R_MOD_Q), .out_valid(stage_valid[s+1]),
          .out0(stage_data0[s+1]), .out1(stage_data1[s+1])
      );
    end
  endgenerate

  mont_mul #(.QW(QW)) u_intt_scale0 (
      .clk(clk), .rst_n(rst_n), .in_valid(stage_valid[LOGN]),
      .a(stage_data0[LOGN]), .b(N_INV_MONT),
      .out_valid(scale_valid0), .y(scaled0)
  );
  mont_mul #(.QW(QW)) u_intt_scale1 (
      .clk(clk), .rst_n(rst_n), .in_valid(stage_valid[LOGN]),
      .a(stage_data1[LOGN]), .b(N_INV_MONT),
      .out_valid(scale_valid1), .y(scaled1)
  );
  delay_line #(.DW(2*QW), .DEPTH(MUL_LAT)) u_ntt_output_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(stage_valid[LOGN]),
      .din({stage_data1[LOGN], stage_data0[LOGN]}),
      .out_valid(delay_valid), .dout(delayed_pair)
  );

  always_comb begin
    if (active_mode == MODE_INTT) begin
      out_valid = scale_valid0 & scale_valid1;
      out0 = scaled0;
      out1 = scaled1;
    end else begin
      out_valid = delay_valid;
      out0 = delayed_pair[QW-1:0];
      out1 = delayed_pair[2*QW-1:QW];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      output_count <= '0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start) output_count <= '0;
      if (out_valid) begin
        if (output_count == N/2-1) begin
          output_count <= '0;
          done <= 1'b1;
        end else output_count <= output_count + 1'b1;
      end
    end
  end

  logic unused_out_ready;
  always_comb unused_out_ready = out_ready;
endmodule
