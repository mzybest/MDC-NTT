# XC7VX485T 150 MHz Proteus Comparison

## Scope

This experiment reruns the current BRAM A/C scratch design on an XC7VX485T at
150 MHz and separates three accounting boundaries:

1. `gs_mdc_core_ntt_only`: one forward NTT engine;
2. `gs_mdc_core_dualctx`: the experimental continuous-frame transform engine;
3. `poly_mul_top_dual_forward`: the complete dual-forward polynomial
   multiplier, including Pre_NTT, two forward cores, Pointwise, INTT, Post_INTT,
   top data banks, and result storage.

The separation is required because Proteus Table III reports an NTT
architecture, not a complete negacyclic polynomial-multiplication top.

## Reproducibility

Local experiment:

- branch: `codex/bram_ac_scratch`;
- commit: `9141671b54b05ad2a3bb51a5b8ff3e38ce826e03`;
- tool: Vivado 2026.1;
- part: `xc7vx485tffg1761-2`;
- signoff clock: 6.667 ns (150 MHz);
- implementation clock: 6.400 ns, restored to 6.667 ns for signoff;
- flow: Explore / AltSpreadLogic_medium / AggressiveFanoutOpt /
  AggressiveExplore / MoreGlobalIterations / post-route Explore;
- no multicycle, false-path, max-delay, algorithm, interface, or RTL change;
- `rtl/*.sv` SHA256 before and after: identical.

The Proteus paper states only Xilinx Virtex-7 XCVX485T, 150 MHz, Vivado
2019.1, and default synthesis/implementation settings. It does not state the
package or speed grade. The local `ffg1761-2` choice is therefore a documented
reproducibility assumption, not a claim that the package and speed grade are
identical to the authors' run.

## Proteus Reference Row

The closest Table III row is MDC OP5/6b for `(n, log2(q)) = (2^12, 64)`:

| Metric | Proteus MDC OP5/6b |
|---|---:|
| LUT | 21.9k |
| FF | 18.0k |
| DSP | 220 |
| BRAM | 16 |
| Single-operation latency | 4251 cycles |
| Average latency over 100 operations | 2070 cycles |

Suffix `b` denotes Proteus word-level Montgomery reduction. OP5 and OP6 are
combined in the paper table, so this is the closest architectural mapping,
not an author-certified statement that the two implementations are identical.

There is also a modulus caveat. Both designs expose a 64-bit datapath, but the
current local modulus is `Q = 0x0fffffffffffc001 = 2^60 - 2^14 + 1`, whose
mathematical bit length is 60. Proteus labels its row with `log2(q) = 64`.

## Functional and Cycle Evidence

Current-RTL Questa reruns:

| Test | Result | Measured cycles |
|---|---|---|
| `tb_gs_mdc_core_ntt_only` | PASS | first output 2242; done 4290 |
| `tb_gs_mdc_core_dualctx` | PASS | frame starts 2241, 4289, 6337, 8385 |

The dual-context frame-start interval is exactly 2048 cycles. Using the same
100-operation averaging convention as the paper:

```text
(4289 + 99 * 2048) / 100 = 2070.41 cycles
```

The existing Scheme A full-top regression passes random and directed
negacyclic multiplication and reports:

```text
poly_mul_top_dual_forward start-to-done = 8623 cycles
```

At 150 MHz, this is 57.49 us of compute latency after A and B are loaded. The
current full top is a single-job controller and reuses the A banks for C_NTT,
so it cannot accept 100 independent jobs back-to-back without reloading A/B.
Consequently a measured full-top 100-job average interval is not available and
must not be replaced by the dual-context NTT-core value.

## Post-Route Results

All three routed designs pass setup and hold and report zero routing errors.

