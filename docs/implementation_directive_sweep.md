# 100 MHz Implementation Directive Sweep

## 1. Experiment scope

This sweep evaluates legal Vivado implementation directives for the frozen full-WL
`poly_mul_top` design. No RTL, algorithm, interface, arithmetic width, pipeline
latency, timing exception, or clock-period change was allowed.

Baseline identity:

- Branch: `optimized_baseline_bfu_inputreg_constq_impl83p3`
- Commit: `89460f593fd154f108e3691e36c2ea9f41ad720d`
- Top: `poly_mul_top`
- Device: `xc7a200tsbg484-1`
- Vivado: 2022.2
- Clock: 10.000 ns / 100 MHz
- Active generics: `MUL_LAT=14`, `USE_WL_MONT=1`,
  `USE_WL_CORE=1`, `USE_WL_PRE_NTT=1`,
  `USE_WL_POINTWISE=1`, `USE_WL_POST_INTT=1`
- Reference post-route result: WNS = +0.080 ns, WHS = +0.016 ns,
  77,050 LUT, 37,047 FF, 400 DSP48E1, 10 BRAM, 2.400 W

The legal directive names were taken from Vivado 2022.2 command help for
`opt_design`, `place_design`, `phys_opt_design`, and `route_design`.
Each completed experiment ran from fresh synthesis through routing and generated
its own checkpoints, timing, utilization, power, route-status, and top-five-path
reports.

## 2. Directive combinations

| ID | opt_design | place_design | pre-route phys_opt | route_design | TNS cleanup | post-route phys_opt |
|---|---|---|---|---|---:|---|
| e00 | Default | Default | Default | Default | No | None |
| e01 | Explore | Explore | Explore | Explore | No | None |
| e02 | Explore | ExtraTimingOpt | AggressiveExplore | AggressiveExplore | No | None |
| e03 | Default | EarlyBlockPlacement | Explore | Explore | No | None |
| e04 | Default | WLDrivenBlockPlacement | Explore | HigherDelayCost | No | None |
| e05 | Explore | AltSpreadLogic_low | Explore | Explore | No | None |
| e06 | Explore | AltSpreadLogic_medium | AggressiveFanoutOpt | MoreGlobalIterations | No | None |
| e07 | Explore | ExtraNetDelay_high | Explore | NoTimingRelaxation | No | None |
| e08 | Explore | ExtraTimingOpt | Explore | Explore | Yes | Explore |
| e09 | ExploreWithRemap | Explore | AggressiveExplore | AggressiveExplore | Yes | Explore |
| e10 | Explore | ExtraTimingOpt | AggressiveFanoutOpt | MoreGlobalIterations | Yes | Explore |
| e11 | ExploreWithRemap | WLDrivenBlockPlacement | Explore | HigherDelayCost | Yes | Explore |

Vivado skipped pre-route or post-route physical optimization when the design
already had non-negative WNS. In e08-e11, a legal post-route pass was requested,
but Vivado reported that no setup violation existed and skipped netlist changes;
the subsequent route call therefore performed only TNS cleanup on the routed
design.

## 3. Timing results

All completed runs have setup TNS = 0.000 ns, hold THS = 0.000 ns, zero routing
errors, zero unrouted nets, and zero partially routed nets.

| ID | Status | WNS (ns) | WHS (ns) | Data path (ns) | Logic (ns) | Route (ns) | Route % | Worst-path class |
|---|---|---:|---:|---:|---:|---:|---:|---|
| e00 | PASS | +0.080 | +0.016 | 9.329 | 4.440 | 4.889 | 52.41 | Stage3 BFU input to WL partial product |
| e01 | PASS | +0.158 | +0.024 | 9.773 | 0.456 | 9.317 | 95.33 | Post address delay to result RAM address |
| e02 | PASS | +0.118 | +0.017 | 10.169 | 0.580 | 9.589 | 94.30 | Stage control to NTT output delay |
| e03 | PASS | +0.140 | +0.012 | 9.063 | 4.521 | 4.542 | 50.12 | Stage9 BFU input to WL partial product |
| e04 | PASS | +0.142 | +0.009 | 9.758 | 0.456 | 9.302 | 95.33 | Post address delay to C_NTT RAM address |
| e05 | PASS | +0.022 | +0.011 | 9.122 | 4.635 | 4.487 | 49.19 | Stage11 BFU input to WL partial product |
| e06 | PASS | **+0.384** | +0.020 | 9.201 | 0.576 | 8.625 | 93.74 | Stage3 flush control to delay-memory BRAM input |
| e07 | ABORTED | N/A | N/A | N/A | N/A | N/A | N/A | Congested NoTimingRelaxation routing |
| e08 | PASS | +0.118 | +0.017 | 10.169 | 0.580 | 9.589 | 94.30 | Stage control to NTT output delay |
| e09 | PASS | +0.062 | +0.013 | 9.236 | 4.521 | 4.715 | 51.05 | Stage5 BFU input to WL partial product |
| e10 | PASS | **+0.356** | **+0.022** | 9.096 | 4.635 | 4.461 | 49.04 | Stage9 BFU input to WL partial product |
| e11 | PASS | +0.114 | +0.016 | 9.161 | 4.639 | 4.522 | 49.36 | Stage8 BFU input to WL partial product |

e07 did not produce signoff metrics. `NoTimingRelaxation` routing ran for more
than 2 h 26 min, reported congestion preventing all nets from routing, reached
an intermediate WNS of -0.095 ns, and then showed a rising overlap count in the
next global iteration. It was stopped as a non-convergent experiment and is not
used in ranking.

## 4. Resource, power, and runtime results

