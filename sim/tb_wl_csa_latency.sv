`timescale 1ns/1ps
// Independent mathematical references. Original tests/goldens are unchanged.
module tb_wl_csa_latency;
  import params_pkg::*;
  logic clk=0,rst_n=0,in_valid=0;
  logic [63:0] ia=0,ib=0,ma=0,mb=0;
  wire [127:0] ip[0:1];
  wire [63:0] my[0:1];
  wire mv[0:1];
  logic ivq[0:3],mvq[0:13];
  logic [127:0] iq[0:3];
  logic [63:0] mq[0:13];
  integer icheck[0:1],mcheck[0:1],idiscard[0:1],mdiscard[0:1];
  integer issued=0,cycle=0,errors=0,seed,dummy,n,j,k;
  logic [63:0] edges[0:15];
  always #5 clk=~clk;
  intmul_64x64_24x17 u_i4(.clk(clk),.rst_n(rst_n),.a(ia),.b(ib),.p(ip[0]));
  intmul_64x64_csa2_experimental u_i2(.clk(clk),.rst_n(rst_n),.a(ia),.b(ib),.p(ip[1]));
  mont_mul_wl #(.REDUCTION_IMPL(2)) u_m14(
      .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.a(ma),.b(mb),.out_valid(mv[0]),.y(my[0]));
  mont_mul_wl_csa12_experimental u_m12(
      .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.a(ma),.b(mb),.out_valid(mv[1]),.y(my[1]));
  function automatic logic [63:0] mont_ref(input logic [63:0] a,b);
    logic [127:0] t,inverse_product,mq0;
    logic [128:0] total;
    logic [64:0] quotient;
    begin
      t=a*b;inverse_product=t[63:0]*QINV;mq0=inverse_product[63:0]*Q;
      total={1'b0,t}+{1'b0,mq0};quotient=total[128:64];
      mont_ref=(quotient>={1'b0,Q})?quotient-{1'b0,Q}:quotient[63:0];
    end
  endfunction
  function automatic logic [63:0] raw64();raw64={$urandom,$urandom};endfunction
  task automatic fail(input string msg);
    begin errors=errors+1;$display("CSA_MISMATCH cycle=%0d %s",cycle,msg);
      if(errors>=12)$fatal(1,"too many failures");end
  endtask
  task automatic tick(input bit reset,valid,input logic [63:0] x,z,a,b);
    integer t,impl,il,ml;
    begin
      @(negedge clk);rst_n=!reset;in_valid=valid;ia=x;ib=z;ma=a;mb=b;
      if(!reset)begin
        ivq[0]=valid;mvq[0]=valid;iq[0]=x*z;mq[0]=mont_ref(a,b);
        if(valid)begin issued=issued+1;
          if(a>=Q||b>=Q)$fatal(1,"invalid modular stimulus");end
      end
      @(posedge clk);#1;cycle=cycle+1;
      if(reset)begin
        for(impl=0;impl<2;impl=impl+1)begin
          il=(impl==0)?4:2;ml=(impl==0)?14:12;
          for(t=1;t<il;t=t+1)if(ivq[t])idiscard[impl]=idiscard[impl]+1;
          for(t=1;t<ml;t=t+1)if(mvq[t])mdiscard[impl]=mdiscard[impl]+1;
          if(ip[impl]!==128'b0||mv[impl]!==1'b0||my[impl]!==64'b0)
            fail($sformatf("reset impl=%0d",impl));
        end
        for(t=0;t<4;t=t+1)begin ivq[t]=0;iq[t]=0;end
        for(t=0;t<14;t=t+1)begin mvq[t]=0;mq[t]=0;end
      end else begin
        for(impl=0;impl<2;impl=impl+1)begin
          il=(impl==0)?4:2;ml=(impl==0)?14:12;
          if(ivq[il-1])begin
            icheck[impl]=icheck[impl]+1;
            if(ip[impl]!==iq[il-1])
              fail($sformatf("integer impl=%0d got=%032x expected=%032x",impl,ip[impl],iq[il-1]));
          end
          if(mv[impl]!==mvq[ml-1])
            fail($sformatf("valid impl=%0d got=%b expected=%b",impl,mv[impl],mvq[ml-1]));
          if(mvq[ml-1])begin
            mcheck[impl]=mcheck[impl]+1;
            if(my[impl]!==mq[ml-1]||my[impl]>=Q)
              fail($sformatf("mont impl=%0d got=%016x expected=%016x",impl,my[impl],mq[ml-1]));
          end
        end
        for(t=3;t>0;t=t-1)begin ivq[t]=ivq[t-1];iq[t]=iq[t-1];end
        for(t=13;t>0;t=t-1)begin mvq[t]=mvq[t-1];mq[t]=mq[t-1];end
      end
    end
  endtask
  initial begin
    seed=32'h20260914;dummy=$urandom(seed);
    for(n=0;n<2;n=n+1)begin icheck[n]=0;mcheck[n]=0;idiscard[n]=0;mdiscard[n]=0;end
    for(n=0;n<4;n=n+1)begin ivq[n]=0;iq[n]=0;end
    for(n=0;n<14;n=n+1)begin mvq[n]=0;mq[n]=0;end
    edges[0]=0;edges[1]=1;edges[2]=2;edges[3]='1;
    edges[4]=64'h8000000000000000;edges[5]=64'h7fffffffffffffff;
    edges[6]=64'h000000000001ffff;edges[7]=64'h0000000000020000;
    edges[8]=64'h0000000000ffffff;edges[9]=64'h0000000001000000;
    edges[10]=64'h0000ffffffffffff;edges[11]=64'h0001000000000000;
    edges[12]=64'haaaaaaaaaaaaaaaa;edges[13]=64'h5555555555555555;
    edges[14]=Q-1;edges[15]=Q-2;
    repeat(4)tick(1,0,0,0,0,0);
    for(j=0;j<16;j=j+1)for(k=0;k<16;k=k+1)
      tick(0,1,edges[j],edges[k],edges[j]%Q,edges[k]%Q);
    for(j=0;j<64;j=j+1)for(k=0;k<64;k=k+1)
      tick(0,1,64'b1<<j,64'b1<<k,(64'b1<<j)%Q,(64'b1<<k)%Q);
    for(n=0;n<20000;n=n+1)tick(0,1,raw64(),raw64(),raw64()%Q,raw64()%Q);
    for(n=0;n<5000;n=n+1)
      tick(0,((n%5)!=1)&&((n%17)!=4),raw64(),raw64(),raw64()%Q,raw64()%Q);
    repeat(16)tick(0,0,0,0,0,0);
    for(n=0;n<10;n=n+1)tick(0,1,'1,'1,Q-1,Q-1);
    tick(1,0,0,0,0,0);
    repeat(16)tick(0,0,0,0,0,0);
    for(n=0;n<100;n=n+1)tick(0,1,raw64(),raw64(),Q-1,raw64()%Q);
    repeat(16)tick(0,0,0,0,0,0);
    for(n=0;n<2;n=n+1)begin
      if(icheck[n]+idiscard[n]!=issued||mcheck[n]+mdiscard[n]!=issued)
        $fatal(1,"transaction accounting impl=%0d issued=%0d integer=%0d+%0d mont=%0d+%0d",
               n,issued,icheck[n],idiscard[n],mcheck[n],mdiscard[n]);
      if(idiscard[n]==0||mdiscard[n]==0)$fatal(1,"missing reset coverage");
      $display("CSA_COUNTS impl=%0d integer_checked=%0d integer_discarded=%0d mont_checked=%0d mont_discarded=%0d",
               n,icheck[n],idiscard[n],mcheck[n],mdiscard[n]);
    end
    if(errors!=0)$fatal(1,"CSA FAIL errors=%0d",errors);
    $display("tb_wl_csa_latency PASS integer_latency=4/2 mont_latency=14/12 II=1 cycles=%0d issued=%0d",cycle,issued);
    $finish;
  end
endmodule
