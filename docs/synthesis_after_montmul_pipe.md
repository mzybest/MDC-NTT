# Synthesis After Montgomery-Multiplier Pipelining

## Run Configuration

- Tool: Vivado 2022.2
- Top: `poly_mul_top`
- Device: `xc7a200tsbg484-1`
- Requested clock: `10.000 ns` / `100 MHz`
- Command: `scripts/run_synth.bat xc7a200tsbg484-1 10.0`
- Active Montgomery multiplier latency: 6 cycles
- Architecture: explicit Pre/Post negacyclic radix-2 GS-MDC

The synthesis run completed successfully with zero errors. The preserved
post-synthesis reports are:

- `reports/utilization_after_montmul_pipe.rpt`
- `reports/timing_after_montmul_pipe.rpt`
- `reports/power_after_montmul_pipe.rpt`

The previous three-cycle implementation is preserved as
`rtl/mont_mul_3cycle_old.sv`. The delay-memory synthesis baseline remains in
`docs/synthesis_after_delaymem.md`.

## Pipeline Change

The active `mont_mul` now separates the Montgomery operations into six
registered stages:

```text
stage 0: t = a * b
stage 1: m = low64(t[63:0] * QINV), delay t
stage 2: mq = m * Q, delay t
stage 3: sum = t + mq
stage 4: u = sum[128:64]
stage 5: compare/subtract Q and output y
```

`MUL_LAT` is now 6. The GS butterfly sum delay, core output delay, pointwise
address delay, and Post-INTT address delay follow the updated latency.

## Functional Verification

| Test | Result |
|---|---|
| `tb_mont_mul` random/boundary values and exact 6-cycle valid delay | PASS |
| `tb_delay_memory` | PASS |
| `tb_gs_butterfly` | PASS |
| `tb_gs_mdc_core` | PASS |
| `tb_poly_mul_top` random negacyclic multiplication | PASS |
| Directed `x^(N-1) * x` negacyclic multiplication | PASS |

## Utilization Comparison

| Resource | After delay_memory | After mont_mul pipeline | Change |
|---|---:|---:|---:|
| Slice LUTs | 92849 | 92987 | +138 (+0.15%) |
| LUT as memory | 26933 | 27726 | +793 (+2.94%) |
| Slice registers | 10166 | 21221 | +11055 (+108.74%) |
| DSP48E1 | 582 | 596 | +14 (+2.41%) |
| Block RAM tiles | 10 | 10 | 0 |

The register increase is the expected cost of isolating the wide arithmetic
operations. The additional LUT-memory use is from the longer valid/data
alignment delays mapping to shift-register LUTs. The previously inferred MDC
block RAMs remain intact.

## Timing Comparison

| Metric | After delay_memory | After mont_mul pipeline | Change |
|---|---:|---:|---:|
| WNS | -21.592 ns | -10.814 ns | +10.778 ns |
| TNS | -66643.016 ns | -48525.773 ns | +18117.243 ns |
| Worst data-path delay | 31.458 ns | 19.234 ns | -12.224 ns |
| Rough post-synthesis Fmax | about 31.8 MHz | about 52.0 MHz | substantial improvement |

The six-cycle pipeline removes the previous critical structure of four
DSP48E1 blocks followed by a 29-element CARRY4 chain. The new worst path is:

```text
Source:
feed_count_reg[10]/C

Destination:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/t_s0_reg/PCIN[0]
```

The new path ends at the Stage0 `mont_mul` stage-0 product register. It has 34
logic levels:

```text
3 DSP48E1 + 24 CARRY4 + LUT/MUX/distributed-RAM input logic
```

Its 19.234 ns data path consists of 13.271 ns logic delay and 5.963 ns routing
delay. The path starts at `feed_count`, passes through upstream distributed
memory and butterfly subtraction logic, and then enters the first 64x64
multiply stage.

Timing is substantially improved but still does not meet 100 MHz. The worst
path is still associated with `mont_mul`, specifically its first full-width
multiply. Adding idle pipeline stages after that multiply would not shorten
this path. The next focused timing step should implement the 64x64 products as
explicit DSP48-friendly partial products with registers between partial-product
generation and accumulation.

## Power Estimate

| Metric | After delay_memory | After mont_mul pipeline |
|---|---:|---:|
| Total on-chip power | 2.500 W | 2.582 W |
| Dynamic power | 2.355 W | 2.436 W |
| Static power | 0.145 W | 0.146 W |
| Junction temperature | 33.3 C | 33.6 C |

The power report is a vector-less post-synthesis estimate with Low confidence.

## Conclusion

The six-cycle Montgomery pipeline preserves functional behavior and nearly
halves the worst negative slack. The critical path no longer combines multiple
Montgomery operations, but a single full-width multiplier stage still exceeds
the 10 ns target. The prepared next step is limited to DSP48-friendly
decomposition and pipelining of the 64x64 multiplication inside `mont_mul`.
