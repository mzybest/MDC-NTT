// One generalized 16-bit word-level Montgomery reduction round for the
// project modulus Q. Latency is 2 cycles in the local valid-pipeline
// convention.
module wlmont_round16 (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [128:0] t_in,
    output logic [128:0] t_out
);
  import params_pkg::*;

  localparam logic [15:0] Q_LO  = Q[15:0];     // 16'hc001
  localparam logic [23:0] Q_H0  = Q[39:16];
  localparam logic [23:0] Q_H1  = Q[63:40];

  logic [15:0]  m_word;
  logic [31:0]  low_cancel_sum;
  logic [15:0]  carry_low;
  logic [112:0] t_high_s1;
  logic [15:0]  carry_s1;
  (* use_dsp = "yes" *) logic [39:0] qh0_prod_s1;
  (* use_dsp = "yes" *) logic [39:0] qh1_prod_s1;
  logic [63:0]  qh_prod;

  // q0 = Q mod 2^16 = 16'hc001.
  // -q0^-1 mod 2^16 = 16'hbfff = -(16'h4001) mod 2^16.
  function automatic logic [15:0] neg_q0_inv_mul(
      input logic [15:0] x
  );
    logic [31:0] tmp;
    begin
      tmp = {16'b0, x} + ({16'b0, x} << 14);
      neg_q0_inv_mul = -tmp[15:0];
    end
  endfunction

  always_comb begin
    m_word = neg_q0_inv_mul(t_in[15:0]);
    // Q_LO = 16'hc001 = 2^15 + 2^14 + 1.
    low_cancel_sum = {16'b0, t_in[15:0]}
                   + ({16'b0, m_word} << 15)
                   + ({16'b0, m_word} << 14)
                   + {16'b0, m_word};
    carry_low = low_cancel_sum[31:16];
    qh_prod = {24'b0, qh0_prod_s1} + {qh1_prod_s1, 24'b0};
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      t_high_s1 <= '0;
      carry_s1 <= '0;
      qh0_prod_s1 <= '0;
      qh1_prod_s1 <= '0;
      t_out <= '0;
    end else begin
      t_high_s1 <= t_in[128:16];
      carry_s1 <= carry_low;
      qh0_prod_s1 <= m_word * Q_H0;
      qh1_prod_s1 <= m_word * Q_H1;

      t_out <= {16'b0, t_high_s1}
             + {65'b0, qh_prod}
             + {113'b0, carry_s1};
    end
  end
endmodule
