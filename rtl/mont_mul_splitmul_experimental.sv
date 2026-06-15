// Experimental Step B split-multiply implementation. This module is preserved
// for comparison only and is not the active Montgomery multiplier.
// y = a*b*R^-1 mod Q, where R=2^64 and inputs are reduced modulo Q.
module mont_mul_splitmul_experimental #(
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

  logic [63:0]  a_r;
  logic [63:0]  b_r;
  logic [31:0]  pp_s0 [0:15];
  logic [127:0] csa_l0 [0:15];
  logic [127:0] csa_l1 [0:10];
  logic [127:0] csa_l2 [0:7];
  logic [127:0] csa_l3 [0:5];
  logic [127:0] csa_l4 [0:3];
  logic [127:0] csa_l5 [0:2];
  logic [127:0] csa_l6 [0:1];
  logic [127:0] csa_sum_s1;
  logic [127:0] csa_carry_s1;
  logic [127:0] t_s0;
  logic [127:0] t_s1;
  logic [127:0] t_s2;
  logic [63:0]  m_s1;
  logic [127:0] mq_s2;
  logic [128:0] sum_s3;
  logic [64:0]  u_s4;
  logic [8:0]   valid_pipe;
  integer i;

  function automatic logic [31:0] mul16(
      input logic [15:0] x,
      input logic [15:0] z
  );
    mul16 = x * z;
  endfunction

  function automatic logic [127:0] csa_sum3(
      input logic [127:0] x,
      input logic [127:0] z,
      input logic [127:0] w
  );
    csa_sum3 = x ^ z ^ w;
  endfunction

  function automatic logic [127:0] csa_carry3(
      input logic [127:0] x,
      input logic [127:0] z,
      input logic [127:0] w
  );
    csa_carry3 = ((x & z) | (x & w) | (z & w)) << 1;
  endfunction

  always_comb begin
    // Align the sixteen registered 16x16 partial products.
    csa_l0[0]  = {{96{1'b0}}, pp_s0[0]};
    csa_l0[1]  = {{96{1'b0}}, pp_s0[1]}  << 16;
    csa_l0[2]  = {{96{1'b0}}, pp_s0[2]}  << 32;
    csa_l0[3]  = {{96{1'b0}}, pp_s0[3]}  << 48;
    csa_l0[4]  = {{96{1'b0}}, pp_s0[4]}  << 16;
    csa_l0[5]  = {{96{1'b0}}, pp_s0[5]}  << 32;
    csa_l0[6]  = {{96{1'b0}}, pp_s0[6]}  << 48;
    csa_l0[7]  = {{96{1'b0}}, pp_s0[7]}  << 64;
    csa_l0[8]  = {{96{1'b0}}, pp_s0[8]}  << 32;
    csa_l0[9]  = {{96{1'b0}}, pp_s0[9]}  << 48;
    csa_l0[10] = {{96{1'b0}}, pp_s0[10]} << 64;
    csa_l0[11] = {{96{1'b0}}, pp_s0[11]} << 80;
    csa_l0[12] = {{96{1'b0}}, pp_s0[12]} << 48;
    csa_l0[13] = {{96{1'b0}}, pp_s0[13]} << 64;
    csa_l0[14] = {{96{1'b0}}, pp_s0[14]} << 80;
    csa_l0[15] = {{96{1'b0}}, pp_s0[15]} << 96;

    // Carry-save compression avoids a wide carry chain in this stage.
    csa_l1[0]  = csa_sum3(csa_l0[0], csa_l0[1], csa_l0[2]);
    csa_l1[1]  = csa_carry3(csa_l0[0], csa_l0[1], csa_l0[2]);
    csa_l1[2]  = csa_sum3(csa_l0[3], csa_l0[4], csa_l0[5]);
    csa_l1[3]  = csa_carry3(csa_l0[3], csa_l0[4], csa_l0[5]);
    csa_l1[4]  = csa_sum3(csa_l0[6], csa_l0[7], csa_l0[8]);
    csa_l1[5]  = csa_carry3(csa_l0[6], csa_l0[7], csa_l0[8]);
    csa_l1[6]  = csa_sum3(csa_l0[9], csa_l0[10], csa_l0[11]);
    csa_l1[7]  = csa_carry3(csa_l0[9], csa_l0[10], csa_l0[11]);
    csa_l1[8]  = csa_sum3(csa_l0[12], csa_l0[13], csa_l0[14]);
    csa_l1[9]  = csa_carry3(csa_l0[12], csa_l0[13], csa_l0[14]);
    csa_l1[10] = csa_l0[15];

    csa_l2[0] = csa_sum3(csa_l1[0], csa_l1[1], csa_l1[2]);
    csa_l2[1] = csa_carry3(csa_l1[0], csa_l1[1], csa_l1[2]);
    csa_l2[2] = csa_sum3(csa_l1[3], csa_l1[4], csa_l1[5]);
    csa_l2[3] = csa_carry3(csa_l1[3], csa_l1[4], csa_l1[5]);
    csa_l2[4] = csa_sum3(csa_l1[6], csa_l1[7], csa_l1[8]);
    csa_l2[5] = csa_carry3(csa_l1[6], csa_l1[7], csa_l1[8]);
    csa_l2[6] = csa_l1[9];
    csa_l2[7] = csa_l1[10];

    csa_l3[0] = csa_sum3(csa_l2[0], csa_l2[1], csa_l2[2]);
    csa_l3[1] = csa_carry3(csa_l2[0], csa_l2[1], csa_l2[2]);
    csa_l3[2] = csa_sum3(csa_l2[3], csa_l2[4], csa_l2[5]);
    csa_l3[3] = csa_carry3(csa_l2[3], csa_l2[4], csa_l2[5]);
    csa_l3[4] = csa_l2[6];
    csa_l3[5] = csa_l2[7];

    csa_l4[0] = csa_sum3(csa_l3[0], csa_l3[1], csa_l3[2]);
    csa_l4[1] = csa_carry3(csa_l3[0], csa_l3[1], csa_l3[2]);
    csa_l4[2] = csa_sum3(csa_l3[3], csa_l3[4], csa_l3[5]);
    csa_l4[3] = csa_carry3(csa_l3[3], csa_l3[4], csa_l3[5]);

    csa_l5[0] = csa_sum3(csa_l4[0], csa_l4[1], csa_l4[2]);
    csa_l5[1] = csa_carry3(csa_l4[0], csa_l4[1], csa_l4[2]);
    csa_l5[2] = csa_l4[3];

    csa_l6[0] = csa_sum3(csa_l5[0], csa_l5[1], csa_l5[2]);
    csa_l6[1] = csa_carry3(csa_l5[0], csa_l5[1], csa_l5[2]);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      a_r <= '0;
      b_r <= '0;
      for (i = 0; i < 16; i = i + 1)
        pp_s0[i] <= '0;
      csa_sum_s1 <= '0;
      csa_carry_s1 <= '0;
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
      valid_pipe <= {valid_pipe[7:0], in_valid};

      // The first product uses registered 16x16 partial products. Their CSA
      // tree is registered before the final carry-propagate addition.
      a_r <= a;
      b_r <= b;
      pp_s0[0]  <= mul16(a_r[15:0],  b_r[15:0]);
      pp_s0[1]  <= mul16(a_r[15:0],  b_r[31:16]);
      pp_s0[2]  <= mul16(a_r[15:0],  b_r[47:32]);
      pp_s0[3]  <= mul16(a_r[15:0],  b_r[63:48]);
      pp_s0[4]  <= mul16(a_r[31:16], b_r[15:0]);
      pp_s0[5]  <= mul16(a_r[31:16], b_r[31:16]);
      pp_s0[6]  <= mul16(a_r[31:16], b_r[47:32]);
      pp_s0[7]  <= mul16(a_r[31:16], b_r[63:48]);
      pp_s0[8]  <= mul16(a_r[47:32], b_r[15:0]);
      pp_s0[9]  <= mul16(a_r[47:32], b_r[31:16]);
      pp_s0[10] <= mul16(a_r[47:32], b_r[47:32]);
      pp_s0[11] <= mul16(a_r[47:32], b_r[63:48]);
      pp_s0[12] <= mul16(a_r[63:48], b_r[15:0]);
      pp_s0[13] <= mul16(a_r[63:48], b_r[31:16]);
      pp_s0[14] <= mul16(a_r[63:48], b_r[47:32]);
      pp_s0[15] <= mul16(a_r[63:48], b_r[63:48]);
      csa_sum_s1 <= csa_l6[0];
      csa_carry_s1 <= csa_l6[1];
      t_s0 <= csa_sum_s1 + csa_carry_s1;
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

  always_comb out_valid = valid_pipe[8];
endmodule
