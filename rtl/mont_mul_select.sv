// Selectable Montgomery multiplier wrapper.
//
// USE_WL_MONT=0 keeps the current active mont_mul implementation.
// USE_WL_MONT=1 selects the experimental word-level Montgomery multiplier.
module mont_mul_select #(
    parameter int QW = 64,
    parameter bit USE_WL_MONT = 1'b0
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          in_valid,
    input  logic [QW-1:0] a,
    input  logic [QW-1:0] b,
    output logic          out_valid,
    output logic [QW-1:0] y
);
  generate
    if (USE_WL_MONT) begin : g_wl
      mont_mul_wl #(.QW(QW)) u_mul (
          .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
          .a(a), .b(b), .out_valid(out_valid), .y(y)
      );
    end else begin : g_current
      mont_mul #(.QW(QW)) u_mul (
          .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
          .a(a), .b(b), .out_valid(out_valid), .y(y)
      );
    end
  endgenerate
endmodule