| Configuration | Slice LUT | LUT Memory | FF | DSP | BRAM | WNS | WHS | Power |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| NTT-only core | 19,165 | 1,623 | 21,947 | 220 | 18 | +0.955 ns | +0.056 ns | 2.033 W |
| Dual-context transform core | 25,532 | 2,507 | 28,397 | 280 | 35 | +0.692 ns | +0.041 ns | 2.311 W |
| Full dual-forward polynomial top | 61,576 | 8,783 | 56,024 | 600 | 59 | +0.736 ns | +0.040 ns | 4.571 W |

Power values are Vivado vectorless estimates and are suitable for relative
comparison, not board-level measured power claims.

## Proteus Comparison Table

| Design | Accounting boundary | LUT | FF | DSP | BRAM | Single latency | 100-operation average |
|---|---|---:|---:|---:|---:|---:|---:|
| Proteus MDC OP5/6b | NTT architecture | 21.9k | 18.0k | 220 | 16 | 4251 cycles | 2070 cycles |
| Local NTT-only core | One forward NTT core | 19,165 | 21,947 | 220 | 18 | 4290 cycles | Not supported as continuous frames |
| Local dual-context core | Continuous NTT/INTT core | 25,532 | 28,397 | 280 | 35 | 4289 cycles | 2070.41 cycles |
| Local full polynomial top | 2 NTT + Pointwise + INTT + Pre/Post + banks | 61,576 | 56,024 | 600 | 59 | 8623 cycles | Not implemented/measured for 100 jobs |

At 150 MHz:

- Proteus OP5/6b single NTT: 28.34 us;
- Proteus average interval: 13.80 us;
- local NTT-only single NTT: 28.60 us;
- local dual-context single transform: 28.59 us;
- local dual-context average interval: 13.80 us;
- local full polynomial multiply compute latency: 57.49 us.

Relative to Proteus OP5/6b, the local NTT-only core has 12.5% fewer LUTs,
21.9% more FFs, the same DSP count, two more BRAM tiles, and 39 more cycles
(0.92%) of one-shot latency. It does not provide Proteus-style continuous
frame throughput. The dual-context core matches the 100-operation average to
rounding accuracy, but costs 16.6% more LUTs, 57.8% more FFs, 27.3% more DSPs,
and 118.8% more BRAM than the Proteus row.

## Worst Paths

### NTT-only core

```text
Stage10 b_r
  -> mod_sub carry chain
  -> mont_mul_wl intmul partial-product DSP input
```

Data-path delay is 5.495 ns, with 24 logic levels and 63.29% routing delay.

### Dual-context core

```text
stage-valid gate
  -> Stage1 mont_mul_wl round0 input register
```

Data-path delay is 6.202 ns and is 95.71% routing delay.

### Full polynomial top

```text
Core A stage-valid register
  -> Stage8 fifo_b delay-memory shift register
```

Data-path delay is 6.125 ns and is 94.61% routing delay. The routed full-top
limiter on XC7VX485T is inter-stage control/fanout routing, not Montgomery
arithmetic.

## Conclusion

The local NTT-only core is competitive with the closest Proteus Table III row:
it uses fewer LUTs, the same number of DSPs, and has one-shot latency within
1%, while paying moderate FF and BRAM overhead. The experimental dual-context
core proves a Proteus-like 2048-cycle steady-state frame interval at 150 MHz,
but it is not area-competitive with Proteus because it duplicates reorder
state and retains two INTT scale multipliers.

The complete dual-forward polynomial top also closes 150 MHz with healthy
setup/hold margins. Its 8623-cycle result is a full negacyclic polynomial
multiplication metric and should be compared only with other complete
polynomial multipliers, not with Proteus Table III NTT-core latency.

## Files

- `scripts/run_xc7vx485t_150mhz_comparison.tcl`
- `scripts/run_xc7vx485t_150mhz_comparison.bat`
- `reports/proteus_xc7vx485t_150mhz/full/`
- `reports/proteus_xc7vx485t_150mhz/ntt_only/`
- `reports/proteus_xc7vx485t_150mhz/dualctx/`
- `reports/proteus_xc7vx485t_150mhz/sim/`
