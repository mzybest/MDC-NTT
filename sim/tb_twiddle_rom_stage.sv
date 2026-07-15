`timescale 1ns/1ps
module tb_twiddle_rom_stage;
  import params_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [1:0] mode = MODE_NTT;
  logic [LOGN-2:0] index = '0;
  logic [LOGN-2:0] prefetch_index = '0;
  logic [QW-1:0] twiddle0, twiddle3, twiddle4, twiddle11;
  logic [QW-1:0] expected0 [0:4095];
  logic [QW-1:0] expected3 [0:511];
  logic [QW-1:0] expected4 [0:255];
  integer errors = 0;
  integer i;

  always #5 clk = ~clk;

  twiddle_rom_stage #(.STAGE_ID(0)) u_stage0 (
      .clk, .rst_n, .mode, .index, .prefetch_index, .twiddle(twiddle0)
  );
  twiddle_rom_stage #(.STAGE_ID(3)) u_stage3 (
      .clk, .rst_n, .mode, .index, .prefetch_index, .twiddle(twiddle3)
  );
  twiddle_rom_stage #(.STAGE_ID(4)) u_stage4 (
      .clk, .rst_n, .mode, .index, .prefetch_index, .twiddle(twiddle4)
  );
  twiddle_rom_stage #(.STAGE_ID(11)) u_stage11 (
      .clk, .rst_n, .mode, .index, .prefetch_index, .twiddle(twiddle11)
  );

  task automatic check_sync0(input logic [1:0] selected_mode, input integer idx);
    integer addr;
    begin
      @(negedge clk);
      mode = selected_mode;
      prefetch_index = idx;
      @(posedge clk);
      #1;
      addr = ((selected_mode == MODE_NTT) ? 0 : 2048) + idx;
      if (twiddle0 !== expected0[addr]) begin
        if (errors < 16)
          $display("stage0 mismatch mode=%0d idx=%0d got=%h exp=%h",
                   selected_mode, idx, twiddle0, expected0[addr]);
        errors = errors + 1;
      end
    end
  endtask

  task automatic check_sync3(input logic [1:0] selected_mode, input integer idx);
    integer addr;
    begin
      @(negedge clk);
      mode = selected_mode;
      prefetch_index = idx;
      @(posedge clk);
      #1;
      addr = ((selected_mode == MODE_NTT) ? 0 : 256) + idx;
      if (twiddle3 !== expected3[addr]) begin
        if (errors < 16)
          $display("stage3 mismatch mode=%0d idx=%0d got=%h exp=%h",
                   selected_mode, idx, twiddle3, expected3[addr]);
        errors = errors + 1;
      end
    end
  endtask

  task automatic check_async4(input logic [1:0] selected_mode, input integer idx);
    integer addr;
    begin
      @(negedge clk);
      mode = selected_mode;
      index = idx;
      #1;
      addr = ((selected_mode == MODE_NTT) ? 0 : 128) + idx;
      if (twiddle4 !== expected4[addr]) begin
        if (errors < 16)
          $display("stage4 mismatch mode=%0d idx=%0d got=%h exp=%h",
                   selected_mode, idx, twiddle4, expected4[addr]);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    $readmemh("mem/twiddle_stage00.mem", expected0);
    $readmemh("mem/twiddle_stage03.mem", expected3);
    $readmemh("mem/twiddle_stage04.mem", expected4);
    repeat (4) @(posedge clk);
    if (twiddle0 !== R_MOD_Q || twiddle3 !== R_MOD_Q || twiddle11 !== R_MOD_Q)
      $fatal(1, "reset/constant twiddle mismatch");
    rst_n = 1'b1;

    for (i = 0; i < 2048; i = i + 1) check_sync0(MODE_NTT, i);
    for (i = 0; i < 2048; i = i + 1) check_sync0(MODE_INTT, i);
    for (i = 0; i < 256; i = i + 1) check_sync3(MODE_NTT, i);
    for (i = 0; i < 256; i = i + 1) check_sync3(MODE_INTT, i);
    for (i = 0; i < 128; i = i + 1) check_async4(MODE_NTT, i);
    for (i = 0; i < 128; i = i + 1) check_async4(MODE_INTT, i);

    if (errors) $fatal(1, "tb_twiddle_rom_stage FAIL errors=%0d", errors);
    $display("tb_twiddle_rom_stage PASS");
    $finish;
  end

  initial begin
    repeat (20000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
