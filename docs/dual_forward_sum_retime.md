# Dual-Forward BFU Sum-Path Retiming Experiment

## 1. Scope

This is a controlled experiment derived from commit `75689d0` on branch
`codex/dual_forward_sum_retime`. It targets the routed critical path observed
in the dual-forward NTT-only architecture without changing the NTT algorithm,
Montgomery multiplier, external interfaces, or transform latency.

The original dual-forward e06 worst path was:

```text
CoreA Stage11 butterfly input register
-> modular addition
-> sum-path delay SRL input
```

The experiment adds one explicit register at the modular-sum boundary and
reduces the following sum delay line from `MUL_LAT` to `MUL_LAT-1`. The
Montgomery difference path remains unchanged, so the external butterfly
latency is still `MUL_LAT+1` and `MUL_LAT` remains 14.

The change is controlled by `USE_BFU_SUM_RETIME`. It defaults to 0 in the
shared modules, preserving the old path. The experimental
`poly_mul_top_dual_forward` top enables it by default.

## 2. Netlist Check

Vivado 2022.2 retained 1,536 explicit `sum_boundary_r` registers:

```text
24 butterfly units x 64 bits = 1,536 registers
```

This confirms that the intended boundary was physically represented in the
synthesized netlist rather than optimized back into the original SRL input.

## 3. Functional Verification

| Testbench | Result | Measured cycles or latency |
|---|---|---:|
| `tb_mont_mul_wl` | PASS | WL latency 14 |
| `tb_gs_butterfly` | PASS | old and retimed outputs cycle-identical, including valid bubbles |
| `tb_gs_mdc_core` | PASS | unchanged |
| `tb_gs_mdc_core_ntt_only` | PASS | first output 2241, done 4289 |
| `tb_poly_mul_top_wavefront` | PASS | 10,669 compute cycles |
| `tb_poly_mul_top_dual_forward` | PASS | 8,621 compute cycles |

The dual-forward cycle count is unchanged. Random and directed negacyclic
tests, including `x^(N-1) * x = -1 mod Q`, pass.

## 4. Synthesis Comparison

Target: `xc7a200tsbg484-1`, 10.000 ns, Vivado 2022.2.

| Metric | Dual-forward baseline | Sum-retimed | Change |
|---|---:|---:|---:|
| Slice LUT | 86,849 | 86,851 | +2 |
| LUT Memory | 25,365 | 25,365 | 0 |
| Registers | 61,508 | 63,033 | +1,525 |
| DSP48E1 | 680 | 680 | 0 |
| BRAM | 43 | 43 | 0 |
| WNS | +1.282 ns | +1.282 ns | 0 |
| TNS | 0.000 ns | 0.000 ns | 0 |
| Estimated power | 3.185 W | 3.202 W | +0.017 W |

The Stage11 modular-add-to-SRL path is absent after synthesis. The worst
synthesis path becomes the existing butterfly subtraction into the WL
partial-product registers.

## 5. Post-Route Comparison

Both runs use the same e06 directives:

```text
opt_design       Explore
place_design     AltSpreadLogic_medium
phys_opt_design  AggressiveFanoutOpt
route_design     MoreGlobalIterations
```

| Metric | Dual-forward baseline | Sum-retimed | Change |
|---|---:|---:|---:|
| Slice LUT | 86,039 | 86,092 | +53 |
| LUT Memory | 25,361 | 25,365 | +4 |
| Registers | 63,548 | 65,311 | +1,763 |
| DSP48E1 | 680 | 680 | 0 |
| BRAM | 43 | 43 | 0 |
| Setup WNS | -0.325 ns | **-0.211 ns** | +0.114 ns |
| Setup TNS | -3.893 ns | **-0.734 ns** | +3.159 ns |
| Setup failing endpoints | 31 | 11 | -20 |
| Hold WHS | +0.050 ns | +0.011 ns | -0.039 ns, PASS |
| Hold THS | 0.000 ns | 0.000 ns | 0 |
| Estimated power | 3.764 W | 3.813 W | +0.049 W |
| Routing errors | 0 | 0 | fully routed |
| Flow runtime | 10,665 s | 45,264 s | 4.24x |

All 147,195 routable nets are fully routed. The rough timing-equivalent
frequency is approximately 97.9 MHz (`1 / 10.211 ns`), but the design does not
meet the 100 MHz setup requirement.

## 6. New Critical Path

The final worst path is:

```text
CoreA Stage2 b_r_reg[13]
-> modular subtraction carry chain
-> mont_mul_wl intmul p31_s1 DSP input register
```

Its data-path delay is 9.810 ns: 3.901 ns logic and 5.909 ns routing
(60.24% routing), with 22 logic levels including 19 CARRY4 blocks. Seven of
the reported top ten setup paths are variants of the BFU input/modular
subtraction to WL partial-product path. The other three are routing-heavy
paths inside WL reduction rounds.

The intended Stage11 sum path has therefore been removed from the critical
set. The remaining setup failure is not caused by the retimed sum datapath.

## 7. Conclusion

The experiment is functionally correct and improves routed WNS by 0.114 ns,
reduces TNS by 3.159 ns, and removes 20 failing endpoints without changing
cycles, DSP, or BRAM. However, it still fails 100 MHz setup timing and adds
1,763 routed registers. The router reported congestion and required 12.6
hours, 4.24 times the baseline e06 runtime.

Therefore this variant is useful evidence that the Stage11 sum path can be
retimed independently, but it should not replace the current routed baseline.
The next RTL experiment, if approved, should target the measured
`mod_sub -> mont_mul_wl` boundary rather than add more sum-path registers.

