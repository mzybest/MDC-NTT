// Frame-oriented polynomial multiplier using one reusable GS-MDC core.
// Host data and result data are Montgomery-domain residues.
module poly_mul_top #(
    parameter int N = 4096,
    parameter int LOGN = 12,
    parameter int QW = 64
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             start,
    input  logic             load_we,
    input  logic             load_sel,
    input  logic [LOGN-1:0]  load_addr,
    input  logic [QW-1:0]    load_data,
    input  logic [LOGN-1:0]  result_addr,
    output logic [QW-1:0]    result_data,
    output logic             busy,
    output logic             done
);
  import params_pkg::*;
  typedef enum logic [3:0] {
    IDLE, NTT_A, WAIT_NTT_A, NTT_B_MUL, WAIT_NTT_B,
    INTT_C, WAIT_INTT_C, DONE
  } ctrl_state_t;

  ctrl_state_t state;
  // A/B are split by polynomial half. Reading the same address from both
  // banks supplies a[k] and a[k+N/2] directly to delay-free MDC stage 0.
  logic [QW-1:0] a_bank0 [0:N/2-1];
  logic [QW-1:0] a_bank1 [0:N/2-1];
  logic [QW-1:0] b_bank0 [0:N/2-1];
  logic [QW-1:0] b_bank1 [0:N/2-1];
  logic [QW-1:0] a_ntt_ram [0:N-1];
  logic [QW-1:0] c_ntt_ram [0:N-1];
  logic [QW-1:0] result_ram [0:N-1];
  logic [LOGN-2:0] feed_count, recv_count, mul_count;
  logic core_start, core_in_valid, core_out_valid, core_done;
  logic [1:0] core_mode;
  logic [QW-1:0] core_in0, core_in1, core_out0, core_out1;
  logic mul_valid0, mul_valid1;
  logic [QW-1:0] mul_out0, mul_out1;
  logic mul_addr_valid;
  logic [LOGN-2:0] mul_addr;

  function automatic logic [LOGN-1:0] bit_reverse(input logic [LOGN-1:0] v);
    integer i;
    for (i = 0; i < LOGN; i = i + 1)
      bit_reverse[i] = v[LOGN-1-i];
  endfunction

  always_ff @(posedge clk) begin
    if (load_we && state == IDLE) begin
      if (load_sel) begin
        if (load_addr[LOGN-1])
          b_bank1[load_addr[LOGN-2:0]] <= load_data;
        else
          b_bank0[load_addr[LOGN-2:0]] <= load_data;
      end else begin
        if (load_addr[LOGN-1])
          a_bank1[load_addr[LOGN-2:0]] <= load_data;
        else
          a_bank0[load_addr[LOGN-2:0]] <= load_data;
      end
    end
  end
  always_comb result_data = result_ram[result_addr];

  gs_mdc_core #(.N(N), .LOGN(LOGN), .QW(QW), .MUL_LAT(MUL_LAT)) u_core (
      .clk(clk), .rst_n(rst_n), .start(core_start), .mode(core_mode),
      .in_valid(core_in_valid), .in_ready(), .in0(core_in0), .in1(core_in1),
      .out_valid(core_out_valid), .out_ready(1'b1),
      .out0(core_out0), .out1(core_out1), .done(core_done)
  );
  pointwise_mul #(.QW(QW)) u_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(core_out_valid && state == WAIT_NTT_B),
      .a_ntt(a_ntt_ram[2*recv_count]), .b_ntt(core_out0),
      .out_valid(mul_valid0), .c_ntt(mul_out0)
  );
  pointwise_mul #(.QW(QW)) u_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(core_out_valid && state == WAIT_NTT_B),
      .a_ntt(a_ntt_ram[2*recv_count+1]), .b_ntt(core_out1),
      .out_valid(mul_valid1), .c_ntt(mul_out1)
  );
  delay_line #(.DW(LOGN-1), .DEPTH(MUL_LAT)) u_mul_addr_delay (
      .clk(clk), .rst_n(rst_n),
      .in_valid(core_out_valid && state == WAIT_NTT_B), .din(recv_count),
      .out_valid(mul_addr_valid), .dout(mul_addr)
  );

  always_comb begin
    core_start = (state == NTT_A) || (state == NTT_B_MUL) || (state == INTT_C);
    core_in_valid = (state == NTT_A) || (state == NTT_B_MUL) || (state == INTT_C);
    core_mode = (state == INTT_C) ? MODE_INTT : MODE_NTT;
    core_in0 = '0;
    core_in1 = '0;
    if (state == NTT_A) begin
      core_in0 = a_bank0[feed_count];
      core_in1 = a_bank1[feed_count];
    end else if (state == NTT_B_MUL) begin
      core_in0 = b_bank0[feed_count];
      core_in1 = b_bank1[feed_count];
    end else if (state == INTT_C) begin
      // INTT consumes the bit-reversed pointwise product in natural index
      // order, again split into lower and upper halves for stage 0.
      core_in0 = c_ntt_ram[bit_reverse({1'b0, feed_count})];
      core_in1 = c_ntt_ram[bit_reverse({1'b1, feed_count})];
    end
    busy = (state != IDLE) && (state != DONE);
    done = (state == DONE);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE;
      feed_count <= '0;
      recv_count <= '0;
      mul_count <= '0;
    end else begin
      case (state)
        IDLE: if (start) begin
          feed_count <= '0; recv_count <= '0; state <= NTT_A;
        end
        NTT_A: if (feed_count == N/2-1) begin
          feed_count <= '0; recv_count <= '0; state <= WAIT_NTT_A;
        end else feed_count <= feed_count + 1'b1;
        WAIT_NTT_A: begin
          if (core_out_valid) begin
            a_ntt_ram[2*recv_count] <= core_out0;
            a_ntt_ram[2*recv_count+1] <= core_out1;
            recv_count <= recv_count + 1'b1;
          end
          if (core_done) begin
            feed_count <= '0; recv_count <= '0; state <= NTT_B_MUL;
          end
        end
        NTT_B_MUL: if (feed_count == N/2-1) begin
          feed_count <= '0; recv_count <= '0; mul_count <= '0; state <= WAIT_NTT_B;
        end else feed_count <= feed_count + 1'b1;
        WAIT_NTT_B: begin
          if (core_out_valid) recv_count <= recv_count + 1'b1;
          if (mul_valid0 && mul_valid1 && mul_addr_valid) begin
            c_ntt_ram[2*mul_addr] <= mul_out0;
            c_ntt_ram[2*mul_addr+1] <= mul_out1;
            if (mul_count == N/2-1) begin
              feed_count <= '0; recv_count <= '0; state <= INTT_C;
            end else mul_count <= mul_count + 1'b1;
          end
        end
        INTT_C: if (feed_count == N/2-1) begin
          feed_count <= '0; recv_count <= '0; state <= WAIT_INTT_C;
        end else feed_count <= feed_count + 1'b1;
        WAIT_INTT_C: begin
          if (core_out_valid) begin
            result_ram[bit_reverse(2*recv_count)] <= core_out0;
            result_ram[bit_reverse(2*recv_count+1)] <= core_out1;
            recv_count <= recv_count + 1'b1;
          end
          if (core_done) state <= DONE;
        end
        DONE: if (!start) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end
endmodule
