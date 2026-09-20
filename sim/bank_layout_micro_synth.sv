// Isolated BRAM banking micro-synthesis harnesses.
//
// The two tops expose every bank's read/write interface independently so the
// synthesizer cannot legally merge banks or remove an unobserved memory.

module bank_2x2048x64_top (
    input  logic          clk,
    input  logic          rst_n,
    input  logic [1:0]    wr_en,
    input  logic [21:0]   wr_addr,
    input  logic [127:0]  wr_data,
    input  logic [1:0]    rd_en,
    input  logic [21:0]   rd_addr,
    output logic [1:0]    rd_valid,
    output logic [127:0]  rd_data
);
  genvar bank;
  generate
    for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
      (* keep_hierarchy = "yes" *)
      top_data_bram #(.DW(64), .DEPTH(2048), .AW(11)) u_bank (
          .clk(clk),
          .rst_n(rst_n),
          .wr_en(wr_en[bank]),
          .wr_addr(wr_addr[bank*11 +: 11]),
          .wr_data(wr_data[bank*64 +: 64]),
          .rd_en(rd_en[bank]),
          .rd_addr(rd_addr[bank*11 +: 11]),
          .rd_valid(rd_valid[bank]),
          .rd_data(rd_data[bank*64 +: 64])
      );
    end
  endgenerate
endmodule

module bank_4x1024x64_top (
    input  logic          clk,
    input  logic          rst_n,
    input  logic [3:0]    wr_en,
    input  logic [39:0]   wr_addr,
    input  logic [255:0]  wr_data,
    input  logic [3:0]    rd_en,
    input  logic [39:0]   rd_addr,
    output logic [3:0]    rd_valid,
    output logic [255:0]  rd_data
);
  genvar bank;
  generate
    for (bank = 0; bank < 4; bank = bank + 1) begin : g_bank
      (* keep_hierarchy = "yes" *)
      top_data_bram #(.DW(64), .DEPTH(1024), .AW(10)) u_bank (
          .clk(clk),
          .rst_n(rst_n),
          .wr_en(wr_en[bank]),
          .wr_addr(wr_addr[bank*10 +: 10]),
          .wr_data(wr_data[bank*64 +: 64]),
          .rd_en(rd_en[bank]),
          .rd_addr(rd_addr[bank*10 +: 10]),
          .rd_valid(rd_valid[bank]),
          .rd_data(rd_data[bank*64 +: 64])
      );
    end
  endgenerate
endmodule
