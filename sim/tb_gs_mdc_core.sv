`timescale 1ns/1ps
module tb_gs_mdc_core;
  import params_pkg::*;
  logic clk=0, rst_n=0, start=0, in_valid=0, out_ready=1;
  logic in_ready, out_valid, done;
  logic [1:0] mode=MODE_NTT;
  logic [QW-1:0] in0,in1,out0,out1;
  logic [QW-1:0] input_mem [0:N-1];
  logic [QW-1:0] golden [0:N-1];
  logic [QW-1:0] captured [0:N-1];
  integer sent=0, received=0, errors=0, fd;
  always #5 clk=~clk;
  gs_mdc_core u_dut (.*);

  initial begin
    $readmemh("mem/input_a.mem",input_mem);
    $readmemh("mem/golden_ntt_a.mem",golden);
    repeat(5) @(posedge clk); rst_n=1;
    @(negedge clk); start=1;
    @(negedge clk); start=0; in_valid=1;
    while(sent<N/2) begin
      // Match the production A/B bank split: lower half on lane 0 and upper
      // half on lane 1. Stage 0 can therefore butterfly without an input FIFO.
      in0=input_mem[sent]; in1=input_mem[sent+N/2];
      @(negedge clk); sent=sent+1;
    end
    in_valid=0;
    wait(done);
    $writememh("mem/output_ntt_a.mem",captured);
    if(errors) $fatal(1,"tb_gs_mdc_core FAIL errors=%0d",errors);
    $display("tb_gs_mdc_core PASS"); $finish;
  end
  always @(posedge clk) if(out_valid) begin
    captured[2*received]=out0;
    captured[2*received+1]=out1;
    if(out0!==golden[2*received]) errors=errors+1;
    if(out1!==golden[2*received+1]) errors=errors+1;
    received=received+1;
  end
  initial begin repeat(1000000) @(posedge clk); $fatal(1,"timeout"); end
endmodule
