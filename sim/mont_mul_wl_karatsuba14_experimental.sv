// Experimental core-only 60-bit Karatsuba frontend, 14 cycles, II=1.
// REDUCTION_IMPL: 0 = original DSP, 1 = sparse q-high, 2 = fused correction.
// Low-cost implementations specialize the project modulus without changing R.
module mont_mul_wl_karatsuba14_experimental #(
    parameter int QW = 64,
    parameter int REDUCTION_IMPL = 2
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

  localparam int WL_LAT = 14;
  localparam int POST_INPUT_LAT = WL_LAT - 1;
  localparam logic [15:0] EXPECT_Q_LO = 16'hc001;
  localparam logic [15:0] EXPECT_NEG_Q0_INV = 16'hbfff;

  logic [QW-1:0] a_r;
  logic [QW-1:0] b_r;
  logic valid_r;
  logic [119:0] product60;
  logic [127:0] product;
  logic [128:0] t0;
  logic [128:0] t1;
  logic [128:0] t2;
  logic [128:0] t3;
  logic [128:0] t4;
  logic [POST_INPUT_LAT-1:0] valid_pipe;

  generate
    if (QW != 64) begin : g_bad_width
      initial $error("mont_mul_wl currently supports QW=64 only");
    end
    if (Q[15:0] != EXPECT_Q_LO) begin : g_bad_q_low
      initial $error("mont_mul_wl expects Q[15:0]=16'hc001");
    end
  endgenerate

  intmul_60x60_karatsuba4_experimental u_intmul (
      .clk(clk),
      .rst_n(rst_n),
      .a(a_r[59:0]),
      .b(b_r[59:0]),
      .p(product60)
  );

  assign product = {8'b0, product60};
  always_comb t0 = {1'b0, product};

  wlmont_round16 #(.REDUCTION_IMPL(REDUCTION_IMPL)) u_round0 (.clk(clk), .rst_n(rst_n), .t_in(t0), .t_out(t1));
  wlmont_round16 #(.REDUCTION_IMPL(REDUCTION_IMPL)) u_round1 (.clk(clk), .rst_n(rst_n), .t_in(t1), .t_out(t2));
  wlmont_round16 #(.REDUCTION_IMPL(REDUCTION_IMPL)) u_round2 (.clk(clk), .rst_n(rst_n), .t_in(t2), .t_out(t3));
  wlmont_round16 #(.REDUCTION_IMPL(REDUCTION_IMPL)) u_round3 (.clk(clk), .rst_n(rst_n), .t_in(t3), .t_out(t4));

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      a_r <= '0;
      b_r <= '0;
      valid_r <= 1'b0;
      valid_pipe <= '0;
      y <= '0;
    end else begin
      a_r <= a;
      b_r <= b;
      valid_r <= in_valid;
      valid_pipe <= {valid_pipe[POST_INPUT_LAT-2:0], valid_r};
      if (t4[64:0] >= {1'b0, Q})
        y <= t4[64:0] - {1'b0, Q};
      else
        y <= t4[QW-1:0];
    end
  end

  always_comb out_valid = valid_pipe[POST_INPUT_LAT-1];
  // This variant is intended only for normalized core operands.
  // R stays 2^64; only the complete integer product is zero-extended.
  // synthesis translate_off
  initial begin
    if (Q[63:60] != 0) $fatal(1, "Karatsuba60 requires a modulus below 2^60");
  end
  always @(posedge clk) begin
    if (rst_n && in_valid) begin
      if ($isunknown({a,b}) || a >= Q || b >= Q)
        $fatal(1, "Karatsuba core input must be known and canonical (<Q)");
    end
    if (rst_n && out_valid) begin
      if ($isunknown(y) || y >= Q)
        $fatal(1, "Karatsuba Montgomery output must be canonical");
    end
  end
  // synthesis translate_on
endmodule
