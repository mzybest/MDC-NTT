# QW64 Dual-Forward Core Control Localization

## 1. Experiment scope

This experiment starts from `codex/natural-ab-dual-loader` commit `b11a819`
and runs on the isolated branch `codex/q64-core-control-localization`.

The pre-experiment routed timing report showed that Vivado had merged equivalent
valid/control pipelines across the two transform engines. The worst paths then
crossed from `u_core_a` into `u_core_b`, with more than 94% of the data-path
delay caused by routing.

The only RTL change is an instance-level synthesis boundary:

```systemverilog
(* keep_hierarchy = "yes" *) gs_mdc_core u_core_a (...);
(* keep_hierarchy = "yes" *) gs_mdc_core_ntt_only u_core_b (...);
```

No arithmetic, algorithm, interface, latency, valid/flush behavior, memory
mapping, twiddle schedule, or Montgomery implementation was changed.

## 2. Configuration

| Item | Value |
|---|---:|
| Top | `poly_mul_top_dual_forward` |
| Device | `xc7vx485tffg1761-2` |
| Vivado | 2026.1 |
| Signoff period | 6.667 ns (150 MHz) |
| Implementation period | 6.400 ns |
| `MUL_LAT` | 14 |
| `USE_WL_CORE` | 1 |
| `USE_WL_PRE_NTT` | 1 |
| `USE_WL_POINTWISE` | 1 |
| `USE_WL_POST_INTT` | 1 |
| `USE_BFU_BOUNDARY_PIPE` | 1 |
| `USE_STAGE_LOCAL_TWIDDLE` | 1 |
| `TWIDDLE_BRAM_STAGES` | 4 |
| `FUSE_INTT_SCALE_IN_POST` | 1 |
| `USE_FINAL_UNIT_TWIDDLE_BYPASS` | 1 |
| `USE_TOP_DATA_BRAM` | 1 |
| `USE_SHARED_PERIPH_MONT` | 1 |
| `USE_NATURAL_AB_LOADER` | 1 |

Implementation directives match the natural-loader baseline: `Explore` opt,
`AltSpreadLogic_medium` place, `AggressiveFanoutOpt` plus
`AggressiveExplore` pre-route physical optimization,
`MoreGlobalIterations -tns_cleanup` route, and post-route `Explore`.

## 3. Functional regression

| Test | Result | Observed latency/cycles |
|---|---|---:|
| `tb_top_data_bram` | PASS | BRAM interface test |
| `tb_mont_mul_wl` | PASS | old 12, WL 14 cycles |
| `tb_gs_butterfly` | PASS | 32 vectors |
| `tb_gs_mdc_core` | PASS | unchanged |
| `tb_gs_mdc_core_ntt_only` | PASS | first output 2242, done 4290 cycles |
| `tb_poly_mul_top_wavefront` | PASS | 10669 compute cycles |
| `tb_poly_mul_top_dual_forward` | PASS | 8623 compute cycles |
| `tb_poly_mul_top_dual_forward_natural_ab` continuous | PASS | load 4096, compute 8623, end-to-end 12719 cycles |
| Natural A/B random input bubbles | PASS | 4096 accepted pairs; address advances only on fire |
| Directed `x^(N-1) * x` | PASS | `result[0] = Q-1` |
| N=16 mapping model | PASS | `N16_MAPPING_CHECK=PASS` |

The synthesis attributes therefore do not change the functional or cycle-level
behavior. The 8623-cycle compute latency and 4096-coefficient output count are
unchanged.

## 4. Synthesis comparison

| Metric | Natural-loader baseline | Core-localized | Delta |
|---|---:|---:|---:|
| Slice LUT | 55241 | 55287 | +46 |
| LUT Memory | 9167 | 9167 | 0 |
| Registers | 47288 | 47342 | +54 |
| DSP48E1 | 520 | 520 | 0 |
| BRAM36 tile | 59 | 59 | 0 |
| WNS at 6.667 ns | +1.788 ns | +1.788 ns | 0.000 ns |

The synthesis resource difference is negligible and the arithmetic/memory
structure is preserved.

## 5. Post-route comparison

| Metric | Natural-loader baseline | Core-localized | Delta |
|---|---:|---:|---:|
| Slice LUT | 53841 | 53866 | +25 |
| LUT Memory | 8573 | 8591 | +18 |
| Registers | 47716 | 47998 | +282 |
| DSP48E1 | 520 | 520 | 0 |
| BRAM36 tile | 59 | 59 | 0 |
| Setup WNS | +0.478 ns | **+0.705 ns** | **+0.227 ns** |
| Setup TNS | 0.000 ns | 0.000 ns | 0.000 ns |
| Hold WHS | +0.043 ns | +0.035 ns | -0.008 ns |
| Hold THS | 0.000 ns | 0.000 ns | 0.000 ns |
| Estimated power | 4.044 W | 4.044 W | 0.000 W |
| Compute latency | 8623 cycles | 8623 cycles | 0 |

Power is vectorless and has a `Low` confidence level, so it is suitable only
for relative comparison. Route status reports 104338 fully routed nets and
zero nets with routing errors.

A rough slack-derived frequency estimate changes from about 161.6 MHz to
167.7 MHz. This is not a measured Fmax sweep; the verified routed operating
point remains 150 MHz.

## 6. Critical-path transfer

Baseline worst path:

```text
u_core_a/g_stage_r_11_rep__4
  -> u_core_b Stage1 sum-delay data register
slack = +0.478 ns
data delay = 5.992 ns
route delay = 5.726 ns (95.561%)
```

Core-localized worst path:

```text
u_core_b/g_stage_r_40
  -> u_core_b Stage2 mont_mul_wl valid_pipe_reg[12]
slack = +0.705 ns
data delay = 5.729 ns
logic delay = 0.266 ns
route delay = 5.463 ns (95.357%)
fanout = 11
logic levels = 1 (LUT2)
```

The top ten setup paths contain zero direct `u_core_a` to `u_core_b` (or the
reverse) crossings. The experiment therefore removes the unintended cross-core
control merge that dominated the baseline.

The `g_stage_gate` LUT still exists on the new worst path. Hierarchy isolation
localizes the control tree but does not eliminate the remaining per-core valid
gate. Any later optimization should treat that as a separate experiment rather
than attributing it to this checkpoint.

## 7. Integrity and decision

The SHA256 list for all 34 `rtl/*.sv` files was recorded before synthesis and
again after implementation. The two lists are identical; Vivado did not modify
the RTL. The intentional top-level attribute change is the only RTL difference
from commit `b11a819`.

This experiment is accepted as the next QW64 checkpoint because it:

- improves routed WNS by 0.227 ns;
- removes all direct cross-CoreA/CoreB paths from the top ten;
- leaves DSP, BRAM, compute latency, and functional behavior unchanged;
- costs only 25 routed LUTs and 282 routed registers.

Reports are under:

```text
reports/dual_forward_dsp_reduction/q64_core_control_localization/
```
