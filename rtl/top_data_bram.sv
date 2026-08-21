// One-write/one-read synchronous RAM for top-level polynomial data banks.
// The memory array is intentionally not reset so Vivado can infer block RAM.
module top_data_bram #(
    parameter int DW = 64,
    parameter int DEPTH = 2048,
    parameter int AW = $clog2(DEPTH)
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          wr_en,
    input  logic [AW-1:0] wr_addr,
    input  logic [DW-1:0] wr_data,
    input  logic          rd_en,
    input  logic [AW-1:0] rd_addr,
    output logic          rd_valid,
    output logic [DW-1:0] rd_data
);
  (* ram_style = "block" *) logic [DW-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (wr_en)
      mem[wr_addr] <= wr_data;
    if (rd_en)
      rd_data <= mem[rd_addr];
  end

  always_ff @(posedge clk) begin
    if (!rst_n)
      rd_valid <= 1'b0;
    else
      rd_valid <= rd_en;
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && wr_en && rd_en && (wr_addr == rd_addr))
      $fatal(1, "top_data_bram same-address read/write collision addr=%0d", wr_addr);
  end
`endif
endmodule
