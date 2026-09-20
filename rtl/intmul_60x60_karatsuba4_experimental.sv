// Experimental unsigned 60x60 integer multiplier; accepts every 60-bit value.
// Four registered stages, II=1, no valid or clock enable:
//   S1: leaf operands / pre-adds, S2: nine leaf products,
//   S3: three child products, S4: the complete 120-bit product.
// The latency convention matches intmul_64x64_24x17: an input sampled into
// S1 reaches p at the fourth sampling edge. Reset is synchronous, active low.
//
// Split a=a0+2^30*a1 and b=b0+2^30*b1, with 30-bit a0/a1/b0/b1.
// P0=a0*b0, P2=a1*b1, S=(a0+a1)*(b0+b1), C=S-P0-P2 >= 0.
// Then p=P0+2^30*C+2^60*P2. P0/P2 are 60 bits, S is 62 bits,
// and C is 61 bits. The two 30-bit children split 15+15; the 31-bit
// sum child splits low 16 + high 15. Only the nine leaf products use DSPs:
// five 15x15, three 16x16 and one 17x17. Actual mapping needs synthesis.
module intmul_60x60_karatsuba4_experimental (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [59:0]  a,
    input  logic [59:0]  b,
    output logic [119:0] p
);
  // Every signal is unsigned. Explicit zero extension retains pre-add carry.
  // The sum child has two combinational pre-add levels before the S1 register.
  (* use_dsp = "no" *) logic [30:0] a_sum, b_sum;
  (* use_dsp = "no" *) logic [15:0] lo_a_sum, lo_b_sum;
  (* use_dsp = "no" *) logic [15:0] hi_a_sum, hi_b_sum;
  (* use_dsp = "no" *) logic [16:0] mid_a_sum, mid_b_sum;

  assign a_sum = {1'b0, a[29:0]} + {1'b0, a[59:30]};
  assign b_sum = {1'b0, b[29:0]} + {1'b0, b[59:30]};
  assign lo_a_sum = {1'b0, a[14:0]} + {1'b0, a[29:15]};
  assign lo_b_sum = {1'b0, b[14:0]} + {1'b0, b[29:15]};
  assign hi_a_sum = {1'b0, a[44:30]} + {1'b0, a[59:45]};
  assign hi_b_sum = {1'b0, b[44:30]} + {1'b0, b[59:45]};
  assign mid_a_sum = {1'b0, a_sum[15:0]} + {2'b0, a_sum[30:16]};
  assign mid_b_sum = {1'b0, b_sum[15:0]} + {2'b0, b_sum[30:16]};

  // S1: each 30-bit child needs 15/15/16-bit operands.
  logic [14:0] lo_a0_s1, lo_a1_s1, lo_b0_s1, lo_b1_s1;
  logic [15:0] lo_as_s1, lo_bs_s1;
  logic [14:0] hi_a0_s1, hi_a1_s1, hi_b0_s1, hi_b1_s1;
  logic [15:0] hi_as_s1, hi_bs_s1;
  // The 31-bit child needs 16/15/17-bit operands. Its pre-add is at most
  // (2^16-1)+(2^15-1)=98302, so all 17 bits must reach the ninth leaf.
  logic [15:0] mid_a0_s1, mid_b0_s1;
  logic [14:0] mid_a1_s1, mid_b1_s1;
  logic [16:0] mid_as_s1, mid_bs_s1;

  // S2: full product destinations have the SUM of the operand widths.
  // A direct assignment supplies that width to the SV multiply expression;
  // no narrow cast, concatenation or shift encloses a multiplication.
  (* use_dsp = "yes" *) logic [29:0] lo_p0_s2, lo_p2_s2;
  (* use_dsp = "yes" *) logic [31:0] lo_ps_s2;
  (* use_dsp = "yes" *) logic [29:0] hi_p0_s2, hi_p2_s2;
  (* use_dsp = "yes" *) logic [31:0] hi_ps_s2;
  (* use_dsp = "yes" *) logic [31:0] mid_p0_s2;
  (* use_dsp = "yes" *) logic [29:0] mid_p2_s2;
  (* use_dsp = "yes" *) logic [33:0] mid_ps_s2;

  // A child's ps=(x0+x1)*(y0+y1) >= p0+p2. Both sequential
  // subtractions are nonnegative, including their intermediate result.
  // Extend to the FULL ps width before subtracting, then narrow only the
  // proven cross term: 31 bits for 15+15, 32 bits for 16+15.
  (* use_dsp = "no" *) logic [31:0] lo_cross_full, hi_cross_full;
  (* use_dsp = "no" *) logic [33:0] mid_cross_full;
  assign lo_cross_full = lo_ps_s2 - {2'b0, lo_p0_s2} - {2'b0, lo_p2_s2};
  assign hi_cross_full = hi_ps_s2 - {2'b0, hi_p0_s2} - {2'b0, hi_p2_s2};
  assign mid_cross_full = mid_ps_s2 - {2'b0, mid_p0_s2} - {4'b0, mid_p2_s2};

  // Reconstruct with a guard bit. Concatenations make the shifted terms
  // 61/63 bits BEFORE addition, so no narrow left-shift can discard bits.
  // For reachable S2 values, all three sums' high guard bits are zero.
  (* use_dsp = "no" *) logic [60:0] lo_product_full, hi_product_full;
  (* use_dsp = "no" *) logic [62:0] mid_product_full;
  assign lo_product_full = {31'b0, lo_p0_s2}
                         + {15'b0, lo_cross_full[30:0], 15'b0}
                         + {1'b0, lo_p2_s2, 30'b0};
  assign hi_product_full = {31'b0, hi_p0_s2}
                         + {15'b0, hi_cross_full[30:0], 15'b0}
                         + {1'b0, hi_p2_s2, 30'b0};
  assign mid_product_full = {31'b0, mid_p0_s2}
                          + {15'b0, mid_cross_full[31:0], 16'b0}
                          + {1'b0, mid_p2_s2, 32'b0};

  // S3: the three child products belong to the same input transaction.
  logic [59:0] lo_product_s3, hi_product_s3;
  logic [61:0] mid_product_s3;

  // S4: S-P0-P2 is nonnegative and <2^61. Keep a full 62-bit
  // subtraction and a 121-bit reconstruction until their final narrowing.
  (* use_dsp = "no" *) logic [61:0] top_cross_full;
  (* use_dsp = "no" *) logic [120:0] product_full;
  assign top_cross_full = mid_product_s3
                        - {2'b0, lo_product_s3} - {2'b0, hi_product_s3};
  assign product_full = {61'b0, lo_product_s3}
                      + {30'b0, top_cross_full[60:0], 30'b0}
                      + {1'b0, hi_product_s3, 60'b0};

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      lo_a0_s1 <= '0; lo_a1_s1 <= '0;
      lo_b0_s1 <= '0; lo_b1_s1 <= '0;
      lo_as_s1 <= '0; lo_bs_s1 <= '0;
      hi_a0_s1 <= '0; hi_a1_s1 <= '0;
      hi_b0_s1 <= '0; hi_b1_s1 <= '0;
      hi_as_s1 <= '0; hi_bs_s1 <= '0;
      mid_a0_s1 <= '0; mid_a1_s1 <= '0; mid_as_s1 <= '0;
      mid_b0_s1 <= '0; mid_b1_s1 <= '0; mid_bs_s1 <= '0;
      lo_p0_s2 <= '0; lo_p2_s2 <= '0; lo_ps_s2 <= '0;
      hi_p0_s2 <= '0; hi_p2_s2 <= '0; hi_ps_s2 <= '0;
      mid_p0_s2 <= '0; mid_p2_s2 <= '0; mid_ps_s2 <= '0;
      lo_product_s3 <= '0; hi_product_s3 <= '0; mid_product_s3 <= '0;
      p <= '0;
    end else begin
      // Stage 1: preserve all three Karatsuba branches' operand alignment.
      lo_a0_s1 <= a[14:0];   lo_a1_s1 <= a[29:15];
      lo_b0_s1 <= b[14:0];   lo_b1_s1 <= b[29:15];
      lo_as_s1 <= lo_a_sum;  lo_bs_s1 <= lo_b_sum;
      hi_a0_s1 <= a[44:30];  hi_a1_s1 <= a[59:45];
      hi_b0_s1 <= b[44:30];  hi_b1_s1 <= b[59:45];
      hi_as_s1 <= hi_a_sum;  hi_bs_s1 <= hi_b_sum;
      mid_a0_s1 <= a_sum[15:0]; mid_a1_s1 <= a_sum[30:16];
      mid_b0_s1 <= b_sum[15:0]; mid_b1_s1 <= b_sum[30:16];
      mid_as_s1 <= mid_a_sum; mid_bs_s1 <= mid_b_sum;

      // Stage 2: exactly nine unsigned leaf multiplication operators.
      lo_p0_s2 <= lo_a0_s1 * lo_b0_s1;
      lo_p2_s2 <= lo_a1_s1 * lo_b1_s1;
      lo_ps_s2 <= lo_as_s1 * lo_bs_s1;
      hi_p0_s2 <= hi_a0_s1 * hi_b0_s1;
      hi_p2_s2 <= hi_a1_s1 * hi_b1_s1;
      hi_ps_s2 <= hi_as_s1 * hi_bs_s1;
      mid_p0_s2 <= mid_a0_s1 * mid_b0_s1;
      mid_p2_s2 <= mid_a1_s1 * mid_b1_s1;
      mid_ps_s2 <= mid_as_s1 * mid_bs_s1;

      // Stage 3: child reconstruction; discard only proven-zero guard bits.
      lo_product_s3 <= lo_product_full[59:0];
      hi_product_s3 <= hi_product_full[59:0];
      mid_product_s3 <= mid_product_full[61:0];

      // Stage 4: full result for a,b in [0,2^60); product_full[120]=0.
      p <= product_full[119:0];
    end
  end
endmodule
