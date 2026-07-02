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

Current stages covered by this document:

- Stage A: WL BFU path plus WL INTT scale inside `gs_mdc_core`.
- Stage B: Stage A plus Pre_NTT lane0/lane1 multipliers in `poly_mul_top`.
- Stage C: Stage B plus Pointwise lane0/lane1 multipliers.
- Stage D: Stage C plus Post_INTT lane0/lane1 multipliers.

Stage D is the current full-top WL replacement checkpoint. The old `mont_mul`
RTL is still preserved and selectable through parameters.

## Safety State

- Current branch during this checkpoint: `optimized_baseline_bfu_inputreg_constq_impl83p3`
- Frozen optimized explicit baseline remains preserved.
- `rtl/mont_mul.sv` is preserved.
- Old multiplier paths are preserved through selectable parameters.
- WL multiplier paths use `mont_mul_select` and `mont_mul_wl`.
- No multicycle path or false path constraint was added.
- `mont_mul_wl` remains an II=1 pipeline.

## Global Montgomery Instances After Stage D

| File | Module | Instance | Stage D type | Purpose | Latency assumption | Selectable |
|---|---|---|---|---|---:|---|
| `rtl/gs_butterfly.sv` | `gs_butterfly` | `u_mul` | `mont_mul_select` | BFU `(a-b) * twiddle` | old 12 / WL 14 | yes |
| `rtl/gs_mdc_core.sv` | `gs_mdc_core` | `u_intt_scale0` | `mont_mul_select` | INTT lane0 final `N_INV_MONT` scale | old 12 / WL 14 | yes |
| `rtl/gs_mdc_core.sv` | `gs_mdc_core` | `u_intt_scale1` | `mont_mul_select` | INTT lane1 final `N_INV_MONT` scale | old 12 / WL 14 | yes |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_pre_mul0` | `mont_mul_select` | Pre_NTT lane0 psi multiply | old 12 / WL 14 | yes |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_pre_mul1` | `mont_mul_select` | Pre_NTT lane1 psi multiply | old 12 / WL 14 | yes |
| `rtl/pointwise_mul.sv` | `pointwise_mul` | `u_mul` | `mont_mul_select` | pointwise multiply | old 12 / WL 14 | yes |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_post_mul0` | `mont_mul_select` | Post_INTT lane0 psi inverse multiply | old 12 / WL 14 | yes |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_post_mul1` | `mont_mul_select` | Post_INTT lane1 psi inverse multiply | old 12 / WL 14 | yes |
| `rtl/mont_mul_select.sv` | `mont_mul_select` | `g_wl.u_mul` | `mont_mul_wl` | selectable WL implementation | 14 | wrapper internal |
| `rtl/mont_mul_select.sv` | `mont_mul_select` | `g_current.u_mul` | `mont_mul` | selectable old implementation | 12 | wrapper internal |

## Stage Scopes

Stage A replaces the WL-sensitive multipliers inside the NTT/INTT core only:
GS butterfly multiplier path and the two INTT scale multipliers.

Stage B adds only the two Pre_NTT multipliers in `poly_mul_top`:
`u_pre_mul0` and `u_pre_mul1`.

Stage C adds only the Pointwise multipliers through `pointwise_mul.u_mul`.

Stage D adds only the two Post_INTT multipliers in `poly_mul_top`:
`u_post_mul0` and `u_post_mul1`.

Stage D synthesis used:

```text
MUL_LAT=14
USE_WL_MONT=1
USE_WL_CORE=1
USE_WL_PRE_NTT=1
USE_WL_POINTWISE=1
USE_WL_POST_INTT=1
```

## Latency Alignment

- old `mont_mul` latency: 12
- `mont_mul_wl` latency: 14
- WL core `MUL_LAT`: 14
- Pointwise address delay uses `POINTWISE_MUL_LAT`.
- `POINTWISE_MUL_LAT = USE_WL_POINTWISE ? 14 : 12`.
- Post_INTT address delay uses `POST_MUL_LAT`.
- `POST_MUL_LAT = USE_WL_POST_INTT ? 14 : 12`.

This keeps Pointwise and Post_INTT output data aligned with their delayed write
addresses in both old and WL modes. Stage D increases full multiplication by 2
cycles compared with Stage C because Post_INTT latency changes from 12 to 14.

## Functional Simulation Results

