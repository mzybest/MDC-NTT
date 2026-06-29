`timescale 1ns/1ps
module tb_gs_mdc_core_roundtrip;
  import params_pkg::*;

  logic clk = 0;
  logic rst_n = 0;
  logic start = 0;
  logic in_valid = 0;
  logic out_ready = 1;
  logic in_ready, out_valid, done;
  logic [1:0] mode = MODE_NTT;
  logic [QW-1:0] in0, in1, out0, out1;

  logic [QW-1:0] input_mem [0:N-1];
  logic [QW-1:0] ntt_even [0:N/2-1];
  logic [QW-1:0] ntt_odd  [0:N/2-1];

  integer sent;
  integer received;
  integer errors;
  integer ntt_first_in_cycle, ntt_first_out_cycle, ntt_last_out_cycle, ntt_done_cycle;
  integer intt_first_in_cycle, intt_first_out_cycle, intt_last_out_cycle, intt_done_cycle;
  integer cycle;

  always #5 clk = ~clk;

  gs_mdc_core u_dut (
      .clk(clk), .rst_n(rst_n), .start(start), .mode(mode),
      .in_valid(in_valid), .in_ready(in_ready), .in0(in0), .in1(in1),
      .out_valid(out_valid), .out_ready(out_ready), .out0(out0), .out1(out1),
      .done(done)
  );

  function automatic logic [LOGN-1:0] bit_reverse(input logic [LOGN-1:0] v);
    integer i;
    for (i = 0; i < LOGN; i = i + 1)
      bit_reverse[i] = v[LOGN-1-i];
  endfunction

  task automatic pulse_start(input logic [1:0] next_mode);
    begin
      @(negedge clk);
      mode = next_mode;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  initial begin
    $readmemh("mem/input_a.mem", input_mem);
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    // Forward NTT: lower half on lane 0, upper half on lane 1.
    pulse_start(MODE_NTT);
    in_valid = 1'b1;
    ntt_first_in_cycle = cycle;
    for (sent = 0; sent < N/2; sent = sent + 1) begin
      in0 = input_mem[sent];
      in1 = input_mem[sent + N/2];
      @(negedge clk);
    end
    in_valid = 1'b0;
    wait(done);
    ntt_done_cycle = cycle;

    // Inverse NTT: match poly_mul_top's external bit-reversal read scheme.
    received = 0;
    pulse_start(MODE_INTT);
    in_valid = 1'b1;
    intt_first_in_cycle = cycle;
    for (sent = 0; sent < N/2; sent = sent + 1) begin
      logic [LOGN-1:0] addr0;
      logic [LOGN-1:0] addr1;
      addr0 = bit_reverse({1'b0, sent[LOGN-2:0]});
      addr1 = bit_reverse({1'b1, sent[LOGN-2:0]});
      in0 = ntt_even[addr0[LOGN-1:1]];
      in1 = ntt_odd[addr1[LOGN-1:1]];
      @(negedge clk);
    end
    in_valid = 1'b0;
    wait(done);
    intt_done_cycle = cycle;

    if (errors) $fatal(1, "tb_gs_mdc_core_roundtrip FAIL errors=%0d", errors);
    $display("NTT_ROUNDTRIP_CYCLES first_in=%0d first_out=%0d last_out=%0d done=%0d first_in_to_first_out=%0d",
             ntt_first_in_cycle, ntt_first_out_cycle, ntt_last_out_cycle, ntt_done_cycle,
             ntt_first_out_cycle - ntt_first_in_cycle);
    $display("INTT_ROUNDTRIP_CYCLES first_in=%0d first_out=%0d last_out=%0d done=%0d first_in_to_first_out=%0d",
             intt_first_in_cycle, intt_first_out_cycle, intt_last_out_cycle, intt_done_cycle,
             intt_first_out_cycle - intt_first_in_cycle);
    $display("tb_gs_mdc_core_roundtrip PASS");
    $finish;
  end

  always @(posedge clk) begin
    if (!rst_n) cycle <= 0;
    else cycle <= cycle + 1;
  end

  always @(posedge clk) begin
    if (out_valid && mode == MODE_NTT) begin
      if (received == 0) ntt_first_out_cycle = cycle;
      ntt_even[received] = out0;
      ntt_odd[received] = out1;
      ntt_last_out_cycle = cycle;
      received = received + 1;
    end else if (out_valid && mode == MODE_INTT) begin
      logic [LOGN-1:0] exp0;
      logic [LOGN-1:0] exp1;
      if (received == 0) intt_first_out_cycle = cycle;
      exp0 = bit_reverse({received[LOGN-2:0], 1'b0});
      exp1 = bit_reverse({received[LOGN-2:0], 1'b1});
      if (out0 !== input_mem[exp0]) begin
        if (errors < 16) $display("INTT mismatch lane0 recv=%0d idx=%0d got=%h exp=%h", received, exp0, out0, input_mem[exp0]);
        errors = errors + 1;
      end
      if (out1 !== input_mem[exp1]) begin
        if (errors < 16) $display("INTT mismatch lane1 recv=%0d idx=%0d got=%h exp=%h", received, exp1, out1, input_mem[exp1]);
        errors = errors + 1;
      end
      intt_last_out_cycle = cycle;
      received = received + 1;
    end
  end

  initial begin
    ntt_first_out_cycle = -1;
    intt_first_out_cycle = -1;
    errors = 0;
    received = 0;
    repeat (2000000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
