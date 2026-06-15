# Optimized Baseline Summary

## Baseline Identification

The current optimized baseline is marked as:

```text
optimized_baseline_bfu_inputreg_constq
```

This name identifies the active RTL configuration and synthesis baseline. It
is a documentation baseline rather than a Git tag because the current working
tree contains the accumulated active RTL changes.

## Architecture Features

- Explicit Pre/Post negacyclic conversion
- BRAM-friendly `delay_memory` for large MDC reorder delays
- Registered `mont_mul` inputs
- Pipelined constant-Q shift/subtract/add implementation for `m * Q`
- Registered `gs_butterfly` inputs
- `MUL_LAT=9`
- Montgomery multiplier II=1
- Radix-2 GS-MDC datapath

No fused Pre/Post, radix-4, new multiplier restructuring, or MDC reorder
algorithm change is included in this baseline.

## Functional Status

The complete functional regression passed before this baseline was frozen:

- `tb_mont_mul`
- `tb_delay_memory`
- `tb_gs_butterfly`
- `tb_gs_mdc_core`
- `tb_poly_mul_top` random negacyclic multiplication
- Directed `x^(N-1) * x` negacyclic multiplication

## Final Resource Metrics

Target device: `xc7a200tsbg484-1`

| Resource | Utilization |
|---|---:|
| Slice LUTs | 74213 |
| LUT as memory | 30362 |
| Slice registers | 25538 |
| DSP48E1 | 520 |
| Block RAM tiles | 10 |

## 100 MHz Timing Baseline

| Metric | Result |
|---|---:|
| Target period | 10.000 ns |
| Target frequency | 100 MHz |
| WNS | -1.736 ns |
| TNS | -1666.626 ns |
| Worst data-path delay | 10.156 ns |
| Rough path-delay Fmax | about 98.5 MHz |

The worst path is inside the Stage0 Montgomery multiplier:

```text
t_s0_reg[16]__4
  -> 1 CARRY4 + 3 DSP48E1
  -> m_s1_reg/PCIN[0]
```

This is the `t_low * QINV` constant-multiplication path. It no longer passes
through the Stage0 butterfly subtraction logic.

The rough `98.5 MHz` value is calculated from the data-path delay alone. The
actual synthesis timing report also includes clock skew, uncertainty, and DSP
setup time, so the 100 MHz target still reports negative slack.

## Frequency-Sweep Conclusion

The multi-frequency synthesis sweep is recorded in `docs/frequency_sweep.md`.
The highest tested target that passes post-synthesis timing is:

```text
12.000 ns / 83.3 MHz, WNS = +0.264 ns
```

The next tested point, `11.500 ns / 87.0 MHz`, misses by only `0.236 ns`.
Therefore, the current synthesis-verified usable frequency is **83.3 MHz**.
Implementation and place-and-route timing have not been evaluated in this
frequency sweep.

## Preserved Reports

The original BFU-input-register 100 MHz reports remain preserved:

- `reports/utilization_after_bfu_inputreg.rpt`
- `reports/timing_after_bfu_inputreg.rpt`
- `reports/power_after_bfu_inputreg.rpt`

