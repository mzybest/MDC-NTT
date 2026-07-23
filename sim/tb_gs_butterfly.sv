`timescale 1ns/1ps
module tb_gs_butterfly;
  import params_pkg::*;
  logic clk = 0, rst_n = 0, in_valid;
  logic [QW-1:0] a, b, twiddle, y0, y1;
  logic [QW-1:0] y0_ref, y1_ref;
  logic out_valid;
  logic out_valid_ref;
  logic [QW-1:0] expected0 [0:31];
  logic [QW-1:0] expected1 [0:31];
  integer sent, received;

  always #5 clk = ~clk;
  gs_butterfly #(.USE_SUM_RETIME(1'b1)) u_dut (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
      .a(a), .b(b), .twiddle(twiddle),
      .out_valid(out_valid), .y0(y0), .y1(y1)
  );
  gs_butterfly #(.USE_SUM_RETIME(1'b0)) u_ref (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
      .a(a), .b(b), .twiddle(twiddle),
      .out_valid(out_valid_ref), .y0(y0_ref), .y1(y1_ref)
  );

  function automatic [63:0] add_ref(input [63:0] x, input [63:0] z);
    reg [64:0] t;
    begin t = x + z; add_ref = (t >= Q) ? t-Q : t; end
  endfunction
  function automatic [63:0] sub_ref(input [63:0] x, input [63:0] z);
    begin sub_ref = (x >= z) ? x-z : x+Q-z; end
  endfunction
  function automatic [63:0] mont_ref(input [63:0] x, input [63:0] z);
    reg [127:0] t, qp, mq;
    reg [63:0] m;
    reg [128:0] total;
    reg [64:0] u;
    begin
      t=x*z; qp=t[63:0]*QINV; m=qp[63:0]; mq=m*Q;
      total={1'b0,t}+{1'b0,mq}; u=total[128:64];
      mont_ref=(u>=Q)?u-Q:u;
    end
  endfunction

  initial begin
    in_valid=0; a=0; b=0; twiddle=0; sent=0; received=0;
    repeat (4) @(posedge clk); rst_n=1;
    while (sent < 32) begin
      @(negedge clk);
      a = {$urandom,$urandom} % Q;
      b = {$urandom,$urandom} % Q;
      twiddle = {$urandom,$urandom} % Q;
      in_valid = $urandom_range(0, 1);
      if (in_valid) begin
        expected0[sent] = add_ref(a,b);
        expected1[sent] = mont_ref(sub_ref(a,b),twiddle);
        sent = sent + 1;
      end
    end
    @(negedge clk); in_valid=0;
    wait (received == sent);
    $display("tb_gs_butterfly PASS (%0d vectors)", received);
    $finish;
  end
  always @(posedge clk) begin
    if (out_valid !== out_valid_ref)
      $fatal(1,"retimed valid mismatch at output %0d",received);
    if (out_valid) begin
      if (y0 !== y0_ref || y1 !== y1_ref)
        $fatal(1,"retimed data mismatch at %0d",received);
      if (y0 !== expected0[received] || y1 !== expected1[received])
        $fatal(1,"butterfly mismatch at %0d",received);
      received = received + 1;
    end
  end
endmodule
