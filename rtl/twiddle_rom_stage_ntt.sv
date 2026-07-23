// Independent per-stage NTT-only Montgomery-domain twiddle ROM.
//
// Unlike twiddle_rom_stage, this module stores no INTT half. Stages 0..3
// therefore use 4+2+1+1 RAMB36 tiles instead of 8+4+2+1 for a combined table.
module twiddle_rom_stage_ntt #(
    parameter int STAGE_ID = 0,
    parameter int QW = 64,
    parameter int LOGN = 12,
    parameter int BRAM_STAGES = 4
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [LOGN-2:0]      index,
    input  logic [LOGN-2:0]      prefetch_index,
    output logic [QW-1:0]        twiddle
);
  import params_pkg::*;

  localparam int ROM_DEPTH = 1 << (LOGN - STAGE_ID - 1);
  localparam int AW = (ROM_DEPTH <= 1) ? 1 : $clog2(ROM_DEPTH);

  generate
    if (STAGE_ID == LOGN-1) begin : g_constant
      always_comb twiddle = R_MOD_Q;
    end else if (STAGE_ID < BRAM_STAGES) begin : g_block
      (* rom_style = "block" *) logic [QW-1:0] mem [0:ROM_DEPTH-1];
      logic [AW-1:0] read_address;

      initial begin
        case (STAGE_ID)
          0:  $readmemh("mem/twiddle_ntt_stage00.mem", mem);
          1:  $readmemh("mem/twiddle_ntt_stage01.mem", mem);
          2:  $readmemh("mem/twiddle_ntt_stage02.mem", mem);
          3:  $readmemh("mem/twiddle_ntt_stage03.mem", mem);
          4:  $readmemh("mem/twiddle_ntt_stage04.mem", mem);
          5:  $readmemh("mem/twiddle_ntt_stage05.mem", mem);
          6:  $readmemh("mem/twiddle_ntt_stage06.mem", mem);
          7:  $readmemh("mem/twiddle_ntt_stage07.mem", mem);
          8:  $readmemh("mem/twiddle_ntt_stage08.mem", mem);
          9:  $readmemh("mem/twiddle_ntt_stage09.mem", mem);
          10: $readmemh("mem/twiddle_ntt_stage10.mem", mem);
          11: $readmemh("mem/twiddle_ntt_stage11.mem", mem);
          default: $error("unsupported STAGE_ID=%0d", STAGE_ID);
        endcase
      end

      always_comb read_address = prefetch_index[AW-1:0];

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
          0:  $readmemh("mem/twiddle_ntt_stage00.mem", mem);
          1:  $readmemh("mem/twiddle_ntt_stage01.mem", mem);
          2:  $readmemh("mem/twiddle_ntt_stage02.mem", mem);
          3:  $readmemh("mem/twiddle_ntt_stage03.mem", mem);
          4:  $readmemh("mem/twiddle_ntt_stage04.mem", mem);
          5:  $readmemh("mem/twiddle_ntt_stage05.mem", mem);
          6:  $readmemh("mem/twiddle_ntt_stage06.mem", mem);
          7:  $readmemh("mem/twiddle_ntt_stage07.mem", mem);
          8:  $readmemh("mem/twiddle_ntt_stage08.mem", mem);
          9:  $readmemh("mem/twiddle_ntt_stage09.mem", mem);
          10: $readmemh("mem/twiddle_ntt_stage10.mem", mem);
          11: $readmemh("mem/twiddle_ntt_stage11.mem", mem);
          default: $error("unsupported STAGE_ID=%0d", STAGE_ID);
        endcase
      end

      always_comb begin
        read_address = index[AW-1:0];
        twiddle = mem[read_address];
      end
    end
  endgenerate
endmodule
