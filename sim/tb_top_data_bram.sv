`timescale 1ns/1ps
module tb_top_data_bram;
  localparam int DW = 64;
  localparam int DEPTH = 16;
  localparam int AW = $clog2(DEPTH);

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic wr_en = 1'b0;
  logic [AW-1:0] wr_addr = '0;
  logic [DW-1:0] wr_data = '0;
  logic rd_en = 1'b0;
  logic [AW-1:0] rd_addr = '0;
  logic rd_valid;
  logic [DW-1:0] rd_data;

  always #5 clk = ~clk;

  top_data_bram #(.DW(DW), .DEPTH(DEPTH), .AW(AW)) u_dut (.*);

  task automatic write_word(
      input logic [AW-1:0] addr,
      input logic [DW-1:0] data
  );
    begin
      @(negedge clk);
      wr_en = 1'b1;
      wr_addr = addr;
      wr_data = data;
      @(posedge clk);
      #1;
      wr_en = 1'b0;
    end
  endtask

  task automatic read_and_check(
      input logic [AW-1:0] addr,
      input logic [DW-1:0] expected
  );
    begin
      @(negedge clk);
      rd_en = 1'b1;
      rd_addr = addr;
      @(posedge clk);
      #1;
      if (!rd_valid || (rd_data !== expected))
        $fatal(1, "BRAM read mismatch addr=%0d data=%016x expected=%016x valid=%0b",
               addr, rd_data, expected, rd_valid);
      rd_en = 1'b0;
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    for (int i = 0; i < DEPTH; i++)
      write_word(i[AW-1:0], 64'h1000_0000_0000_0000 + i);

    for (int i = 0; i < DEPTH; i++)
      read_and_check(i[AW-1:0], 64'h1000_0000_0000_0000 + i);

    @(negedge clk);
    wr_en = 1'b1;
    wr_addr = 4'd15;
    wr_data = 64'hfeed_face_cafe_beef;
    rd_en = 1'b1;
    rd_addr = 4'd0;
    @(posedge clk);
    #1;
    if (!rd_valid || (rd_data !== 64'h1000_0000_0000_0000))
      $fatal(1, "BRAM concurrent read/write mismatch");
    wr_en = 1'b0;
    rd_en = 1'b0;

    read_and_check(4'd15, 64'hfeed_face_cafe_beef);
    @(posedge clk);
    #1;
    if (rd_valid)
      $fatal(1, "BRAM rd_valid did not clear");

    $display("tb_top_data_bram PASS");
    $finish;
  end
endmodule
