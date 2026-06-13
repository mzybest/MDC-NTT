# Vivado Synthesis Baseline

## Run Configuration

- Tool: Vivado 2022.2
- Top: `poly_mul_top`
- Device: `xc7a200tsbg484-1`
- Requested clock: 10.000 ns / 100 MHz
- Architecture: explicit Pre/Post negacyclic radix-2 GS-MDC baseline

The synthesis run completed successfully with zero errors. The complete reports
are stored in `reports/`.

## Post-Synthesis Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 102215 | 134600 | 75.94% |
| LUT as logic | 66834 | 134600 | 49.65% |
| LUT as memory | 35381 | 46200 | 76.58% |
| Slice registers | 9449 | 269200 | 3.51% |
| DSP48E1 | 570 | 740 | 77.03% |
| Block RAM tiles | 0 | 365 | 0.00% |

The dominant resource issues are DSP usage and distributed-memory LUT usage.
No block RAM was inferred. The current asynchronous-read MDC FIFOs, transform
RAMs, result RAMs, and ROMs therefore require further BRAM-friendly work.

## Post-Synthesis Timing

- WNS: `-21.706 ns`
- TNS: `-67897.711 ns`
- Requested period: `10.000 ns`
- Worst data path delay: `31.572 ns`
- Rough post-synthesis Fmax estimate: approximately `31.5 MHz`

The worst path ends in a Montgomery multiplier accumulation register and
contains four DSP48E1 blocks plus a long carry chain. The current three-cycle
behavioral Montgomery multiplier is the primary timing bottleneck.

## Power Estimate

- Total on-chip power: `2.582 W`
- Dynamic power: `2.437 W`
- Static power: `0.145 W`
- Junction temperature: `33.6 C`
- Confidence: Low

This is a vector-less post-synthesis estimate and should not be treated as a
final implementation power result.

## Synthesis Preparation Finding

Before this baseline could synthesize, `a_ntt_ram`, `c_ntt_ram`, and
`result_ram` had to be split into access-compatible banks. The original arrays
had two writes to one inferred memory in the same process, which Vivado could
not map to RAM. This physical bank split preserves the verified algorithm and
external data ordering.

The next optimization priority remains replacing large asynchronous-read
storage with synchronous BRAM-friendly structures, followed by Montgomery
multiplier pipelining based on the measured critical path.
