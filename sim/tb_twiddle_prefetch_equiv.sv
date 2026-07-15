`timescale 1ns/1ps
module tb_twiddle_prefetch_equiv;
  import params_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [1:0] mode = MODE_NTT;
  logic in_valid = 1'b0;
  logic [QW-1:0] in0 = '0;
  logic [QW-1:0] in1 = '0;
  logic local_valid, legacy_valid;
  logic [QW-1:0] local0, local1, legacy0, legacy1;
  integer sent = 0;
  integer received = 0;
  integer errors = 0;
  integer seed = 32'h4d444354;

  always #5 clk = ~clk;

  mdc_stage #(
      .STAGE_ID(0), .DEPTH(0), .USE_STAGE_LOCAL_TWIDDLE(1'b1)
  ) u_local (
      .clk, .rst_n, .mode, .in_valid, .in0, .in1, .twiddle(R_MOD_Q),
      .out_valid(local_valid), .out0(local0), .out1(local1)
  );
  mdc_stage #(
      .STAGE_ID(0), .DEPTH(0), .USE_STAGE_LOCAL_TWIDDLE(1'b0)
  ) u_legacy (
      .clk, .rst_n, .mode, .in_valid, .in0, .in1, .twiddle(R_MOD_Q),
      .out_valid(legacy_valid), .out0(legacy0), .out1(legacy1)
  );

  task automatic send_transform(input logic [1:0] selected_mode);
    begin
      mode = selected_mode;
      sent = 0;
      received = 0;
      in_valid = 1'b0;
      repeat (2) @(negedge clk);
      while (sent < N/2) begin
        in_valid = ($urandom(seed) % 4) != 0;
        if (in_valid) begin
          in0 = sent + 64'h1234;
          in1 = sent + 64'h5678;
          sent = sent + 1;
        end
        @(negedge clk);
      end
      in_valid = 1'b0;
      wait (received == N/2);
      repeat (2) @(negedge clk);
    end
  endtask

  always @(posedge clk) begin
    #1;
    if (local_valid !== legacy_valid) begin
      if (errors < 16)
        $display("valid mismatch local=%b legacy=%b", local_valid, legacy_valid);
      errors = errors + 1;
    end
    if (local_valid && legacy_valid) begin
      if (local0 !== legacy0 || local1 !== legacy1) begin
        if (errors < 16)
          $display("data mismatch recv=%0d local=%h,%h legacy=%h,%h",
                   received, local0, local1, legacy0, legacy1);
        errors = errors + 1;
      end
      received = received + 1;
    end
  end

  initial begin
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    send_transform(MODE_NTT);
    send_transform(MODE_INTT);
    if (errors) $fatal(1, "tb_twiddle_prefetch_equiv FAIL errors=%0d", errors);
    $display("tb_twiddle_prefetch_equiv PASS: random bubbles, NTT and INTT");
    $finish;
  end

  initial begin
    repeat (50000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
