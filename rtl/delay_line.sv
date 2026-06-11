// Valid-qualified register delay. DEPTH=0 is a combinational bypass.
module delay_line #(
    parameter int DW = 64,
    parameter int DEPTH = 1
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
    end else begin : g_delay
      logic [DW-1:0] data_pipe [0:DEPTH-1];
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