| ID | LUT | LUT Memory | FF | DSP48E1 | BRAM | Power (W) | Runtime |
|---|---:|---:|---:|---:|---:|---:|---:|
| e00 | 77,050 | 27,823 | 37,047 | 400 | 10 | 2.400 | 00:53:02 |
| e01 | 77,050 | 27,823 | 37,047 | 400 | 10 | 2.401 | 01:30:25 |
| e02 | 77,076 | 27,823 | 37,202 | 400 | 10 | 2.422 | 00:45:39 |
| e03 | 77,068 | 27,823 | 36,850 | 400 | 10 | 2.372 | 00:43:56 |
| e04 | 77,049 | 27,808 | 37,007 | 400 | 10 | 2.354 | 00:46:58 |
| e05 | 77,065 | 27,820 | 37,159 | 400 | 10 | 2.403 | 00:47:59 |
| e06 | 77,111 | 27,823 | 37,258 | 400 | 10 | 2.427 | 01:41:30 |
| e07 | N/A | N/A | N/A | N/A | N/A | N/A | >02:26:56 |
| e08 | 77,076 | 27,823 | 37,202 | 400 | 10 | 2.422 | 00:51:01 |
| e09 | 77,027 | 27,820 | 36,753 | 400 | 10 | 2.405 | 01:11:14 |
| e10 | 77,076 | 27,823 | 37,202 | 400 | 10 | 2.426 | 01:00:25 |
| e11 | 77,027 | 27,823 | 36,763 | 400 | 10 | 2.394 | 00:57:27 |

The DSP and BRAM structure is unchanged across every completed experiment.
Small LUT/FF differences come from implementation-time replication, packing,
and physical optimization, not RTL changes.

## 5. Best three runs

| Rank | ID | WNS | WHS | Power | Reason |
|---:|---|---:|---:|---:|---|
| 1 | e06 | +0.384 ns | +0.020 ns | 2.427 W | Largest legal setup margin; clean route; target exceeded |
| 2 | e10 | +0.356 ns | +0.022 ns | 2.426 W | Independent target-passing result; best hold margin |
| 3 | e01 | +0.158 ns | +0.024 ns | 2.401 W | Clean Explore result with no material resource change |

e06 improves WNS by **+0.304 ns** over the +0.080 ns baseline. Its changes are:

- LUT: +61 (+0.08%)
- FF: +211 (+0.57%)
- DSP48E1: unchanged at 400
- BRAM: unchanged at 10
- Estimated power: +0.027 W (+1.13%)
- Runtime: 01:41:30 versus 00:53:02

The e06 combination uses:

```text
opt_design      -directive Explore
place_design    -directive AltSpreadLogic_medium
phys_opt_design -directive AggressiveFanoutOpt
route_design    -directive MoreGlobalIterations
```

The improvement is consistent with a placement that spreads timing-sensitive
logic and a router that evaluates more global alternatives. This attribution is
an implementation inference, not an RTL change.

## 6. Critical-path movement

Baseline e00:

```text
Stage3 gs_butterfly b_r
-> mod_sub / carry chain
-> mont_mul_wl intmul partial-product register
```

Best e06:

```text
Stage3 mdc_stage flushing_reg
-> fifo_a_delay BRAM data input
```

The e06 worst path is 93.74% routing delay. The next reported critical-path class
includes Stage4 `mont_mul_wl` reduction logic
(`qh0_prod_s1_reg -> t_out_reg[80]`), but the original
`b_r/mod_sub -> intmul partial-product` path is no longer the number-one path.

e10 still reports the original BFU-to-WL class at Stage9, which shows that
`MoreGlobalIterations` alone is not sufficient; the medium logic-spreading
placement used by e06 is the important distinguishing choice.

## 7. RTL integrity

RTL hashes were collected before and after the sweep and compared byte-for-byte.

- `rtl/*.sv` SHA256 before/after identical: **YES**
- RTL files modified by this experiment: **none**
- Clock period remained 10.000 ns
- No multicycle, false-path, `set_max_delay`, or other timing relaxation was added

Final verification is stored in:

- `reports/directive_sweep/rtl_hash_before.txt`
- `reports/directive_sweep/rtl_hash_after_final.txt`
- `reports/directive_sweep/rtl_hash_compare_final.txt`

## 8. Recommended implementation flow

Use e06 as the normal 100 MHz routed flow:

```tcl
opt_design -directive Explore
place_design -directive AltSpreadLogic_medium
phys_opt_design -directive AggressiveFanoutOpt
route_design -directive MoreGlobalIterations
```

It meets setup and hold timing with WNS = +0.384 ns and WHS = +0.020 ns, has no
routing errors, and preserves the 400-DSP/10-BRAM architecture. e10 is a useful
fallback or reproducibility cross-check but has 0.028 ns less setup margin.

Because the target of +0.300 ns was reached without RTL changes, adding another
BFU-to-`mont_mul_wl` pipeline register is **not recommended at this stage**.
Such a change should only be reconsidered if a later device seed, integration
constraint, or full board-level implementation consumes the current margin.

## 9. Generated artifacts and limitations

Scripts:

- `scripts/run_impl_directive_sweep.tcl`
- `scripts/run_impl_directive_sweep.bat`

Per-run artifacts are under
`reports/directive_sweep/<experiment_name>/`, including routed checkpoints,
timing summary, top timing paths, utilization, power, route status, metrics, and
runtime.

The initial e00 invocation did not capture its full Tcl console log inside the
experiment directory because `-log/-journal` appeared after `-tclargs` in the
first wrapper revision. Its reports, checkpoints, metrics, and route-status
files are complete and were not overwritten. The wrapper has been corrected,
and its experiment-list mode was validated with Vivado 2022.2. e07 is explicitly
recorded as aborted rather than being reported as a signoff result.
