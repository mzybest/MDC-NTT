`timescale 1ns/1ps
module tb_gs_mdc_core_dualctx;
  import params_pkg::*;

  localparam int FRAME_W = 2;
  localparam int FRAMES = 4;
  localparam int PAIRS = N/2;

  logic clk = 0;
  logic rst_n = 0;
  logic in_valid = 0;
  logic in_ready;
  logic [QW-1:0] in0, in1;
  logic [1:0] in_mode;
  logic [FRAME_W-1:0] in_frame;
  logic out_valid;
  logic out_ready = 1;
  logic [QW-1:0] out0, out1;
  logic [1:0] out_mode;
  logic [FRAME_W-1:0] out_frame;
  logic frame_done;
  logic [FRAME_W-1:0] done_frame;

  logic [QW-1:0] input_mem [0:N-1];
  logic [QW-1:0] golden_ntt [0:N-1];

  integer cycle;
  integer errors;
  integer received [0:FRAMES-1];
  integer first_out_cycle [0:FRAMES-1];
  integer last_out_cycle [0:FRAMES-1];
  integer done_count;
  integer total_received;
  logic output_started;

  always #5 clk = ~clk;

  gs_mdc_core_dualctx #(.FRAME_W(FRAME_W)) u_dut (
      .clk(clk), .rst_n(rst_n),
      .in_valid(in_valid), .in_ready(in_ready),
      .in0(in0), .in1(in1), .in_mode(in_mode), .in_frame(in_frame),
      .out_valid(out_valid), .out_ready(out_ready),
      .out0(out0), .out1(out1), .out_mode(out_mode), .out_frame(out_frame),
      .frame_done(frame_done), .done_frame(done_frame)
  );

  function automatic logic [LOGN-1:0] bit_reverse(input logic [LOGN-1:0] v);
    integer i;
    for (i = 0; i < LOGN; i = i + 1)
      bit_reverse[i] = v[LOGN-1-i];
  endfunction

  task automatic drive_frame(
      input integer frame_number,
      input logic [1:0] frame_mode
  );
    integer sent;
    logic [LOGN-1:0] addr0;
    logic [LOGN-1:0] addr1;
    begin
      for (sent = 0; sent < PAIRS; sent = sent + 1) begin
        in_valid = 1'b1;
        in_frame = frame_number;
        in_mode = frame_mode;
        if (frame_mode == MODE_NTT) begin
          in0 = input_mem[sent];
          in1 = input_mem[sent + PAIRS];
        end else begin
          addr0 = bit_reverse({1'b0, sent[LOGN-2:0]});
          addr1 = bit_reverse({1'b1, sent[LOGN-2:0]});
          in0 = golden_ntt[2*addr0[LOGN-1:1]];
          in1 = golden_ntt[2*addr1[LOGN-1:1] + 1];
        end
        @(negedge clk);
      end
    end
  endtask

  initial begin
    integer i;
    $readmemh("mem/input_a.mem", input_mem);
    $readmemh("mem/golden_ntt_a.mem", golden_ntt);
    for (i = 0; i < FRAMES; i = i + 1) begin
      received[i] = 0;
      first_out_cycle[i] = -1;
      last_out_cycle[i] = -1;
    end
    errors = 0;
    done_count = 0;
    total_received = 0;
    output_started = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    // Four continuous frames exercise both context banks twice and switch mode
    // at every boundary while older frames remain in later pipeline stages.
    drive_frame(0, MODE_NTT);
    drive_frame(1, MODE_INTT);
    drive_frame(2, MODE_NTT);
    drive_frame(3, MODE_INTT);
    in_valid = 1'b0;
    in0 = '0;
    in1 = '0;
    in_mode = MODE_NTT;
    in_frame = '0;

    wait (done_count == FRAMES);
    repeat (5) @(posedge clk);

    for (i = 0; i < FRAMES; i = i + 1) begin
      if (received[i] != PAIRS) begin
        $display("frame %0d output count %0d expected %0d",
                 i, received[i], PAIRS);
        errors = errors + 1;
      end
      if (i > 0 && first_out_cycle[i] != last_out_cycle[i-1] + 1) begin
        $display("frame boundary bubble %0d->%0d: last=%0d first=%0d",
                 i-1, i, last_out_cycle[i-1], first_out_cycle[i]);
        errors = errors + 1;
      end
    end

    $display("DUALCTX_CYCLES frame0_first=%0d frame0_last=%0d frame1_first=%0d frame2_first=%0d frame3_first=%0d",
             first_out_cycle[0], last_out_cycle[0], first_out_cycle[1],
             first_out_cycle[2], first_out_cycle[3]);
    if (errors)
      $fatal(1, "tb_gs_mdc_core_dualctx FAIL errors=%0d", errors);
    $display("tb_gs_mdc_core_dualctx PASS");
    $finish;
  end

  always @(posedge clk) begin
    if (!rst_n)
      cycle <= 0;
    else
      cycle <= cycle + 1;
  end

  always @(posedge clk) begin
    integer frame_number;
    integer index;
    integer expected_frame;
    logic [LOGN-2:0] index_bits;
    logic [LOGN-1:0] exp_index0;
    logic [LOGN-1:0] exp_index1;
    logic [QW-1:0] expected0;
    logic [QW-1:0] expected1;
    logic [1:0] expected_mode;

    if (rst_n && output_started && total_received < FRAMES*PAIRS && !out_valid) begin
      $display("unexpected output bubble at cycle %0d after %0d pairs",
               cycle, total_received);
      errors = errors + 1;
    end

    if (out_valid) begin
      output_started = 1'b1;
      frame_number = out_frame;
      expected_frame = total_received / PAIRS;
      if (frame_number != expected_frame) begin
        if (errors < 16)
          $display("frame order mismatch cycle=%0d got=%0d expected=%0d",
                   cycle, frame_number, expected_frame);
        errors = errors + 1;
      end

      index = received[frame_number];
      index_bits = index;
      expected_mode = frame_number[0] ? MODE_INTT : MODE_NTT;
      if (out_mode != expected_mode) begin
        if (errors < 16)
          $display("mode mismatch frame=%0d index=%0d got=%0d expected=%0d",
                   frame_number, index, out_mode, expected_mode);
        errors = errors + 1;
      end

      if (expected_mode == MODE_NTT) begin
        expected0 = golden_ntt[2*index];
        expected1 = golden_ntt[2*index + 1];
      end else begin
        exp_index0 = bit_reverse({index_bits, 1'b0});
        exp_index1 = bit_reverse({index_bits, 1'b1});
        expected0 = input_mem[exp_index0];
        expected1 = input_mem[exp_index1];
      end

      if (out0 !== expected0) begin
        if (errors < 16)
          $display("lane0 mismatch frame=%0d index=%0d got=%h expected=%h",
                   frame_number, index, out0, expected0);
        errors = errors + 1;
      end
      if (out1 !== expected1) begin
        if (errors < 16)
          $display("lane1 mismatch frame=%0d index=%0d got=%h expected=%h",
                   frame_number, index, out1, expected1);
        errors = errors + 1;
      end

      if (index == 0)
        first_out_cycle[frame_number] = cycle;
      last_out_cycle[frame_number] = cycle;
      received[frame_number] = index + 1;
      total_received = total_received + 1;
    end

    if (frame_done) begin
      if (done_frame != done_count) begin
        $display("done tag mismatch got=%0d expected=%0d", done_frame, done_count);
        errors = errors + 1;
      end
      done_count = done_count + 1;
    end
  end

  initial begin
    repeat (2000000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
