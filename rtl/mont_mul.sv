// Nine-cycle, valid-pipelined 64-bit Montgomery multiplication.
// y = a*b*R^-1 mod Q, where R=2^64 and inputs are reduced modulo Q.
module mont_mul #(
    parameter int QW = 64
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          in_valid,
    input  logic [QW-1:0] a,
    input  logic [QW-1:0] b,
    output logic          out_valid,
    output logic [QW-1:0] y
);
  import params_pkg::*;

  // The pipelined shift/add reduction below relies on:
  // Q = 64'h0fffffffffffc001 = 2^60 - 2^14 + 1.
  localparam logic [63:0] Q_SHIFT_FORM =
      (64'h1 << 60) - (64'h1 << 14) + 64'h1;

  logic [63:0]  a_r;
  logic [63:0]  b_r;
  logic [127:0] t_s0;
  logic [127:0] t_s1;
  logic [127:0] t_s2;
  logic [127:0] t_s3;
  logic [127:0] t_s4;
  logic [63:0]  m_s1;
  logic [127:0] term_hi_s2;
  logic [127:0] term_mid_s2;
  logic [127:0] term_lo_s2;
  logic [127:0] tmp_s3;
  logic [127:0] term_lo_s3;
  logic [127:0] mq_s4;
  logic [128:0] sum_s5;
  logic [64:0]  u_s6;
  logic [8:0]   valid_pipe;

  generate
    if (Q != Q_SHIFT_FORM) begin : g_invalid_q
      initial $error("mont_mul constant-Q pipeline requires Q=2^60-2^14+1");
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      a_r <= '0;
      b_r <= '0;
      t_s0 <= '0;
      t_s1 <= '0;
      t_s2 <= '0;
      t_s3 <= '0;
      t_s4 <= '0;
      m_s1 <= '0;
      term_hi_s2 <= '0;
      term_mid_s2 <= '0;
      term_lo_s2 <= '0;
      tmp_s3 <= '0;
      term_lo_s3 <= '0;
      mq_s4 <= '0;
      sum_s5 <= '0;
      u_s6 <= '0;
      y <= '0;
      valid_pipe <= '0;
    end else begin
      valid_pipe <= {valid_pipe[7:0], in_valid};

      // Step A input register isolates the upstream butterfly/data-memory path.
      a_r <= a;
      b_r <= b;
      t_s0 <= a_r * b_r;

      t_s1 <= t_s0;
      m_s1 <= (t_s0[63:0] * QINV);

      // m*Q = (m << 60) - (m << 14) + m, split across three
      // registered stages to avoid one long 128-bit add/subtract chain.
      t_s2 <= t_s1;
      term_hi_s2 <= {64'b0, m_s1} << 60;
      term_mid_s2 <= {64'b0, m_s1} << 14;
      term_lo_s2 <= {64'b0, m_s1};

      t_s3 <= t_s2;
      tmp_s3 <= term_hi_s2 - term_mid_s2;
      term_lo_s3 <= term_lo_s2;

      t_s4 <= t_s3;
      mq_s4 <= tmp_s3 + term_lo_s3;

      sum_s5 <= {1'b0, t_s4} + {1'b0, mq_s4};
      u_s6 <= sum_s5[128:64];

      if (u_s6 >= {1'b0, Q})
        y <= u_s6 - {1'b0, Q};
      else
        y <= u_s6[QW-1:0];
    end
  end

  always_comb out_valid = valid_pipe[8];
endmodule
