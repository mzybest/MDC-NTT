// Equal registered IO boundary: adds two common cycles to every kernel.
// BENCH_KIND=0 integer, 1 complete Montgomery. INT_IMPL=0 old, 1 CSA.
module wl_csa_bench_top #(
    parameter int BENCH_KIND=0, INT_IMPL=0
)(
    input logic clk,rst_n,in_valid,
    input logic [63:0] a,b,
    output logic out_valid,
    output logic [127:0] y
);
  logic [63:0] a_r,b_r;
  logic in_valid_r;
  wire [127:0] kernel_y;
  wire kernel_valid;
  generate
    if(BENCH_KIND==0) begin:g_integer
      localparam int LAT=(INT_IMPL==0)?4:2;
      logic [LAT-1:0] valid_pipe;
      always_ff @(posedge clk)
        if(!rst_n) valid_pipe<='0;
        else valid_pipe<={valid_pipe[LAT-2:0],in_valid_r};
      assign kernel_valid=valid_pipe[LAT-1];
      if(INT_IMPL==0) begin:g_old
        (* keep_hierarchy="yes" *) intmul_64x64_24x17 u_kernel(
            .clk(clk),.rst_n(rst_n),.a(a_r),.b(b_r),.p(kernel_y));
      end else begin:g_csa
        (* keep_hierarchy="yes" *) intmul_64x64_csa2_experimental u_kernel(
            .clk(clk),.rst_n(rst_n),.a(a_r),.b(b_r),.p(kernel_y));
      end
    end else begin:g_mont
      wire [63:0] mont_y;
      assign kernel_y={64'b0,mont_y};
      if(INT_IMPL==0) begin:g_old
        (* keep_hierarchy="yes" *) mont_mul_wl #(.QW(64),.REDUCTION_IMPL(2)) u_kernel(
            .clk(clk),.rst_n(rst_n),.in_valid(in_valid_r),.a(a_r),.b(b_r),
            .out_valid(kernel_valid),.y(mont_y));
      end else begin:g_csa
        (* keep_hierarchy="yes" *) mont_mul_wl_csa12_experimental u_kernel(
            .clk(clk),.rst_n(rst_n),.in_valid(in_valid_r),.a(a_r),.b(b_r),
            .out_valid(kernel_valid),.y(mont_y));
      end
    end
  endgenerate
  always_ff @(posedge clk) begin
    if(!rst_n) begin a_r<='0;b_r<='0;in_valid_r<=0;y<='0;out_valid<=0;end
    else begin a_r<=a;b_r<=b;in_valid_r<=in_valid;y<=kernel_y;out_valid<=kernel_valid;end
  end
endmodule
