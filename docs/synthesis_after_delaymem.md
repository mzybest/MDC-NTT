# Synthesis After MDC Delay-Memory Integration

## Run Configuration

- Tool: Vivado 2022.2
- Top: `poly_mul_top`
- Device: `xc7a200tsbg484-1`
- Requested clock: `10.000 ns` / `100 MHz`
- Command: `scripts/run_synth.bat xc7a200tsbg484-1 10.0`
- Architecture: explicit Pre/Post negacyclic radix-2 GS-MDC

The synthesis run completed successfully with zero errors. The preserved
post-synthesis reports are:

- `reports/utilization_after_delaymem.rpt`
- `reports/timing_after_delaymem.rpt`
- `reports/power_after_delaymem.rpt`

## Utilization Comparison

| Resource | Before delay_memory | After delay_memory | Change |
|---|---:|---:|---:|
| Slice LUTs | 102215 | 92849 | -9366 (-9.16%) |
| LUT as memory | 35381 | 26933 | -8448 (-23.88%) |
| Slice registers | 9449 | 10166 | +717 (+7.59%) |
| DSP48E1 | 570 | 582 | +12 (+2.11%) |
| Block RAM tiles | 0 | 10 | +10 |

The large MDC reorder delays now infer block RAM. Vivado's final block-RAM
mapping report identifies the `delay_memory` `g_ram.data_mem_reg` arrays as
synchronous `READ_FIRST` memories driving registered outputs. The mapped large
delay memories include the `1023 x 64`, `511 x 64`, `255 x 64`, and `127 x 64`
storage configurations corresponding to the `DEPTH >= 128` MDC stages.

BRAM inference is therefore successful. The design now uses 10 RAMB36E1 tiles,
and LUT-memory usage fell by 8448 LUTs, or 23.88%, relative to the previous
baseline. Small MDC delays remain mapped to SHIFT/SRL/register resources as
intended.

## Timing Comparison

| Metric | Before delay_memory | After delay_memory | Change |
|---|---:|---:|---:|
| WNS | -21.706 ns | -21.592 ns | +0.114 ns |
| TNS | -67897.711 ns | -66643.016 ns | +1254.695 ns |
| Worst data-path delay | 31.572 ns | 31.458 ns | -0.114 ns |
| Rough post-synthesis Fmax | about 31.5 MHz | about 31.8 MHz | slight improvement |

Timing still does not meet the requested 10 ns period. The new worst path is:

```text
Source:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/sum_s12__5/CLK

Destination:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/sum_s1_reg[128]/D
```

The path remains inside the Stage0 butterfly `mont_mul`. It has 44 logic
levels, including 4 DSP48E1 blocks and 29 CARRY4 elements. Its 31.458 ns data
path consists of 22.777 ns logic delay and 8.681 ns routing delay.

The critical path is therefore still the Montgomery multiplier accumulation
path, not the new MDC delay memory.

## Power Estimate

| Metric | Before delay_memory | After delay_memory |
|---|---:|---:|
| Total on-chip power | 2.582 W | 2.500 W |
| Dynamic power | 2.437 W | 2.355 W |
| Static power | 0.145 W | 0.145 W |
| Junction temperature | 33.6 C | 33.3 C |

The power report is a vector-less post-synthesis estimate with Low confidence.

## Conclusion

Replacing the behavioral MDC reorder arrays with `delay_memory` achieved the
intended BRAM inference without changing the verified algorithm. The primary
resource improvement is the 23.88% reduction in LUT-memory usage. The primary
timing bottleneck remains `mont_mul.sv`; no further optimization is included in
this synthesis measurement.
