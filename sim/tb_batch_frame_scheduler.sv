`timescale 1ns/1ps
module tb_batch_frame_scheduler;
  localparam int N = 4096;
  localparam int LOGN = 12;
  localparam int PAIRS = N/2;
  localparam int JOB_COUNT = 60;
  localparam int JOB_BUFFERS = 3;
  localparam int JOB_W = $clog2(JOB_COUNT);
  localparam int BANK_W = $clog2(JOB_BUFFERS);
  localparam int RESULT_LATENCY = 4303;

  localparam logic [1:0] ROLE_A_NTT = 2'd0;
  localparam logic [1:0] ROLE_B_NTT = 2'd1;
  localparam logic [1:0] ROLE_C_INTT = 2'd2;

  logic clk = 0;
  logic rst_n = 0;
  logic start = 0;
  logic pointwise_done_valid;
  logic [JOB_W-1:0] pointwise_done_job;
  logic [BANK_W-1:0] pointwise_done_bank;
  logic result_done_valid;
  logic [JOB_W-1:0] result_done_job;
  logic [BANK_W-1:0] result_done_bank;
  logic frame_valid, frame_sof, frame_eof;
  logic [LOGN-2:0] frame_pair;
  logic [1:0] frame_role;
  logic [JOB_W-1:0] frame_job;
  logic [BANK_W-1:0] frame_bank;
  logic frame_context;
  logic busy, done;

  integer cycle = 0;
  integer point_due [0:JOB_COUNT-1];
  integer result_due [0:JOB_COUNT-1];
  integer point_bank [0:JOB_COUNT-1];
  integer result_bank [0:JOB_COUNT-1];
  integer a_start [0:JOB_COUNT-1];
  integer frame_count = 0;
  integer first_frame_cycle = -1;
  integer last_frame_cycle = -1;
  integer errors = 0;
  integer j;
  integer j_event;

  always #5 clk = ~clk;

  batch_frame_scheduler #(
      .N(N), .LOGN(LOGN), .JOB_COUNT(JOB_COUNT),
      .JOB_BUFFERS(JOB_BUFFERS)
  ) u_dut (.*);

  always_comb begin
    pointwise_done_valid = 1'b0;
    pointwise_done_job = '0;
    pointwise_done_bank = '0;
    result_done_valid = 1'b0;
    result_done_job = '0;
    result_done_bank = '0;
    for (j_event = 0; j_event < JOB_COUNT; j_event = j_event + 1) begin
      if (point_due[j_event] == cycle) begin
        if (pointwise_done_valid)
          $fatal(1, "two pointwise completions collide at cycle %0d", cycle);
        pointwise_done_valid = 1'b1;
        pointwise_done_job = JOB_W'(j_event);
        pointwise_done_bank = BANK_W'(point_bank[j_event]);
      end
      if (result_due[j_event] == cycle) begin
        if (result_done_valid)
          $fatal(1, "two result completions collide at cycle %0d", cycle);
        result_done_valid = 1'b1;
        result_done_job = JOB_W'(j_event);
        result_done_bank = BANK_W'(result_bank[j_event]);
      end
    end
  end

  initial begin
    for (j = 0; j < JOB_COUNT; j = j + 1) begin
      point_due[j] = -1;
      result_due[j] = -1;
      point_bank[j] = -1;
      result_bank[j] = -1;
      a_start[j] = -1;
    end

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    wait (done);
    repeat (2) @(posedge clk);

    if (frame_count != 3*JOB_COUNT) begin
      $display("frame_count=%0d expected=%0d", frame_count, 3*JOB_COUNT);
      errors = errors + 1;
    end
    if ((last_frame_cycle - first_frame_cycle + 1) - frame_count*PAIRS != 209) begin
      $display("finite batch idle=%0d expected=209",
               (last_frame_cycle - first_frame_cycle + 1) - frame_count*PAIRS);
      errors = errors + 1;
    end
    for (j = 6; j < JOB_COUNT-6-2; j = j + 1) begin
      if (a_start[j+2] - a_start[j] != 2*3*PAIRS) begin
        if (errors < 16)
          $display("steady cadence job %0d->%0d is %0d expected=%0d",
                   j, j+2, a_start[j+2]-a_start[j], 2*3*PAIRS);
        errors = errors + 1;
      end
    end

    if (errors)
      $fatal(1, "tb_batch_frame_scheduler FAIL errors=%0d", errors);
    $display("BATCH_SCHEDULER_CYCLES first=%0d last=%0d idle=%0d steady_ii=6144",
             first_frame_cycle, last_frame_cycle,
             (last_frame_cycle-first_frame_cycle+1)-frame_count*PAIRS);
    $display("tb_batch_frame_scheduler PASS");
    $finish;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      cycle = 0;
    end else begin
      if (frame_valid) begin
        if (first_frame_cycle < 0)
          first_frame_cycle = cycle;
        last_frame_cycle = cycle;

        if (frame_sof) begin
          if (frame_pair != 0) begin
            $display("SOF pair mismatch at cycle %0d", cycle);
            errors = errors + 1;
          end
          if (frame_context != frame_count[0]) begin
            $display("context mismatch frame=%0d got=%0d", frame_count,
                     frame_context);
            errors = errors + 1;
          end
          case (frame_role)
            ROLE_A_NTT: a_start[frame_job] = cycle;
            ROLE_B_NTT: begin
              point_due[frame_job] = cycle + RESULT_LATENCY;
              point_bank[frame_job] = frame_bank;
            end
            ROLE_C_INTT: begin
              result_due[frame_job] = cycle + RESULT_LATENCY;
              result_bank[frame_job] = frame_bank;
            end
            default: begin
              $display("invalid role %0d", frame_role);
              errors = errors + 1;
            end
          endcase
          frame_count = frame_count + 1;
        end

        if (frame_eof != (frame_pair == PAIRS-1)) begin
          $display("EOF mismatch cycle=%0d pair=%0d", cycle, frame_pair);
          errors = errors + 1;
        end
      end
      cycle = cycle + 1;
    end
  end

  initial begin
    repeat (1000000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
