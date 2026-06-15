// Two-path radix-2 GS-MDC stage.
//
// Stage boundary:
//   current stage input -> GS butterfly -> two-FIFO/C2 reorder -> next stage
//
// DEPTH is the output reorder delay required by the next stage. For N=4096:
//   stage 0..11 DEPTH = 1024,512,256,128,64,32,16,8,4,2,1,0.
//
// The top-level lower/upper-half banks already pair stage-0 butterfly inputs,
// so there is no FIFO before stage 0. Its DEPTH=1024 FIFOs are after the BFU
// and arrange stage-0 U/V results into the pairs required by stage 1.
module mdc_stage #(
    parameter int STAGE_ID = 0,
    parameter int QW       = 64,
    parameter int DEPTH    = 1024,
    parameter int MUL_LAT  = 9,
    parameter int LOGN     = 12,
    parameter int N        = 4096
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic [1:0]    mode,
    input  logic          in_valid,
    input  logic [QW-1:0] in0,
    input  logic [QW-1:0] in1,
    input  logic [QW-1:0] twiddle,
    output logic          out_valid,
    output logic [QW-1:0] out0,
    output logic [QW-1:0] out1
);
  localparam int PAIRS = N / 2;
  localparam int BF_DISTANCE = 1 << (LOGN - STAGE_ID - 1);

  logic [LOGN-2:0] bf_count;
  logic [LOGN-1:0] twiddle_index;
  logic [QW-1:0] stage_twiddle;
  logic bf_valid;
  logic [QW-1:0] bf_u;
  logic [QW-1:0] bf_v;

  // The butterfly input stream is already paired by the previous stage's
  // reorder network. The counter only selects this stage's twiddle sequence.
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

  always_comb twiddle_index = bf_count % BF_DISTANCE;

  twiddle_rom #(.QW(QW), .LOGN(LOGN)) u_twiddle_rom (
      .clk(clk), .mode(mode), .stage_id(STAGE_ID[3:0]),
      .index(twiddle_index), .twiddle(stage_twiddle)
  );
  gs_butterfly #(.QW(QW), .MUL_LAT(MUL_LAT)) u_butterfly (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
      .a(in0), .b(in1), .twiddle(stage_twiddle),
      .out_valid(bf_valid), .y0(bf_u), .y1(bf_v)
  );

  generate
    if (DEPTH == 0) begin : g_no_reorder
      // The final stage has no following butterfly pairing to prepare.
      always_comb begin
        out_valid = bf_valid;
        out0 = bf_u;
        out1 = bf_v;
      end
    end else begin : g_output_reorder
      // FIFO_A delays V before C2. FIFO_B delays either U-first or the
      // delayed V-first selected by C2. Both delays are exactly DEPTH cycles.
      logic [LOGN-2:0] reorder_count;
      logic [LOGN-2:0] flush_count;
      logic flushing;
      logic phase;
      logic delay_in_valid;
      logic [QW-1:0] fifo_a_din;
      logic [QW-1:0] fifo_a_dout;
      logic [QW-1:0] fifo_b_din;
      logic [QW-1:0] fifo_b_dout;

      always_comb begin
        phase = (reorder_count / DEPTH) & 1'b1;
        delay_in_valid = bf_valid | flushing;
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

        if (flushing) begin
          // Drain the final V-first/V-second pair after BFU input ends.
          out_valid = 1'b1;
          out0 = fifo_b_dout;
          out1 = fifo_a_dout;
        end else if (bf_valid && phase) begin
          // Second D cycles: delayed U-first pairs with current U-second.
          out_valid = 1'b1;
          out0 = fifo_b_dout;
          out1 = bf_u;
        end else if (bf_valid && !phase && (reorder_count >= 2*DEPTH)) begin
          // Following phase-0 cycles: emit the previous V pair while the
          // current U/V first halves enter the delay memories.
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
        end else if (flushing) begin
          if (flush_count == DEPTH-1) begin
            flush_count <= '0;
            flushing <= 1'b0;
          end else begin
            flush_count <= flush_count + 1'b1;
          end
        end else if (bf_valid) begin
          if (reorder_count == PAIRS-1) begin
            reorder_count <= '0;
            flush_count <= '0;
            flushing <= 1'b1;
          end else begin
            reorder_count <= reorder_count + 1'b1;
          end
        end
      end
    end
  endgenerate

  logic [QW-1:0] unused_twiddle;
  always_comb unused_twiddle = twiddle;
endmodule
