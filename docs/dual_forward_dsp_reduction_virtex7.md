# Dual-Forward DSP Reduction and Virtex-7 Frequency Experiment

## Scope

This experiment starts from commit `9a5c1e9` on branch
`codex/dual_forward_dsp_reduction`. The frozen source is the 100 MHz
dual-forward GS-MDC design with two NTT engines, one reused INTT engine,
WL Montgomery multiplication, and a measured full-multiply interval of
8623 cycles.

The experiment keeps the radix, modulus, interfaces, MDC reorder, WL
Montgomery II=1 behavior, and 14-cycle multiplier latency unchanged. No
multicycle, false-path, or relaxed clock constraint is used.

## DSP Reduction A: Load-Time Preprocessing

The serial load interface accepts one coefficient per cycle. With
`USE_LOAD_PREPROCESS=1`, one II=1 `mont_mul_select` performs

```text
load_data * psi^index -> preprocessed A/B input bank
```

during the existing 8192-cycle A/B load phase. This replaces the four
lane-parallel Pre_NTT Montgomery units used after `start`. A delayed
`{load_sel, load_addr}` tag aligns each result with its destination bank,
and `WAIT_LOAD_DRAIN` prevents transform launch until the last 14-cycle
Montgomery result has been written. The old four-multiplier path remains
selectable with `USE_LOAD_PREPROCESS=0`.

## DSP Reduction B: INTT Scale/Post Fusion

The explicit design performs two consecutive Montgomery operations at the
INTT output:

```text
x -> mont(x, N_INV_MONT) -> mont(result, psi_inv_mont[index])
```

The generated table stores

```text
fused_factor[index] = psi_inv_mont[index] * N^-1 mod Q
```

so that one operation is equivalent:

```text
mont(x, fused_factor[index])
```

With `FUSE_INTT_SCALE_IN_POST=1`, the two core scale Montgomery units are
omitted and the existing two Post_INTT units use `psi_inv_ninv.mem`. The
core retains the 14-cycle output delay, so valid, address, done, and total
cycle behavior do not change. The original scale and factor path remains
selectable with the parameter set to zero.

`validate_fused_post_factors.py` checked all 4096 table entries and 10000
random Montgomery-domain equivalence cases.

## Functional Verification

| Test | Configuration | Result | Cycles |
|---|---|---:|---:|
| `tb_mont_mul_wl` | old/WL latency check | PASS | old 12, WL 14 |
| `tb_gs_butterfly` | WL BFU | PASS | 32 vectors |
| `tb_gs_mdc_core` | shared NTT/INTT core | PASS | unchanged |
| `tb_gs_mdc_core_ntt_only` | second forward core | PASS | unchanged |
| `tb_poly_mul_top_dual_forward` | baseline 0/0 | PASS | 8623 |
| `tb_poly_mul_top_dual_forward` | load Pre only 1/0 | PASS | 8623 |
| `tb_poly_mul_top_dual_forward` | fused Post only 0/1 | PASS | 8623 |
| `tb_poly_mul_top_dual_forward` | combined 1/1 | PASS | 8623 |

Every top-level configuration passed both random and directed negacyclic
tests. The directed case remains `x^(N-1) * x = -1 mod (x^N+1)`.

## Artix-7 Synthesis Comparison

Target: `xc7a200tsbg484-1`, Vivado 2022.2, 10.000 ns.

| Configuration | Slice LUT | LUT Memory | Registers | DSP48E1 | BRAM | WNS (ns) | Power (W) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Frozen baseline | 86851 | 25365 | 61938 | 680 | 43 | +1.282 | 3.190 |
| Load Pre only | 81423 | 25375 | 57535 | 620 | 50 | +1.282 | 3.098 |
| Fused Post only | 82198 | 25299 | 58542 | 640 | 50 | +1.282 | 3.148 |
| Combined | 79386 | 25309 | 54239 | 580 | 50 | +1.282 | 3.041 |

The combined synthesis result removes 100 DSP48E1 blocks (14.7%), 7465
LUTs (8.6%), and 7699 registers (12.4%) relative to the same-flow baseline.
The new single-table Post factor ROM is inferred as seven RAMB36E1 blocks,
which explains the BRAM increase from 43 to 50. LUT Memory is essentially
unchanged; the LUT reduction is mainly logic removed with six Montgomery
instances.

## Artix-7 Post-Route Result

Flow: `opt_design Explore`, `place_design AltSpreadLogic_medium`,
`phys_opt_design AggressiveFanoutOpt`, and
`route_design MoreGlobalIterations`. For like-for-like final signoff, the
routed checkpoint is temporarily constrained to 9.8 ns, processed by
post-route `phys_opt_design Explore` and incremental routing, then restored
to 10.0 ns. No timing exception or relaxed constraint is used.

| Metric | Frozen 680-DSP record | Combined 580-DSP result | Change |
|---|---:|---:|---:|
| Slice LUT | 86069 | 78503 | -7566 (-8.8%) |
| LUT Memory | 25354 | 25305 | -49 |
| Registers | 63704 | 54923 | -8781 (-13.8%) |
| DSP48E1 | 680 | 580 | -100 (-14.7%) |
| BRAM | 43 | 50 | +7 |
| Setup WNS | +0.201 ns | +0.204 ns | +0.003 ns |
| Setup TNS | 0.000 ns | 0.000 ns | unchanged |
| Hold WHS | +0.014 ns | +0.015 ns | +0.001 ns |
| Hold THS | 0.000 ns | 0.000 ns | unchanged |
| Estimated power | 3.745 W | 3.444 W | -0.301 W (-8.0%) |
| Full multiply | 8623 cycles | 8623 cycles | unchanged |

