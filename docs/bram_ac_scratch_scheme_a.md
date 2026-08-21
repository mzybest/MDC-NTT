# BRAM A/C Scratch Scheme A

## Scope

This controlled experiment starts from commit `70c4a6d` on branch
`codex/bram_ac_scratch`. It keeps the dual-forward GS-MDC arithmetic,
explicit Pre/Post negacyclic flow, radix, modulus, 14-cycle WL Montgomery
pipeline, MDC reorder network, two-path II=1 behavior, Pointwise units, and
result read interface unchanged.

Scheme A changes the top-level transform-data storage and launch dataflow:

- raw A and B coefficients are written into synchronous block RAM;
- after `start`, four lane-parallel Pre_NTT Montgomery units read raw A/B and
  feed the two forward cores;
- Pointwise C_NTT results overwrite the no-longer-live A banks;
- the final `result_bank0/1` arrays remain on the original combinational-read
  LUTRAM path;
- `USE_TOP_DATA_BRAM=0` retains the prior LUTRAM implementation.

No multicycle path, false path, relaxed clock, or algorithm change is used.

## Storage and Lifetime Mapping

The BRAM mode instantiates four independent 2048 x 64 simple dual-port banks:

| Physical bank | Load phase owner | Later owner | Read consumer |
|---|---|---|---|
| `u_ac_bank0` | A indices 0 to 2047 | C_NTT lane 0 | Forward Core A, then INTT |
| `u_ac_bank1` | A indices 2048 to 4095 | C_NTT lane 1 | Forward Core A, then INTT |
| `u_b_bank0` | B indices 0 to 2047 | B remains resident | Forward Core B |
| `u_b_bank1` | B indices 2048 to 4095 | B remains resident | Forward Core B |

Each bank has one synchronous read port and one write port. Address zero is
prefetched at the load-to-forward and Pointwise-to-INTT boundaries, so the
one-cycle BRAM read latency does not add a transform cycle. Registered index,
mode, first-pair, and valid tags stay aligned with returned data.

The Pointwise phase cannot overlap input loading, and INTT reading cannot
overlap forward A reading. Simulation assertions check these ownership rules,
same-address read/write collisions, and four-lane read-valid alignment.

Vivado maps every top bank to four RAMB36E1 primitives, for 16 explicit top
data BRAMs. The complete routed design contains 59 BRAM tiles: 25 in Core A,
18 in Core B, and 16 in the new top data banks. The previous elaboration had
50 total BRAMs, including seven non-core inferred RAMB36 instances that are
absent in Scheme A, so the net device-level increase is nine tiles.

## Functional Verification

The complete regression finished successfully in 1497 seconds.

| Test | Result | Relevant check |
|---|---:|---|
| `tb_top_data_bram` | PASS | Synchronous read, valid, concurrent different-address access |
| `tb_mont_mul_wl` | PASS | WL Montgomery latency and arithmetic |
| `tb_gs_butterfly` | PASS | Multiplier and unit-twiddle bypass paths |
| `tb_gs_mdc_core` | PASS | Shared NTT/INTT core |
| `tb_gs_mdc_core_ntt_only` | PASS | Second forward core |
| `tb_poly_mul_top_wavefront` | PASS | Existing wavefront baseline |
| `tb_poly_mul_top_dual_forward` old modes | PASS | Baseline/load/fused/bypass parameter paths |
| `tb_poly_mul_top_dual_forward` Scheme A | PASS | Random and directed negacyclic multiplication |

The directed case remains `x^(N-1) * x = -1 mod (x^N+1)`. Scheme A preserves
all pair counts and the exact full-multiplication timing:

```text
start-to-done                 8623 cycles
A/B forward input window     8207 to 10254
A/B forward output window   10449 to 12496
C INTT input window         12511 to 14558
C INTT output window        14753 to 16800
```

## Same-Frequency 150 MHz Comparison

Device: `xc7vx330tffg1157-1`
Tool: Vivado 2026.1
Clock: 6.667 ns
Implementation flow: Explore / AltSpreadLogic_medium /
AggressiveFanoutOpt / MoreGlobalIterations

