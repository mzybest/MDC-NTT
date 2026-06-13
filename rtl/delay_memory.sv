// Parameterized valid-qualified cycle delay.
//
// IMPL values:
//   "AUTO"  : DEPTH >= 128 selects the RAM circular buffer, otherwise SHIFT.
//   "RAM"   : BRAM-friendly circular buffer with registered output.
//   "SHIFT" : register/SRL-friendly shift delay.
//
// A sample accepted with in_valid at cycle t appears with out_valid at
// cycle t+DEPTH. The storage advances every clock, so valid bubbles are
// delayed by exactly the same number of cycles as data.
module delay_memory #(
    parameter int DW = 64,
    parameter int DEPTH = 1,
    parameter string IMPL = "AUTO"
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          in_valid,
    input  logic [DW-1:0] din,
    output logic          out_valid,
    output logic [DW-1:0] dout
);
  generate
    if (DEPTH == 0) begin : g_bypass
      always_comb begin
        out_valid = in_valid;
        dout = din;
      end
    end else if ((IMPL == "RAM") || ((IMPL == "AUTO") && (DEPTH >= 128))) begin : g_ram
      // The registered synchronous RAM output contributes one delay cycle.
      // The circular storage therefore holds DEPTH-1 earlier cycles.
      localparam int RAM_DEPTH = DEPTH - 1;
      localparam int AW = (RAM_DEPTH <= 1) ? 1 : $clog2(RAM_DEPTH);

      // Vivado can map the data array to BRAM. The valid bits remain a small
      // control memory so reset does not require clearing the data RAM.
      (* ram_style = "block" *) logic [DW-1:0] data_mem [0:RAM_DEPTH-1];
      logic valid_mem [0:RAM_DEPTH-1];
      logic [AW-1:0] pointer;
      integer i;

      always_ff @(posedge clk) begin
        if (!rst_n) begin
          pointer <= '0;
          out_valid <= 1'b0;
          dout <= '0;
          for (i = 0; i < RAM_DEPTH; i = i + 1)
            valid_mem[i] <= 1'b0;
        end else begin
          // Nonblocking assignments read the old addressed word before the
          // current input replaces it, implementing a DEPTH-cycle ring delay.
          dout <= data_mem[pointer];
          out_valid <= valid_mem[pointer];
          data_mem[pointer] <= din;
          valid_mem[pointer] <= in_valid;

          if (pointer == RAM_DEPTH-1)
            pointer <= '0;
          else
            pointer <= pointer + 1'b1;
        end
      end
    end else begin : g_shift
      (* shreg_extract = "yes" *) logic [DW-1:0] data_pipe [0:DEPTH-1];
      logic [DEPTH-1:0] valid_pipe;
      integer i;

      always_ff @(posedge clk) begin
        if (!rst_n) begin
          valid_pipe <= '0;
          for (i = 0; i < DEPTH; i = i + 1)
            data_pipe[i] <= '0;
        end else begin
          valid_pipe[0] <= in_valid;
          data_pipe[0] <= din;
          for (i = 1; i < DEPTH; i = i + 1) begin
            valid_pipe[i] <= valid_pipe[i-1];
            data_pipe[i] <= data_pipe[i-1];
          end
        end
      end

      always_comb begin
        out_valid = valid_pipe[DEPTH-1];
        dout = data_pipe[DEPTH-1];
      end
    end
  endgenerate
endmodule
