# 12 ns Implementation Results

## Configuration

- Baseline: `optimized_baseline_bfu_inputreg_constq`
- Tool: Vivado 2022.2
- Top: `poly_mul_top`
- Device: `xc7a200tsbg484-1`
- Target period: `12.000 ns`
- Target frequency: `83.3 MHz`
- Command: `scripts/run_impl.bat xc7a200tsbg484-1 12.0`
- Constraint scope: current clock-only repository flow

The implementation flow executed:

```text
synth_design
opt_design
place_design
route_design
report_utilization
report_timing_summary
report_power
```

No RTL was modified. SHA256 hashes of every `rtl/*.sv` file were recorded
before and after implementation and matched exactly.

## Post-Route Result

The `12.0 ns / 83.3 MHz` post-route implementation **passes timing**.

| Metric | Post-route result |
|---|---:|
| WNS | +0.113 ns |
| TNS | 0.000 ns |
| Worst data-path delay | 10.432 ns |
| Hold WNS | +0.024 ns |
| Slice LUTs | 73293 |
| LUT as memory | 30362 |
| Slice registers | 25830 |
| DSP48E1 | 520 |
| Block RAM tiles | 10 |
| Total on-chip power | 1.892 W |
| Dynamic power | 1.751 W |
| Static power | 0.141 W |

Routing completed successfully with zero failed, unrouted, or partially routed
nets.

## Worst Path

The post-route worst path remains inside a Montgomery multiplier and still
represents the `t_low * QINV` calculation from `t_s0` to `m_s1`:

```text
Source:
u_core/g_stage[5].u_stage/u_butterfly/u_mul/t_s0_reg__2/CLK

Destination:
u_core/g_stage[5].u_stage/u_butterfly/u_mul/m_s1_reg/PCIN[0]
```

The post-route path is in Stage5 rather than the Stage0 instance reported by
synthesis. Its structure after physical optimization is:

```text
5 CARRY4 + 2 DSP48E1 + 1 LUT2
```

The path has a `10.432 ns` data-path delay: `7.712 ns` logic plus `2.720 ns`
routing. It does not pass through the GS butterfly subtraction logic.

## Synthesis Comparison

| Metric | 12 ns synthesis | 12 ns post-route | Change |
|---|---:|---:|---:|
| WNS | +0.264 ns | +0.113 ns | -0.151 ns |
| TNS | 0.000 ns | 0.000 ns | 0.000 ns |
| Worst data-path delay | 10.156 ns | 10.432 ns | +0.276 ns |

Post-route timing is slightly worse than synthesis timing, but the design
retains positive setup and hold slack at `83.3 MHz`.

Physical optimization reduces Slice LUTs from the synthesis value of `74213`
to `73293`, while increasing Slice registers from `25538` to `25830`. DSP,
BRAM, and LUT-memory counts are unchanged.

## Conclusion

The `optimized_baseline_bfu_inputreg_constq` version passes post-route timing
at `12.0 ns / 83.3 MHz` and can be frozen as the current optimized baseline.
Further architectural work, including fused NWC research, should start as a
separate experimental branch so this verified baseline remains available.

## Generated Artifacts

- `scripts/run_impl.tcl`
- `scripts/run_impl.bat`
- `reports/impl_12ns_utilization.rpt`
- `reports/impl_12ns_timing.rpt`
- `reports/impl_12ns_power.rpt`
- `reports/poly_mul_top_impl_12ns_opt.dcp`
- `reports/poly_mul_top_impl_12ns_placed.dcp`
- `reports/poly_mul_top_impl_12ns_routed.dcp`
- `reports/impl_12ns_rtl_hash_before.txt`
- `reports/impl_12ns_rtl_hash_after.txt`
