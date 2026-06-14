// Preserved three-cycle Montgomery multiplier used by the delay-memory
// synthesis baseline. This renamed module is not part of the active design.
module mont_mul_3cycle_old #(
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
  logic [128:0] sum_s1;
  logic [64:0]  u_comb;
  logic [127:0] qinv_product;
  logic [63:0]  m_comb;
  logic [127:0] mq_comb;
  logic [2:0]   valid_pipe;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      t_s0 <= '0;
      sum_s1 <= '0;
      y <= '0;
      valid_pipe <= '0;
    end else begin
      valid_pipe <= {valid_pipe[1:0], in_valid};
      t_s0 <= a * b;
      sum_s1 <= {1'b0, t_s0} + {1'b0, mq_comb};
      if (u_comb >= {1'b0, Q})
        y <= u_comb - {1'b0, Q};
      else
        y <= u_comb[QW-1:0];
    end
  end

  always_comb begin
    qinv_product = t_s0[63:0] * QINV;
    m_comb = qinv_product[63:0];
    mq_comb = m_comb * Q;
    u_comb = sum_s1[128:64];
    out_valid = valid_pipe[2];
  end
endmodule
