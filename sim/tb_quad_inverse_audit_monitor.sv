`timescale 1ns/1ps
// Passive audit, elaborated alongside the existing natural-loader testbench.
// No DUT drives or RTL changes. Dumps the first, random, continuous-load job.
`define AUDIT_TB tb_poly_mul_top_dual_forward_natural_ab
`define AUDIT_DUT tb_poly_mul_top_dual_forward_natural_ab.u_dut
module tb_quad_inverse_audit_monitor;
  integer fd;
  integer job = 0;
  integer fw_count = 0;
  integer ii_count = 0;
  integer io_count = 0;
  initial begin
    fd = $fopen("reports/quad_inverse_audit/rtl_trace.csv", "w");
    if (!fd) $fatal(1, "Cannot open audit trace");
  end
  always @(posedge `AUDIT_TB.clk) begin
    if (`AUDIT_TB.rst_n) begin
      if (`AUDIT_TB.start) job = job + 1;
      if (job == 1) begin
        if (`AUDIT_TB.start)
          $fdisplay(fd, "START,%0d", `AUDIT_TB.cycle);
        if (`AUDIT_DUT.g_top_bram.forward_rd_en)
          $fdisplay(fd, "READ_A,%0d,%0d", `AUDIT_TB.cycle,
                    `AUDIT_DUT.g_top_bram.forward_rd_addr);
        if (`AUDIT_DUT.pre_pair_valid)
          $fdisplay(fd, "PRE,%0d,%016x,%016x,%016x,%016x", `AUDIT_TB.cycle,
                    `AUDIT_DUT.pre_a_out0, `AUDIT_DUT.pre_a_out1,
                    `AUDIT_DUT.pre_b_out0, `AUDIT_DUT.pre_b_out1);
        if (`AUDIT_DUT.forward_pair_valid) begin
          $fdisplay(fd, "FWD,%0d,%0d,%016x,%016x,%016x,%016x", `AUDIT_TB.cycle,
                    fw_count, `AUDIT_DUT.core_a_out0, `AUDIT_DUT.core_a_out1,
                    `AUDIT_DUT.core_b_out0, `AUDIT_DUT.core_b_out1);
          fw_count = fw_count + 1;
        end
        if (`AUDIT_DUT.c_write_valid)
          $fdisplay(fd, "PW,%0d,%0d,%016x,%016x", `AUDIT_TB.cycle,
                    `AUDIT_DUT.mul_addr, `AUDIT_DUT.mul_out0, `AUDIT_DUT.mul_out1);
        if (`AUDIT_DUT.g_top_bram.intt_rd_en)
          $fdisplay(fd, "INTT_READ,%0d,%0d,%0d", `AUDIT_TB.cycle,
                    `AUDIT_DUT.g_top_bram.intt_pair_index,
                    `AUDIT_DUT.g_top_bram.intt_rd_addr0[11:1]);
        if (`AUDIT_DUT.intt_mem_valid) begin
          $fdisplay(fd, "INTT_IN,%0d,%0d,%016x,%016x", `AUDIT_TB.cycle,
                    ii_count, `AUDIT_DUT.core_a_in0, `AUDIT_DUT.core_a_in1);
          ii_count = ii_count + 1;
        end
        if (`AUDIT_DUT.intt_pair_valid) begin
          $fdisplay(fd, "INTT_OUT,%0d,%0d,%016x,%016x", `AUDIT_TB.cycle,
                    io_count, `AUDIT_DUT.core_a_out0, `AUDIT_DUT.core_a_out1);
          io_count = io_count + 1;
        end
        if (`AUDIT_DUT.post_valid0 && `AUDIT_DUT.post_valid1 && `AUDIT_DUT.post_addr_valid)
          $fdisplay(fd, "POST,%0d,%0d,%0d,%016x,%016x", `AUDIT_TB.cycle,
                    `AUDIT_DUT.delayed_post_addrs[11:0],
                    `AUDIT_DUT.delayed_post_addrs[23:12],
                    `AUDIT_DUT.post_out0, `AUDIT_DUT.post_out1);
        if (`AUDIT_DUT.done) begin
          $fdisplay(fd, "DONE,%0d", `AUDIT_TB.cycle);
          $fflush(fd);
        end
      end
    end
  end
  for (genvar s = 0; s < 12; s = s + 1) begin : g_stage_timing
    integer count_a = 0;
    integer count_b = 0;
    always @(posedge `AUDIT_TB.clk) begin
      if (`AUDIT_TB.rst_n && job == 1) begin
        if (`AUDIT_DUT.u_core_a.stage_valid[s]) begin
          if (count_a == 0 || count_a == 2047 || count_a == 2048 || count_a == 4095)
            $fdisplay(fd, "STAGE_A,%0d,%0d,%0d", `AUDIT_TB.cycle, s, count_a);
          count_a = count_a + 1;
        end
        if (`AUDIT_DUT.u_core_b.stage_valid[s]) begin
          if (count_b == 0 || count_b == 2047)
            $fdisplay(fd, "STAGE_B,%0d,%0d,%0d", `AUDIT_TB.cycle, s, count_b);
          count_b = count_b + 1;
        end
      end
    end
  end
endmodule
`undef AUDIT_TB
`undef AUDIT_DUT
