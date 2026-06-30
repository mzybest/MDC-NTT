# Controlled WL Montgomery Full-Top Replacement

This document records the staged, selectable replacement of old Montgomery
multipliers with the word-level Montgomery (`mont_mul_wl`) implementation in the
full `poly_mul_top` flow. The experiment is intentionally staged so the frozen
explicit baseline and the old multiplier path remain recoverable at every step.

## Experiment Purpose

The goal is to reduce DSP pressure and improve 100 MHz timing without changing
algorithm behavior, without deleting `rtl/mont_mul.sv`, and without using
multicycle/false-path constraints. All replacements are controlled through
parameters so the old path can still be selected.

The current experiment stops at Stage B:

- Stage A: WL BFU path plus WL INTT scale inside `gs_mdc_core`.
- Stage B: Stage A plus Pre_NTT lane0/lane1 multipliers in `poly_mul_top`.
- Pointwise and Post_INTT multipliers are still old direct `mont_mul` paths.
- Stage C is not part of this checkpoint.

## Safety State

- Current branch during this checkpoint: `optimized_baseline_bfu_inputreg_constq_impl83p3`
- Frozen optimized explicit baseline remains preserved.
- `rtl/mont_mul.sv` is preserved.
- Old multiplier paths are preserved through `USE_WL_MONT=0`.
- WL multiplier paths use `USE_WL_MONT=1`.
- No multicycle path or false path constraint was added.
- `mont_mul_wl` remains an II=1 pipeline.

## Full `poly_mul_top` Baseline

The frozen full-top baseline for this controlled comparison uses the optimized
explicit Pre/Post negacyclic design, BRAM-friendly delay memories, constant-Q
Montgomery optimization, and BFU input registers. For the old full-top synthesis
comparison, `USE_WL_MONT=0` selects the old `mont_mul` path.

Old full-top synthesis reports were reused from the existing report files; they
were not regenerated during this checkpoint.

## Global Montgomery Instances

| File | Module | Instance | Stage B type | Purpose | Latency assumption | Selectable |
|---|---|---|---|---|---:|---|
| `rtl/gs_butterfly.sv` | `gs_butterfly` | `u_mul` | `mont_mul_select` | BFU `(a-b) * twiddle` | old 12 / WL 14 | yes |
| `rtl/gs_mdc_core.sv` | `gs_mdc_core` | `u_intt_scale0` | `mont_mul_select` | INTT lane0 final `N_INV_MONT` scale | old 12 / WL 14 | yes |
| `rtl/gs_mdc_core.sv` | `gs_mdc_core` | `u_intt_scale1` | `mont_mul_select` | INTT lane1 final `N_INV_MONT` scale | old 12 / WL 14 | yes |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_pre_mul0` | `mont_mul_select` | Pre_NTT lane0 psi multiply | old 12 / WL 14 | yes |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_pre_mul1` | `mont_mul_select` | Pre_NTT lane1 psi multiply | old 12 / WL 14 | yes |
| `rtl/pointwise_mul.sv` | `pointwise_mul` | `u_mul` | direct `mont_mul` | pointwise multiply | old 12 | no |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_post_mul0` | direct `mont_mul` | Post_INTT lane0 psi inverse multiply | old 12 | no |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_post_mul1` | direct `mont_mul` | Post_INTT lane1 psi inverse multiply | old 12 | no |
| `rtl/mont_mul_select.sv` | `mont_mul_select` | `g_wl.u_mul` | `mont_mul_wl` | selectable WL implementation | 14 | wrapper internal |
| `rtl/mont_mul_select.sv` | `mont_mul_select` | `g_current.u_mul` | `mont_mul` | selectable old implementation | 12 | wrapper internal |

## Stage A Scope

Stage A replaces the WL-sensitive multipliers inside the NTT/INTT core only:

- GS butterfly multiplier path through `gs_butterfly.u_mul`.
- `gs_mdc_core.u_intt_scale0`.
- `gs_mdc_core.u_intt_scale1`.

In Stage A full-top synthesis, `poly_mul_top` Pre_NTT, Pointwise, and Post_INTT
multipliers remain old `mont_mul` behavior.

Stage A full-top synthesis was run at 100 MHz with:

```text
MUL_LAT=14
USE_WL_MONT=0
USE_WL_CORE=1
USE_WL_PRE_NTT=0
```

## Stage B Scope

Stage B adds only the two Pre_NTT multipliers in `poly_mul_top`:

- `poly_mul_top.u_pre_mul0`
- `poly_mul_top.u_pre_mul1`

Both are selectable through `mont_mul_select`. Pointwise and Post_INTT remain
old direct `mont_mul` paths. This is intentional: Stage B stops before the next
worst path is optimized.

Stage B full-top synthesis used:

```text
MUL_LAT=14
USE_WL_MONT=1
USE_WL_CORE=1
USE_WL_PRE_NTT=1
```

## Latency Alignment

- old `mont_mul` latency: 12
- `mont_mul_wl` latency: 14
- WL core `MUL_LAT`: 14
- Pointwise and Post_INTT address delays remain aligned to old latency 12 while
  those paths are still direct old `mont_mul`.

The Pre_NTT write address and valid paths are driven through the selected
multiplier valid latency, so Stage B keeps Pre_NTT data/write-address alignment.

