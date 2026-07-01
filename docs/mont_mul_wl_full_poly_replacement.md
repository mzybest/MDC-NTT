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

Current stage covered by this document:

- Stage A: WL BFU path plus WL INTT scale inside `gs_mdc_core`.
- Stage B: Stage A plus Pre_NTT lane0/lane1 multipliers in `poly_mul_top`.
- Stage C: Stage B plus Pointwise lane0/lane1 multipliers.
- Post_INTT multipliers remain old direct `mont_mul` paths after Stage C.
- Stage D is not part of this checkpoint.

## Safety State

- Current branch during this checkpoint: `optimized_baseline_bfu_inputreg_constq_impl83p3`
- Frozen optimized explicit baseline remains preserved.
- `rtl/mont_mul.sv` is preserved.
- Old multiplier paths are preserved through selectable parameters.
- WL multiplier paths use `mont_mul_select` and `mont_mul_wl`.
- No multicycle path or false path constraint was added.
- `mont_mul_wl` remains an II=1 pipeline.

## Full `poly_mul_top` Baseline

The frozen full-top baseline for this controlled comparison uses the optimized
explicit Pre/Post negacyclic design, BRAM-friendly delay memories, constant-Q
Montgomery optimization, and BFU input registers. For the old full-top synthesis
comparison, `USE_WL_MONT=0` selects the old `mont_mul` path.

Old full-top synthesis reports were reused from the existing report files; they
were not regenerated during the Stage B checkpoint.

## Global Montgomery Instances After Stage C

| File | Module | Instance | Stage C type | Purpose | Latency assumption | Selectable |
|---|---|---|---|---|---:|---|
| `rtl/gs_butterfly.sv` | `gs_butterfly` | `u_mul` | `mont_mul_select` | BFU `(a-b) * twiddle` | old 12 / WL 14 | yes |
| `rtl/gs_mdc_core.sv` | `gs_mdc_core` | `u_intt_scale0` | `mont_mul_select` | INTT lane0 final `N_INV_MONT` scale | old 12 / WL 14 | yes |
| `rtl/gs_mdc_core.sv` | `gs_mdc_core` | `u_intt_scale1` | `mont_mul_select` | INTT lane1 final `N_INV_MONT` scale | old 12 / WL 14 | yes |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_pre_mul0` | `mont_mul_select` | Pre_NTT lane0 psi multiply | old 12 / WL 14 | yes |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_pre_mul1` | `mont_mul_select` | Pre_NTT lane1 psi multiply | old 12 / WL 14 | yes |
| `rtl/pointwise_mul.sv` | `pointwise_mul` | `u_mul` | `mont_mul_select` | pointwise multiply | old 12 / WL 14 | yes |
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
old direct `mont_mul` paths in Stage B.

Stage B full-top synthesis used:

```text
MUL_LAT=14
USE_WL_MONT=1
USE_WL_CORE=1
USE_WL_PRE_NTT=1
USE_WL_POINTWISE=0
```

## Stage C Scope

Stage C adds only the Pointwise multipliers:

- `rtl/pointwise_mul.sv` internal instance `u_mul`.
- Full-top paths `poly_mul_top.u_mul0/u_mul` and `poly_mul_top.u_mul1/u_mul`.

`pointwise_mul` now has parameter `USE_WL_POINTWISE`. When it is `0`, the
wrapper selects old `mont_mul`; when it is `1`, it selects `mont_mul_wl`.
Post_INTT remains unchanged in Stage C:

- `poly_mul_top.u_post_mul0` is still direct old `mont_mul`.
- `poly_mul_top.u_post_mul1` is still direct old `mont_mul`.

Stage C full-top synthesis used:

```text
MUL_LAT=14
USE_WL_MONT=1
USE_WL_CORE=1
USE_WL_PRE_NTT=1
USE_WL_POINTWISE=1
```

## Latency Alignment

- old `mont_mul` latency: 12
- `mont_mul_wl` latency: 14
- WL core `MUL_LAT`: 14
- Pointwise address delay uses `POINTWISE_MUL_LAT`.
- `POINTWISE_MUL_LAT = USE_WL_POINTWISE ? 14 : 12`.
- Post_INTT address delay remains `POST_MUL_LAT = 12` while Post_INTT is still
  direct old `mont_mul`.

