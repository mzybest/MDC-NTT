`timescale 1ns/1ps
// Independent arithmetic and transaction checks for all three reduction choices.
// Existing production testbenches and reference vectors are deliberately unused.
module tb_wlmont_lowcost;
  import params_pkg::*;

  localparam int IMPL_COUNT = 3;
  localparam int ROUND_LAT = 2;
  localparam int MONT_LAT = 14;
  localparam int EDGE_COUNT = 12;
  localparam int HIGH_PATTERNS = 5;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [128:0] round_input = '0;
  wire [128:0] round_output [0:IMPL_COUNT-1];
  logic in_valid = 1'b0;
  logic [63:0] a = '0;
  logic [63:0] b = '0;
  wire out_valid [0:IMPL_COUNT-1];
  wire [63:0] y [0:IMPL_COUNT-1];

  logic round_valid_expected [0:ROUND_LAT-1];
  logic [128:0] round_expected [0:ROUND_LAT-1];
  logic mont_valid_expected [0:MONT_LAT-1];
  logic [63:0] mont_expected [0:MONT_LAT-1];
  logic [63:0] edge_values [0:EDGE_COUNT-1];

  integer errors = 0;
  integer cycle_count = 0;
  integer round_issued = 0;
  integer round_checked = 0;
  integer round_discarded = 0;
  integer mont_issued = 0;
  integer mont_checked = 0;
  integer mont_discarded = 0;
  integer exhaustive_start_checked;
  integer ia, ib, n, pattern, low_index;
  integer seed;
  integer seed_result;
  logic [112:0] high_word;
  logic [15:0] low_word;

  always #5 clk = ~clk;

  for (genvar implementation = 0; implementation < IMPL_COUNT;
       implementation = implementation + 1) begin : g_impl
    wlmont_round16 #(.REDUCTION_IMPL(implementation)) u_round (
        .clk(clk), .rst_n(rst_n), .t_in(round_input),
        .t_out(round_output[implementation])
    );
    mont_mul_wl #(.QW(64), .REDUCTION_IMPL(implementation)) u_mont (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .a(a), .b(b), .out_valid(out_valid[implementation]),
        .y(y[implementation])
    );
  end

  // A full-width, single-step mathematical Montgomery round. The 130-bit
  // addition deliberately preserves the carry for arbitrary 129-bit inputs.
  function automatic logic [128:0] round_reference(
      input logic [128:0] t
  );
    logic [31:0] inverse_product;
    logic [15:0] m;
    logic [79:0] mq;
    logic [129:0] total;
    begin
      inverse_product = t[15:0] * 16'hbfff;
      m = inverse_product[15:0];
      mq = m * Q;
      total = {1'b0, t} + {50'b0, mq};
      round_reference = total[129:16];
    end
  endfunction

  // Independent 64-bit REDC reference, rather than repeating the four
  // 16-bit rounds or using another implementation's result as the golden.
  function automatic logic [63:0] mont_reference(
      input logic [63:0] x,
      input logic [63:0] z
  );
    logic [127:0] product;
    logic [127:0] inverse_product;
    logic [63:0] m;
    logic [127:0] mq;
    logic [128:0] total;
    logic [64:0] quotient;
    begin
      product = x * z;
      inverse_product = product[63:0] * QINV;
      m = inverse_product[63:0];
      mq = m * Q;
      total = {1'b0, product} + {1'b0, mq};
      quotient = total[128:64];
      mont_reference = (quotient >= {1'b0, Q})
                     ? quotient - {1'b0, Q} : quotient[63:0];
    end
  endfunction

  function automatic logic [63:0] random_residue();
    logic [63:0] raw;
    begin
      raw = {$urandom, $urandom};
      random_residue = raw % Q;
    end
  endfunction

  task automatic report_failure(input string message_text);
    begin
      errors = errors + 1;
      $display("LOWCOST MISMATCH cycle=%0d %s", cycle_count, message_text);
      if (errors >= 20)
        $fatal(1, "tb_wlmont_lowcost FAIL: stopped after %0d mismatches", errors);
    end
  endtask

  // Drive at negedge and sample after the nonblocking updates at posedge.
  // Expected slot 0 is the current request; slot LAT-1 is checked now.
  task automatic tick(
      input bit do_reset,
      input logic [128:0] requested_round,
      input bit check_round,
      input bit requested_valid,
      input logic [63:0] requested_a,
      input logic [63:0] requested_b
  );
    integer index;
    integer implementation;
    begin
      @(negedge clk);
      rst_n = !do_reset;
      round_input = requested_round;
      in_valid = requested_valid;
      a = requested_a;
      b = requested_b;

      if (!do_reset) begin
        round_valid_expected[0] = check_round;
        round_expected[0] = round_reference(requested_round);
        mont_valid_expected[0] = requested_valid;
        mont_expected[0] = mont_reference(requested_a, requested_b);
        if (check_round) round_issued = round_issued + 1;
        if (requested_valid) begin
          mont_issued = mont_issued + 1;
          if (requested_a >= Q || requested_b >= Q)
            $fatal(1, "tb_wlmont_lowcost stimulus outside canonical residue domain");
        end
      end

      @(posedge clk);
      #1;
      cycle_count = cycle_count + 1;
      if (do_reset) begin
        // Slot 0 is a retained copy of slot 1 after the previous tick.
        // Only slots 1..LAT-1 describe requests still in the pipeline.
        for (index = 1; index < ROUND_LAT; index = index + 1)
          if (round_valid_expected[index])
            round_discarded = round_discarded + 1;
        for (index = 1; index < MONT_LAT; index = index + 1)
          if (mont_valid_expected[index])
            mont_discarded = mont_discarded + 1;
        for (index = 0; index < ROUND_LAT; index = index + 1) begin
          round_valid_expected[index] = 1'b0;
          round_expected[index] = '0;
        end
        for (index = 0; index < MONT_LAT; index = index + 1) begin
          mont_valid_expected[index] = 1'b0;
          mont_expected[index] = '0;
        end
        for (implementation = 0; implementation < IMPL_COUNT;
             implementation = implementation + 1) begin
          if (out_valid[implementation] !== 1'b0 ||
              y[implementation] !== 64'b0 ||
              round_output[implementation] !== 129'b0)
            report_failure($sformatf("impl=%0d reset did not clear outputs", implementation));
        end
      end else begin
        for (implementation = 0; implementation < IMPL_COUNT;
             implementation = implementation + 1) begin
          if (round_valid_expected[ROUND_LAT-1] &&
              round_output[implementation] !== round_expected[ROUND_LAT-1])
            report_failure($sformatf(
                "round impl=%0d got=%033x expected=%033x",
                implementation, round_output[implementation], round_expected[ROUND_LAT-1]));
          if (out_valid[implementation] !== mont_valid_expected[MONT_LAT-1])
            report_failure($sformatf(
                "mont valid impl=%0d got=%b expected=%b",
                implementation, out_valid[implementation], mont_valid_expected[MONT_LAT-1]));
          if (mont_valid_expected[MONT_LAT-1] &&
              y[implementation] !== mont_expected[MONT_LAT-1])
            report_failure($sformatf(
                "mont data impl=%0d got=%016x expected=%016x",
                implementation, y[implementation], mont_expected[MONT_LAT-1]));
          if (mont_valid_expected[MONT_LAT-1] && y[implementation] >= Q)
            report_failure($sformatf("mont impl=%0d noncanonical result", implementation));
        end
        if (round_valid_expected[ROUND_LAT-1]) round_checked = round_checked + 1;
        if (mont_valid_expected[MONT_LAT-1]) mont_checked = mont_checked + 1;
        for (index = ROUND_LAT-1; index > 0; index = index - 1) begin
          round_valid_expected[index] = round_valid_expected[index-1];
          round_expected[index] = round_expected[index-1];
        end
        for (index = MONT_LAT-1; index > 0; index = index - 1) begin
          mont_valid_expected[index] = mont_valid_expected[index-1];
          mont_expected[index] = mont_expected[index-1];
        end
      end
    end
  endtask

  initial begin
    if (QW != 64 || Q !== 64'h0fffffffffffc001)
      $fatal(1, "tb_wlmont_lowcost expects the current fixed Q64 modulus");
    seed = 32'h20260912;
    seed_result = $urandom(seed);
    for (n = 0; n < ROUND_LAT; n = n + 1) begin
      round_valid_expected[n] = 1'b0;
      round_expected[n] = '0;
    end
    for (n = 0; n < MONT_LAT; n = n + 1) begin
      mont_valid_expected[n] = 1'b0;
      mont_expected[n] = '0;
    end

    edge_values[0] = 0;
    edge_values[1] = 1;
    edge_values[2] = 2;
    edge_values[3] = 65535;
    edge_values[4] = 65536;
    edge_values[5] = 64'h00000000ffffffff;
    edge_values[6] = 64'h0000000100000000;
    edge_values[7] = 64'h0800000000000000;
    edge_values[8] = Q - 2;
    edge_values[9] = Q - 1;
    edge_values[10] = R_MOD_Q;
    edge_values[11] = Q >> 1;

    repeat (4) tick(1, '0, 0, 0, 0, 0);

    // Every edge pair is valid, including the important (Q-1)*(Q-1).
    for (ia = 0; ia < EDGE_COUNT; ia = ia + 1)
      for (ib = 0; ib < EDGE_COUNT; ib = ib + 1)
        tick(0, '0, 0, 1, edge_values[ia], edge_values[ib]);

    // Sustained input makes both the exact 14-cycle latency and II=1 observable.
    for (n = 0; n < 4096; n = n + 1)
      tick(0, '0, 0, 1, random_residue(), random_residue());
    for (n = 0; n < 4096; n = n + 1)
      tick(0, '0, 0, ((n % 5) != 1) && ((n % 17) != 4),
           random_residue(), random_residue());
    repeat (MONT_LAT) tick(0, '0, 0, 0, 0, 0);

    // Reset deliberately interrupts both the round and full-multiplier pipelines.
    for (n = 0; n < 8; n = n + 1)
      tick(0, {129{1'b1}}, 1, 1, Q - 1, random_residue());
    tick(1, '0, 0, 0, 0, 0);
    repeat (MONT_LAT + 2) tick(0, '0, 0, 0, 0, 0);
    for (n = 0; n < 64; n = n + 1)
      tick(0, '0, 0, 1, Q - 1, edge_values[n % EDGE_COUNT]);
    repeat (MONT_LAT) tick(0, '0, 0, 0, 0, 0);

    exhaustive_start_checked = round_checked;
    // Since multiplication by 0xbfff is a permutation modulo 2^16,
    // every low word also covers every m, including m=0 and d=0 boundaries.
    for (pattern = 0; pattern < HIGH_PATTERNS; pattern = pattern + 1) begin
      case (pattern)
        0: high_word = '0;
        1: high_word = '1;
        2: high_word = (113'b1 << 112);
        3: high_word = (113'b1 << 112) - 1'b1;
        default: high_word = {17'h1aaaa, 32'h5555aaaa,
                             32'haaaa5555, 32'h01234567};
      endcase
      for (low_index = 0; low_index < 65536; low_index = low_index + 1) begin
        low_word = low_index[15:0];
        tick(0, {high_word, low_word}, 1, 0, 0, 0);
      end
    end
    repeat (MONT_LAT) tick(0, '0, 0, 0, 0, 0);

    if (round_checked - exhaustive_start_checked != HIGH_PATTERNS * 65536)
      $fatal(1, "tb_wlmont_lowcost exhaustive coverage count mismatch");
    if (round_checked + round_discarded != round_issued ||
        mont_checked + mont_discarded != mont_issued)
      $fatal(1, "tb_wlmont_lowcost outstanding transaction accounting mismatch");
    if (round_discarded == 0 || mont_discarded == 0)
      $fatal(1, "tb_wlmont_lowcost reset did not interrupt pending transactions");
    if (errors != 0)
      $fatal(1, "tb_wlmont_lowcost FAIL errors=%0d", errors);

    $display("tb_wlmont_lowcost PASS: implementations=%0d round_cases=%0d mont_cases=%0d round_latency=%0d mont_latency=%0d reset_discarded=%0d/%0d",
             IMPL_COUNT, round_checked, mont_checked, ROUND_LAT, MONT_LAT,
             round_discarded, mont_discarded);
    $finish;
  end
endmodule