| Metric | Stage11-bypass baseline | Scheme A | Change |
|---|---:|---:|---:|
| Slice LUT | 76,681 | 61,614 | -15,067 (-19.65%) |
| LUT Memory | 25,302 | 8,782 | -16,520 (-65.29%) |
| Registers | 53,355 | 56,144 | +2,789 (+5.23%) |
| DSP48E1 | 540 | 600 | +60 (+11.11%) |
| BRAM tiles | 50 | 59 | +9 |
| Setup WNS | +0.089 ns | +0.184 ns | +0.095 ns |
| Setup TNS | 0.000 ns | 0.000 ns | unchanged |
| Hold WHS | +0.023 ns | +0.015 ns | -0.008 ns |
| Hold THS | 0.000 ns | 0.000 ns | unchanged |
| Estimated power | 4.997 W | 4.546 W | -0.451 W (-9.03%) |
| Full multiplication | 8623 cycles | 8623 cycles | unchanged |

The 60-DSP increase is intentional: Scheme A replaces the one load-time
Pre_NTT Montgomery unit with four after-start lane-parallel units. It is a
storage, routing, and peak-frequency variant rather than the minimum-DSP
variant.

## Virtex-7 Frequency Results

Each frequency was synthesized and implemented independently. All routes
contain zero routing errors and pass setup and hold timing.

| Target | Period | WNS | TNS | WHS | THS | Slice LUT | LUT Memory | Registers | DSP | BRAM | Power | Impl runtime |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 150 MHz | 6.667 ns | +0.184 ns | 0.000 ns | +0.015 ns | 0.000 ns | 61,614 | 8,782 | 56,144 | 600 | 59 | 4.546 W | 4,484 s |
| 155 MHz | 6.452 ns | +0.225 ns | 0.000 ns | +0.020 ns | 0.000 ns | 61,576 | 8,782 | 56,482 | 600 | 59 | 4.724 W | 4,880 s |
| 160 MHz | 6.250 ns | +0.234 ns | 0.000 ns | +0.017 ns | 0.000 ns | 61,586 | 8,783 | 57,007 | 600 | 59 | 4.865 W | 5,593 s |

The non-monotonic WNS is caused by independent frequency-driven placement,
physical optimization, and DSP-register pushing. It must not be interpreted
as a deterministic gain from tightening the clock. The highest demonstrated
point is 160 MHz, where 8623 cycles correspond to about 53.894 us and 18,555
compute-only polynomial multiplications per second once A/B preload is
complete. This rate does not include the external coefficient-loading phase.

## Critical-Path Movement

The 150 MHz baseline worst path was the distributed C_NTT write-address path:

```text
Pointwise address delay -> c_ntt_odd LUTRAM WADR
```

Scheme A removes that path class. At 150 MHz, the worst path is a Core A
Stage6 control route into a delay-memory shift register and is 93.54 percent
routing delay. At 160 MHz, the worst path is:

```text
Core B Stage6 butterfly a_r
  -> sum/delay control logic
  -> sum delay SRL input
```

Its data path is 5.614 ns: 2.460 ns logic and 3.154 ns routing. Other top-ten
paths include route-dominated MDC delay-memory control and BRAM-return valid
signals into Stage0. The old C_NTT LUTRAM write-address bottleneck is gone.

## Files and Reports

- `rtl/top_data_bram.sv`
- `rtl/poly_mul_top_dual_forward.sv`
- `sim/tb_top_data_bram.sv`
- `sim/tb_poly_mul_top_dual_forward.sv`
- `scripts/run_dual_forward_dsp_reduction_regression.bat`
- `scripts/run_synth_dual_forward_dsp_reduction.tcl`
- `scripts/run_virtex7_bram_ac_scratch_scheme_a.bat`
- `reports/dual_forward_dsp_reduction/bram_ac_scratch/virtex7_v2026_1/`

## Conclusion

Scheme A is functionally correct and preserves the 8623-cycle schedule. It
converts raw A/B and reusable A/C storage to synchronous BRAM, reduces routed
LUT Memory by 65.29 percent, removes the prior C_NTT LUTRAM routing limiter,
and demonstrates post-route timing closure through 160 MHz. The tradeoff is
60 additional DSP48E1 blocks and a small register increase. The next DSP
experiment should be separate and parameterized, for example sharing
phase-mutually-exclusive peripheral Montgomery units; it should not alter this
verified BRAM/storage checkpoint.
