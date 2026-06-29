`timescale 1ns/1ps
module tb_mont_mul_wl;
  import params_pkg::*;

  localparam int TEST_CYCLES = 800;
  localparam int REF_LAT = 12;
  localparam int WL_LAT = 14;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic in_valid = 1'b0;
  logic [QW-1:0] a = '0;
  logic [QW-1:0] b = '0;

  logic ref_valid;
  logic [QW-1:0] ref_y;
  logic wl_valid;
  logic [QW-1:0] wl_y;

  logic expected_valid_ref [0:REF_LAT];
  logic [QW-1:0] expected_data_ref [0:REF_LAT];
  logic expected_valid_wl [0:WL_LAT];
  logic [QW-1:0] expected_data_wl [0:WL_LAT];

  integer cycle;
  integer errors = 0;
  integer i;

  always #5 clk = ~clk;

  mont_mul u_ref (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
      .a(a), .b(b), .out_valid(ref_valid), .y(ref_y)
  );

  mont_mul_wl u_wl (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
      .a(a), .b(b), .out_valid(wl_valid), .y(wl_y)
  );

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

  task automatic check_one(
      input string name,
      input logic got_valid,
      input logic [QW-1:0] got_data,
      input logic exp_valid,
      input logic [QW-1:0] exp_data
  );
    begin
      if (got_valid !== exp_valid) begin
        $display("%s valid mismatch cycle=%0d got=%b expected=%b",
                 name, cycle, got_valid, exp_valid);
        errors = errors + 1;
      end else if (got_valid && got_data !== exp_data) begin
        $display("%s data mismatch cycle=%0d got=%016x expected=%016x",
                 name, cycle, got_data, exp_data);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    for (i = 0; i <= REF_LAT; i = i + 1) begin
      expected_valid_ref[i] = 1'b0;
      expected_data_ref[i] = '0;
    end
    for (i = 0; i <= WL_LAT; i = i + 1) begin
      expected_valid_wl[i] = 1'b0;
      expected_data_wl[i] = '0;
    end

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    for (cycle = 0; cycle < TEST_CYCLES + WL_LAT + 4; cycle = cycle + 1) begin
      @(negedge clk);
      if (cycle < TEST_CYCLES) begin
        in_valid = ((cycle % 5) != 1) && ((cycle % 17) != 4);
        case (cycle)
          0: begin a = '0; b = '0; end
          1: begin a = Q - 1'b1; b = Q - 1'b1; end
          2: begin a = R_MOD_Q; b = R_MOD_Q; end
          3: begin a = Q - 2; b = Q - 3; end
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

      expected_valid_ref[0] = in_valid;
      expected_data_ref[0] = mont_ref(a, b);
      expected_valid_wl[0] = in_valid;
      expected_data_wl[0] = mont_ref(a, b);

      @(posedge clk);
      #1;
      check_one("mont_mul", ref_valid, ref_y,
                expected_valid_ref[REF_LAT-1], expected_data_ref[REF_LAT-1]);
      check_one("mont_mul_wl", wl_valid, wl_y,
                expected_valid_wl[WL_LAT-1], expected_data_wl[WL_LAT-1]);

      for (i = REF_LAT; i > 0; i = i - 1) begin
        expected_valid_ref[i] = expected_valid_ref[i-1];
        expected_data_ref[i] = expected_data_ref[i-1];
      end
      for (i = WL_LAT; i > 0; i = i - 1) begin
        expected_valid_wl[i] = expected_valid_wl[i-1];
        expected_data_wl[i] = expected_data_wl[i-1];
      end
    end

    if (errors)
      $fatal(1, "tb_mont_mul_wl FAIL errors=%0d", errors);

    $display("tb_mont_mul_wl PASS: mont_mul latency=%0d, mont_mul_wl latency=%0d",
             REF_LAT, WL_LAT);
    $finish;
  end
endmodule


