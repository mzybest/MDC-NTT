`timescale 1ns/1ps
module tb_poly_mul_top_batch_wavefront;
  import params_pkg::*;

  localparam int JOB_COUNT = 6;
  localparam int JOB_BUFFERS = 3;
  localparam int JOB_W = $clog2(JOB_COUNT);
  localparam int BANK_W = $clog2(JOB_BUFFERS);
  localparam int FRAME_W = JOB_W + BANK_W + 3;
  localparam int PAIRS = N/2;
  localparam logic [1:0] ROLE_A_NTT = 2'd0;
  localparam logic [1:0] ROLE_B_NTT = 2'd1;
  localparam logic [1:0] ROLE_C_INTT = 2'd2;

  logic clk = 0;
  logic rst_n = 0;
  logic start = 0;
  logic load_we = 0;
  logic [JOB_W-1:0] load_job = '0;
  logic load_sel = 0;
  logic [LOGN-1:0] load_addr = '0;
  logic [QW-1:0] load_data = '0;
  logic result_rd_en = 0;
  logic [JOB_W-1:0] result_job = '0;
  logic [LOGN-1:0] result_addr = '0;
  logic result_rd_valid;
  logic [QW-1:0] result_data;
  logic busy, done;

  logic [QW-1:0] a [0:JOB_COUNT*N-1];
  logic [QW-1:0] b [0:JOB_COUNT*N-1];
  logic [QW-1:0] golden [0:JOB_COUNT*N-1];
  integer frame_first [0:JOB_COUNT-1][0:2];
  integer frame_last [0:JOB_COUNT-1][0:2];
  integer frame_pairs [0:JOB_COUNT-1][0:2];
  integer core_out_first [0:JOB_COUNT-1][0:2];
  integer core_out_last [0:JOB_COUNT-1][0:2];
  integer pointwise_done_cycle [0:JOB_COUNT-1];
  integer result_done_cycle [0:JOB_COUNT-1];
  integer cycle = 0;
  integer errors = 0;
  integer printed = 0;
  integer batch_start_cycle = -1;
  integer batch_done_cycle = -1;
  integer total_frames = 0;
  integer core_first_cycle = -1;
  integer core_last_cycle = -1;
  integer core_valid_pairs = 0;
  integer i, j, role;

  always #5 clk = ~clk;

  poly_mul_top_batch_wavefront #(
      .JOB_COUNT(JOB_COUNT), .JOB_BUFFERS(JOB_BUFFERS)
  ) u_dut (.*);

  task automatic load_poly(
      input integer job_index,
      input logic select_b
  );
    integer index;
    begin
      load_job = JOB_W'(job_index);
      load_sel = select_b;
      load_we = 1'b1;
      for (index = 0; index < N; index = index + 1) begin
        load_addr = index;
        load_data = select_b ? b[job_index*N + index]
                             : a[job_index*N + index];
        @(negedge clk);
      end
      load_we = 1'b0;
    end
  endtask

  task automatic check_job(input integer job_index);
    integer index;
    logic [QW-1:0] expected;
    begin
      result_job = JOB_W'(job_index);
      result_rd_en = 1'b1;
      for (index = 0; index < N; index = index + 1) begin
        result_addr = index;
        @(posedge clk);
        #1;
        expected = golden[job_index*N + index];
        if (!result_rd_valid) begin
          if (printed < 16)
            $display("missing result valid job=%0d index=%0d", job_index, index);
          printed = printed + 1;
          errors = errors + 1;
        end else if (result_data !== expected) begin
          if (printed < 16)
            $display("mismatch job=%0d index=%0d rtl=%016x golden=%016x",
                     job_index, index, result_data, expected);
          printed = printed + 1;
          errors = errors + 1;
        end
      end
      result_rd_en = 1'b0;
      @(negedge clk);
    end
  endtask

  initial begin
    for (j = 0; j < JOB_COUNT; j = j + 1) begin
      pointwise_done_cycle[j] = -1;
      result_done_cycle[j] = -1;
      for (role = 0; role < 3; role = role + 1) begin
        frame_first[j][role] = -1;
        frame_last[j][role] = -1;
        frame_pairs[j][role] = 0;
        core_out_first[j][role] = -1;
        core_out_last[j][role] = -1;
      end
    end

    $readmemh("reports/batch_wavefront_scheduler/vectors/batch_input_a.mem", a);
    $readmemh("reports/batch_wavefront_scheduler/vectors/batch_input_b.mem", b);
    $readmemh("reports/batch_wavefront_scheduler/vectors/batch_golden.mem", golden);

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    for (j = 0; j < JOB_COUNT; j = j + 1) begin
      load_poly(j, 1'b0);
      load_poly(j, 1'b1);
    end

    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    wait (done);
    batch_done_cycle = cycle;
    repeat (2) @(posedge clk);

    for (j = 0; j < JOB_COUNT; j = j + 1)
      check_job(j);

    for (j = 0; j < JOB_COUNT; j = j + 1) begin
      for (role = 0; role < 3; role = role + 1) begin
        if (frame_pairs[j][role] != PAIRS) begin
          $display("frame count job=%0d role=%0d got=%0d expected=%0d",
                   j, role, frame_pairs[j][role], PAIRS);
          errors = errors + 1;
        end
        $display("BATCH_FRAME job=%0d role=%0d first=%0d last=%0d pairs=%0d",
                 j, role, frame_first[j][role], frame_last[j][role],
                 frame_pairs[j][role]);
      end
    end

    if (total_frames != 3*JOB_COUNT) begin
      $display("total_frames=%0d expected=%0d", total_frames, 3*JOB_COUNT);
      errors = errors + 1;
    end
    if ((frame_first[5][ROLE_A_NTT] - frame_first[2][ROLE_A_NTT]) !=
        3*3*PAIRS) begin
      $display("steady A-frame II average=%0f expected=%0d",
               (frame_first[5][ROLE_A_NTT]-frame_first[2][ROLE_A_NTT])/3.0,
               3*PAIRS);
      errors = errors + 1;
    end

    $display("BATCH_FULL_CYCLES start=%0d done=%0d start_to_done=%0d",
             batch_start_cycle, batch_done_cycle,
             batch_done_cycle-batch_start_cycle);
    $display("BATCH_COMPUTE_THROUGHPUT jobs=%0d steady_product_ii=6144 core_input_idle_observed=%0d",
             JOB_COUNT, core_last_cycle-core_first_cycle+1-core_valid_pairs);
    for (j = 0; j < JOB_COUNT; j = j + 1)
      $display("BATCH_B_PIPELINE job=%0d in_first=%0d out_first=%0d out_last=%0d pointwise_done=%0d c_first=%0d",
               j, frame_first[j][ROLE_B_NTT], core_out_first[j][ROLE_B_NTT],
               core_out_last[j][ROLE_B_NTT], pointwise_done_cycle[j],
               frame_first[j][ROLE_C_INTT]);

    if (errors)
      $fatal(1, "tb_poly_mul_top_batch_wavefront FAIL errors=%0d", errors);
    $display("tb_poly_mul_top_batch_wavefront PASS: five random and one directed negacyclic jobs");
    $finish;
  end

  always @(posedge clk) begin
    integer observed_job;
    integer observed_role;
    integer observed_out_job;
    integer observed_out_role;
    if (!rst_n) begin
      cycle = 0;
      core_first_cycle = -1;
      core_last_cycle = -1;
      core_valid_pairs = 0;
    end else begin
      if (start && batch_start_cycle < 0)
        batch_start_cycle = cycle;

      if (u_dut.core_in_valid) begin
        observed_role = u_dut.core_in_frame[2:1];
        observed_job = u_dut.core_in_frame[FRAME_W-1:3+BANK_W];
        if (core_first_cycle < 0)
          core_first_cycle = cycle;
        core_last_cycle = cycle;
        core_valid_pairs = core_valid_pairs + 1;
        if (frame_pairs[observed_job][observed_role] == 0) begin
          frame_first[observed_job][observed_role] = cycle;
          total_frames = total_frames + 1;
        end
        frame_last[observed_job][observed_role] = cycle;
        frame_pairs[observed_job][observed_role] =
            frame_pairs[observed_job][observed_role] + 1;
      end
      if (u_dut.core_out_valid) begin
        observed_out_role = u_dut.core_out_frame[2:1];
        observed_out_job = u_dut.core_out_frame[FRAME_W-1:3+BANK_W];
        if (core_out_first[observed_out_job][observed_out_role] < 0)
          core_out_first[observed_out_job][observed_out_role] = cycle;
        core_out_last[observed_out_job][observed_out_role] = cycle;
      end

      if (u_dut.pointwise_done_valid)
        pointwise_done_cycle[u_dut.pointwise_done_job] = cycle;
      if (u_dut.result_done_valid)
        result_done_cycle[u_dut.result_done_job] = cycle;
      cycle = cycle + 1;
    end
  end

  initial begin
    repeat (3000000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule