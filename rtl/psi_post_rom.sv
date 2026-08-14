// Post-INTT factor ROM. The fused table folds N^-1 into psi^-index while
// preserving the Montgomery-domain representation expected by mont_mul.
module psi_post_rom #(
    parameter int QW = 64,
    parameter int LOGN = 12,
    parameter int N = 4096,
    parameter bit FUSE_N_INV = 1'b0
) (
    input  logic [LOGN-1:0] index,
    output logic [QW-1:0]   factor
);
  logic [QW-1:0] factor_mem [0:N-1];

  initial begin
    if (FUSE_N_INV)
      $readmemh("mem/psi_inv_ninv.mem", factor_mem);
    else
      $readmemh("mem/psi_inv.mem", factor_mem);
  end

  always_comb factor = factor_mem[index];
endmodule
