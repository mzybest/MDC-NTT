# MDC Flush Gating and SRL Cleanup (B1+B2)

## Scope

This controlled experiment starts from commit `8fa586c` and keeps the
algorithm, transform ordering, Montgomery arithmetic, interfaces, and cycle
schedule unchanged.

- Branch: `codex/mdc-flush-srl-cleanup`
- B1 commit: `e4188c2` (`Remove MDC flush data gating`)
- B2 commit: `b55e654` (`Allow SRL inference in MDC shift delays`)
- Top: `poly_mul_top_dual_forward`
- Device: `xc7vx485tffg1761-2`
- Vivado: 2026.1
- Signoff clock: 6.667 ns (150 MHz)

## RTL Changes

### B1: MDC flush data selection

`rtl/mdc_stage.sv` no longer uses `flushing` to select zero-valued inputs or
to override the output data buses. Flush still asserts `delay_in_valid` and
`out_valid` for the same number of cycles. Data shifted into the delay memories
during flush is intentionally don't-care because it is never observed with a
subsequent valid output.

### B2: reset-free SHIFT data storage

In the small-depth SHIFT implementation of `rtl/delay_memory.sv`, only the
valid pipeline is reset. The data pipeline shifts every clock and is meaningful
only when its parallel valid bit is asserted. This permits Vivado to infer SRL
storage. The circular RAM path for large depths is unchanged.

## Functional Verification

| Test | Result | Relevant observation |
|---|---:|---|
| Full dual-forward DSP-reduction regression | PASS | All unit, core, wavefront, random, and directed negacyclic variants passed |
| `tb_delay_memory` | PASS | DEPTH 1, 2, 8, 64, and 1024 |
| `tb_gs_mdc_core_roundtrip` | PASS | NTT and INTT latency remained 2241 cycles |
| Active full polynomial multiplication | PASS | Start-to-done remained 8623 cycles |

The active `bram_raw_pre_shared` timing windows were unchanged:

- A/B input: cycles 8207 through 10254
- Forward output: cycles 10449 through 12496
- INTT input: cycles 12511 through 14558
- INTT output: cycles 14753 through 16800

## Synthesis Evidence

| Metric | A1/A2 candidate | B1+B2 | Change |
|---|---:|---:|---:|
| Slice LUT | 57,475 | 55,229 | -2,246 |
| LUT Memory | 8,783 | 9,167 | +384 |
| LUT as Shift Register | 3,279 | 3,663 | +384 |
| Registers | 49,087 | 47,273 | -1,814 |
| DSP48E1 | 520 | 520 | 0 |
| BRAM | 59 | 59 | 0 |

The exact +384 shift-register LUT change at synthesis confirms that the B2
data pipelines are being mapped into SRL resources instead of resettable FF
chains. Physical optimization later combines and removes additional logic, so
post-route LUT Memory is lower than the synthesis count.

## Post-route Signoff

| Metric | Pre-A1 baseline | A1/A2 candidate | B1+B2 |
|---|---:|---:|---:|
| Setup WNS | +0.550 ns | +0.516 ns | **+0.694 ns** |
| Setup TNS | 0.000 ns | 0.000 ns | 0.000 ns |
| Hold WNS | not recorded here | +0.022 ns | +0.018 ns |
| Hold TNS | not recorded here | 0.000 ns | 0.000 ns |
| Slice LUT | 58,287 | 56,557 | **53,820** |
| LUT Memory | 8,783 | 8,783 | **8,591** |
| Registers | 50,521 | 49,369 | **48,157** |
| DSP48E1 | 520 | 520 | 520 |
| BRAM | 59 | 59 | 59 |
| Estimated power | 4.048 W | 3.970 W | 4.085 W |

The power report has low confidence, so the small power difference is not a
signoff-quality regression. The routed design has zero routing errors.

Relative to A1/A2, B1+B2 improves WNS by 0.178 ns, removes 2,737 Slice LUTs,
and removes 1,212 registers. Relative to the pre-A1 baseline, it improves WNS
by 0.144 ns and removes 4,467 Slice LUTs and 2,364 registers.

## Critical Path Result

The former worst path from `u_core_a/g_stage_r_29` into the Core B Stage 5 MDC
data pipeline is absent from the top ten setup paths. The new worst setup path
is:

```text
u_core_a/g_stage_r_12
  -> u_core_b/g_stage_gate__130 (LUT2)
  -> Core B Stage 1 mont_mul_wl valid_pipe_reg[12]
```

- Slack: +0.694 ns
- Data-path delay: 5.696 ns
- Logic: 0.266 ns (4.7%)
- Routing: 5.430 ns (95.3%)
- Fanout on the long net: 22

Thus, the wide `bf_valid -> data` gate removed by B1 is no longer the timing
bottleneck. A `g_stage_gate` LUT2 remains on a valid-control path because
Vivado merges equivalent valid pipelines across Core A and Core B. The next
candidate, if more margin is required, is controlled per-core valid-tree
isolation; it is separate from B1+B2 and was not implemented here.

## Reproducibility

The implementation used an overconstrained 6.400 ns optimization run followed
by a 6.667 ns signoff report. The routed checkpoint is fully routed. SHA256
manifests for all 31 `rtl/*.sv` files before and after Vivado are identical.

Reports are under:

`reports/dual_forward_dsp_reduction/mdc_flush_srl_b1b2/xc7vx485t_150mhz/`

Measured tool runtimes were approximately 27 minutes for the full regression,
3 minutes for supplemental simulation, 53 minutes for synthesis, and 98
minutes for implementation (about 3 hours total tool runtime).
