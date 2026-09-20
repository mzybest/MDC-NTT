`timescale 1ns/1ps
// Fixed-inverse audit harness: reuse existing BFU, ROM, MDC and Post RTL.
// The production top is unchanged. This does not implement runtime switching.
module tb_gs_quad_inverse_audit;
  import params_pkg::*;
  localparam int BEATS=N/4;
  logic clk=0, rst_n=0, in_valid=0;
  logic [QW-1:0] input_mem [0:N-1];
  logic [QW-1:0] golden [0:N-1];
  logic [QW-1:0] x0='0,x1='0,x2='0,x3='0;
  logic [LOGN-3:0] input_count='0;
  logic [LOGN-2:0] wa,wb,pa,pb;
  logic [QW-1:0] tw_a,tw_b,ua,va,ub,vb;
  logic sva,svb;
  logic [LOGN:1] av,bv;
  logic [QW-1:0] a0[1:LOGN],a1[1:LOGN];
  logic [QW-1:0] b0[1:LOGN],b1[1:LOGN];
  logic co_va,co_vb;
  logic [2*QW-1:0] co_a,co_b;
  logic [QW-1:0] core_data[0:3],factors[0:3],post_data[0:3];
  logic [LOGN-1:0] logical_index[0:3];
  logic [LOGN-1:0] delayed_index[0:3];
  logic post_valid[0:3],index_valid[0:3];
  logic [LOGN-3:0] output_count='0;
  integer cycle=0, frame=0, in_seen=0, core_seen=0, post_seen=0;
  integer first_input=-1, first_core=-1, last_core=-1, first_post=-1, last_post=-1;
  always #5 clk=~clk;
  function automatic logic [LOGN-3:0] reverse10(input logic [LOGN-3:0] x);
    for(integer k=0;k<LOGN-2;k=k+1) reverse10[k]=x[LOGN-3-k];
  endfunction
  function automatic logic [QW-1:0] scaled(input logic [QW-1:0] x);
    logic [QW:0] twice;
    begin
      twice={1'b0,x}<<1;
      scaled=(twice>=Q)?twice-Q:twice;
    end
  endfunction
  always_ff @(posedge clk) begin
    if(!rst_n) input_count<='0;
    else if(in_valid) input_count<=input_count+1'b1;
    if(!rst_n) output_count<='0;
    else if(co_va&&co_vb) output_count<=output_count+1'b1;
  end
  always_comb begin
    wa=input_count;
    wb=BEATS+input_count;
    pa=in_valid ? ((input_count==BEATS-1)?0:input_count+1'b1) : wa;
    pb=BEATS+pa;
  end
  // MODE_INTT is held before first valid: B's initial factor has exponent N/4.
  twiddle_rom_stage #(.STAGE_ID(0)) rom_a(
    .clk(clk),.rst_n(rst_n),.mode(MODE_INTT),.index(wa),.prefetch_index(pa),.twiddle(tw_a));
  twiddle_rom_stage #(.STAGE_ID(0)) rom_b(
    .clk(clk),.rst_n(rst_n),.mode(MODE_INTT),.index(wb),.prefetch_index(pb),.twiddle(tw_b));
  gs_butterfly #(.USE_BFU_BOUNDARY_PIPE(1)) bf_a(
    .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.a(x0),.b(x2),.twiddle(tw_a),
    .out_valid(sva),.y0(ua),.y1(va));
  gs_butterfly #(.USE_BFU_BOUNDARY_PIPE(1)) bf_b(
    .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.a(x1),.b(x3),.twiddle(tw_b),
    .out_valid(svb),.y0(ub),.y1(vb));
  assign av[1]=sva;
  assign bv[1]=svb;
  assign a0[1]=ua; assign a1[1]=ub;
  assign b0[1]=va; assign b1[1]=vb;
  for(genvar s=1;s<LOGN;s=s+1) begin:g_tail
    localparam int D=(s==LOGN-1)?0:(1<<(LOGN-s-2));
    // Global LOGN/STAGE_ID preserve omega_N exponents; N/2 selects 1024 pairs.
    mdc_stage #(.STAGE_ID(s),.DEPTH(D),.N(N/2),.LOGN(LOGN),
      .BYPASS_TWIDDLE_MUL(s==LOGN-1)) stage_a(
      .clk(clk),.rst_n(rst_n),.mode(MODE_INTT),.in_valid(av[s]),
      .in0(a0[s]),.in1(a1[s]),.twiddle(R_MOD_Q),
      .out_valid(av[s+1]),.out0(a0[s+1]),.out1(a1[s+1]));
    mdc_stage #(.STAGE_ID(s),.DEPTH(D),.N(N/2),.LOGN(LOGN),
      .BYPASS_TWIDDLE_MUL(s==LOGN-1)) stage_b(
      .clk(clk),.rst_n(rst_n),.mode(MODE_INTT),.in_valid(bv[s]),
      .in0(b0[s]),.in1(b1[s]),.twiddle(R_MOD_Q),
      .out_valid(bv[s+1]),.out0(b0[s+1]),.out1(b1[s+1]));
  end
  delay_line #(.DW(2*QW),.DEPTH(14)) tail_a(
    .clk(clk),.rst_n(rst_n),.in_valid(av[LOGN]),.din({a1[LOGN],a0[LOGN]}),
    .out_valid(co_va),.dout(co_a));
  delay_line #(.DW(2*QW),.DEPTH(14)) tail_b(
    .clk(clk),.rst_n(rst_n),.in_valid(bv[LOGN]),.din({b1[LOGN],b0[LOGN]}),
    .out_valid(co_vb),.dout(co_b));
  assign core_data[0]=co_a[QW-1:0]; assign core_data[1]=co_a[2*QW-1:QW];
  assign core_data[2]=co_b[QW-1:0]; assign core_data[3]=co_b[2*QW-1:QW];
  assign logical_index[0]={1'b0,reverse10(output_count),1'b0};
  assign logical_index[1]={1'b1,reverse10(output_count),1'b0};
  assign logical_index[2]={1'b0,reverse10(output_count),1'b1};
  assign logical_index[3]={1'b1,reverse10(output_count),1'b1};
  for(genvar l=0;l<4;l=l+1) begin:g_post
    psi_post_rom #(.FUSE_N_INV(1)) factor_rom(.index(logical_index[l]),.factor(factors[l]));
    mont_mul_select #(.USE_WL_MONT(1)) post_mul(.clk(clk),.rst_n(rst_n),.in_valid(co_va&&co_vb),
      .a(core_data[l]),.b(factors[l]),.out_valid(post_valid[l]),.y(post_data[l]));
    delay_line #(.DW(LOGN),.DEPTH(14)) index_delay(
      .clk(clk),.rst_n(rst_n),.in_valid(co_va&&co_vb),.din(logical_index[l]),
      .out_valid(index_valid[l]),.dout(delayed_index[l]));
  end
  always @(posedge clk) begin:checks
    logic [QW-1:0] expected;
    if(rst_n) begin
      cycle<=cycle+1;
      if(in_valid) begin
        if(in_seen==0) first_input=cycle;
        in_seen=in_seen+1;
      end
      if(co_va!==co_vb || sva!==svb) $fatal(1,"quad lane alignment failure");
      if(co_va) begin
        if(core_seen==0) first_core=cycle;
        last_core=cycle;
        core_seen=core_seen+1;
      end
      if(post_valid[0]) begin
        if(post_seen==0) first_post=cycle;
        last_post=cycle;
        for(integer l=0;l<4;l=l+1) begin
          if(!post_valid[l]||!index_valid[l]) $fatal(1,"Post valid mismatch");
          if(frame==1) expected=golden[delayed_index[l]];
          else if(frame==2) expected=scaled(golden[delayed_index[l]]);
          else expected=(delayed_index[l]==0)?R_MOD_Q:'0;
          if(post_data[l]!==expected)
            $fatal(1,"frame=%0d lane=%0d index=%0d got=%016x expected=%016x",frame,l,delayed_index[l],post_data[l],expected);
        end
        post_seen=post_seen+1;
      end
    end
  end
  initial begin:run_test
    $readmemh("reports/quad_inverse_audit/c_ntt_reference.mem",input_mem);
    $readmemh("mem/golden_result.mem",golden);
    repeat(5) @(negedge clk);
    rst_n=1;
    repeat(3) @(negedge clk);
    for(integer f=1;f<=3;f=f+1) begin
      frame=f;in_seen=0;core_seen=0;post_seen=0;
      first_input=-1;first_core=-1;first_post=-1;
      for(integer k=0;k<BEATS;k=k+1) begin
        in_valid=1;
        if(f==3) begin x0=R_MOD_Q;x1=R_MOD_Q;x2=R_MOD_Q;x3=R_MOD_Q;end
        else begin
          x0=(f==1)?input_mem[k]:scaled(input_mem[k]);
          x1=(f==1)?input_mem[k+BEATS]:scaled(input_mem[k+BEATS]);
          x2=(f==1)?input_mem[k+2*BEATS]:scaled(input_mem[k+2*BEATS]);
          x3=(f==1)?input_mem[k+3*BEATS]:scaled(input_mem[k+3*BEATS]);
        end
        @(negedge clk);
      end
      in_valid=0;
      wait(post_seen==BEATS);
      @(negedge clk);
      if(in_seen!=BEATS||core_seen!=BEATS) $fatal(1,"quad frame count");
      if(first_core-first_input!=1218 || first_post-first_input!=1232)
        $fatal(1,"quad latency first_core=%0d first_post=%0d",first_core-first_input,first_post-first_input);
      if(last_core-first_core+1!=BEATS || last_post-first_post+1!=BEATS)
        $fatal(1,"quad output bubbles");
      $display("QUAD_INVERSE_RTL frame=%0d coefficients=%0d first_core=%0d last_core=%0d first_post=%0d last_post=%0d PASS",f,N,
        first_core-first_input,last_core-first_input,first_post-first_input,last_post-first_input);
      repeat(3) @(negedge clk);
    end
    $display("tb_gs_quad_inverse_audit PASS");
    $finish;
  end
  initial begin repeat(100000) @(posedge clk);$fatal(1,"quad timeout");end
endmodule
