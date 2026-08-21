`timescale 1ns/1ps
module tb_poly_mul_top_dual_forward #(
    parameter bit USE_LOAD_PREPROCESS = 1'b0,
    parameter bit FUSE_INTT_SCALE_IN_POST = 1'b0,
    parameter bit USE_TOP_DATA_BRAM = 1'b0,
    parameter bit USE_FINAL_UNIT_TWIDDLE_BYPASS = 1'b0
);
  import params_pkg::*;

  logic clk = 0;
  logic rst_n = 0;
  logic start = 0;
  logic load_we = 0;
  logic load_sel = 0;
  logic busy, done;
  logic [LOGN-1:0] load_addr, result_addr;
  logic [QW-1:0] load_data, result_data;
  logic [QW-1:0] a [0:N-1];
  logic [QW-1:0] b [0:N-1];
  logic [QW-1:0] golden [0:N-1];

  integer i;
  integer errors = 0;
  integer printed = 0;
  integer fd;
  integer cycle = 0;
  integer first_start = -1;
  integer first_done = -1;
  integer a_in_first = -1, a_in_last = -1, a_in_count = 0;
  integer b_in_first = -1, b_in_last = -1, b_in_count = 0;
  integer fwd_out_first = -1, fwd_out_last = -1, fwd_out_count = 0;
  integer intt_in_first = -1, intt_in_last = -1, intt_in_count = 0;
  integer intt_out_first = -1, intt_out_last = -1, intt_out_count = 0;
  localparam int BASE_FULL_MUL_CYCLES = 8621;
  localparam int PIPELINED_FULL_MUL_CYCLES = BASE_FULL_MUL_CYCLES + 2;

  always #5 clk = ~clk;

  poly_mul_top_dual_forward #(
      .USE_LOAD_PREPROCESS(USE_LOAD_PREPROCESS),
      .FUSE_INTT_SCALE_IN_POST(FUSE_INTT_SCALE_IN_POST),
      .USE_TOP_DATA_BRAM(USE_TOP_DATA_BRAM),
      .USE_FINAL_UNIT_TWIDDLE_BYPASS(USE_FINAL_UNIT_TWIDDLE_BYPASS)
  ) u_dut (.*);

  task automatic load_poly(input logic select_b);
    begin
      load_sel = select_b;
      load_we = 1'b1;
      for (i = 0; i < N; i = i + 1) begin
        load_addr = i;
        load_data = select_b ? b[i] : a[i];
        @(negedge clk);
      end
      load_we = 1'b0;
    end
  endtask

  task automatic start_and_wait;
    begin
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
      wait (done);
    end
  endtask

  task automatic wait_for_idle;
    begin
      @(posedge clk);
      @(negedge clk);
    end
  endtask

  initial begin
    $display("DSP_REDUCTION_CONFIG load_pre=%0d fused_post=%0d unit_twiddle=%0d top_bram=%0d",
             USE_LOAD_PREPROCESS, FUSE_INTT_SCALE_IN_POST,
             USE_FINAL_UNIT_TWIDDLE_BYPASS, USE_TOP_DATA_BRAM);
    $readmemh("mem/input_a.mem", a);
    $readmemh("mem/input_b.mem", b);
    $readmemh("mem/golden_result.mem", golden);
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    load_poly(1'b0);
    load_poly(1'b1);
    start_and_wait();
    first_done = cycle;

    fd = $fopen("mem/result_dual_forward.mem", "w");
    for (i = 0; i < N; i = i + 1) begin
      result_addr = i;
      #1;
      $fdisplay(fd, "%016x", result_data);
      if (result_data !== golden[i]) begin
        errors = errors + 1;
        if (printed < 16) begin
          $display("mismatch index=%0d rtl=%016x golden=%016x",
                   i, result_data, golden[i]);
          printed = printed + 1;
        end
      end
    end
    $fclose(fd);

    if (first_done-first_start != PIPELINED_FULL_MUL_CYCLES)
      $fatal(1, "dual-forward cycles=%0d expected=%0d",
             first_done-first_start, PIPELINED_FULL_MUL_CYCLES);
    if (a_in_count != N/2 || b_in_count != N/2 ||
        fwd_out_count != N/2 || intt_in_count != N/2 ||
        intt_out_count != N/2)
      $fatal(1, "dual-forward pair counts A=%0d B=%0d FWD=%0d IIN=%0d IOUT=%0d",
             a_in_count, b_in_count, fwd_out_count,
             intt_in_count, intt_out_count);
    if (errors)
      $fatal(1, "tb_poly_mul_top_dual_forward FAIL errors=%0d", errors);

    $display("DUAL_FORWARD_FULL_MUL_CYCLES start=%0d done=%0d start_to_done=%0d",
             first_start, first_done, first_done-first_start);
    $display("DUAL_FORWARD_PHASES a_in=%0d..%0d b_in=%0d..%0d fwd_out=%0d..%0d intt_in=%0d..%0d intt_out=%0d..%0d",
             a_in_first, a_in_last, b_in_first, b_in_last,
             fwd_out_first, fwd_out_last, intt_in_first, intt_in_last,
             intt_out_first, intt_out_last);

    wait_for_idle();
    for (i = 0; i < N; i = i + 1) begin
      a[i] = '0;
      b[i] = '0;
    end
    a[N-1] = R_MOD_Q;
    b[1] = R_MOD_Q;
    load_poly(1'b0);
    load_poly(1'b1);
    start_and_wait();

    for (i = 0; i < N; i = i + 1) begin
      result_addr = i;
      #1;
      if (i == 0) begin
        if (result_data !== Q-R_MOD_Q)
          $fatal(1, "directed result[0]=%016x expected=%016x",
                 result_data, Q-R_MOD_Q);
      end else if (result_data !== '0) begin
        $fatal(1, "directed nonzero result[%0d]=%016x", i, result_data);
      end
    end

    $display("tb_poly_mul_top_dual_forward PASS: random and directed negacyclic cases");
    $finish;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      cycle <= 0;
    end else begin
      if (start && first_start < 0)
        first_start = cycle;
      if (first_done < 0 && u_dut.core_a_in_valid &&
          u_dut.core_a_mode == MODE_NTT) begin
        if (a_in_first < 0)
          a_in_first = cycle;
        a_in_last = cycle;
        a_in_count = a_in_count + 1;
      end
      if (first_done < 0 && u_dut.pre_pair_valid) begin
        if (b_in_first < 0)
          b_in_first = cycle;
        b_in_last = cycle;
        b_in_count = b_in_count + 1;
      end
      if (first_done < 0 && u_dut.forward_pair_valid) begin
        if (fwd_out_first < 0)
          fwd_out_first = cycle;
        fwd_out_last = cycle;
        fwd_out_count = fwd_out_count + 1;
      end
      if (first_done < 0 && u_dut.core_a_in_valid &&
          u_dut.core_a_mode == MODE_INTT) begin
        if (intt_in_first < 0)
          intt_in_first = cycle;
        intt_in_last = cycle;
        intt_in_count = intt_in_count + 1;
      end
      if (first_done < 0 && u_dut.intt_pair_valid) begin
        if (intt_out_first < 0)
          intt_out_first = cycle;
        intt_out_last = cycle;
        intt_out_count = intt_out_count + 1;
      end
      cycle <= cycle + 1;
    end
  end

  initial begin
    repeat (3000000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
