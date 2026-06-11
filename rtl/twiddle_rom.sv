// Stage-major Montgomery-domain twiddle ROM.
// The clk port is retained for a future synchronous BRAM implementation.
module twiddle_rom #(
    parameter int QW = 64,
    parameter int LOGN = 12
) (
    input  logic              clk,
    input  logic [1:0]        mode,
    input  logic [3:0]        stage_id,
    input  logic [LOGN-1:0]   index,
    output logic [QW-1:0]     twiddle
);
  import params_pkg::*;
  localparam int ROM_DEPTH = LOGN * (1 << (LOGN-1));
  logic [QW-1:0] ntt_mem [0:ROM_DEPTH-1];
  logic [QW-1:0] intt_mem [0:ROM_DEPTH-1];
  logic [$clog2(ROM_DEPTH)-1:0] address;

  initial begin
    $readmemh("mem/twiddle_ntt.mem", ntt_mem);
    $readmemh("mem/twiddle_intt.mem", intt_mem);
  end

  always_comb begin
    address = stage_id * (1 << (LOGN-1)) + index[LOGN-2:0];
    if (stage_id >= LOGN)
      twiddle = R_MOD_Q;
    else if (mode == MODE_NTT)
      twiddle = ntt_mem[address];
    else
      twiddle = intt_mem[address];
  end

  logic unused_clk;
  always_comb unused_clk = clk;
endmodule
