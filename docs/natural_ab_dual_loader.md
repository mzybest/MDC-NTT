# Natural-Order Dual A/B Loader

## Experiment Identity

This controlled experiment starts from the frozen B1+B2 checkpoint and changes
only the top-level input and BRAM ownership control.

- Base branch: **codex/mdc-flush-srl-cleanup**
- Base commit: **f9a7a62**
- Experiment branch: **codex/natural-ab-dual-loader**
- Functional checkpoint: **213a09a**
- Top: **poly_mul_top_dual_forward**
- Device: **xc7vx485tffg1761-2**
- Vivado: **2026.1**
- Signoff clock: **6.667 ns (150 MHz)**
- Active configuration: **natural_ab_raw_pre_shared**

The GS butterfly, MDC reorder, Montgomery arithmetic, twiddle tables, and
NTT/INTT algorithm are unchanged. The original pre-split bank input path remains
available with **USE_NATURAL_AB_LOADER=0**.

## Motivation

The legacy interface writes one coefficient through **load_data** and requires
software or an upstream DMA to provide an already selected polynomial, bank,
and address. It exposes the physical bank split at the system boundary.

The natural-order interface accepts one A coefficient and one B coefficient at
the same logical address on every successful handshake. It hides the physical
bank split while preserving the existing two-path Stage0 access pattern.

The logical input bandwidth is 128 bits per accepted cycle:

    A[k] (64 bits) || B[k] (64 bits), k = 0..4095

## Data Representation

In the active **bram_raw_pre_shared** configuration:

- **USE_LOAD_PREPROCESS=0**
- the A/B banks store raw input coefficients in Montgomery representation;
- the shared peripheral Montgomery pool performs the existing Pre_NTT
  multiplication after the synchronous BRAM read;
- the new loader writes exactly the same representation as the legacy raw
  preload path.

The loader neither repeats Pre_NTT nor bypasses it. A host that starts from
ordinary residues must still encode them into the representation expected by
the existing top-level interface.

## External Interface

| Signal | Direction | Meaning |
|---|---|---|
| **ab_load_start** | input | Starts a new 4096-pair natural-order load |
| **ab_in_valid** | input | A/B input pair is valid |
| **ab_in_ready** | output | DUT can accept the pair |
| **a_coeff_in[63:0]** | input | A coefficient at logical index k |
| **b_coeff_in[63:0]** | input | B coefficient at logical index k |
| **ab_load_done** | output | One-cycle pulse after pair k=4095 is accepted |

The transfer event is:

    ab_fire = ab_in_valid && ab_in_ready

The 12-bit **load_index** advances only on **ab_fire**. Computation is accepted
only after all 4096 pairs have been loaded. **ab_load_start** arms the loader;
the first pair is accepted when **ab_in_ready** is asserted.

## Automatic Bank Mapping

    bank_sel  = load_index[11]
    bank_addr = load_index[10:0]

| Logical range | A destination | B destination |
|---|---|---|
| k=0..2047 | AC_bank0[k] | B_bank0[k] |
| k=2048..4095 | AC_bank1[k-2048] | B_bank1[k-2048] |

The testbench explicitly checks k=0, 1, 2047, 2048, and 4095. Random valid
bubbles confirm that neither the address nor the selected bank advances without
**ab_fire**.

## Forward Read and BRAM Ownership

After the complete load, local pair index i=0..2047 reads:

    AC_bank0[i] -> A[i]
    AC_bank1[i] -> A[i+2048]
    B_bank0[i]  -> B[i]
    B_bank1[i]  -> B[i+2048]

All four reads use separate physical banks, so each cycle supplies one legal
GS Stage0 pair to each Forward Core without a bank conflict.

| State/phase | AC banks | B banks |
|---|---|---|
| LOAD_AB | write raw A | write raw B |
| FORWARD | read A | read B |
| POINTWISE | overwrite with C_NTT | no longer needed |
| INTT | read C_NTT | idle |

