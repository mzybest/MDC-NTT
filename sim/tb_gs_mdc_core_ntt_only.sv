`timescale 1ns/1ps
module tb_gs_mdc_core_ntt_only;
  import params_pkg::*;

  logic clk = 0;
  logic rst_n = 0;
  logic start = 0;
  logic in_valid = 0;
  logic [QW-1:0] in0, in1;

  logic ref_in_ready, ref_out_valid, ref_done;
  logic [QW-1:0] ref_out0, ref_out1;
  logic ntt_in_ready, ntt_out_valid, ntt_done;
  logic [QW-1:0] ntt_out0, ntt_out1;

  logic [QW-1:0] input_mem [0:N-1];
  logic [QW-1:0] golden [0:N-1];
  integer cycle = 0;
  integer first_in = -1;
  integer first_out = -1;
  integer done_cycle = -1;
  localparam int BASE_FIRST_LATENCY = 2241;
  localparam int BASE_DONE_LATENCY = 4289;
  localparam int PIPELINED_FIRST_LATENCY = BASE_FIRST_LATENCY + 1;
  localparam int PIPELINED_DONE_LATENCY = BASE_DONE_LATENCY + 1;
  integer received = 0;
  integer errors = 0;

  always #5 clk = ~clk;

  gs_mdc_core #(
      .BFU_BOUNDARY_PIPE_MASK({1'b1, {(LOGN-1){1'b0}}})
  ) u_reference (
      .clk(clk), .rst_n(rst_n), .start(start), .mode(MODE_NTT),
      .in_valid(in_valid), .in_ready(ref_in_ready), .in0(in0), .in1(in1),
      .out_valid(ref_out_valid), .out_ready(1'b1),
      .out0(ref_out0), .out1(ref_out1), .done(ref_done)
  );

  gs_mdc_core_ntt_only #(
      .BFU_BOUNDARY_PIPE_MASK({{(LOGN-1){1'b0}}, 1'b1})
  ) u_dut (
      .clk(clk), .rst_n(rst_n), .start(start),
      .in_valid(in_valid), .in_ready(ntt_in_ready), .in0(in0), .in1(in1),
      .out_valid(ntt_out_valid), .out_ready(1'b1),
      .out0(ntt_out0), .out1(ntt_out1), .done(ntt_done)
  );

  initial begin
    integer sent;
    $readmemh("mem/input_a.mem", input_mem);
    $readmemh("mem/golden_ntt_a.mem", golden);
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    for (sent = 0; sent < N/2; sent = sent + 1) begin
      start = (sent == 0);
      in_valid = 1'b1;
      in0 = input_mem[sent];
      in1 = input_mem[sent + N/2];
      @(negedge clk);
    end
    start = 1'b0;
    in_valid = 1'b0;
    in0 = '0;
    in1 = '0;

    wait (ref_done && ntt_done);
    repeat (3) @(posedge clk);
    if (received != N/2)
      $fatal(1, "NTT-only output count=%0d expected=%0d", received, N/2);
    if (first_out-first_in != PIPELINED_FIRST_LATENCY)
      $fatal(1, "NTT-only first latency=%0d expected=%0d",
             first_out-first_in, PIPELINED_FIRST_LATENCY);
    if (done_cycle-first_in != PIPELINED_DONE_LATENCY)
      $fatal(1, "NTT-only done latency=%0d expected=%0d",
             done_cycle-first_in, PIPELINED_DONE_LATENCY);
    if (errors)
      $fatal(1, "tb_gs_mdc_core_ntt_only FAIL errors=%0d", errors);
    $display("NTT_ONLY_CORE_CYCLES first_in=%0d first_out=%0d done=%0d first_latency=%0d done_latency=%0d",
             first_in, first_out, done_cycle, first_out-first_in,
             done_cycle-first_in);
    $display("tb_gs_mdc_core_ntt_only PASS");
    $finish;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      cycle <= 0;
    end else begin
      if (in_valid && first_in < 0)
        first_in = cycle;
      if ((ref_in_ready != ntt_in_ready) ||
          (ref_out_valid != ntt_out_valid) ||
          (ref_done != ntt_done)) begin
        if (errors < 16)
          $display("control mismatch cycle=%0d ready=%0b/%0b valid=%0b/%0b done=%0b/%0b",
                   cycle, ref_in_ready, ntt_in_ready, ref_out_valid,
                   ntt_out_valid, ref_done, ntt_done);
        errors = errors + 1;
      end

      if (ref_out_valid && ntt_out_valid) begin
        if (first_out < 0)
          first_out = cycle;
        if (ref_out0 !== ntt_out0 || ref_out1 !== ntt_out1 ||
            ntt_out0 !== golden[2*received] ||
            ntt_out1 !== golden[2*received+1]) begin
          if (errors < 16)
            $display("data mismatch pair=%0d ref=%h/%h ntt=%h/%h golden=%h/%h",
                     received, ref_out0, ref_out1, ntt_out0, ntt_out1,
                     golden[2*received], golden[2*received+1]);
          errors = errors + 1;
        end
        received = received + 1;
      end
      if (ref_done && ntt_done)
        done_cycle = cycle;
      cycle <= cycle + 1;
    end
  end

  initial begin
    repeat (1000000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
