# Synthesis After Montgomery-Multiplier Input Register

## Run Configuration

- Tool: Vivado 2022.2
- Top: `poly_mul_top`
- Device: `xc7a200tsbg484-1`
- Requested clock: `10.000 ns` / `100 MHz`
- Command: `scripts/run_synth.bat xc7a200tsbg484-1 10.0`
- Active Montgomery multiplier latency: 7 cycles

Step A adds registered `a_r`, `b_r`, and valid state at the unchanged
`mont_mul` interface. The full-width `t = a_r * b_r` multiplication starts on
the following cycle.

The preserved reports are:

- `reports/utilization_after_montmul_inputreg.rpt`
- `reports/timing_after_montmul_inputreg.rpt`
- `reports/power_after_montmul_inputreg.rpt`

## Functional Verification

| Test | Result |
|---|---|
| `tb_mont_mul` random/boundary values and exact 7-cycle valid delay | PASS |
| `tb_delay_memory` | PASS |
| `tb_gs_butterfly` | PASS |
| `tb_gs_mdc_core` | PASS |
| `tb_poly_mul_top` random negacyclic multiplication | PASS |
| Directed `x^(N-1) * x` negacyclic multiplication | PASS |

## Utilization Comparison

| Resource | 6-cycle pipeline | 7-cycle input register | Change |
|---|---:|---:|---:|
| Slice LUTs | 92987 | 85778 | -7209 |
| LUT as memory | 27726 | 27802 | +76 |
| Slice registers | 21221 | 20408 | -813 |
| DSP48E1 | 596 | 700 | +104 |
| Block RAM tiles | 10 | 10 | 0 |

Vivado absorbed more input/output registers into DSP48E1 structures, increasing
DSP use while reducing surrounding LUT logic. The inferred MDC block RAMs
remain unchanged.

## Timing Comparison

| Metric | 6-cycle pipeline | 7-cycle input register | Change |
|---|---:|---:|---:|
| WNS | -10.814 ns | -3.196 ns | +7.618 ns |
| Worst data-path delay | 19.234 ns | 11.136 ns | -8.098 ns |
| Rough post-synthesis Fmax | about 52.0 MHz | about 89.8 MHz | substantial improvement |

The previous path from `feed_count` through RAMD64E, butterfly subtraction,
and the Stage0 `t_s0` multiplier input is no longer the worst path. The new
worst path is fully inside the Stage0 Montgomery multiplier:

```text
Source:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/m_s1_reg[0]__4/C

Destination:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/mq_s2_reg__0/C[45]
```

The path has 16 logic levels:

```text
12 CARRY4 + 2 LUT3 + 2 LUT4
```

It does not terminate at `mont_mul/t_s0_reg` and does not pass through the
twiddle ROM or RAMD64E. Step A therefore successfully isolated the external
input path.

## Step B Decision

The Step A WNS is still slightly below the requested `-3 ns` threshold, so
Step B is triggered. Per the requested scope, Step B rewrites only the first
`t = a*b` multiplication as a pipelined DSP-friendly partial-product tree.

The measured Step A worst path is now the later `m * Q` stage, so splitting
only `a*b` is not expected to remove the current worst path. Step B synthesis
is still required to measure the resource and timing impact without changing
the Montgomery reduction.

## Power Estimate

- Total on-chip power: `2.489 W`
- Dynamic power: `2.344 W`
- Static power: `0.145 W`
- Confidence: Low
