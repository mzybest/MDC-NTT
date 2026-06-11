// Combinational modular addition. Inputs must be reduced modulo Q.
module mod_add #(
    parameter int QW = 64
) (
    input  logic [QW-1:0] a,
    input  logic [QW-1:0] b,
    output logic [QW-1:0] y
);
  import params_pkg::Q;
  logic [QW:0] sum_ext;

  always_comb begin
    sum_ext = {1'b0, a} + {1'b0, b};
    if (sum_ext >= {1'b0, Q})
      y = sum_ext - {1'b0, Q};
    else
      y = sum_ext[QW-1:0];
  end
endmodule
