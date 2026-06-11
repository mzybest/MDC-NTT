// Combinational modular subtraction. Inputs must be reduced modulo Q.
module mod_sub #(
    parameter int QW = 64
) (
    input  logic [QW-1:0] a,
    input  logic [QW-1:0] b,
    output logic [QW-1:0] y
);
  import params_pkg::Q;

  always_comb begin
    if (a >= b)
      y = a - b;
    else
      y = a + Q - b;
  end
endmodule
