// Twelve-cycle, valid-pipelined 64-bit Montgomery multiplication.
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
  localparam logic [15:0] QINV_C0 = QINV[15:0];
  localparam logic [15:0] QINV_C1 = QINV[31:16];
  localparam logic [15:0] QINV_C2 = QINV[47:32];
  localparam logic [15:0] QINV_C3 = QINV[63:48];

  logic [63:0]  a_r;
  logic [63:0]  b_r;
  logic [127:0] t_s0;
  logic [127:0] t_s1;
  logic [127:0] t_s2;
  logic [127:0] t_s3;
  logic [127:0] t_s4;
  logic [127:0] t_s5;
  logic [127:0] t_s6;
  logic [127:0] t_s7;
  (* keep = "true", dont_touch = "true" *) logic [15:0] x0_s1;
  (* keep = "true", dont_touch = "true" *) logic [15:0] x1_s1;
  (* keep = "true", dont_touch = "true" *) logic [15:0] x2_s1;
  (* keep = "true", dont_touch = "true" *) logic [15:0] x3_s1;
  logic [63:0]  m_s4;
  logic [31:0]  qinv_pp00_s2;
  logic [31:0]  qinv_pp01_s2;
  logic [31:0]  qinv_pp10_s2;
  logic [31:0]  qinv_pp02_s2;
  logic [31:0]  qinv_pp11_s2;
  logic [31:0]  qinv_pp20_s2;
  logic [31:0]  qinv_pp03_s2;
  logic [31:0]  qinv_pp12_s2;
  logic [31:0]  qinv_pp21_s2;
  logic [31:0]  qinv_pp30_s2;
  logic [63:0]  qinv_op0;
  logic [63:0]  qinv_op1;
  logic [63:0]  qinv_op2;
  logic [63:0]  qinv_op3;
  logic [63:0]  qinv_op4;
  logic [63:0]  qinv_op5;
  logic [63:0]  qinv_op6;
  logic [63:0]  qinv_op7;
  logic [63:0]  qinv_op8;
  logic [63:0]  qinv_op9;
  logic [63:0]  qinv_sum_s3;
  logic [63:0]  qinv_carry_s3;
  logic [127:0] term_hi_s5;
  logic [127:0] term_mid_s5;
  logic [127:0] term_lo_s5;
  logic [127:0] tmp_s6;
  logic [127:0] term_lo_s6;
  logic [127:0] mq_s7;
  logic [128:0] sum_s8;
  logic [64:0]  u_s9;
  logic [11:0]  valid_pipe;

  function automatic logic [127:0] csa3(
      input logic [63:0] x,
      input logic [63:0] y,
      input logic [63:0] z
  );
    logic [63:0] sum_bits;
    logic [63:0] carry_bits;
    begin
      sum_bits = x ^ y ^ z;
      carry_bits = ((x & y) | (x & z) | (y & z)) << 1;
      csa3 = {carry_bits, sum_bits};
    end
  endfunction

  logic [127:0] qinv_csa0;
  logic [127:0] qinv_csa1;
  logic [127:0] qinv_csa2;
  logic [127:0] qinv_csa3;
  logic [127:0] qinv_csa4;
  logic [127:0] qinv_csa5;
  logic [127:0] qinv_csa6;
  logic [127:0] qinv_csa7;

  generate
    if (Q != Q_SHIFT_FORM) begin : g_invalid_q
      initial $error("mont_mul constant-Q pipeline requires Q=2^60-2^14+1");
    end
  endgenerate

  // Truncated low-64 QINV constant product:
  //   m is the low 64 bits of t_s0[63:0] times QINV.
  // Only the i+j<=3 limb products can contribute below bit 64.
  always_comb begin
    qinv_op0 = {32'b0, qinv_pp00_s2};
    qinv_op1 = {16'b0, qinv_pp01_s2, 16'b0};
    qinv_op2 = {16'b0, qinv_pp10_s2, 16'b0};
    qinv_op3 = {qinv_pp02_s2, 32'b0};
    qinv_op4 = {qinv_pp11_s2, 32'b0};
    qinv_op5 = {qinv_pp20_s2, 32'b0};
    qinv_op6 = {qinv_pp03_s2[15:0], 48'b0};
    qinv_op7 = {qinv_pp12_s2[15:0], 48'b0};
    qinv_op8 = {qinv_pp21_s2[15:0], 48'b0};
    qinv_op9 = {qinv_pp30_s2[15:0], 48'b0};

    qinv_csa0 = csa3(qinv_op0, qinv_op1, qinv_op2);
    qinv_csa1 = csa3(qinv_op3, qinv_op4, qinv_op5);
    qinv_csa2 = csa3(qinv_op6, qinv_op7, qinv_op8);
    qinv_csa3 = csa3(qinv_csa0[63:0], qinv_csa0[127:64], qinv_csa1[63:0]);
    qinv_csa4 = csa3(qinv_csa1[127:64], qinv_csa2[63:0], qinv_csa2[127:64]);
    qinv_csa5 = csa3(qinv_csa3[63:0], qinv_csa3[127:64], qinv_csa4[63:0]);
    qinv_csa6 = csa3(qinv_csa5[63:0], qinv_csa5[127:64], qinv_csa4[127:64]);
    qinv_csa7 = csa3(qinv_csa6[63:0], qinv_csa6[127:64], qinv_op9);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      a_r <= '0;
      b_r <= '0;
      t_s0 <= '0;
      t_s1 <= '0;
      t_s2 <= '0;
      t_s3 <= '0;
      t_s4 <= '0;
      t_s5 <= '0;
      t_s6 <= '0;
      t_s7 <= '0;
      x0_s1 <= '0;
      x1_s1 <= '0;
      x2_s1 <= '0;
      x3_s1 <= '0;
      m_s4 <= '0;
      qinv_pp00_s2 <= '0;
      qinv_pp01_s2 <= '0;
      qinv_pp10_s2 <= '0;
      qinv_pp02_s2 <= '0;
      qinv_pp11_s2 <= '0;
      qinv_pp20_s2 <= '0;
      qinv_pp03_s2 <= '0;
      qinv_pp12_s2 <= '0;
      qinv_pp21_s2 <= '0;
      qinv_pp30_s2 <= '0;
      qinv_sum_s3 <= '0;
      qinv_carry_s3 <= '0;
      term_hi_s5 <= '0;
      term_mid_s5 <= '0;
      term_lo_s5 <= '0;
      tmp_s6 <= '0;
      term_lo_s6 <= '0;
      mq_s7 <= '0;
      sum_s8 <= '0;
      u_s9 <= '0;
      y <= '0;
      valid_pipe <= '0;
    end else begin
      valid_pipe <= {valid_pipe[10:0], in_valid};

      // Step A input register isolates the upstream butterfly/data-memory path.
      a_r <= a;
      b_r <= b;
      t_s0 <= a_r * b_r;

      t_s1 <= t_s0;
      x0_s1 <= t_s0[15:0];
      x1_s1 <= t_s0[31:16];
      x2_s1 <= t_s0[47:32];
      x3_s1 <= t_s0[63:48];

      t_s2 <= t_s1;
      qinv_pp00_s2 <= x0_s1 * QINV_C0;
      qinv_pp01_s2 <= x0_s1 * QINV_C1;
      qinv_pp10_s2 <= x1_s1 * QINV_C0;
      qinv_pp02_s2 <= x0_s1 * QINV_C2;
      qinv_pp11_s2 <= x1_s1 * QINV_C1;
      qinv_pp20_s2 <= x2_s1 * QINV_C0;
      qinv_pp03_s2 <= x0_s1 * QINV_C3;
      qinv_pp12_s2 <= x1_s1 * QINV_C2;
      qinv_pp21_s2 <= x2_s1 * QINV_C1;
      qinv_pp30_s2 <= x3_s1 * QINV_C0;

      t_s3 <= t_s2;
      qinv_sum_s3 <= qinv_csa7[63:0];
      qinv_carry_s3 <= qinv_csa7[127:64];

      t_s4 <= t_s3;
      m_s4 <= qinv_sum_s3 + qinv_carry_s3;

      // m*Q = (m << 60) - (m << 14) + m, split across three
      // registered stages to avoid one long 128-bit add/subtract chain.
      t_s5 <= t_s4;
      term_hi_s5 <= {64'b0, m_s4} << 60;
      term_mid_s5 <= {64'b0, m_s4} << 14;
      term_lo_s5 <= {64'b0, m_s4};

      t_s6 <= t_s5;
      tmp_s6 <= term_hi_s5 - term_mid_s5;
      term_lo_s6 <= term_lo_s5;

      t_s7 <= t_s6;
      mq_s7 <= tmp_s6 + term_lo_s6;

      sum_s8 <= {1'b0, t_s7} + {1'b0, mq_s7};
      u_s9 <= sum_s8[128:64];

      if (u_s9 >= {1'b0, Q})
        y <= u_s9 - {1'b0, Q};
      else
        y <= u_s9[QW-1:0];
    end
  end

  always_comb out_valid = valid_pipe[11];
endmodule
