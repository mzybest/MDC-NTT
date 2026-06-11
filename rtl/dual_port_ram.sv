// Simple synchronous true dual-port RAM with registered read data.
module dual_port_ram #(
    parameter int DW = 64,
    parameter int DEPTH = 4096,
    parameter int AW = $clog2(DEPTH)
) (
    input logic clk,
    input logic a_we,
    input logic [AW-1:0] a_addr,
    input logic [DW-1:0] a_wdata,
    output logic [DW-1:0] a_rdata,
    input logic b_we,
    input logic [AW-1:0] b_addr,
    input logic [DW-1:0] b_wdata,
    output logic [DW-1:0] b_rdata
);
  logic [DW-1:0] mem [0:DEPTH-1];
  always_ff @(posedge clk) begin
    if (a_we) mem[a_addr] <= a_wdata;
    if (b_we) mem[b_addr] <= b_wdata;
    a_rdata <= mem[a_addr];
    b_rdata <= mem[b_addr];
  end
endmodule
