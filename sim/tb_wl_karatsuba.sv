`timescale 1ns/1ps
// Independent arithmetic references for the four-cycle integer frontend and
// fourteen-cycle complete Montgomery multiplier. Old tests/goldens are intact.
module tb_wl_karatsuba;
  import params_pkg::*;

  localparam int INT_LAT = 4;
  localparam int MONT_LAT = 14;
  localparam int EDGE_COUNT = 24;
  localparam logic [63:0] STIM_SEED = 64'h20260915_9d5a713b;
  localparam logic [59:0] MAX60 = 60'hfffffffffffffff;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic in_valid = 1'b0;
  logic [59:0] ia = '0, ib = '0;
  logic [63:0] ma = '0, mb = '0;
  wire [127:0] integer_old;
  wire [119:0] integer_karatsuba;
  wire [63:0] mont_y [0:1];
  wire mont_valid [0:1];

  logic integer_expected_valid [0:INT_LAT-1];
  logic mont_expected_valid [0:MONT_LAT-1];
  logic [127:0] integer_expected [0:INT_LAT-1];
  logic [63:0] mont_expected [0:MONT_LAT-1];
  logic [59:0] edges [0:EDGE_COUNT-1];
  logic [63:0] rng_state;
  integer integer_checked [0:1];
  integer mont_checked [0:1];
  integer integer_discarded [0:1];
  integer mont_discarded [0:1];
  integer issued = 0;
  integer cycles = 0;
  integer errors = 0;
  integer integer_above_q = 0;
  integer bubble_cycles = 0;
  integer reset_cycles = 0;
  integer post_reset_issued = 0;
  integer n, j, k;

  always #5 clk = ~clk;

  intmul_64x64_24x17 u_integer_old (
      .clk(clk), .rst_n(rst_n),
      .a({4'b0, ia}), .b({4'b0, ib}), .p(integer_old)
  );
  intmul_60x60_karatsuba4_experimental u_integer_karatsuba (
      .clk(clk), .rst_n(rst_n), .a(ia), .b(ib), .p(integer_karatsuba)
  );
  mont_mul_wl #(.QW(64), .REDUCTION_IMPL(2)) u_mont_old (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
      .a(ma), .b(mb), .out_valid(mont_valid[0]), .y(mont_y[0])
  );
  mont_mul_wl_karatsuba14_experimental #(.QW(64), .REDUCTION_IMPL(2)) u_mont_karatsuba (
      .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
      .a(ma), .b(mb), .out_valid(mont_valid[1]), .y(mont_y[1])
  );

  // This reference is one 64-bit REDC step with R=2^64. It neither reuses
  // either DUT output nor duplicates their four word-level reduction rounds.
  function automatic logic [63:0] mont_ref(
      input logic [63:0] a, b
  );
    logic [127:0] product;
    logic [127:0] inverse_product;
    logic [127:0] correction;
    logic [128:0] total;
    logic [64:0] quotient;
    begin
      product = a * b;
      inverse_product = product[63:0] * QINV;
      correction = inverse_product[63:0] * Q;
      total = {1'b0, product} + {1'b0, correction};
      quotient = total[128:64];
      mont_ref = (quotient >= {1'b0, Q}) ?
                 quotient - {1'b0, Q} : quotient[63:0];
    end
  endfunction

  // Dedicated deterministic stimulus stream, independent of simulator RNGs
  // and of any random calls inside a DUT. Seed is printed with the result.
  function automatic logic [63:0] random64();
    begin
      rng_state = rng_state ^ (rng_state << 13);
      rng_state = rng_state ^ (rng_state >> 7);
      rng_state = rng_state ^ (rng_state << 17);
      random64 = rng_state;
    end
  endfunction

  task automatic fail(input string message_text);
    begin
      errors = errors + 1;
      $display("KARATSUBA_MISMATCH cycle=%0d %s", cycles, message_text);
      if (errors >= 12)
        $fatal(1, "tb_wl_karatsuba too many failures");
    end
  endtask

  // The integer units have no valid port. TB valid tags identify the same
  // sampled transactions in both integer pipelines, including across bubbles.
  // Checks happen after NBA updates; the input-sampling edge is latency edge 1.
  task automatic tick(
      input bit reset_active, valid,
      input logic [59:0] x, z,
      input logic [63:0] a, b
  );
    integer t, impl;
    logic [127:0] integer_got;
    begin
      @(negedge clk);
      rst_n = !reset_active;
      in_valid = valid;
      ia = x;
      ib = z;
      ma = a;
      mb = b;
      if (!reset_active) begin
        integer_expected_valid[0] = valid;
        mont_expected_valid[0] = valid;
        // Explicitly widen before the reference multiply; all 120 result bits
        // are significant even for inputs greater than or equal to Q.
        integer_expected[0] = {68'b0, x} * {68'b0, z};
        mont_expected[0] = mont_ref(a, b);
        if (valid) begin
          issued = issued + 1;
          if (({4'b0, x} >= Q) || ({4'b0, z} >= Q))
            integer_above_q = integer_above_q + 1;
          if ((a >= Q) || (b >= Q))
            $fatal(1, "noncanonical Montgomery stimulus a=%016x b=%016x", a, b);
        end else begin
          bubble_cycles = bubble_cycles + 1;
        end
      end

      @(posedge clk);
      #1;
      cycles = cycles + 1;
      if (reset_active) begin
        reset_cycles = reset_cycles + 1;
        for (impl = 0; impl < 2; impl = impl + 1) begin
          // Entry zero duplicates the most recently issued item after shifting;
          // only entries 1..LAT-1 are still in flight at the next reset edge.
          for (t = 1; t < INT_LAT; t = t + 1)
            if (integer_expected_valid[t])
              integer_discarded[impl] = integer_discarded[impl] + 1;
          for (t = 1; t < MONT_LAT; t = t + 1)
            if (mont_expected_valid[t])
              mont_discarded[impl] = mont_discarded[impl] + 1;
          if ((mont_valid[impl] !== 1'b0) || (mont_y[impl] !== 64'b0))
            fail($sformatf("reset Montgomery impl=%0d valid=%b data=%016x",
                           impl, mont_valid[impl], mont_y[impl]));
        end
        if ((integer_old !== 128'b0) || (integer_karatsuba !== 120'b0))
          fail("reset integer outputs were not cleared");
        for (t = 0; t < INT_LAT; t = t + 1) begin
          integer_expected_valid[t] = 1'b0;
          integer_expected[t] = '0;
        end
        for (t = 0; t < MONT_LAT; t = t + 1) begin
          mont_expected_valid[t] = 1'b0;
          mont_expected[t] = '0;
        end
      end else begin
        for (impl = 0; impl < 2; impl = impl + 1) begin
          integer_got = (impl == 0) ? integer_old : {8'b0, integer_karatsuba};
          if (integer_expected_valid[INT_LAT-1]) begin
            integer_checked[impl] = integer_checked[impl] + 1;
            if (integer_got !== integer_expected[INT_LAT-1])
              fail($sformatf("integer impl=%0d got=%032x expected=%032x",
                             impl, integer_got, integer_expected[INT_LAT-1]));
          end
          if (mont_valid[impl] !== mont_expected_valid[MONT_LAT-1])
            fail($sformatf("valid impl=%0d got=%b expected=%b",
                           impl, mont_valid[impl], mont_expected_valid[MONT_LAT-1]));
          if (mont_expected_valid[MONT_LAT-1]) begin
            mont_checked[impl] = mont_checked[impl] + 1;
            if ((mont_y[impl] !== mont_expected[MONT_LAT-1]) || (mont_y[impl] >= Q))
              fail($sformatf("Montgomery impl=%0d got=%016x expected=%016x",
                             impl, mont_y[impl], mont_expected[MONT_LAT-1]));
          end
        end
        for (t = INT_LAT-1; t > 0; t = t - 1) begin
          integer_expected_valid[t] = integer_expected_valid[t-1];
          integer_expected[t] = integer_expected[t-1];
        end
        for (t = MONT_LAT-1; t > 0; t = t - 1) begin
          mont_expected_valid[t] = mont_expected_valid[t-1];
          mont_expected[t] = mont_expected[t-1];
        end
      end
    end
  endtask

  task automatic random_tick(input bit valid);
    logic [63:0] x, z, a, b;
    begin
      // Ordered draws also make the seed independent of argument evaluation.
      x = random64();
      z = random64();
      a = random64();
      b = random64();
      tick(1'b0, valid, x[59:0], z[59:0], a % Q, b % Q);
    end
  endtask

  initial begin
    if ((QW != 64) || (Q[63:60] != 0) || !Q[0])
      $fatal(1, "this test requires the current odd Q below 2^60 with a 64-bit interface");
    rng_state = STIM_SEED;
    $display("KARATSUBA_STIMULUS seed=%016x integer_width=60 R_bits=64 Q=%016x", STIM_SEED, Q);
    for (n = 0; n < 2; n = n + 1) begin
      integer_checked[n] = 0;
      mont_checked[n] = 0;
      integer_discarded[n] = 0;
      mont_discarded[n] = 0;
    end
    for (n = 0; n < INT_LAT; n = n + 1) begin
      integer_expected_valid[n] = 1'b0;
      integer_expected[n] = '0;
    end
    for (n = 0; n < MONT_LAT; n = n + 1) begin
      mont_expected_valid[n] = 1'b0;
      mont_expected[n] = '0;
    end

    edges[0] = '0;
    edges[1] = 1;
    edges[2] = 2;
    edges[3] = MAX60;
    edges[4] = 60'b1 << 59;
    edges[5] = (60'b1 << 59) - 1'b1;
    edges[6] = (60'b1 << 15) - 1'b1;
    edges[7] = 60'b1 << 15;
    edges[8] = (60'b1 << 16) - 1'b1;
    edges[9] = 60'b1 << 16;
    edges[10] = (60'b1 << 17) - 1'b1;
    edges[11] = 60'b1 << 17;
    edges[12] = (60'b1 << 30) - 1'b1;
    edges[13] = 60'b1 << 30;
    edges[14] = (60'b1 << 31) - 1'b1;
    edges[15] = 60'b1 << 31;
    edges[16] = (60'b1 << 45) - 1'b1;
    edges[17] = 60'b1 << 45;
    edges[18] = 60'haaaaaaaaaaaaaaa;
    edges[19] = 60'h555555555555555;
    edges[20] = Q[59:0] - 1'b1;
    edges[21] = Q[59:0] - 2;
    edges[22] = Q[59:0];
    edges[23] = Q[59:0] + 1'b1;

    repeat (4) tick(1'b1, 1'b0, '0, '0, '0, '0);
    for (j = 0; j < EDGE_COUNT; j = j + 1)
      for (k = 0; k < EDGE_COUNT; k = k + 1)
        tick(1'b0, 1'b1, edges[j], edges[k], {4'b0, edges[j]} % Q, {4'b0, edges[k]} % Q);
    for (j = 0; j < 60; j = j + 1)
      for (k = 0; k < 60; k = k + 1)
        tick(1'b0, 1'b1, 60'b1 << j, 60'b1 << k,
             (64'b1 << j) % Q, (64'b1 << k) % Q);
    for (n = 0; n < 20000; n = n + 1)
      random_tick(1'b1);
    for (n = 0; n < 5000; n = n + 1)
      random_tick(((n % 5) != 1) && ((n % 17) != 4));
    repeat (MONT_LAT+2) tick(1'b0, 1'b0, '0, '0, '0, '0);

    // Both pipelines contain valid transactions when reset interrupts them.
    // Assert valid as well on the reset edge: reset must take precedence.
    for (n = 0; n < 20; n = n + 1)
      tick(1'b0, 1'b1, MAX60, MAX60, Q-1'b1, Q-1'b1);
    tick(1'b1, 1'b1, MAX60, MAX60, Q-1'b1, Q-1'b1);
    repeat (MONT_LAT+2) tick(1'b0, 1'b0, '0, '0, '0, '0);
    post_reset_issued = issued;
    for (n = 0; n < 128; n = n + 1)
      random_tick(1'b1);
    for (n = 0; n < 32; n = n + 1)
      random_tick((n % 3) != 1);
    post_reset_issued = issued - post_reset_issued;
    repeat (MONT_LAT+2) tick(1'b0, 1'b0, '0, '0, '0, '0);

    for (n = 0; n < 2; n = n + 1) begin
      if ((integer_checked[n] + integer_discarded[n] != issued) ||
          (mont_checked[n] + mont_discarded[n] != issued))
        $fatal(1, "transaction accounting impl=%0d issued=%0d integer=%0d+%0d mont=%0d+%0d",
               n, issued, integer_checked[n], integer_discarded[n],
               mont_checked[n], mont_discarded[n]);
      if ((integer_discarded[n] != INT_LAT-1) ||
          (mont_discarded[n] != MONT_LAT-1))
        $fatal(1, "in-flight reset coverage impl=%0d integer_discarded=%0d mont_discarded=%0d",
               n, integer_discarded[n], mont_discarded[n]);
      $display("KARATSUBA_COUNTS impl=%0d integer_checked=%0d integer_discarded=%0d mont_checked=%0d mont_discarded=%0d",
               n, integer_checked[n], integer_discarded[n], mont_checked[n], mont_discarded[n]);
    end
    if ((integer_above_q == 0) || (bubble_cycles == 0) || (post_reset_issued <= 128))
      $fatal(1, "missing range/bubble/recovery stimulus coverage");
    if (errors != 0)
      $fatal(1, "tb_wl_karatsuba FAIL errors=%0d", errors);
    $display("KARATSUBA_COVERAGE seed=%016x edge_pairs=%0d single_bit_pairs=3600 continuous_random=20000 bubble_random=5000 integer_above_q=%0d bubble_cycles=%0d reset_cycles=%0d post_reset_issued=%0d",
             STIM_SEED, EDGE_COUNT*EDGE_COUNT, integer_above_q, bubble_cycles, reset_cycles, post_reset_issued);
    $display("tb_wl_karatsuba PASS integer_latency=4/4 mont_latency=14/14 II=1 cycles=%0d issued=%0d", cycles, issued);
    $finish;
  end

  initial begin
    repeat (100000) @(posedge clk);
    $fatal(1, "tb_wl_karatsuba timeout");
  end
endmodule
