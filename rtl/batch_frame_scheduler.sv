// Frame-granular scheduler for batched polynomial multiplication.
//
// A transform occupies the shared two-path core for exactly N/2 cycles. The
// scheduler never interleaves pairs from different transforms; it only chooses
// which complete A_NTT, B_NTT, or C_INTT frame enters next.
module batch_frame_scheduler #(
    parameter int N = 4096,
    parameter int LOGN = 12,
    parameter int JOB_COUNT = 6,
    parameter int JOB_BUFFERS = 3,
    parameter int JOB_W = (JOB_COUNT <= 1) ? 1 : $clog2(JOB_COUNT),
    parameter int BANK_W = (JOB_BUFFERS <= 1) ? 1 : $clog2(JOB_BUFFERS)
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  start,

    input  logic                  pointwise_done_valid,
    input  logic [JOB_W-1:0]      pointwise_done_job,
    input  logic [BANK_W-1:0]     pointwise_done_bank,
    input  logic                  result_done_valid,
    input  logic [JOB_W-1:0]      result_done_job,
    input  logic [BANK_W-1:0]     result_done_bank,

    output logic                  frame_valid,
    output logic                  frame_sof,
    output logic                  frame_eof,
    output logic [LOGN-2:0]       frame_pair,
    output logic [1:0]            frame_role,
    output logic [JOB_W-1:0]      frame_job,
    output logic [BANK_W-1:0]     frame_bank,
    output logic                  frame_context,
    output logic                  busy,
    output logic                  done
);
  localparam int PAIRS = N / 2;

  localparam logic [1:0] ROLE_A_NTT = 2'd0;
  localparam logic [1:0] ROLE_B_NTT = 2'd1;
  localparam logic [1:0] ROLE_C_INTT = 2'd2;

  typedef enum logic [2:0] {
    BANK_FREE,
    A_READY,
    B_READY,
    WAIT_C_READY,
    C_READY,
    C_RUNNING
  } bank_state_t;

  bank_state_t bank_state [0:JOB_BUFFERS-1];
  logic [JOB_W-1:0] bank_job [0:JOB_BUFFERS-1];

  logic frame_active;
  logic [LOGN-2:0] pair_count;
  logic [1:0] active_role;
  logic [JOB_W-1:0] active_job;
  logic [BANK_W-1:0] active_bank;
  logic active_context;
  logic next_context;

  logic candidate_valid;
  logic [1:0] candidate_priority;
  logic [1:0] candidate_role;
  logic [JOB_W-1:0] candidate_job;
  logic [BANK_W-1:0] candidate_bank;
  logic [JOB_W:0] next_job;
  logic [JOB_W:0] completed_jobs;
  integer i_candidate;
  integer i_seq;

  always_comb begin
    candidate_valid = 1'b0;
    candidate_priority = 2'd3;
    candidate_role = ROLE_A_NTT;
    candidate_job = '1;
    candidate_bank = '0;

    for (i_candidate = 0; i_candidate < JOB_BUFFERS; i_candidate = i_candidate + 1) begin
      case (bank_state[i_candidate])
        C_READY: begin
          if (!candidate_valid || (candidate_priority > 2'd0) ||
              ((candidate_priority == 2'd0) &&
               (bank_job[i_candidate] < candidate_job))) begin
            candidate_valid = 1'b1;
            candidate_priority = 2'd0;
            candidate_role = ROLE_C_INTT;
            candidate_job = bank_job[i_candidate];
            candidate_bank = BANK_W'(i_candidate);
          end
        end
        B_READY: begin
          if (!candidate_valid || (candidate_priority > 2'd1) ||
              ((candidate_priority == 2'd1) &&
               (bank_job[i_candidate] < candidate_job))) begin
            candidate_valid = 1'b1;
            candidate_priority = 2'd1;
            candidate_role = ROLE_B_NTT;
            candidate_job = bank_job[i_candidate];
            candidate_bank = BANK_W'(i_candidate);
          end
        end
        A_READY: begin
          if (!candidate_valid || (candidate_priority > 2'd2) ||
              ((candidate_priority == 2'd2) &&
               (bank_job[i_candidate] < candidate_job))) begin
            candidate_valid = 1'b1;
            candidate_priority = 2'd2;
            candidate_role = ROLE_A_NTT;
            candidate_job = bank_job[i_candidate];
            candidate_bank = BANK_W'(i_candidate);
          end
        end
        default: begin end
      endcase
    end
  end

  always_comb begin
    frame_valid = frame_active;
    frame_sof = frame_active && (pair_count == 0);
    frame_eof = frame_active && (pair_count == PAIRS-1);
    frame_pair = pair_count;
    frame_role = active_role;
    frame_job = active_job;
    frame_bank = active_bank;
    frame_context = active_context;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      frame_active <= 1'b0;
      pair_count <= '0;
      active_role <= ROLE_A_NTT;
      active_job <= '0;
      active_bank <= '0;
      active_context <= 1'b0;
      next_context <= 1'b0;
      next_job <= '0;
      completed_jobs <= '0;
      busy <= 1'b0;
      done <= 1'b0;
      for (i_seq = 0; i_seq < JOB_BUFFERS; i_seq = i_seq + 1) begin
        bank_state[i_seq] <= BANK_FREE;
        bank_job[i_seq] <= '0;
      end
    end else begin
      done <= 1'b0;

      if (start && !busy) begin
        frame_active <= 1'b0;
        pair_count <= '0;
        next_context <= 1'b0;
        next_job <= (JOB_COUNT < JOB_BUFFERS) ? JOB_COUNT : JOB_BUFFERS;
        completed_jobs <= '0;
        busy <= 1'b1;
        for (i_seq = 0; i_seq < JOB_BUFFERS; i_seq = i_seq + 1) begin
          if (i_seq < JOB_COUNT) begin
            bank_state[i_seq] <= A_READY;
            bank_job[i_seq] <= JOB_W'(i_seq);
          end else begin
            bank_state[i_seq] <= BANK_FREE;
            bank_job[i_seq] <= '0;
          end
        end
      end else if (busy) begin
        if (pointwise_done_valid)
          bank_state[pointwise_done_bank] <= C_READY;

        if (result_done_valid) begin
          completed_jobs <= completed_jobs + 1'b1;
          if (next_job < JOB_COUNT) begin
            bank_state[result_done_bank] <= A_READY;
            bank_job[result_done_bank] <= next_job[JOB_W-1:0];
            next_job <= next_job + 1'b1;
          end else begin
            bank_state[result_done_bank] <= BANK_FREE;
          end

          if (completed_jobs == JOB_COUNT-1) begin
            busy <= 1'b0;
            done <= 1'b1;
            frame_active <= 1'b0;
          end
        end

        if (frame_active) begin
          if (pair_count == PAIRS-1) begin
            if (candidate_valid) begin
              pair_count <= '0;
              active_role <= candidate_role;
              active_job <= candidate_job;
              active_bank <= candidate_bank;
              active_context <= next_context;
              next_context <= ~next_context;
              case (candidate_role)
                ROLE_A_NTT: bank_state[candidate_bank] <= B_READY;
                ROLE_B_NTT: bank_state[candidate_bank] <= WAIT_C_READY;
                ROLE_C_INTT: bank_state[candidate_bank] <= C_RUNNING;
                default: begin end
              endcase
            end else begin
              frame_active <= 1'b0;
              pair_count <= '0;
            end
          end else begin
            pair_count <= pair_count + 1'b1;
          end
        end else if (candidate_valid) begin
          frame_active <= 1'b1;
          pair_count <= '0;
          active_role <= candidate_role;
          active_job <= candidate_job;
          active_bank <= candidate_bank;
          active_context <= next_context;
          next_context <= ~next_context;
          case (candidate_role)
            ROLE_A_NTT: bank_state[candidate_bank] <= B_READY;
            ROLE_B_NTT: bank_state[candidate_bank] <= WAIT_C_READY;
            ROLE_C_INTT: bank_state[candidate_bank] <= C_RUNNING;
            default: begin end
          endcase
        end
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && pointwise_done_valid) begin
      if ((pointwise_done_bank >= JOB_BUFFERS) ||
          (bank_job[pointwise_done_bank] != pointwise_done_job) ||
          (bank_state[pointwise_done_bank] != WAIT_C_READY))
        $fatal(1, "pointwise completion tag/state mismatch");
    end
    if (rst_n && result_done_valid) begin
      if ((result_done_bank >= JOB_BUFFERS) ||
          (bank_job[result_done_bank] != result_done_job) ||
          (bank_state[result_done_bank] != C_RUNNING))
        $fatal(1, "result completion tag/state mismatch");
    end
  end
`endif
endmodule