No new C_NTT BRAM is added. Assertions reject natural-load/C-write overlap,
A-read/C-write overlap, natural-load/transform-read overlap, and simultaneous
Forward/INTT ownership.

## C_NTT and INTT Mapping

Let **rev11(x)** reverse the 11-bit pair index. Signal-flow analysis and
simulation show that Forward output pair t has logical indices:

    core_out0(t) = NTT[rev11(t)]
    core_out1(t) = NTT[2048 + rev11(t)]

Pointwise preserves this pair order and writes:

    AC_bank0[t] = C_NTT[rev11(t)]
    AC_bank1[t] = C_NTT[2048 + rev11(t)]

INTT input pair i reads address **rev11(i)**. Since bit reversal is involutive:

    AC_bank0[rev11(i)] = C_NTT[i]
    AC_bank1[rev11(i)] = C_NTT[2048+i]

Thus the AC banks are overwritten in physical output order and read back in the
order required by the all-GS INTT.

### N=16 Mapping Example

For N=16, the pair index has three bits.

| t/i | pair bits | rev3 | Forward lane0 | Forward lane1 | C write addr | INTT read addr | INTT lane0 | INTT lane1 |
|---:|:---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 000 | 0 | 0 | 8 | 0 | 0 | 0 | 8 |
| 1 | 001 | 4 | 4 | 12 | 1 | 4 | 1 | 9 |
| 2 | 010 | 2 | 2 | 10 | 2 | 2 | 2 | 10 |
| 3 | 011 | 6 | 6 | 14 | 3 | 6 | 3 | 11 |
| 4 | 100 | 1 | 1 | 9 | 4 | 1 | 4 | 12 |
| 5 | 101 | 5 | 5 | 13 | 5 | 5 | 5 | 13 |
| 6 | 110 | 3 | 3 | 11 | 6 | 3 | 6 | 14 |
| 7 | 111 | 7 | 7 | 15 | 7 | 7 | 7 | 15 |

The independent model in **scripts/natural_ab_mapping_model.py** checks the full
table and reports **N16_MAPPING_CHECK=PASS**.

## Functional Verification

| Test | Result | Observation |
|---|---:|---|
| tb_top_data_bram | PASS | Synchronous top BRAM behavior |
| tb_mont_mul_wl | PASS | Old latency 12, WL latency 14 |
| tb_gs_butterfly | PASS | 32 vectors |
| tb_gs_mdc_core | PASS | NTT/INTT core regression |
| tb_gs_mdc_core_ntt_only | PASS | First output 2242, done 4290 |
| tb_poly_mul_top_wavefront | PASS | Random and directed negacyclic |
| Unit-twiddle bypass variants | PASS | Butterfly and core |
| All legacy Dual-Forward configurations | PASS | Includes active bram_raw_pre_shared |
| Natural A/B continuous random | PASS | 4096 consecutive accepted pairs |
| Natural A/B random bubbles | PASS | Address advances only on ab_fire |
| Natural directed x^(N-1)*x | PASS | Logical result[0]=Q-1 |
| Natural output count | PASS | 4096 coefficients, zero mismatches |

The directed result is stored in the existing Montgomery representation:
logical Q-1 appears as **0ffffffffffbc011**.

## Cycle Results

| Case | Accepted pairs | Load elapsed | Compute | First input to done | First input to first result | First input to last result |
|---|---:|---:|---:|---:|---:|---:|
| Continuous random | 4096 | 4096 | 8623 | 12719 | 10671 | 12718 |
| Random bubbles | 4096 | 5422 | 8623 | 14045 | 11997 | 14044 |
| Directed bubbles | 4096 | 5422 | 8623 | 14045 | 11997 | 14044 |

**load_elapsed** is the inclusive interval from the first to the last accepted
pair. **compute** is accepted start to done and remains exactly 8623 cycles.
The continuous end-to-end value is measured, not hard-coded.

