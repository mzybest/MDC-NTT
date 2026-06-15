# Synthesis After GS Butterfly Input Register

## Run Configuration

- Tool: Vivado 2022.2
- Top: `poly_mul_top`
- Device: `xc7a200tsbg484-1`
- Requested clock: `10.000 ns` / `100 MHz`
- Command: `scripts/run_synth.bat xc7a200tsbg484-1 10.0`
- Active Montgomery multiplier latency: 9 cycles
- Montgomery multiplier initiation interval: 1 cycle
- GS butterfly latency: `MUL_LAT+1` cycles

This step adds one register stage at the `gs_butterfly` input. The registered
`a`, `b`, and `twiddle` values feed the modular add/subtract and Montgomery
multiply paths, while the registered valid signal feeds both aligned paths.
No Montgomery multiplier, GS-MDC reorder, Pre/Post, or algorithm change is
included.

The preserved reports are:

- `reports/utilization_after_bfu_inputreg.rpt`
- `reports/timing_after_bfu_inputreg.rpt`
- `reports/power_after_bfu_inputreg.rpt`

## Functional Verification

| Test | Result |
|---|---|
| `tb_mont_mul` random/boundary values and exact 9-cycle valid delay | PASS |
| `tb_delay_memory` | PASS |
| `tb_gs_butterfly` | PASS |
| `tb_gs_mdc_core` | PASS |
| `tb_poly_mul_top` random negacyclic multiplication | PASS |
| Directed `x^(N-1) * x` negacyclic multiplication | PASS |

The butterfly input register adds one cycle to the butterfly's total latency.
The MDC stages continue to use `bf_valid`, and the complete core and top-level
regressions confirm that the output ordering remains correct.

## Utilization Comparison

| Resource | Constant-Q pipeline | BFU input register | Change |
|---|---:|---:|---:|
| Slice LUTs | 74236 | 74213 | -23 |
| LUT as memory | 30362 | 30362 | 0 |
| Slice registers | 24006 | 25538 | +1532 |
| DSP48E1 | 520 | 520 | 0 |
| Block RAM tiles | 10 | 10 | 0 |

The new input registers increase the global register count as expected. LUT,
DSP, and BRAM use are effectively unchanged.

## Timing Comparison

| Metric | Constant-Q pipeline | BFU input register | Change |
|---|---:|---:|---:|
| WNS | -2.590 ns | -1.736 ns | +0.854 ns |
| TNS | -2958.803 ns | -1666.626 ns | +1292.177 ns |
| Worst data-path delay | 11.781 ns | 10.156 ns | -1.625 ns |
| Rough path-delay Fmax | about 84.9 MHz | about 98.5 MHz | +13.6 MHz |

The previous worst path:

```text
feed_count_reg[10]
  -> Stage0 butterfly subtraction
  -> mont_mul t=a*b DSP input
```

is no longer critical. The new worst path is entirely inside the Stage0
Montgomery multiplier:

```text
Source:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/t_s0_reg[16]__4/C

Destination:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/m_s1_reg/PCIN[0]
```

Its structure is:

```text
1 CARRY4 + 3 DSP48E1
```

The path has 4 logic levels and a `10.156 ns` data-path delay: `8.635 ns`
logic plus `1.521 ns` routing. It does not pass through the Stage0 subtraction
logic. The `100 MHz` synthesis target still misses timing by `1.736 ns`,
primarily because the destination DSP48E1 has a large setup-time contribution.
The path-delay-only Fmax estimate is about `98.5 MHz`; a conservative estimate
derived directly from the `100 MHz` WNS is about `85.2 MHz`.

## Power Estimate

| Metric | Constant-Q pipeline | BFU input register |
|---|---:|---:|
| Total on-chip power | 1.955 W | 1.973 W |
| Dynamic power | 1.813 W | 1.831 W |
| Static power | 0.141 W | 0.142 W |

The power report is a vector-less post-synthesis estimate with Low confidence.

## Conclusion

The GS butterfly input register is functionally correct and removes the long
top-level feed-counter and Stage0 subtraction path from the timing bottleneck.
WNS improves from `-2.590 ns` to `-1.736 ns`, while DSP, BRAM, and LUT use stay
essentially unchanged. The new worst path remains inside the Stage0
Montgomery multiplier and consists of a short carry element followed by three
cascaded DSP48E1 blocks; it no longer passes through Stage0 subtraction.
