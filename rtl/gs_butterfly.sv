// Gentleman-Sande butterfly. Latency is MUL_LAT+1 cycles, including the
// registered input stage before the add/subtract logic.
module gs_butterfly #(
    parameter int QW = 64,
    parameter int MUL_LAT = 14,
    parameter bit USE_WL_MONT = 1'b1,
    parameter bit USE_SUM_RETIME = 1'b0
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          in_valid,
    input  logic [QW-1:0] a,
    input  logic [QW-1:0] b,
    input  logic [QW-1:0] twiddle,
    output logic          out_valid,
    output logic [QW-1:0] y0,
    output logic [QW-1:0] y1
);
  logic [QW-1:0] a_r;
  logic [QW-1:0] b_r;
  logic [QW-1:0] twiddle_r;
  logic valid_r;
  logic [QW-1:0] sum;
  logic [QW-1:0] diff;
  logic sum_valid;
  logic mul_valid;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      a_r <= '0;
      b_r <= '0;
      twiddle_r <= '0;
      valid_r <= 1'b0;
    end else begin
      a_r <= a;
      b_r <= b;
      twiddle_r <= twiddle;
      valid_r <= in_valid;
    end
  end

  mod_add #(.QW(QW)) u_add (.a(a_r), .b(b_r), .y(sum));
  mod_sub #(.QW(QW)) u_sub (.a(a_r), .b(b_r), .y(diff));
  generate
    if (USE_SUM_RETIME) begin : g_sum_retime
      localparam int RETIMED_DEPTH = (MUL_LAT > 0) ? MUL_LAT-1 : 0;
      (* shreg_extract = "no" *) logic [QW-1:0] sum_boundary_r;
      logic sum_boundary_valid_r;

      always_ff @(posedge clk) begin
        if (!rst_n) begin
          sum_boundary_r <= '0;
          sum_boundary_valid_r <= 1'b0;
        end else begin
          sum_boundary_r <= sum;
          sum_boundary_valid_r <= valid_r;
        end
      end

      delay_line #(.DW(QW), .DEPTH(RETIMED_DEPTH)) u_sum_delay (
          .clk(clk), .rst_n(rst_n),
          .in_valid(sum_boundary_valid_r), .din(sum_boundary_r),
          .out_valid(sum_valid), .dout(y0)
      );
    end else begin : g_sum_direct
      delay_line #(.DW(QW), .DEPTH(MUL_LAT)) u_sum_delay (
          .clk(clk), .rst_n(rst_n), .in_valid(valid_r), .din(sum),
          .out_valid(sum_valid), .dout(y0)
      );
    end
  endgenerate
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_MONT)) u_mul (
      .clk(clk), .rst_n(rst_n), .in_valid(valid_r), .a(diff), .b(twiddle_r),
      .out_valid(mul_valid), .y(y1)
  );

  always_comb out_valid = sum_valid & mul_valid;
endmodule



