`timescale 1ns/1ps
module tb_delay_memory;
  localparam int DW = 32;
  localparam int MAX_DEPTH = 1024;
  localparam int TEST_CYCLES = 2200;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic in_valid = 1'b0;
  logic [DW-1:0] din = '0;

  logic valid1, valid2, valid8, valid64, valid1024;
  logic [DW-1:0] dout1, dout2, dout8, dout64, dout1024;
  logic expected_valid [0:MAX_DEPTH];
  logic [DW-1:0] expected_data [0:MAX_DEPTH];
  integer cycle;
  integer errors = 0;
  integer i;

  always #5 clk = ~clk;

  delay_memory #(.DW(DW), .DEPTH(1)) u_d1 (
      .clk, .rst_n, .in_valid, .din, .out_valid(valid1), .dout(dout1));
  delay_memory #(.DW(DW), .DEPTH(2)) u_d2 (
      .clk, .rst_n, .in_valid, .din, .out_valid(valid2), .dout(dout2));
  delay_memory #(.DW(DW), .DEPTH(8)) u_d8 (
      .clk, .rst_n, .in_valid, .din, .out_valid(valid8), .dout(dout8));
  delay_memory #(.DW(DW), .DEPTH(64)) u_d64 (
      .clk, .rst_n, .in_valid, .din, .out_valid(valid64), .dout(dout64));
  delay_memory #(.DW(DW), .DEPTH(1024)) u_d1024 (
      .clk, .rst_n, .in_valid, .din, .out_valid(valid1024), .dout(dout1024));

  task automatic check_output(
      input integer depth,
      input logic actual_valid,
      input logic [DW-1:0] actual_data
  );
    begin
      if (actual_valid !== expected_valid[depth-1]) begin
        $display("valid mismatch cycle=%0d depth=%0d rtl=%b expected=%b",
                 cycle, depth, actual_valid, expected_valid[depth-1]);
        errors = errors + 1;
      end else if (actual_valid && actual_data !== expected_data[depth-1]) begin
        $display("data mismatch cycle=%0d depth=%0d rtl=%08x expected=%08x",
                 cycle, depth, actual_data, expected_data[depth-1]);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    for (i = 0; i <= MAX_DEPTH; i = i + 1) begin
      expected_valid[i] = 1'b0;
      expected_data[i] = '0;
    end

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    for (cycle = 0; cycle < TEST_CYCLES; cycle = cycle + 1) begin
      @(negedge clk);
      // Include regular bubbles so valid alignment is checked as well as data.
      in_valid = ((cycle % 7) != 2) && ((cycle % 11) != 5);
      din = 32'h5a000000 + cycle;
      expected_valid[0] = in_valid;
      expected_data[0] = din;

      @(posedge clk);
      #1;
      check_output(1, valid1, dout1);
      check_output(2, valid2, dout2);
      check_output(8, valid8, dout8);
      check_output(64, valid64, dout64);
      check_output(1024, valid1024, dout1024);

      for (i = MAX_DEPTH; i > 0; i = i - 1) begin
        expected_valid[i] = expected_valid[i-1];
        expected_data[i] = expected_data[i-1];
      end
    end

    if (errors)
      $fatal(1, "tb_delay_memory FAIL errors=%0d", errors);
    $display("tb_delay_memory PASS: DEPTH=1,2,8,64,1024");
    $finish;
  end
endmodule