The cycle numbers do not include a serialized output-RAM readout. Results are
written before done and the current **result_addr/result_data** interface is a
combinational addressed read without output ready/valid. A system requiring a
4096-cycle streaming output protocol must account for that separately.

## Synthesis Resource Gate

The implementation was allowed to start only after synthesis confirmed that
BRAM and DSP were unchanged.

| Metric | B1+B2 synthesis | Natural loader synthesis | Change |
|---|---:|---:|---:|
| Slice LUT | 55,229 | 55,241 | +12 |
| LUT Memory | 9,167 | 9,167 | 0 |
| Registers | 47,273 | 47,288 | +15 |
| DSP48E1 | 520 | 520 | 0 |
| BRAM | 59 | 59 | 0 |
| Synthesis WNS | not recorded in baseline document | +1.788 ns | n/a |

The small +12 LUT/+15 register delta is consistent with a 12-bit loader index,
handshake state, and completion control.

## 150 MHz Post-Route Results

The implementation used a 6.400 ns optimization constraint and restored
6.667 ns for signoff.

| Metric | B1+B2 baseline | Natural loader | Change |
|---|---:|---:|---:|
| Slice LUT | 53,820 | 53,841 | +21 |
| LUT Memory | 8,591 | 8,573 | -18 |
| Registers | 48,157 | 47,716 | -441 |
| DSP48E1 | 520 | 520 | 0 |
| BRAM | 59 | 59 | 0 |
| Setup WNS | +0.694 ns | +0.478 ns | -0.216 ns |
| Setup TNS | 0.000 ns | 0.000 ns | 0 |
| Hold WNS | +0.018 ns | +0.043 ns | +0.025 ns |
| Hold TNS | 0.000 ns | 0.000 ns | 0 |
| Estimated power | 4.085 W | 4.044 W | -0.041 W |
| Compute latency | 8623 cycles | 8623 cycles | 0 |

Power confidence is Low, so the 0.041 W difference is not treated as a
signoff-quality improvement. Physical optimization can change the final
LUT/register count even when the logical RTL delta is small.

The routed design has 104,020 fully routed nets and zero routing errors.

## Critical Path

The new worst setup path is:

    u_core_a/g_stage_r_11_rep__4/C
      -> LUT2 / merged cross-core control-data gate
      -> u_core_b Stage1 sum delay data_pipe_reg[13][0]/D

- Slack: +0.478 ns
- Data-path delay: 5.992 ns
- Logic: 0.266 ns (4.439%)
- Routing: 5.726 ns (95.561%)
- Long-net fanout reported on the path: 250

The path does not pass through the natural A/B loader or top-level BRAM write
selection. It is another Vivado cross-core equivalent-control merge, similar to
the B1+B2 baseline's cross-core valid path. The 0.216 ns WNS reduction is a
placement/routing sensitivity of this merged cross-core network, not an added
coefficient-input combinational path. Timing and hold both still pass at
150 MHz.

## Reproducibility

- Synthesis runtime: 1364 seconds.
- Implementation runtime: 2512 seconds.
- All 31 **rtl/*.sv** SHA256 values match before and after Vivado.
- **scripts/write_rtl_sha256.ps1** uses the .NET SHA256 API so it also works
  with the older powershell.exe available in the batch environment.

Reports and manifests are stored under:

    reports/dual_forward_dsp_reduction/natural_ab_dual_loader/

## Conclusion

The experiment provides a complete, natural-order input interface for one
4096-coefficient A/B polynomial pair:

- A[k] and B[k] are accepted together;
- physical bank selection is automatic;
- the existing raw Pre_NTT path is preserved;
- Dual-Forward Stage0 receives conflict-free A and B pairs;
- AC BRAM is safely reused for C_NTT;
- compute latency, DSP count, and BRAM count are unchanged;
- 150 MHz post-route setup and hold both pass.

The legacy pre-split bank path remains selectable for rollback. A future
batch-oriented version may add ping-pong job banks to overlap load, compute,
and result drain, but that extension is intentionally outside this experiment.
