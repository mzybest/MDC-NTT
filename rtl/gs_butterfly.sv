// Gentleman-Sande butterfly. Latency is MUL_LAT cycles.
module gs_butterfly #(
    parameter int QW = 64,
    parameter int MUL_LAT = 3
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          in_valid,
    input  logic [QW-1:0] a,
    input  logic [QW-1:0] b,
    input  logic [QW-1:0] twiddle,
    output logic          out_valid,
    output logic [QW-1:0] y0,
    output logic [QW-1:0] y1
);
  logic [QW-1:0] sum;
  logic [QW-1:0] diff;
  logic sum_valid;
  logic mul_valid;

  mod_add #(.QW(QW)) u_add (.a(a), .b(b), .y(sum));
  mod_sub #(.QW(QW)) u_sub (.a(a), .b(b), .y(diff));
  delay_line #(.DW(QW), .DEPTH(MUL_LAT)) u_sum_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .din(sum),
      .out_valid(sum_valid), .dout(y0)
  );
  mont_mul #(.QW(QW)) u_mul (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .a(diff), .b(twiddle),
      .out_valid(mul_valid), .y(y1)
  );

  always_comb out_valid = sum_valid & mul_valid;
endmodule
