`timescale 1ns/1ps
module tb_poly_mul_top_phase_cycles;
  import params_pkg::*;
  logic clk=0,rst_n=0,start=0,load_we=0,load_sel=0,busy,done;
  logic [LOGN-1:0] load_addr,result_addr;
  logic [QW-1:0] load_data,result_data;
  logic [QW-1:0] a [0:N-1], b [0:N-1], golden [0:N-1];
  integer i, errors=0, printed=0, fd;
  integer cycle=0;
  integer full_start=-1, full_done=-1;
  integer phase_idx=0;
  integer p_start[0:2], p_done[0:2];
  integer p_first_in[0:2], p_last_in[0:2], p_in_count[0:2];
  integer p_first_out[0:2], p_last_out[0:2], p_out_count[0:2], p_bubbles[0:2];
  string p_name[0:2];

  always #5 clk=~clk;
  poly_mul_top u_dut(.*);

  task automatic init_stats;
    integer k;
    begin
      p_name[0]="A_NTT"; p_name[1]="B_NTT"; p_name[2]="INTT";
      for(k=0;k<3;k=k+1) begin
        p_start[k]=-1; p_done[k]=-1;
        p_first_in[k]=-1; p_last_in[k]=-1; p_in_count[k]=0;
        p_first_out[k]=-1; p_last_out[k]=-1; p_out_count[k]=0; p_bubbles[k]=0;
      end
    end
  endtask

  task automatic load_poly(input logic select_b);
    begin
      load_sel=select_b; load_we=1;
      for(i=0;i<N;i=i+1) begin
        load_addr=i; load_data=select_b?b[i]:a[i]; @(negedge clk);
      end
      load_we=0;
    end
  endtask

  task automatic start_and_wait;
    begin
      start=1; @(negedge clk); start=0; wait(done); full_done=cycle;
    end
  endtask

  initial begin
    init_stats();
    $readmemh("mem/input_a.mem",a);
    $readmemh("mem/input_b.mem",b);
    $readmemh("mem/golden_result.mem",golden);
    repeat(5) @(posedge clk); rst_n=1; @(negedge clk);
    load_poly(0); load_poly(1);
    start_and_wait();

    fd=$fopen("mem/result_phase_cycles.mem","w");
    for(i=0;i<N;i=i+1) begin
      result_addr=i; #1;
      $fdisplay(fd,"%016x",result_data);
      if(result_data!==golden[i]) begin
        errors=errors+1;
        if(printed<16) begin
          $display("mismatch index=%0d rtl=%016x golden=%016x", i,result_data,golden[i]);
          printed=printed+1;
        end
      end
    end
    $fclose(fd);
    if(errors) $fatal(1,"tb_poly_mul_top_phase_cycles FAIL errors=%0d",errors);

    $display("FULL_MUL_RESULT PASS errors=0");
    $display("FULL_MUL_CYCLES start=%0d done=%0d start_to_done=%0d", full_start, full_done, full_done-full_start);
    for(i=0;i<3;i=i+1) begin
      $display("PHASE %s start=%0d first_in=%0d last_in=%0d first_out=%0d last_out=%0d done=%0d start_to_done=%0d first_in_to_first_out=%0d input_valid_cycles=%0d output_valid_cycles=%0d output_bubbles=%0d output_coefficients=%0d",
        p_name[i], p_start[i], p_first_in[i], p_last_in[i], p_first_out[i], p_last_out[i], p_done[i],
        p_done[i]-p_start[i], p_first_out[i]-p_first_in[i], p_in_count[i], p_out_count[i], p_bubbles[i], 2*p_out_count[i]);
    end
    $display("tb_poly_mul_top_phase_cycles PASS");
    $finish;
  end

  always @(posedge clk) begin
    integer ap;
    if(!rst_n) begin
      cycle <= 0;
    end else begin
      if(start && full_start<0) full_start=cycle;
      if(u_dut.core_start && phase_idx<3) begin
        p_start[phase_idx]=cycle;
        phase_idx=phase_idx+1;
      end
      ap = phase_idx - 1;
      if(ap>=0 && ap<3 && p_done[ap]<0) begin
        if(u_dut.core_in_valid) begin
          if(p_first_in[ap]<0) p_first_in[ap]=cycle;
          p_last_in[ap]=cycle;
          p_in_count[ap]=p_in_count[ap]+1;
        end
        if(u_dut.core_out_valid) begin
          if(p_first_out[ap]<0) p_first_out[ap]=cycle;
          p_last_out[ap]=cycle;
          p_out_count[ap]=p_out_count[ap]+1;
        end else if(p_first_out[ap]>=0) begin
          p_bubbles[ap]=p_bubbles[ap]+1;
        end
        if(u_dut.core_done) p_done[ap]=cycle;
      end
      cycle <= cycle+1;
    end
  end

  initial begin repeat(3000000) @(posedge clk); $fatal(1,"timeout"); end
endmodule
