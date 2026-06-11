`timescale 1ns/1ps
module tb_poly_mul_top;
  import params_pkg::*;
  logic clk=0,rst_n=0,start=0,load_we=0,load_sel=0,busy,done;
  logic [LOGN-1:0] load_addr,result_addr;
  logic [QW-1:0] load_data,result_data;
  logic [QW-1:0] a [0:N-1], b [0:N-1], golden [0:N-1];
  integer i,errors=0,fd;
  always #5 clk=~clk;
  poly_mul_top u_dut(.*);

  task automatic load_poly(input logic select_b);
    begin
      load_sel=select_b; load_we=1;
      for(i=0;i<N;i=i+1) begin
        load_addr=i; load_data=select_b?b[i]:a[i]; @(negedge clk);
      end
      load_we=0;
    end
  endtask
  initial begin
    $readmemh("mem/input_a.mem",a); $readmemh("mem/input_b.mem",b);
    $readmemh("mem/golden_result.mem",golden);
    repeat(5) @(posedge clk); rst_n=1; @(negedge clk);
    load_poly(0); load_poly(1);
    start=1; @(negedge clk); start=0; wait(done);
    fd=$fopen("mem/result.mem","w");
    for(i=0;i<N;i=i+1) begin
      result_addr=i; #1;
      $fdisplay(fd,"%016x",result_data);
      if(result_data!==golden[i]) errors=errors+1;
    end
    $fclose(fd);
    if(errors) $fatal(1,"tb_poly_mul_top FAIL errors=%0d",errors);
    $display("tb_poly_mul_top PASS"); $finish;
  end
  initial begin repeat(2000000) @(posedge clk); $fatal(1,"timeout"); end
endmodule
