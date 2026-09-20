// Experimental 64x64 unsigned multiplier: 2 cycles, initiation interval 1.
// Cycle 1 registers the same twelve 24x17 DSP-shaped partial products as
// intmul_64x64_24x17. Cycle 2 registers a combinational CSA tree plus one CPA.
// The five 3:2-compressor levels reduce row counts 12 -> 8 -> 6 -> 4 -> 3 -> 2.
// This is a timing/resource candidate; it does not replace the production core.
module intmul_64x64_csa2_experimental (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [63:0]  a,
    input  logic [63:0]  b,
    output logic [127:0] p
);
  // Four guard bits hold the sum of twelve arbitrary 128-bit rows. The real
  // aligned partial products sum to a*b < 2^128, so all final guard bits vanish.
  localparam int TREE_W = 132;

  logic [23:0] a0, a1, a2;
  logic [16:0] b0, b1, b2, b3;

  (* use_dsp = "yes" *) logic [40:0] p00_s1, p01_s1, p02_s1;
  (* use_dsp = "yes" *) logic [40:0] p10_s1, p11_s1, p12_s1;
  (* use_dsp = "yes" *) logic [40:0] p20_s1, p21_s1, p22_s1;
  (* use_dsp = "yes" *) logic [40:0] p30_s1, p31_s1, p32_s1;

  logic [TREE_W-1:0] row0 [0:11];
  logic [TREE_W-1:0] row1 [0:7];
  logic [TREE_W-1:0] row2 [0:5];
  logic [TREE_W-1:0] row3 [0:3];
  logic [TREE_W-1:0] row4 [0:2];
  logic [TREE_W-1:0] row5 [0:1];
  logic [TREE_W:0] final_sum;

  assign a0 = a[23:0];
  assign a1 = a[47:24];
  assign a2 = {8'b0, a[63:48]};
  assign b0 = b[16:0];
  assign b1 = b[33:17];
  assign b2 = b[50:34];
  assign b3 = {4'b0, b[63:51]};

  function automatic logic [TREE_W-1:0] align_pp (
      input logic [40:0] pp,
      input int unsigned shift
  );
    // Widen before shifting: shifting a 41-bit value first would lose bits.
    align_pp = ({{(TREE_W-41){1'b0}}, pp} << shift);
  endfunction

  function automatic logic [TREE_W-1:0] csa_sum (
      input logic [TREE_W-1:0] x, y, z
  );
    csa_sum = x ^ y ^ z;
  endfunction

  function automatic logic [TREE_W-1:0] csa_carry (
      input logic [TREE_W-1:0] x, y, z
  );
    csa_carry = ((x & y) | (x & z) | (y & z)) << 1;
  endfunction

  assign row0[0]  = align_pp(p00_s1, 0);
  assign row0[1]  = align_pp(p01_s1, 24);
  assign row0[2]  = align_pp(p02_s1, 48);
  assign row0[3]  = align_pp(p10_s1, 17);
  assign row0[4]  = align_pp(p11_s1, 41);
  assign row0[5]  = align_pp(p12_s1, 65);
  assign row0[6]  = align_pp(p20_s1, 34);
  assign row0[7]  = align_pp(p21_s1, 58);
  assign row0[8]  = align_pp(p22_s1, 82);
  assign row0[9]  = align_pp(p30_s1, 51);
  assign row0[10] = align_pp(p31_s1, 75);
  assign row0[11] = align_pp(p32_s1, 99);

  generate
    for (genvar i = 0; i < 4; i = i + 1) begin : g_level1
      assign row1[2*i]   = csa_sum(row0[3*i], row0[3*i+1], row0[3*i+2]);
      assign row1[2*i+1] = csa_carry(row0[3*i], row0[3*i+1], row0[3*i+2]);
    end
    for (genvar i = 0; i < 2; i = i + 1) begin : g_level2
      assign row2[2*i]   = csa_sum(row1[3*i], row1[3*i+1], row1[3*i+2]);
      assign row2[2*i+1] = csa_carry(row1[3*i], row1[3*i+1], row1[3*i+2]);
    end
    for (genvar i = 0; i < 2; i = i + 1) begin : g_level3
      assign row3[2*i]   = csa_sum(row2[3*i], row2[3*i+1], row2[3*i+2]);
      assign row3[2*i+1] = csa_carry(row2[3*i], row2[3*i+1], row2[3*i+2]);
    end
  endgenerate
  assign row2[4] = row1[6];
  assign row2[5] = row1[7];
  assign row4[0] = csa_sum(row3[0], row3[1], row3[2]);
  assign row4[1] = csa_carry(row3[0], row3[1], row3[2]);
  assign row4[2] = row3[3];
  assign row5[0] = csa_sum(row4[0], row4[1], row4[2]);
  assign row5[1] = csa_carry(row4[0], row4[1], row4[2]);
  assign final_sum = {1'b0, row5[0]} + {1'b0, row5[1]};

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      p00_s1 <= '0; p01_s1 <= '0; p02_s1 <= '0;
      p10_s1 <= '0; p11_s1 <= '0; p12_s1 <= '0;
      p20_s1 <= '0; p21_s1 <= '0; p22_s1 <= '0;
      p30_s1 <= '0; p31_s1 <= '0; p32_s1 <= '0;
      p <= '0;
    end else begin
      p00_s1 <= a0 * b0;
      p01_s1 <= a1 * b0;
      p02_s1 <= a2 * b0;
      p10_s1 <= a0 * b1;
      p11_s1 <= a1 * b1;
      p12_s1 <= a2 * b1;
      p20_s1 <= a0 * b2;
      p21_s1 <= a1 * b2;
      p22_s1 <= a2 * b2;
      p30_s1 <= a0 * b3;
      p31_s1 <= a1 * b3;
      p32_s1 <= a2 * b3;
      p <= final_sum[127:0];
    end
  end
endmodule
