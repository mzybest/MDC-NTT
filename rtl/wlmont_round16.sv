// One 16-bit Montgomery reduction round, two cycles, II=1.
// All variants compute (T + m*Q)/2^16, m = -T_low/Q_low mod 2^16.
// Implementations 1/2 specialize Q=2^60-2^14+1. Other supported Q values
// retain the original DSP implementation; Q_low must still equal 16'hc001.
module wlmont_round16 #(
    parameter int REDUCTION_IMPL = 2
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [128:0] t_in,
    output logic [128:0] t_out
);
  import params_pkg::*;

  localparam logic [63:0] SPARSE_Q = 64'h0fffffffffffc001;
  logic [15:0] m_word;

  function automatic logic [15:0] neg_q0_inv_mul(input logic [15:0] x);
    logic [31:0] tmp;
    begin
      tmp = {16'b0, x} + ({16'b0, x} << 14);
      neg_q0_inv_mul = -tmp[15:0];
    end
  endfunction
  always_comb m_word = neg_q0_inv_mul(t_in[15:0]);

  generate
    if (REDUCTION_IMPL < 0 || REDUCTION_IMPL > 2) begin : g_bad_impl
      initial $error("wlmont_round16 REDUCTION_IMPL must be 0, 1, or 2");
    end
    if (Q[15:0] != 16'hc001) begin : g_bad_q_low
      initial $error("wlmont_round16 expects Q[15:0]=16'hc001");
    end

    if (REDUCTION_IMPL == 2 && Q == SPARSE_Q) begin : g_fused
      logic [112:0] t_high_s1;
      logic [15:0] m_minus_one;
      logic [13:0] d, d_minus_one;
      logic [59:0] correction, correction_s1;
      logic borrow_d;

      always_comb begin
        // d = floor(m*(2^14-1)/2^16), carry_low = m-d.
        borrow_d = (m_word > {m_word[1:0], 14'b0});
        d = m_word[15:2] - {13'b0, borrow_d};
        d_minus_one = d - 14'd1;
        m_minus_one = m_word - 16'd1;
        // m*(Q>>16) + carry_low = (m<<44)-d.
        // Concatenation localizes borrow propagation to 16/14 bits.
        if (d == 0)
          correction = {m_word, 44'b0};
        else
          correction = {m_minus_one, 30'h3fffffff, ~d_minus_one};
      end
      always_ff @(posedge clk) begin
        if (!rst_n) begin
          t_high_s1 <= '0;
          correction_s1 <= '0;
          t_out <= '0;
        end else begin
          t_high_s1 <= t_in[128:16];
          correction_s1 <= correction;
          t_out <= {16'b0, t_high_s1} + {69'b0, correction_s1};
        end
      end
    end else if (REDUCTION_IMPL == 1 && Q == SPARSE_Q) begin : g_sparse_qh
      logic [112:0] t_high_s1;
      logic [15:0] m_minus_one, carry_s1;
      logic [31:0] low_cancel_sum;
      logic [59:0] qh_prod, qh_prod_s1;
      always_comb begin
        low_cancel_sum = {16'b0, t_in[15:0]}
                       + ({16'b0, m_word} << 15)
                       + ({16'b0, m_word} << 14) + {16'b0, m_word};
        m_minus_one = m_word - 16'd1;
        // m*(2^44-1); m=0 must be handled before the unsigned borrow.
        qh_prod = (m_word == 0) ? 60'b0
                  : {m_minus_one, 28'hfffffff, ~m_minus_one};
      end
      always_ff @(posedge clk) begin
        if (!rst_n) begin
          t_high_s1 <= '0;
          carry_s1 <= '0;
          qh_prod_s1 <= '0;
          t_out <= '0;
        end else begin
          t_high_s1 <= t_in[128:16];
          carry_s1 <= low_cancel_sum[31:16];
          qh_prod_s1 <= qh_prod;
          t_out <= {16'b0, t_high_s1} + {69'b0, qh_prod_s1}
                 + {113'b0, carry_s1};
        end
      end
    end else begin : g_dsp
      localparam logic [23:0] Q_H0 = Q[39:16];
      localparam logic [23:0] Q_H1 = Q[63:40];
      logic [31:0] low_cancel_sum;
      logic [112:0] t_high_s1;
      logic [15:0] carry_s1;
      (* use_dsp = "yes" *) logic [39:0] qh0_prod_s1;
      (* use_dsp = "yes" *) logic [39:0] qh1_prod_s1;
      logic [63:0] qh_prod;
      always_comb begin
        low_cancel_sum = {16'b0, t_in[15:0]}
                       + ({16'b0, m_word} << 15)
                       + ({16'b0, m_word} << 14) + {16'b0, m_word};
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
          carry_s1 <= low_cancel_sum[31:16];
          qh0_prod_s1 <= m_word * Q_H0;
          qh1_prod_s1 <= m_word * Q_H1;
          t_out <= {16'b0, t_high_s1} + {65'b0, qh_prod}
                 + {113'b0, carry_s1};
        end
      end
    end
  endgenerate
endmodule
