`timescale 1ns/1ps
module tb_poly_mul_top_dual_forward_natural_ab;
  import params_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic start = 1'b0;

  logic load_we = 1'b0;
  logic load_sel = 1'b0;
  logic [LOGN-1:0] load_addr = '0;
  logic [QW-1:0] load_data = '0;

  logic ab_load_start = 1'b0;
  logic ab_in_valid = 1'b0;
  logic ab_in_ready;
  logic [QW-1:0] a_coeff_in = '0;
  logic [QW-1:0] b_coeff_in = '0;
  logic ab_load_done;

  logic [LOGN-1:0] result_addr = '0;
  logic [QW-1:0] result_data;
  logic busy, done;

  logic [QW-1:0] a [0:N-1];
  logic [QW-1:0] b [0:N-1];
  logic [QW-1:0] golden [0:N-1];

  integer cycle = 0;
  integer expected_load_index = 0;
  integer result_pair_count = 0;
  integer first_result_cycle = -1;
  integer last_result_cycle = -1;
  integer compute_start_cycle = -1;
  integer c_mapping_count = 0;
  integer intt_mapping_count = 0;
  logic print_mapping = 1'b0;

  always #5 clk = ~clk;

  poly_mul_top_dual_forward #(
      .MUL_LAT(14),
      .USE_WL_MONT(1'b1),
      .USE_WL_CORE(1'b1),
      .USE_WL_PRE_NTT(1'b1),
      .USE_LOAD_PREPROCESS(1'b0),
      .USE_WL_POINTWISE(1'b1),
      .USE_WL_POST_INTT(1'b1),
      .USE_SHARED_PERIPH_MONT(1'b1),
      .FUSE_INTT_SCALE_IN_POST(1'b1),
      .USE_FINAL_UNIT_TWIDDLE_BYPASS(1'b1),
      .USE_TOP_DATA_BRAM(1'b1),
      .USE_NATURAL_AB_LOADER(1'b1),
      .USE_BFU_BOUNDARY_PIPE(1'b1),
      .USE_STAGE_LOCAL_TWIDDLE(1'b1),
      .TWIDDLE_BRAM_STAGES(4)
  ) u_dut (.*);

  function automatic logic [LOGN-2:0] bit_reverse_pair(
      input logic [LOGN-2:0] value
  );
    integer bit_index;
    for (bit_index = 0; bit_index < LOGN-1; bit_index = bit_index + 1)
      bit_reverse_pair[bit_index] = value[LOGN-2-bit_index];
  endfunction

  function automatic bit is_boundary_index(input integer index);
    is_boundary_index = (index == 0) || (index == 1) ||
                        (index == N/2-1) || (index == N/2) ||
                        (index == N-1);
  endfunction

  task automatic load_natural(
      input bit insert_bubbles,
      output integer accepted_count,
      output integer elapsed_cycles,
      output integer first_fire_cycle,
      output integer last_fire_cycle
  );
    logic [15:0] lfsr;
    bit drive_valid;
    bit fire_expected;
    integer index;
    begin
      accepted_count = 0;
      elapsed_cycles = 0;
      first_fire_cycle = -1;
      last_fire_cycle = -1;
      lfsr = 16'h1ace;

      ab_in_valid = 1'b0;
      ab_load_start = 1'b1;
      @(negedge clk);
      ab_load_start = 1'b0;

      index = 0;
      while (index < N) begin
        drive_valid = !insert_bubbles || lfsr[0] || lfsr[3];
        ab_in_valid = drive_valid;
        a_coeff_in = a[index];
        b_coeff_in = b[index];
        fire_expected = drive_valid && ab_in_ready;

        @(negedge clk);
        if (fire_expected) begin
          accepted_count = accepted_count + 1;
          if (first_fire_cycle < 0)
            first_fire_cycle = cycle - 1;
          last_fire_cycle = cycle - 1;
          index = index + 1;
        end
        lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
      end

      ab_in_valid = 1'b0;
      a_coeff_in = '0;
      b_coeff_in = '0;
      elapsed_cycles = last_fire_cycle - first_fire_cycle + 1;
      if (!ab_load_done)
        $fatal(1, "ab_load_done missing after final accepted coefficient pair");
      if (expected_load_index != N)
        $fatal(1, "accepted load index count=%0d expected=%0d",
               expected_load_index, N);
    end
  endtask

  task automatic start_and_wait(
      output integer start_cycle,
      output integer done_cycle
  );
    begin
      result_pair_count = 0;
      first_result_cycle = -1;
      last_result_cycle = -1;
      compute_start_cycle = -1;
      c_mapping_count = 0;
      intt_mapping_count = 0;

      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
      wait (done);
      start_cycle = compute_start_cycle;
      done_cycle = cycle;
      if (start_cycle < 0)
        $fatal(1, "compute start was not accepted");
      if (done_cycle - start_cycle != 8623)
        $fatal(1, "natural loader compute cycles=%0d expected=8623",
               done_cycle - start_cycle);
      if (result_pair_count != N/2)
        $fatal(1, "result pair count=%0d expected=%0d",
               result_pair_count, N/2);
    end
  endtask

  task automatic check_random_result;
    integer index;
    integer errors;
    integer printed;
    begin
      errors = 0;
      printed = 0;
      for (index = 0; index < N; index = index + 1) begin
        result_addr = index;
        #1;
        if (result_data !== golden[index]) begin
          errors = errors + 1;
          if (printed < 16) begin
            $display("natural mismatch index=%0d rtl=%016x golden=%016x",
                     index, result_data, golden[index]);
            printed = printed + 1;
          end
        end
      end
      if (errors)
        $fatal(1, "natural random negacyclic errors=%0d", errors);
    end
  endtask

  task automatic check_directed_result;
    integer index;
    begin
      for (index = 0; index < N; index = index + 1) begin
        result_addr = index;
        #1;
        if (index == 0) begin
          if (result_data !== Q-R_MOD_Q)
            $fatal(1, "directed result[0]=%016x expected_mont=%016x",
                   result_data, Q-R_MOD_Q);
        end else if (result_data !== '0) begin
          $fatal(1, "directed nonzero result[%0d]=%016x",
                 index, result_data);
        end
      end
      $display("DIRECTED_LOGICAL_RESULT result[0]=Q-1 raw_mont=%016x PASS",
               Q-R_MOD_Q);
    end
  endtask

  task automatic wait_for_idle;
    begin
      wait (!done);
      @(negedge clk);
    end
  endtask

  task automatic report_cycles(
      input string case_name,
      input integer accepted_count,
      input integer load_elapsed,
      input integer first_fire,
      input integer last_fire,
      input integer start_cycle,
      input integer done_cycle
  );
    begin
      $display("NATURAL_AB_CYCLES case=%s accepted=%0d load_elapsed=%0d first_fire=%0d last_fire=%0d compute_start=%0d done=%0d compute=%0d end_to_end=%0d first_input_to_first_result=%0d first_input_to_last_result=%0d output_count=%0d output_read_included=0",
               case_name, accepted_count, load_elapsed,
               first_fire, last_fire, start_cycle, done_cycle,
               done_cycle-start_cycle, done_cycle-first_fire,
               first_result_cycle-first_fire, last_result_cycle-first_fire,
               result_pair_count*2);
    end
  endtask

  always @(posedge clk) begin : p_loader_checks
    logic [LOGN-1:0] index_before;
    logic fire_before;
    logic active_before;

    index_before = u_dut.load_index;
    fire_before = ab_in_valid && ab_in_ready;
    active_before = u_dut.ab_load_active;

    if (rst_n && ab_load_start)
      expected_load_index = 0;

    if (rst_n && fire_before) begin
      if (u_dut.load_index !== expected_load_index[LOGN-1:0])
        $fatal(1, "load_index=%0d expected=%0d",
               u_dut.load_index, expected_load_index);

      if (!u_dut.load_index[LOGN-1]) begin
        if (!u_dut.g_top_bram.ac0_wr_en || u_dut.g_top_bram.ac1_wr_en ||
            !u_dut.g_top_bram.b0_wr_en || u_dut.g_top_bram.b1_wr_en)
          $fatal(1, "bank0 write-enable mapping failed k=%0d",
                 u_dut.load_index);
        if ((u_dut.g_top_bram.ac0_wr_addr !== u_dut.load_index[LOGN-2:0]) ||
            (u_dut.g_top_bram.b0_wr_addr !== u_dut.load_index[LOGN-2:0]))
          $fatal(1, "bank0 address mapping failed k=%0d",
                 u_dut.load_index);
      end else begin
        if (u_dut.g_top_bram.ac0_wr_en || !u_dut.g_top_bram.ac1_wr_en ||
            u_dut.g_top_bram.b0_wr_en || !u_dut.g_top_bram.b1_wr_en)
          $fatal(1, "bank1 write-enable mapping failed k=%0d",
                 u_dut.load_index);
        if ((u_dut.g_top_bram.ac1_wr_addr !== u_dut.load_index[LOGN-2:0]) ||
            (u_dut.g_top_bram.b1_wr_addr !== u_dut.load_index[LOGN-2:0]))
          $fatal(1, "bank1 address mapping failed k=%0d",
                 u_dut.load_index);
      end

      if (is_boundary_index(expected_load_index))
        $display("AB_LOAD_MAP k=%0d bank_sel=%0d bank_addr=%0d A=%016x B=%016x",
                 expected_load_index, u_dut.load_index[LOGN-1],
                 u_dut.load_index[LOGN-2:0], a_coeff_in, b_coeff_in);
      expected_load_index = expected_load_index + 1;
    end

    #1;
    if (rst_n && active_before && !fire_before && !ab_load_start &&
        (u_dut.load_index !== index_before))
      $fatal(1, "load_index advanced without ab_fire old=%0d new=%0d",
             index_before, u_dut.load_index);
    if (rst_n && fire_before && (index_before != N-1) &&
        (u_dut.load_index !== index_before + 1'b1))
      $fatal(1, "load_index failed to advance old=%0d new=%0d",
             index_before, u_dut.load_index);
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      cycle <= 0;
    end else begin
      if (start)
        compute_start_cycle = cycle;

      if (u_dut.post_valid0 && u_dut.post_valid1 &&
          u_dut.post_addr_valid) begin
        if (result_pair_count == 0)
          first_result_cycle = cycle;
        last_result_cycle = cycle;
        result_pair_count = result_pair_count + 1;
      end

      if (print_mapping && u_dut.c_write_valid && c_mapping_count < 16) begin
        if ((u_dut.g_top_bram.ac0_wr_addr !== u_dut.mul_addr) ||
            (u_dut.g_top_bram.ac1_wr_addr !== u_dut.mul_addr))
          $fatal(1, "C_NTT write address mismatch t=%0d", u_dut.mul_addr);
        $display("C_NTT_MAP t=%0d ac_addr=%0d lane0_logical=%0d lane1_logical=%0d",
                 u_dut.mul_addr, u_dut.g_top_bram.ac0_wr_addr,
                 bit_reverse_pair(u_dut.mul_addr),
                 N/2 + bit_reverse_pair(u_dut.mul_addr));
        c_mapping_count = c_mapping_count + 1;
      end

      if (print_mapping && u_dut.g_top_bram.intt_rd_en &&
          intt_mapping_count < 16) begin
        if ((u_dut.g_top_bram.intt_rd_addr0[LOGN-1:1] !==
             bit_reverse_pair(u_dut.g_top_bram.intt_pair_index)) ||
            (u_dut.g_top_bram.intt_rd_addr1[LOGN-1:1] !==
             bit_reverse_pair(u_dut.g_top_bram.intt_pair_index)))
          $fatal(1, "INTT C_NTT read mapping mismatch i=%0d",
                 u_dut.g_top_bram.intt_pair_index);
        $display("INTT_READ_MAP i=%0d ac_addr=%0d lane0_logical=%0d lane1_logical=%0d",
                 u_dut.g_top_bram.intt_pair_index,
                 bit_reverse_pair(u_dut.g_top_bram.intt_pair_index),
                 u_dut.g_top_bram.intt_pair_index,
                 N/2 + u_dut.g_top_bram.intt_pair_index);
        intt_mapping_count = intt_mapping_count + 1;
      end

      cycle <= cycle + 1;
    end
  end

  initial begin : p_test
    integer accepted_count;
    integer load_elapsed;
    integer first_fire;
    integer last_fire;
    integer start_cycle;
    integer done_cycle;
    integer index;

    $readmemh("mem/input_a.mem", a);
    $readmemh("mem/input_b.mem", b);
    $readmemh("mem/golden_result.mem", golden);

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    print_mapping = 1'b1;
    load_natural(1'b0, accepted_count, load_elapsed,
                 first_fire, last_fire);
    if ((accepted_count != N) || (load_elapsed != N))
      $fatal(1, "continuous load accepted=%0d elapsed=%0d expected=%0d",
             accepted_count, load_elapsed, N);
    start_and_wait(start_cycle, done_cycle);
    check_random_result();
    report_cycles("random_continuous", accepted_count, load_elapsed,
                  first_fire, last_fire, start_cycle, done_cycle);
    wait_for_idle();

    print_mapping = 1'b0;
    load_natural(1'b1, accepted_count, load_elapsed,
                 first_fire, last_fire);
    if ((accepted_count != N) || (load_elapsed <= N))
      $fatal(1, "bubble load accepted=%0d elapsed=%0d", accepted_count,
             load_elapsed);
    start_and_wait(start_cycle, done_cycle);
    check_random_result();
    report_cycles("random_bubbles", accepted_count, load_elapsed,
                  first_fire, last_fire, start_cycle, done_cycle);
    wait_for_idle();

    for (index = 0; index < N; index = index + 1) begin
      a[index] = '0;
      b[index] = '0;
    end
    a[N-1] = R_MOD_Q;
    b[1] = R_MOD_Q;

    load_natural(1'b1, accepted_count, load_elapsed,
                 first_fire, last_fire);
    start_and_wait(start_cycle, done_cycle);
    check_directed_result();
    report_cycles("directed_bubbles", accepted_count, load_elapsed,
                  first_fire, last_fire, start_cycle, done_cycle);

    $display("tb_poly_mul_top_dual_forward_natural_ab PASS");
    $finish;
  end

  initial begin
    repeat (5000000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
