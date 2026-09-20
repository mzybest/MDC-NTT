// Experiment only: 1 input + 2 integer + 8 reduction + 1 correction = 12 cycles.
module mont_mul_wl_csa12_experimental (
    input logic clk, rst_n, in_valid,
    input logic [63:0] a, b,
    output logic out_valid,
    output logic [63:0] y
);
  import params_pkg::*;
  localparam int WL_LAT=12;
  logic [63:0] a_r,b_r;
  logic valid_r;
  logic [WL_LAT-2:0] valid_pipe;
  wire [127:0] product;
  wire [128:0] t[0:4];
  intmul_64x64_csa2_experimental u_intmul(
      .clk(clk),.rst_n(rst_n),.a(a_r),.b(b_r),.p(product));
  assign t[0]={1'b0,product};
  for(genvar i=0;i<4;i=i+1) begin:g_round
    wlmont_round16 #(.REDUCTION_IMPL(2)) u_round(
        .clk(clk),.rst_n(rst_n),.t_in(t[i]),.t_out(t[i+1]));
  end
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      a_r<='0;b_r<='0;valid_r<=0;valid_pipe<='0;y<='0;
    end else begin
      a_r<=a;b_r<=b;valid_r<=in_valid;
      valid_pipe<={valid_pipe[WL_LAT-3:0],valid_r};
      if(t[4][64:0]>={1'b0,Q}) y<=t[4][64:0]-{1'b0,Q};
      else y<=t[4][63:0];
    end
  end
  assign out_valid=valid_pipe[WL_LAT-2];
endmodule
