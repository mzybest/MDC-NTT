// Experimental word-level Montgomery multiplier.
//
// This module is intentionally not wired into the active datapath yet. It is a
// comparison candidate for replacing mont_mul after standalone verification and
// synthesis measurement.
module mont_mul_wl #(
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

  localparam int WL_LAT = 14;
  localparam int POST_INPUT_LAT = WL_LAT - 1;
  localparam logic [15:0] EXPECT_Q_LO = 16'hc001;
  localparam logic [15:0] EXPECT_NEG_Q0_INV = 16'hbfff;

  logic [QW-1:0] a_r;
  logic [QW-1:0] b_r;
  logic valid_r;
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

  intmul_64x64_24x17 u_intmul (
      .clk(clk),
      .rst_n(rst_n),
      .a(a_r),
      .b(b_r),
      .p(product)
  );

  always_comb t0 = {1'b0, product};

  wlmont_round16 u_round0 (.clk(clk), .rst_n(rst_n), .t_in(t0), .t_out(t1));
  wlmont_round16 u_round1 (.clk(clk), .rst_n(rst_n), .t_in(t1), .t_out(t2));
  wlmont_round16 u_round2 (.clk(clk), .rst_n(rst_n), .t_in(t2), .t_out(t3));
  wlmont_round16 u_round3 (.clk(clk), .rst_n(rst_n), .t_in(t3), .t_out(t4));

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
endmodule
