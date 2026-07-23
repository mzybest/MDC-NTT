# Asymmetric Dual-Forward GS-MDC RTL Experiment

## 1. Scope

This controlled experiment implements the architecture proposed in
`docs/dual_forward_core_feasibility.md`. It starts from the single-job,
mode-tagged dual-context wavefront checkpoint at commit `8f21a55` and keeps
the existing polynomial-multiply tops available.

The experimental datapath is:

```text
A bank0/1 -> four-lane Pre_NTT boundary -> full CoreA (NTT) ----+
                                                               +-> Pointwise -> C_NTT banks
B bank0/1 -> four-lane Pre_NTT boundary -> NTT-only CoreB ------+                  |
                                                                                  v
                                                                    CoreA (INTT)
                                                                                  |
                                                                                  v
                                                                         Post_INTT
```

CoreA retains NTT/INTT support and its two `N^-1` scale multipliers. CoreB
contains the same 12 radix-2 GS-MDC stages but is forward-only, uses an
independent NTT-only twiddle image, and omits the two INTT scale multipliers.
The two forward cores run in lockstep and feed the existing two-lane
Pointwise datapath directly, so the A_NTT distributed cache is removed.

This experiment does not change the modulus, radix, GS butterfly equation,
Montgomery arithmetic, explicit Pre/Post negacyclic factors, or external
coefficient mapping. `MUL_LAT=14` and every Montgomery multiplier remains
II=1.

## 2. NTT-only twiddle storage

`scripts/gen_twiddle_ntt_only.py` generates one NTT-only image per stage:

```text
mem/twiddle_ntt_stage00.mem ... mem/twiddle_ntt_stage11.mem
```

The stage depths are `2048, 1024, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1`,
for 4,095 words in total. `twiddle_rom_stage_ntt` maps Stages 0-3 to
synchronous block ROM and later stages to distributed ROM/register logic.
The final stage is the Montgomery-domain constant one.

The synthesis RAM report confirms that CoreB's first four NTT-only tables use
`4 + 2 + 1 + 1 = 8` RAMB36 tiles. CoreB uses 18 BRAM tiles in total: eight
for twiddle storage and ten for its large MDC delay memories. This matches
the pre-RTL dedicated-ROM estimate exactly.

## 3. RTL changes

The experiment adds:

- `rtl/twiddle_rom_stage_ntt.sv`
- `rtl/gs_mdc_core_ntt_only.sv`
- `rtl/poly_mul_top_dual_forward.sv`

`rtl/mdc_stage.sv` gains a default-disabled `USE_NTT_ONLY_TWIDDLE` selection.
The existing stage-local combined NTT/INTT ROM and legacy twiddle paths remain
the defaults for existing tops. The frozen Stage-local regression, including
legacy twiddle mode, still passes.

The dual-forward top adds two Pre_NTT WL multipliers so A and B can enter
their cores in the same cycle. The lane psi factors are broadcast to the A
and B multipliers. The full CoreA is reused for C_INTT after Pointwise has
filled the two C_NTT banks.

## 4. Functional verification and cycles

| Test | Result | Key observation |
|---|---|---|
| `tb_mont_mul_wl` | PASS | old latency 12, WL latency 14 |
| `tb_gs_butterfly` | PASS | 32 vectors |
| `tb_gs_mdc_core` | PASS | existing full core unchanged |
| `tb_gs_mdc_core_ntt_only` | PASS | cycle/data equivalent to full core in NTT mode |
| `tb_poly_mul_top_wavefront` | PASS | existing random and directed negacyclic cases |
| `tb_poly_mul_top_dual_forward` | PASS | random and directed `x^(N-1)*x` |
| frozen Stage-local regression | PASS | nine tests plus legacy twiddle mode |

The NTT-only core measured:

- first input to first output: 2,241 cycles;
- first input to done: 4,289 cycles;
- input and output stream width: 2,048 pair cycles.

The full-top boundaries are:

| Phase | First input | Last input | First output | Last output |
|---|---:|---:|---:|---:|
| A_NTT | 8207 | 10254 | 10448 | 12495 |
| B_NTT | 8207 | 10254 | 10448 | 12495 |
| C_INTT | 12510 | 14557 | 14751 | 16798 |

