// Combinational negacyclic pre/post-factor ROM.
// Both tables contain Montgomery-domain values: psi^(+/-index) * R mod Q.
module psi_rom #(
    parameter int QW = 64,
    parameter int LOGN = 12,
    parameter int N = 4096
) (
    input  logic             table_sel,
    input  logic [LOGN-1:0]  index,
    output logic [QW-1:0]    factor
);
  import params_pkg::*;
  logic [QW-1:0] psi_mem [0:N-1];
  logic [QW-1:0] psi_inv_mem [0:N-1];

  initial begin
    $readmemh("mem/psi.mem", psi_mem);
    $readmemh("mem/psi_inv.mem", psi_inv_mem);
  end

  always_comb begin
    if (table_sel == PSI_INV)
      factor = psi_inv_mem[index];
    else
      factor = psi_mem[index];
  end
endmodule
