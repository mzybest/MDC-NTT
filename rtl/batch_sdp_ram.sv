// BRAM-friendly simple dual-port RAM: one write port and one synchronous read.
// Data storage is intentionally not reset so Vivado can infer block RAM.
module batch_sdp_ram #(
    parameter int DW = 64,
    parameter int DEPTH = 4096,
    parameter int AW = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic              clk,
    input  logic              wr_en,
    input  logic [AW-1:0]     wr_addr,
    input  logic [DW-1:0]     wr_data,
    input  logic              rd_en,
    input  logic [AW-1:0]     rd_addr,
    output logic              rd_valid,
    output logic [DW-1:0]     rd_data
);
  (* ram_style = "block" *) logic [DW-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    rd_valid <= rd_en;
    if (wr_en)
      mem[wr_addr] <= wr_data;
    if (rd_en)
      rd_data <= mem[rd_addr];
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (wr_en && (wr_addr >= DEPTH))
      $fatal(1, "batch_sdp_ram write address out of range");
    if (rd_en && (rd_addr >= DEPTH))
      $fatal(1, "batch_sdp_ram read address out of range");
  end
`endif
endmodule