This keeps Pointwise output data and delayed write address aligned in both old
and WL modes. In Stage C, full multiplication increases by 2 cycles compared
with Stage B because Pointwise latency changes from 12 to 14.

## Functional Simulation Results

| Testbench | Result | Scope | Latency / cycles | Mismatch |
|---|---|---|---|---|
| `tb_mont_mul_wl` | PASS | standalone WL multiplier | WL latency 14 | none |
| `tb_gs_butterfly` | PASS | WL BFU path | `MUL_LAT=14` | none |
| `tb_gs_mdc_core` | PASS | WL BFU + WL INTT scale | core test PASS at 42945 ns | none |
| `tb_gs_mdc_core_roundtrip` | PASS | NTT then INTT round trip | NTT done-first_in = 4289, INTT done-first_in = 4289 | none |
| `tb_poly_mul_top` | PASS | Stage C full top | random + directed negacyclic PASS | none |
| `tb_poly_mul_top_phase_cycles` | PASS | Stage C phase-cycle measurement | full_mul_cycles = 12923 | none |

Stage C directed negacyclic test includes `x^(N-1) * x`, with the wrapped result
at coefficient 0 equal to `Q-1`.

## Cycle Measurements

| Measurement | Stage B full top | Stage C full top | Delta |
|---|---:|---:|---:|
| Full multiplication cycles | 12921 | 12923 | +2 |
| A_NTT cycles | 4303 | 4303 | 0 |
| B_NTT cycles | 4303 | 4303 | 0 |
| INTT cycles | 4289 | 4289 | 0 |
| Output coefficients | 4096 | 4096 | 0 |

Stage C phase-cycle detail:

```text
FULL_MUL_RESULT PASS errors=0
FULL_MUL_CYCLES start=8192 done=21115 start_to_done=12923
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

| Metric | Old full top | Stage A full top | Stage B full top | Stage C full top | Stage C delta vs Stage B |
|---|---:|---:|---:|---:|---:|
| Slice LUT | 80765 | 78599 | 78259 | 77857 | -402 |
| LUT Memory | 30363 | 28596 | 28331 | 28077 | -254 |
| Registers | 29542 | 34197 | 34825 | 35498 | +673 |
| DSP48E1 | 520 | 436 | 424 | 412 | -12 |
| BRAM | 10 | 10 | 10 | 10 | 0 |
| WNS | +0.733 ns | +0.733 ns | +0.733 ns | +0.733 ns | 0.000 ns |
| TNS | 0.000 ns | 0.000 ns | 0.000 ns | 0.000 ns | 0.000 ns |
| Power | 2.273 W | 2.177 W | 2.172 W | 2.156 W | -0.016 W |

## Worst Path Transfer

Stage B full top:

```text
u_mul0/u_mul/t_s00/CLK
-> u_mul0/u_mul/t_s0_reg/PCIN[0]
Data Path Delay: 7.687 ns
Logic Levels: DSP48E1=2
WNS: +0.733 ns
```

Stage C full top:

```text
u_post_mul0/t_s00/CLK
-> u_post_mul0/t_s0_reg/PCIN[0]
Data Path Delay: 7.687 ns
Logic Levels: DSP48E1=2
WNS: +0.733 ns
```

After Stage C, the old Pointwise DSP cascade path is removed from the worst
path. The new top-level worst path is the unreplaced Post_INTT old `mont_mul`
path (`u_post_mul0`). This is the expected next target for Stage D.

## Current Conclusion

Stage C is functionally correct and meets 100 MHz synthesis timing. Compared
with Stage B, it reduces DSP48E1 from 424 to 412, reduces Slice LUT from 78259
to 77857, and reduces estimated power from 2.172 W to 2.156 W. Registers
increase from 34825 to 35498 due to the deeper WL Pointwise pipeline.

Recommended next stage: replace only the Post_INTT multipliers
(`poly_mul_top.u_post_mul0/1`) under a selectable parameter. Keep the old path
selectable and rerun full functional simulation before synthesis.
