`timescale 1ns/1ps
module tb_poly_mul_top_wavefront;
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
  integer frame_first_in [0:2];
  integer frame_last_in [0:2];
  integer frame_in_count [0:2];
  integer frame_first_out [0:2];
  integer frame_last_out [0:2];
  integer frame_out_count [0:2];
  integer frame_done_cycle [0:2];

  always #5 clk = ~clk;

  poly_mul_top_wavefront u_dut (.*);

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
    integer k;
    for (k = 0; k < 3; k = k + 1) begin
      frame_first_in[k] = -1;
      frame_last_in[k] = -1;
      frame_in_count[k] = 0;
      frame_first_out[k] = -1;
      frame_last_out[k] = -1;
      frame_out_count[k] = 0;
      frame_done_cycle[k] = -1;
    end
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

    fd = $fopen("mem/result_wavefront.mem", "w");
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
    if (errors)
      $fatal(1, "tb_poly_mul_top_wavefront FAIL errors=%0d", errors);

    $display("WAVEFRONT_FULL_MUL_CYCLES start=%0d done=%0d start_to_done=%0d",
             first_start, first_done, first_done-first_start);
    for (i = 0; i < 3; i = i + 1)
      $display("WAVEFRONT_FRAME id=%0d first_in=%0d last_in=%0d first_out=%0d last_out=%0d done=%0d input_pairs=%0d output_pairs=%0d",
               i, frame_first_in[i], frame_last_in[i], frame_first_out[i],
               frame_last_out[i], frame_done_cycle[i], frame_in_count[i],
               frame_out_count[i]);

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

    $display("tb_poly_mul_top_wavefront PASS: random and directed negacyclic cases");
    $finish;
  end

  always @(posedge clk) begin
    integer frame_number;
    if (!rst_n)
      cycle <= 0;
    else begin
      if (start && first_start < 0)
        first_start = cycle;
      if (first_done < 0 && u_dut.core_in_valid) begin
        frame_number = u_dut.core_in_frame;
        if (frame_first_in[frame_number] < 0)
          frame_first_in[frame_number] = cycle;
        frame_last_in[frame_number] = cycle;
        frame_in_count[frame_number] = frame_in_count[frame_number] + 1;
      end
      if (first_done < 0 && u_dut.core_out_valid) begin
        frame_number = u_dut.core_out_frame;
        if (frame_first_out[frame_number] < 0)
          frame_first_out[frame_number] = cycle;
        frame_last_out[frame_number] = cycle;
        frame_out_count[frame_number] = frame_out_count[frame_number] + 1;
      end
      if (first_done < 0 && u_dut.core_frame_done)
        frame_done_cycle[u_dut.core_done_frame] = cycle;
      cycle <= cycle + 1;
    end
  end

  initial begin
    repeat (3000000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