The first combined e06 route produced WNS +0.167 ns. That result was not a
like-for-like comparison with the frozen +0.201 ns checkpoint, because the
frozen result also used a forced post-route optimization at 9.8 ns before
restoring 10.0 ns for signoff. Applying the same legal flow to the 580-DSP
checkpoint produced WNS +0.004 ns at 9.8 ns and final WNS +0.204 ns at
10.0 ns. The optimized design has 129143 fully routed nets, zero routing
errors, setup TNS 0.000 ns, hold WHS +0.015 ns, and hold THS 0.000 ns.

The new worst path is:

```text
u_core_a Stage0 gs_butterfly b_r
  -> modular subtraction/carry logic
  -> mont_mul_wl intmul p31_s1 partial-product register
```

Its data path is 9.400 ns, split into 3.877 ns logic (41.2%) and 5.523 ns
routing (58.8%). DSP reduction lowers area and power but does not remove the
BFU-to-WL-partial-product critical-path class. The final routed checkpoint is
`artix_impl/combined_100mhz_postroute_oc9p8/routed_signoff_10ns.dcp`.

## Virtex-7 Frequency Sweep

Selected target: `xc7vx330tffg1157-1`. Vivado confirms this exact part is
installed. It keeps the 7-series DSP48E1 architecture and `-1` speed grade,
making it a controlled platform comparison.

The original Vivado 2022.2 attempt stopped before netlist construction because
the installed license did not cover Virtex-7. The experiment was resumed with
Vivado 2026.1, which reported a valid Vivado Design Suite BASIC license
covering `xc7vx330t`.

The same RTL and implementation directives were used at every frequency:

```text
opt_design        Explore
place_design      AltSpreadLogic_medium
phys_opt_design   AggressiveFanoutOpt
route_design      MoreGlobalIterations
```

No timing exception, overconstraint, relaxed clock, or RTL change was used.
All routed designs have zero routing errors and zero unrouted or partially
routed nets.

### Post-Route Timing and Resources

| Target | Period | WNS | TNS | WHS | THS | Slice LUT | LUT Memory | Registers | DSP48E1 | BRAM | Power | Implementation runtime |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 MHz | 10.000 ns | +0.641 ns | 0.000 ns | +0.006 ns | 0.000 ns | 78491 | 25309 | 54603 | 580 | 50 | 3.443 W | 7038 s |
| 120 MHz | 8.333 ns | +0.379 ns | 0.000 ns | +0.015 ns | 0.000 ns | 78480 | 25309 | 54740 | 580 | 50 | 4.075 W | 5964 s |
| 150 MHz | 6.667 ns | +0.101 ns | 0.000 ns | +0.032 ns | 0.000 ns | 78510 | 25304 | 55742 | 580 | 50 | 5.152 W | 6713 s |

All three target frequencies pass both setup and hold timing after routing.
The small register-count variation is caused by frequency-dependent physical
optimization and DSP register pushing; it does not represent an RTL change.

The full multiplication remains 8623 cycles in every case:

| Target | Full multiplication latency | Approximate operations/s |
|---:|---:|---:|
| 100 MHz | 86.230 us | 11597 |
| 120 MHz | 71.858 us | 13916 |
| 150 MHz | 57.487 us | 17395 |

### Worst-Path Movement

The Virtex-7 worst paths no longer pass through the BFU modular subtraction
and WL partial-product input register. They are route-dominated writes into
the load-preprocessed A/B coefficient banks:

| Target | Source to destination class | Data path | Logic | Routing |
|---:|---|---:|---:|---:|
| 100 MHz | load Pre `y_reg` to `a_bank0/1` LUTRAM data input | 8.966 ns | 0.308 ns (3.4%) | 8.658 ns (96.6%) |
| 120 MHz | load Pre `y_reg` to `a_bank0` LUTRAM data input | 7.575 ns | 0.269 ns (3.6%) | 7.306 ns (96.4%) |
| 150 MHz | delayed load metadata to `b_bank1` LUTRAM write address | 6.247 ns | 0.269 ns (4.3%) | 5.978 ns (95.7%) |

At 150 MHz, the first four reported setup paths are replicated LUTRAM write
address pins with identical +0.101 ns slack. The fifth path is the load Pre
Montgomery result to a `b_bank1` data input with +0.105 ns slack. The
present high-frequency limit is therefore distributed-memory bank routing,
not Montgomery arithmetic.

The 150 MHz result is the highest demonstrated frequency in this sweep. It is
a valid routed checkpoint, but its +0.101 ns setup margin is narrow. The
120 MHz result has a more comfortable +0.379 ns margin and is the safer
default operating point when robustness is preferred over peak measured
frequency.

Reports and routed checkpoints are stored under:

```text
reports/dual_forward_dsp_reduction/virtex7_v2026_1/
```

The pre-sweep and post-sweep RTL SHA256 manifests were compared by hash value;
all `rtl/*.sv` hashes are identical.

## Conclusion

The DSP-reduction architecture is functionally proven and closes 100 MHz on
Artix-7 with WNS +0.204 ns and the full dual-forward performance unchanged.
It reduces DSP utilization from 91.9% to 78.4%, creates useful placement
headroom, and reduces estimated routed power by about 8.0%.

On `xc7vx330tffg1157-1`, the unchanged 580-DSP design passes complete
post-route timing at 100, 120, and 150 MHz. Relative to the Artix-7 100 MHz
result, Virtex-7 improves WNS from +0.204 ns to +0.641 ns at the same clock.
At 150 MHz it still passes with WNS +0.101 ns and reduces the 8623-cycle full
multiplication time to about 57.49 us. Therefore 150 MHz is the measured peak
checkpoint from this sweep, while 120 MHz is the recommended margin-oriented
operating point. Further frequency work should target BRAM-friendly input-bank
storage and local placement/routing, not the already-resolved BFU/WL path.