| Testbench | Result | Scope | Latency / cycles | Mismatch |
|---|---|---|---|---|
| `tb_mont_mul_wl` | PASS | standalone WL multiplier | WL latency 14 | none |
| `tb_gs_butterfly` | PASS | WL BFU path | `MUL_LAT=14` | none |
| `tb_gs_mdc_core` | PASS | WL BFU + WL INTT scale | core test PASS at 42945 ns | none |
| `tb_gs_mdc_core_roundtrip` | PASS | NTT then INTT round trip | NTT done-first_in = 4289, INTT done-first_in = 4289 | none |
| `tb_poly_mul_top` | PASS | Stage D full top | random + directed negacyclic PASS | none |
| `tb_poly_mul_top_phase_cycles` | PASS | Stage D phase-cycle measurement | full_mul_cycles = 12925 | none |

Stage D directed negacyclic test includes `x^(N-1) * x`, with the wrapped result
at coefficient 0 equal to `Q-1`.

## Cycle Measurements

| Measurement | Stage C full top | Stage D full top | Delta |
|---|---:|---:|---:|
| Full multiplication cycles | 12923 | 12925 | +2 |
| A_NTT cycles | 4303 | 4303 | 0 |
| B_NTT cycles | 4303 | 4303 | 0 |
| INTT cycles | 4289 | 4289 | 0 |
| Output coefficients | 4096 | 4096 | 0 |

Stage D phase-cycle detail:

```text
FULL_MUL_RESULT PASS errors=0
FULL_MUL_CYCLES start=8192 done=21117 start_to_done=12925
PHASE A_NTT start=8193 first_in=8207 last_in=10254 first_out=10448 last_out=12495 done=12496 start_to_done=4303 first_in_to_first_out=2241 input_valid_cycles=2048 output_valid_cycles=2048 output_bubbles=1 output_coefficients=4096
PHASE B_NTT start=12497 first_in=12511 last_in=14558 first_out=14752 last_out=16799 done=16800 start_to_done=4303 first_in_to_first_out=2241 input_valid_cycles=2048 output_valid_cycles=2048 output_bubbles=1 output_coefficients=4096
PHASE INTT start=16814 first_in=16814 last_in=18861 first_out=19055 last_out=21102 done=21103 start_to_done=4289 first_in_to_first_out=2241 input_valid_cycles=2048 output_valid_cycles=2048 output_bubbles=1 output_coefficients=4096
```

## Full `poly_mul_top` Synthesis Comparison

Vivado target:

```text
xc7a200tsbg484-1
10.0 ns / 100 MHz
```

| Metric | Stage C full top | Stage D full top | Stage D delta vs Stage C |
|---|---:|---:|---:|
| Slice LUT | 77857 | 77613 | -244 |
| LUT Memory | 28077 | 27823 | -254 |
| Registers | 35498 | 36165 | +667 |
| DSP48E1 | 412 | 400 | -12 |
| BRAM | 10 | 10 | 0 |
| WNS | +0.733 ns | +1.282 ns | +0.549 ns |
| TNS | 0.000 ns | 0.000 ns | 0.000 ns |
| Power | 2.156 W | 2.147 W | -0.009 W |

Stage D synthesis has no remaining direct old 64x64 Montgomery multiplier path
in the active full-top configuration. The old RTL remains available through
`mont_mul_select` parameters.

## Worst Path Transfer

Stage C full top:

```text
u_post_mul0/t_s00/CLK
-> u_post_mul0/t_s0_reg/PCIN[0]
Data Path Delay: 7.687 ns
Logic Levels: DSP48E1=2
WNS: +0.733 ns
```

Stage D full top:

```text
u_core/g_stage[0].u_stage/u_butterfly/b_r_reg[0]/C
-> u_core/g_stage[0].u_stage/u_butterfly/u_mul/g_wl.u_mul/u_intmul/p02_s1_reg/B[13]
Data Path Delay: 7.909 ns
Logic Levels: CARRY4=24 LUT3=1 LUT4=1
WNS: +1.282 ns
```

After Stage D, the old Post_INTT DSP cascade path is removed from the worst
path. The new worst path is inside the WL BFU input/mod-sub side feeding the
word-level partial-product register, and it meets the 10 ns synthesis
constraint.

## Current Conclusion

Stage D is functionally correct and meets 100 MHz synthesis timing. Compared
with Stage C, it reduces DSP48E1 from 412 to 400, reduces Slice LUT from 77857
to 77613, improves WNS from +0.733 ns to +1.282 ns, and reduces estimated power
from 2.156 W to 2.147 W. Registers increase from 35498 to 36165 due to the
deeper WL Post_INTT pipelines.

Recommended next step: run 100 MHz implementation for the Stage D full-WL
configuration. Stage D is a good candidate for the current WL full-top optimized
checkpoint, pending post-route timing confirmation.
