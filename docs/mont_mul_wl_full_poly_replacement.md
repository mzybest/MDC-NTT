# Controlled WL Montgomery Full-Top Replacement

This document tracks the staged replacement plan for moving the selectable
word-level Montgomery multiplier beyond the GS butterfly path. The experiment
is intentionally staged so the explicit baseline and old multiplier path remain
recoverable at every step.

## Safety State

- Current branch: `optimized_baseline_bfu_inputreg_constq_impl83p3`
- Frozen baseline remains available on the same branch/tag name.
- The initial safety check found a clean `git status` before Stage A edits.
- `rtl/mont_mul.sv` is preserved.
- Old multiplier paths are preserved through `USE_WL_MONT=0`.
- WL multiplier paths use `USE_WL_MONT=1`.
- No multicycle path or false path constraint was added.
- `mont_mul_wl` remains an II=1 pipeline.

## Global Montgomery Instances

| File | Module | Instance | Current type | Purpose | Latency assumption | Selectable |
|---|---|---|---|---|---:|---|
| `rtl/gs_butterfly.sv` | `gs_butterfly` | `u_mul` | `mont_mul_select` | BFU `(a-b) * twiddle` | old 12 / WL 14 | yes |
| `rtl/gs_mdc_core.sv` | `gs_mdc_core` | `u_intt_scale0` | `mont_mul_select` | INTT lane0 final `N_INV_MONT` scale | old 12 / WL 14 | yes |
| `rtl/gs_mdc_core.sv` | `gs_mdc_core` | `u_intt_scale1` | `mont_mul_select` | INTT lane1 final `N_INV_MONT` scale | old 12 / WL 14 | yes |
| `rtl/pointwise_mul.sv` | `pointwise_mul` | `u_mul` | `mont_mul` | pointwise multiply | old 12 | no |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_pre_mul0` | `mont_mul` | Pre_NTT lane0 psi multiply | old 12 | no |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_pre_mul1` | `mont_mul` | Pre_NTT lane1 psi multiply | old 12 | no |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_post_mul0` | `mont_mul` | Post_INTT lane0 psi inverse multiply | old 12 | no |
| `rtl/poly_mul_top.sv` | `poly_mul_top` | `u_post_mul1` | `mont_mul` | Post_INTT lane1 psi inverse multiply | old 12 | no |
| `rtl/mont_mul_select.sv` | `mont_mul_select` | `g_wl.u_mul` | `mont_mul_wl` | selectable WL implementation | 14 | wrapper internal |
| `rtl/mont_mul_select.sv` | `mont_mul_select` | `g_current.u_mul` | `mont_mul` | selectable old implementation | 12 | wrapper internal |

## Stage A Scope

Stage A replaces only the INTT scale multipliers inside `gs_mdc_core`:

- `u_intt_scale0`
- `u_intt_scale1`

Both instances now use `mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_MONT))`.
With `USE_WL_MONT=0`, they still instantiate the old `mont_mul`. With
`USE_WL_MONT=1`, they instantiate `mont_mul_wl`.

The following full-top multipliers were not changed in Stage A:

- `poly_mul_top.u_pre_mul0`
- `poly_mul_top.u_pre_mul1`
- `pointwise_mul.u_mul`
- `poly_mul_top.u_post_mul0`
- `poly_mul_top.u_post_mul1`

## Latency Alignment

The active WL core configuration uses:

- old `mont_mul` latency: 12
- `mont_mul_wl` latency: 14
- `MUL_LAT`: 14 for the WL core synthesis/test configuration

No additional magic-number delay was added for INTT scale. The final scale path
uses the multiplier `out_valid` signals, so the output valid, write enable, and
done behavior follow the selected multiplier implementation.

## Functional Simulation

| Testbench | Result | Latency | Cycles | Mismatch |
|---|---|---|---|---|
| `tb_mont_mul_wl` | PASS | old 12, WL 14 | n/a | none |
| `tb_gs_butterfly` | PASS | WL path 14 | n/a | none |
| `tb_gs_mdc_core` | PASS | WL BFU + WL INTT scale | test finished at 42945 ns | none |
| `tb_gs_mdc_core_roundtrip` | PASS | WL BFU + WL INTT scale | NTT done-first_in = 4289, INTT done-first_in = 4289 | none |

Round-trip detail from `tb_gs_mdc_core_roundtrip`:

```text
NTT_ROUNDTRIP_CYCLES first_in=1 first_out=2242 last_out=4289 done=4290 first_in_to_first_out=2241
INTT_ROUNDTRIP_CYCLES first_in=4291 first_out=6532 last_out=8579 done=8580 first_in_to_first_out=2241
```

## GS-MDC Core Synthesis

Vivado target:

```text
xc7a200tsbg484-1
10.0 ns
```

| Metric | Old core | WL BFU only | WL BFU + INTT scale | Delta vs old | Delta vs WL BFU only |
|---|---:|---:|---:|---:|---:|
| Slice LUT | 34407 | 32082 | 31731 | -2676 | -351 |
| LUT Memory | 3468 | 1944 | 1691 | -1777 | -253 |
| Registers | 22031 | 25966 | 26621 | +4590 | +655 |
| DSP48E1 | 364 | 292 | 280 | -84 | -12 |
| BRAM | 10 | 10 | 10 | 0 | 0 |
| WNS | +0.733 ns | +0.733 ns | +1.282 ns | +0.549 ns | +0.549 ns |
| TNS | 0.000 ns | 0.000 ns | 0.000 ns | 0.000 ns | 0.000 ns |
| Power | 1.796 W | 1.718 W | 1.664 W | -0.132 W | -0.054 W |
| NTT cycles | ~4274 | 4288 | 4289 measured in round-trip test | +15 approx | +1 approx |
| INTT cycles | not measured | not measured | 4289 measured in round-trip test | n/a | n/a |

## Worst Path

Old core:

```text
g_stage[0].u_stage/u_butterfly/u_mul/g_current.u_mul/t_s00/CLK
-> g_stage[0].u_stage/u_butterfly/u_mul/g_current.u_mul/t_s0_reg/PCIN[0]
Data Path Delay: 7.687 ns
Logic Levels: DSP48E1=2
WNS: +0.733 ns
```

WL BFU only:

```text
u_intt_scale0/t_s00/CLK
-> u_intt_scale0/t_s0_reg/PCIN[0]
Data Path Delay: 7.687 ns
Logic Levels: DSP48E1=2
WNS: +0.733 ns
```

WL BFU + INTT scale:

```text
g_stage[0].u_stage/u_butterfly/b_r_reg[0]/C
-> g_stage[0].u_stage/u_butterfly/u_mul/g_wl.u_mul/u_intmul/p02_s1_reg/B[13]
Data Path Delay: 7.909 ns
Logic Levels: CARRY4=24 LUT3=1 LUT4=1
WNS: +1.282 ns
```

The old INTT scale DSP cascade path is removed from the worst path after Stage
A. The new worst path is in the Stage0 BFU input/mod-sub side feeding the WL
partial-product register, but it still meets the 10 ns synthesis constraint.

## Stage A Conclusion

Stage A is functionally correct and meets 100 MHz synthesis timing for
`gs_mdc_core`. Relative to WL BFU only, replacing the two INTT scale multipliers
reduces DSP48E1 by 12, LUT by 351, LUT Memory by 253, and estimated power by
0.054 W, while adding 655 registers.

The controlled next step can enter Stage B: replace only the two Pre_NTT
multipliers in `poly_mul_top` with `mont_mul_select`, then re-run functional
simulation before touching pointwise or Post_INTT paths.
