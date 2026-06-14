`timescale 1ns/1ps
module tb_mont_mul;
  import params_pkg::*;
  localparam int TEST_CYCLES = 600;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic in_valid = 1'b0;
  logic [QW-1:0] a = '0;
  logic [QW-1:0] b = '0;
  logic out_valid;
  logic [QW-1:0] y;

  logic expected_valid [0:MUL_LAT];
  logic [QW-1:0] expected_data [0:MUL_LAT];
  integer cycle;
  integer errors = 0;
  integer i;

  always #5 clk = ~clk;

  mont_mul u_dut (.*);

  function automatic [QW-1:0] mont_ref(
      input logic [QW-1:0] x,
      input logic [QW-1:0] z
  );
    logic [127:0] t;
    logic [127:0] qinv_product;
    logic [63:0] m;
    logic [127:0] mq;
    logic [128:0] total;
    logic [64:0] u;
    begin
      t = x * z;
      qinv_product = t[63:0] * QINV;
      m = qinv_product[63:0];
      mq = m * Q;
      total = {1'b0, t} + {1'b0, mq};
      u = total[128:64];
      mont_ref = (u >= {1'b0, Q}) ? u - {1'b0, Q} : u[QW-1:0];
    end
  endfunction

  initial begin
    for (i = 0; i <= MUL_LAT; i = i + 1) begin
      expected_valid[i] = 1'b0;
      expected_data[i] = '0;
    end

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    for (cycle = 0; cycle < TEST_CYCLES + MUL_LAT; cycle = cycle + 1) begin
      @(negedge clk);
      if (cycle < TEST_CYCLES) begin
        in_valid = ((cycle % 7) != 2) && ((cycle % 13) != 5);
        case (cycle)
          0: begin a = '0; b = '0; end
          1: begin a = Q - 1'b1; b = Q - 1'b1; end
          3: begin a = R_MOD_Q; b = R_MOD_Q; end
          default: begin
            a = {$urandom, $urandom} % Q;
            b = {$urandom, $urandom} % Q;
          end
        endcase
      end else begin
        in_valid = 1'b0;
        a = '0;
        b = '0;
      end
      expected_valid[0] = in_valid;
      expected_data[0] = mont_ref(a, b);

      @(posedge clk);
      #1;
      if (out_valid !== expected_valid[MUL_LAT-1]) begin
        $display("valid mismatch cycle=%0d rtl=%b expected=%b",
                 cycle, out_valid, expected_valid[MUL_LAT-1]);
        errors = errors + 1;
      end else if (out_valid && y !== expected_data[MUL_LAT-1]) begin
        $display("data mismatch cycle=%0d rtl=%016x expected=%016x",
                 cycle, y, expected_data[MUL_LAT-1]);
        errors = errors + 1;
      end

      for (i = MUL_LAT; i > 0; i = i - 1) begin
        expected_valid[i] = expected_valid[i-1];
        expected_data[i] = expected_data[i-1];
      end
    end

    if (errors)
      $fatal(1, "tb_mont_mul FAIL errors=%0d", errors);
    $display("tb_mont_mul PASS: %0d-cycle latency", MUL_LAT);
    $finish;
  end
endmodule
