// Pointwise multiplication of two Montgomery-domain NTT coefficients.
module pointwise_mul #(
    parameter int QW = 64,
    parameter bit USE_WL_POINTWISE = 1'b0
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          in_valid,
    input  logic [QW-1:0] a_ntt,
    input  logic [QW-1:0] b_ntt,
    output logic          out_valid,
    output logic [QW-1:0] c_ntt
);
  mont_mul_select #(
      .QW(QW),
      .USE_WL_MONT(USE_WL_POINTWISE)
  ) u_mul (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
      .a(a_ntt), .b(b_ntt), .out_valid(out_valid), .y(c_ntt)
  );
endmodule

