// One independently drainable post-BFU reorder context.
//
// Two instances let one transform frame flush its delayed V data while the
// other accepts the next frame's BFU outputs. The butterfly itself remains
// shared and accepts one two-lane pair per cycle.
module mdc_reorder_context #(
    parameter int QW = 64,
    parameter int DEPTH = 1024,
    parameter int PAIRS = 2048,
    parameter int FRAME_W = 2
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic [QW-1:0]      bf_u,
    input  logic [QW-1:0]      bf_v,
    input  logic [1:0]         in_mode,
    input  logic [FRAME_W-1:0] in_frame,
    output logic               out_valid,
    output logic [QW-1:0]      out0,
    output logic [QW-1:0]      out1,
    output logic [1:0]         out_mode,
    output logic [FRAME_W-1:0] out_frame
);
  localparam int COUNT_W = (PAIRS <= 1) ? 1 : $clog2(PAIRS);

  logic [COUNT_W-1:0] reorder_count;
  logic [COUNT_W-1:0] flush_count;
  logic flushing;
  logic phase;
  logic delay_in_valid;
  logic [QW-1:0] fifo_a_din;
  logic [QW-1:0] fifo_a_dout;
  logic [QW-1:0] fifo_b_din;
  logic [QW-1:0] fifo_b_dout;
  logic [1:0] frame_mode;
  logic [FRAME_W-1:0] frame_id;

  always_comb begin
    phase = (reorder_count / DEPTH) & 1'b1;
    delay_in_valid = in_valid | flushing;
    fifo_a_din = flushing ? '0 : bf_v;
    if (flushing)
      fifo_b_din = '0;
    else if (phase)
      fifo_b_din = fifo_a_dout;
    else
      fifo_b_din = bf_u;

    out_valid = 1'b0;
    out0 = '0;
    out1 = '0;
    out_mode = frame_mode;
    out_frame = frame_id;

    if (flushing) begin
      out_valid = 1'b1;
      out0 = fifo_b_dout;
      out1 = fifo_a_dout;
    end else if (in_valid && phase) begin
      out_valid = 1'b1;
      out0 = fifo_b_dout;
      out1 = bf_u;
    end else if (in_valid && !phase && (reorder_count >= 2*DEPTH)) begin
      out_valid = 1'b1;
      out0 = fifo_b_dout;
      out1 = fifo_a_dout;
    end
  end

  delay_memory #(.DW(QW), .DEPTH(DEPTH)) fifo_a_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(delay_in_valid),
      .din(fifo_a_din), .out_valid(), .dout(fifo_a_dout)
  );
  delay_memory #(.DW(QW), .DEPTH(DEPTH)) fifo_b_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(delay_in_valid),
      .din(fifo_b_din), .out_valid(), .dout(fifo_b_dout)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      reorder_count <= '0;
      flush_count <= '0;
      flushing <= 1'b0;
      frame_mode <= '0;
      frame_id <= '0;
    end else if (flushing) begin
      if (flush_count == DEPTH-1) begin
        flush_count <= '0;
        flushing <= 1'b0;
      end else begin
        flush_count <= flush_count + 1'b1;
      end
    end else if (in_valid) begin
      if (reorder_count == 0) begin
        frame_mode <= in_mode;
        frame_id <= in_frame;
      end
      if (reorder_count == PAIRS-1) begin
        reorder_count <= '0;
        flush_count <= '0;
        flushing <= 1'b1;
      end else begin
        reorder_count <= reorder_count + 1'b1;
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && in_valid && flushing)
      $fatal(1, "dual-context reorder bank reused before flush completed");
    if (rst_n && in_valid && (reorder_count != 0) &&
        ((in_mode != frame_mode) || (in_frame != frame_id)))
      $fatal(1, "mode/frame tag changed within one transform frame");
  end
`endif
endmodule