## Functional Simulation Results

| Testbench | Result | Scope | Latency / cycles | Mismatch |
|---|---|---|---|---|
| `tb_mont_mul_wl` | PASS | standalone WL multiplier | WL latency 14 | none |
| `tb_gs_butterfly` | PASS | WL BFU path | `MUL_LAT=14` | none |
| `tb_gs_mdc_core` | PASS | WL BFU + WL INTT scale | core test PASS | none |
| `tb_gs_mdc_core_roundtrip` | PASS | NTT then INTT round trip | NTT done-first_in = 4289, INTT done-first_in = 4289 | none |
| `tb_poly_mul_top` | PASS | Stage B full top | random + directed negacyclic PASS | none |
| `tb_poly_mul_top_phase_cycles` | PASS | Stage B phase-cycle measurement | full_mul_cycles = 12921 | none |

Stage B directed negacyclic test includes `x^(N-1) * x`, with the wrapped result
at coefficient 0 equal to `Q-1`.

## Cycle Measurements

| Measurement | Old full top | Stage A full top | Stage B full top |
|---|---:|---:|---:|
| Full multiplication cycles | not remeasured in this checkpoint | not remeasured in this checkpoint | 12921 |
| A_NTT cycles | not remeasured in this checkpoint | not remeasured in this checkpoint | 4303 |
| B_NTT cycles | not remeasured in this checkpoint | not remeasured in this checkpoint | 4303 |
| INTT cycles | not remeasured in this checkpoint | not remeasured in this checkpoint | 4289 |
| Output coefficients | not remeasured in this checkpoint | not remeasured in this checkpoint | 4096 |

Stage B phase-cycle detail:

```text
FULL_MUL_CYCLES start=8192 done=21113 start_to_done=12921
PHASE A_NTT start=8193 first_in=8207 last_in=10254 first_out=10448 last_out=12495 done=12496 start_to_done=4303 first_in_to_first_out=2241 input_valid_cycles=2048 output_valid_cycles=2048 output_bubbles=1 output_coefficients=4096
PHASE B_NTT start=12497 first_in=12511 last_in=14558 first_out=14752 last_out=16799 done=16800 start_to_done=4303 first_in_to_first_out=2241 input_valid_cycles=2048 output_valid_cycles=2048 output_bubbles=1 output_coefficients=4096
PHASE INTT start=16812 first_in=16812 last_in=18859 first_out=19053 last_out=21100 done=21101 start_to_done=4289 first_in_to_first_out=2241 input_valid_cycles=2048 output_valid_cycles=2048 output_bubbles=1 output_coefficients=4096
```

## Full `poly_mul_top` Synthesis Comparison

Vivado target:

```text
xc7a200tsbg484-1
10.0 ns / 100 MHz
```

| Metric | Old full top | Stage A full top | Stage B full top | Stage B delta vs old |
|---|---:|---:|---:|---:|
| Slice LUT | 80765 | 78599 | 78259 | -2506 |
| LUT Memory | 30363 | 28596 | 28331 | -2032 |
| Registers | 29542 | 34197 | 34825 | +5283 |
| DSP48E1 | 520 | 436 | 424 | -96 |
| BRAM | 10 | 10 | 10 | 0 |
| WNS | +0.733 ns | +0.733 ns | +0.733 ns | 0.000 ns |
| TNS | 0.000 ns | 0.000 ns | 0.000 ns | 0.000 ns |
| Power | 2.273 W | 2.177 W | 2.172 W | -0.101 W |

## Worst Path Transfer

Old full top:

```text
u_core/g_stage[0].u_stage/u_butterfly/u_mul/g_current.u_mul/t_s00/CLK
-> u_core/g_stage[0].u_stage/u_butterfly/u_mul/g_current.u_mul/t_s0_reg/PCIN[0]
Data Path Delay: 7.687 ns
Logic Levels: DSP48E1=2
WNS: +0.733 ns
```

Stage A full top:

```text
u_mul0/u_mul/t_s00/CLK
-> u_mul0/u_mul/t_s0_reg/PCIN[0]
Data Path Delay: 7.687 ns
Logic Levels: DSP48E1=2
WNS: +0.733 ns
```

Stage B full top:

```text
u_mul0/u_mul/t_s00/CLK
-> u_mul0/u_mul/t_s0_reg/PCIN[0]
Data Path Delay: 7.687 ns
Logic Levels: DSP48E1=2
WNS: +0.733 ns
```

The old Stage0 BFU DSP cascade path is removed from the top-level worst path by
Stage A. After Stage A and Stage B, the top-level worst path is the unreplaced
Pointwise old `mont_mul` path (`u_mul0/u_mul`). This confirms the next timing
and DSP target is Pointwise, not Post_INTT.

## Current Conclusion

Stage B is functionally correct and meets 100 MHz synthesis timing. Compared
with the old full-top synthesis, it reduces DSP48E1 from 520 to 424 and reduces
estimated power from 2.273 W to 2.172 W, while increasing registers from 29542
to 34825 due to the deeper WL pipelines.

Recommended next stage: replace only the Pointwise multipliers (`u_mul0/1` via
`pointwise_mul.u_mul`) under a selectable parameter. Keep Post_INTT unchanged
until Pointwise has passed simulation and synthesis.