| Metric | Dual-context wavefront | Dual-forward RTL | Change |
|---|---:|---:|---:|
| Compute latency | 10,669 cycles | 8,621 cycles | -2,048 (-19.20%) |
| Compute time at 100 MHz | 106.69 us | 86.21 us | -20.48 us |
| Relative operation rate | 1.000x | 1.2376x | +23.76% |
| First load to done | 18,861 cycles | 16,813 cycles | -2,048 (-10.86%) |

The measured RTL cycle result exactly matches the pre-RTL model.

## 5. 100 MHz synthesis

Target: Vivado 2022.2, `xc7a200tsbg484-1`, 10.000 ns.

| Metric | Pre-RTL estimate | Synthesis result | Difference |
|---|---:|---:|---:|
| Slice LUT | 90,211 | 86,849 | -3,362 |
| LUT Memory | 25,418 | 25,365 | -53 |
| Registers | 62,581 | 61,508 | -1,073 |
| DSP48E1 | 680 | 680 | 0 |
| BRAM | 43 | 43 | 0 |
| WNS | not predicted | +1.282 ns | PASS |
| TNS | not predicted | 0.000 ns | PASS |
| Estimated power | not predicted | 3.185 W | vectorless |

The hierarchical result is:

| Block | Slice LUT | LUT Memory | Registers | DSP48E1 | BRAM |
|---|---:|---:|---:|---:|---:|
| Full CoreA | 24,250 | 1,691 | 26,214 | 280 | 25 |
| NTT-only CoreB | 20,444 | 1,625 | 22,835 | 240 | 18 |

CoreB therefore removes the two INTT-scale WL multipliers exactly as intended:
`280 - 240 = 40 DSP48E1`.

## 6. 100 MHz post-route implementation

The isolated e06 flow uses `Explore`, `AltSpreadLogic_medium`,
`AggressiveFanoutOpt`, and `MoreGlobalIterations`.

| Metric | Current wavefront e06 | Dual-forward e06 | Change |
|---|---:|---:|---:|
| Slice LUT | 73,645 | 86,039 | +12,394 (+16.83%) |
| LUT Memory | 30,046 | 25,361 | -4,685 (-15.59%) |
| Registers | 38,492 | 63,548 | +25,056 (+65.10%) |
| DSP48E1 | 400 | 680 | +280 (+70.00%) |
| BRAM | 35 | 43 | +8 (+22.86%) |
| Setup WNS | +0.317 ns | **-0.325 ns** | -0.642 ns |
| Setup TNS | 0.000 ns | **-3.893 ns** | 31 failing endpoints |
| Hold WHS | +0.012 ns | +0.050 ns | PASS |
| Hold THS | 0.000 ns | 0.000 ns | PASS |
| Estimated power | 2.454 W | 3.764 W | +1.310 W (+53.38%) |
| Routing errors | 0 | 0 | fully routed |

The implementation is physically legal: all 146,986 routable nets are fully
routed and setup misses 100 MHz by only 0.325 ns. The rough timing-equivalent
frequency is about 96.9 MHz (`1 / 10.325 ns`). This is an engineering estimate,
not a replacement for a routed timing run at a relaxed constraint.

The worst routed path is no longer the Stage0 subtract-to-multiplier path:

```text
CoreA Stage11 butterfly a_r
-> modular add (17 CARRY4)
-> sum-path delay SRL input
```

It has 10.007 ns data-path delay: 4.269 ns logic and 5.738 ns routing
(57.34% route). Six of the ten reported worst paths share this Stage11
modular-add structure. Three other top-ten paths are in CoreB Stage0:

```text
b_r -> mod_sub (24 CARRY4) -> mont_mul_wl partial-product DSP register
```

Thus the added core creates two near-critical path families rather than one
single multiplier bottleneck.

## 7. Conclusion

The independent-twiddle asymmetric dual-forward architecture is proven at
the cycle model, RTL function, resource-capacity, placement, and complete
routing levels. It reduces single-product compute latency by 19.20% and raises
the operation rate by 23.76%, with no algorithm change.

It is not yet a 100 MHz routed checkpoint because setup WNS is -0.325 ns.
The experiment should therefore remain an optimization branch rather than
replace the +0.317 ns wavefront baseline. A next timing experiment should be
controlled and target the two measured path families. In particular, an
explicit register/retiming boundary before the sum-path SRL can keep the
external BFU latency unchanged by shortening the remaining delay depth, while
the Stage0 diff-to-WL path must be checked separately. No such RTL change is
made in this experiment.
