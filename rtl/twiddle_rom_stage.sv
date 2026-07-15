// Compact per-stage Montgomery-domain twiddle ROM.
//
// Stages below BRAM_STAGES use a synchronous block ROM. The caller supplies
// the next accepted sample's index so the registered ROM output is prefetched
// without adding a visible stage cycle. Later stages use small asynchronous
// distributed ROMs; the final stage is the constant Montgomery one.
module twiddle_rom_stage #(
    parameter int STAGE_ID = 0,
    parameter int QW = 64,
    parameter int LOGN = 12,
    parameter int BRAM_STAGES = 4
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [1:0]           mode,
    input  logic [LOGN-2:0]      index,
    input  logic [LOGN-2:0]      prefetch_index,
    output logic [QW-1:0]        twiddle
);
  import params_pkg::*;

  localparam int DISTANCE = 1 << (LOGN - STAGE_ID - 1);
  localparam int ROM_DEPTH = 2 * DISTANCE;
  localparam int AW = (ROM_DEPTH <= 1) ? 1 : $clog2(ROM_DEPTH);

  function automatic logic [AW-1:0] table_address(
      input logic [1:0] selected_mode,
      input logic [LOGN-2:0] selected_index
  );
    logic [AW-1:0] local_index;
    begin
      local_index = selected_index;
      if (selected_mode == MODE_NTT)
        table_address = local_index;
      else
        table_address = DISTANCE + local_index;
    end
  endfunction

  generate
    if (STAGE_ID == LOGN-1) begin : g_constant
      always_comb twiddle = R_MOD_Q;
    end else if (STAGE_ID < BRAM_STAGES) begin : g_block
      (* rom_style = "block" *) logic [QW-1:0] mem [0:ROM_DEPTH-1];
      logic [AW-1:0] read_address;

      initial begin
        case (STAGE_ID)
          0:  $readmemh("mem/twiddle_stage00.mem", mem);
          1:  $readmemh("mem/twiddle_stage01.mem", mem);
          2:  $readmemh("mem/twiddle_stage02.mem", mem);
          3:  $readmemh("mem/twiddle_stage03.mem", mem);
          4:  $readmemh("mem/twiddle_stage04.mem", mem);
          5:  $readmemh("mem/twiddle_stage05.mem", mem);
          6:  $readmemh("mem/twiddle_stage06.mem", mem);
          7:  $readmemh("mem/twiddle_stage07.mem", mem);
          8:  $readmemh("mem/twiddle_stage08.mem", mem);
          9:  $readmemh("mem/twiddle_stage09.mem", mem);
          10: $readmemh("mem/twiddle_stage10.mem", mem);
          11: $readmemh("mem/twiddle_stage11.mem", mem);
          default: $error("unsupported STAGE_ID=%0d", STAGE_ID);
        endcase
      end

      always_comb read_address = table_address(mode, prefetch_index);

      always_ff @(posedge clk) begin
        if (!rst_n)
          twiddle <= R_MOD_Q;
        else
          twiddle <= mem[read_address];
      end
    end else begin : g_distributed
      (* rom_style = "distributed" *) logic [QW-1:0] mem [0:ROM_DEPTH-1];
      logic [AW-1:0] read_address;

      initial begin
        case (STAGE_ID)
          0:  $readmemh("mem/twiddle_stage00.mem", mem);
          1:  $readmemh("mem/twiddle_stage01.mem", mem);
          2:  $readmemh("mem/twiddle_stage02.mem", mem);
          3:  $readmemh("mem/twiddle_stage03.mem", mem);
          4:  $readmemh("mem/twiddle_stage04.mem", mem);
          5:  $readmemh("mem/twiddle_stage05.mem", mem);
          6:  $readmemh("mem/twiddle_stage06.mem", mem);
          7:  $readmemh("mem/twiddle_stage07.mem", mem);
          8:  $readmemh("mem/twiddle_stage08.mem", mem);
          9:  $readmemh("mem/twiddle_stage09.mem", mem);
          10: $readmemh("mem/twiddle_stage10.mem", mem);
          11: $readmemh("mem/twiddle_stage11.mem", mem);
          default: $error("unsupported STAGE_ID=%0d", STAGE_ID);
        endcase
      end

      always_comb begin
        read_address = table_address(mode, index);
        twiddle = mem[read_address];
      end
    end
  endgenerate
endmodule
