# Controlled WL Montgomery Core Replacement

This experiment adds a selectable Montgomery multiplier wrapper and applies the
word-level Montgomery multiplier only to the GS butterfly path inside
`gs_mdc_core`. The full `poly_mul_top` replacement is intentionally not part of
this stage.

## RTL Scope

Active datapath changes in this stage:

- Added `rtl/mont_mul_select.sv`.
- `gs_butterfly` instantiates `mont_mul_select` instead of direct `mont_mul`.
- `mdc_stage` and `gs_mdc_core` pass `USE_WL_MONT` down to the butterfly path.
- `mont_mul_wl` now has an internal input register:
  - `a_r <= a`
  - `b_r <= b`
  - `valid_r <= in_valid`
- The WL BFU path uses `MUL_LAT = 14`.

Not changed in this stage:

- Original `rtl/mont_mul.sv` is preserved.
- `poly_mul_top` Pre_NTT, Pointwise, and Post_INTT direct `mont_mul` instances
  are not replaced.
- `gs_mdc_core` INTT scale `u_intt_scale0/1` remain direct `mont_mul` instances
  in this stage.

## Functional Simulation

| Testbench | Result | Notes |
|---|---|---|
| `tb_mont_mul_wl` | PASS | `mont_mul` latency = 12, `mont_mul_wl` latency = 14 |
| `tb_gs_butterfly` | PASS | 32 random vectors |
| `tb_gs_mdc_core` | PASS | NTT output matches `golden_ntt_a.mem` |

The `tb_gs_mdc_core` simulation finished at 42945 ns. With the existing
testbench schedule, the first input-valid sample is at 65 ns, so the first
input-valid to done interval is:

```text
(42945 ns - 65 ns) / 10 ns = 4288 cycles
```

## GS-MDC Core Synthesis

Vivado target:

```text
xc7a200tsbg484-1
10.0 ns
```

| Metric | Old core (`USE_WL_MONT=0`, `MUL_LAT=12`) | WL BFU core (`USE_WL_MONT=1`, `MUL_LAT=14`) | Delta |
|---|---:|---:|---:|
| Slice LUT | 34407 | 32082 | -2325 |
| LUT Memory | 3468 | 1944 | -1524 |
| Registers | 22031 | 25966 | +3935 |
| DSP48E1 | 364 | 292 | -72 |
| BRAM | 10 | 10 | 0 |
| WNS | +0.733 ns | +0.733 ns | 0.000 ns |
| TNS | 0.000 ns | 0.000 ns | 0.000 ns |
| Power | 1.796 W | 1.718 W | -0.078 W |
| NTT cycles | ~4274 | 4288 | +14 |
| INTT cycles | not measured in this stage | not measured in this stage | n/a |

## Worst Path

Old core worst path:

```text
g_stage[0].u_stage/u_butterfly/u_mul/g_current.u_mul/t_s00/CLK
-> g_stage[0].u_stage/u_butterfly/u_mul/g_current.u_mul/t_s0_reg/PCIN[0]
Data Path Delay: 7.687 ns
Logic Levels: DSP48E1=2
WNS: +0.733 ns
```

WL BFU latency13 worst path, before the input-register fix:

```text
g_stage[0].u_stage/u_butterfly/b_r_reg[0]/C
-> g_stage[0].u_stage/u_butterfly/u_mul/g_wl.u_mul/u_intmul/p32_s1_reg/A[13]
Data Path Delay: 7.909 ns
Logic Levels: CARRY4=24 LUT3=1 LUT4=1
WNS: -1.990 ns
```

WL BFU latency14 worst path, after the input-register fix:

```text
u_intt_scale0/t_s00/CLK
-> u_intt_scale0/t_s0_reg/PCIN[0]
Data Path Delay: 7.687 ns
Logic Levels: DSP48E1=2
WNS: +0.733 ns
```

The previous integrated WL failure path from Stage0 `b_r` through
`mod_sub/diff` into the WL partial-product register is no longer the worst path
and no timing violations remain in the 100 MHz synthesis timing summary.

## Poly Top Stage

The second replacement stage has not been executed yet. Pre_NTT, Pointwise,
Post_INTT, and INTT scale replacement should only be evaluated after the WL BFU
core timing fix, because full-top replacement introduces additional latency
alignment and control changes.

| Metric | Old `poly_mul_top` | WL `poly_mul_top` |
|---|---:|---:|
| Slice LUT | not rerun in this stage | not executed |
| LUT Memory | not rerun in this stage | not executed |
| Registers | not rerun in this stage | not executed |
| DSP48E1 | not rerun in this stage | not executed |
| BRAM | not rerun in this stage | not executed |
| WNS | not rerun in this stage | not executed |
| TNS | not rerun in this stage | not executed |
| Power | not rerun in this stage | not executed |
| full_mul_cycles | not rerun in this stage | not executed |
| Function | previous baseline only | not executed |

## Conclusion

The latency14 WL BFU core replacement is functionally correct and meets 100 MHz
synthesis timing. It reduces the GS-MDC core DSP count by 72 and total LUT count
by 2325 versus the old core, while increasing registers by 3935. The next
controlled experiment can replace the remaining Montgomery users in the full
`poly_mul_top` datapath, with explicit latency alignment for Pre_NTT,
Pointwise, Post_INTT, and INTT scale.
