// Six-cycle, valid-pipelined 64-bit Montgomery multiplication.
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

  logic [127:0] t_s0;
  logic [127:0] t_s1;
  logic [127:0] t_s2;
  logic [63:0]  m_s1;
  logic [127:0] mq_s2;
  logic [128:0] sum_s3;
  logic [64:0]  u_s4;
  logic [5:0]   valid_pipe;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      t_s0 <= '0;
      t_s1 <= '0;
      t_s2 <= '0;
      m_s1 <= '0;
      mq_s2 <= '0;
      sum_s3 <= '0;
      u_s4 <= '0;
      y <= '0;
      valid_pipe <= '0;
    end else begin
      valid_pipe <= {valid_pipe[4:0], in_valid};

      // Each wide multiply and the final wide addition occupy separate
      // pipeline stages so synthesis cannot combine them into one long path.
      t_s0 <= a * b;
      t_s1 <= t_s0;
      m_s1 <= (t_s0[63:0] * QINV);
      t_s2 <= t_s1;
      mq_s2 <= m_s1 * Q;
      sum_s3 <= {1'b0, t_s2} + {1'b0, mq_s2};
      u_s4 <= sum_s3[128:64];

      if (u_s4 >= {1'b0, Q})
        y <= u_s4 - {1'b0, Q};
      else
        y <= u_s4[QW-1:0];
    end
  end

  always_comb out_valid = valid_pipe[5];
endmodule
