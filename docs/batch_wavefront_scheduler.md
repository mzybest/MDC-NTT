# Multi-Job Frame-Level Wavefront Scheduler

## Status

This document freezes the first RTL experiment for dependency-aware batch
scheduling on the shared two-path GS-MDC core.

- Experiment branch: `feature/batch_wavefront_scheduler`
- Parent checkpoint: `8f21a55`
- Frozen parent feature: mode-tagged dual-context wavefront core
- Device: `xc7a200tsbg484-1`
- Vivado: 2022.2
- Clock target: 10.000 ns / 100 MHz
- Arithmetic path: full WL Montgomery, `MUL_LAT=14`, II=1
- Algorithm: explicit Pre/Post negacyclic NTT, unchanged
- Transform core: one shared radix-2, two-path GS-MDC NTT/INTT core

The existing single-job top and all old Montgomery-selectable paths remain
available. This experiment adds an isolated batch top and does not replace the
frozen baseline.

## Motivation

A product requires three transform frames on the shared core:

1. `A_NTT`
2. `B_NTT`
3. `C_INTT`

Each frame presents `N/2 = 2048` valid pairs. The theoretical compute-throughput
lower bound of one product is therefore:

```text
3 * N/2 = 6144 cycles/product
```

The single-job wavefront top completes one product in 10669 cycles. Its core
must wait while the same job's pointwise results become ready and while the job
finishes before its storage is reused. The optimization in this experiment is
to fill those dependency gaps with complete transform frames from other jobs.
It does not shorten a butterfly, Montgomery multiply, or transform frame.

## Architecture

### Frame scheduler

`batch_frame_scheduler` schedules only complete 2048-pair frames. It does not
arbitrate individual pairs and does not add dynamic pair-level backpressure.
Once a frame starts, its valid stream is continuous through EOF.

The ready-frame priority is:

```text
ready C_INTT > ready B_NTT > new A_NTT
```

A bank moves through these states:

```text
FREE -> A_READY -> B_READY -> WAIT_C_READY
     -> C_READY -> C_RUNNING -> FREE/reassigned
```

The bank is not reused until the final Post_INTT result for that job has been
written. This prevents A_NTT, C_NTT, and result storage from being overwritten
by a later job.

### Frame tag

Every core frame carries:

```text
{job_id, bank_id, transform_role, context_select}
```

`context_select` remains the least-significant bit because the existing
dual-context reorder stages use that bit directly. `transform_role` identifies
`A_NTT`, `B_NTT`, or `C_INTT`. The tags pass through the existing mode-tagged
core with the data.

### Bank-aware storage

`batch_sdp_ram` is a synchronous one-write/one-read BRAM-friendly wrapper. Its
data array is not reset. With six preloaded jobs and three live job contexts,
Vivado maps the storage as follows:

| Storage | Logical organization | RAMB36 |
|---|---:|---:|
| Source A lane 0/1 and B lane 0/1 | 4 x 12288 x 64 | 128 |
| Result lane 0/1 | 2 x 12288 x 64 | 64 |
| A_NTT lane 0/1 | 2 x 6144 x 64 | 32 |
| C_NTT lane 0/1 | 2 x 6144 x 64 | 32 |
| Dual-context GS-MDC core | reorder/twiddle storage | 35 |
| **Total** | | **291** |

The four intermediate A_NTT/C_NTT memories are indexed by
`bank_id * 2048 + pair_index`. Source and result memories are indexed by
`job_id * 2048 + pair_index`. This separates long-lived job identity from the
three physical compute contexts.

### Datapath alignment

A/B frames and C_INTT frames use the same frontend latency before entering the
core:

- one cycle for synchronous BRAM read;
- 14 cycles for Pre_NTT WL Montgomery, or a matching 14-cycle C-data delay.

A_NTT synchronous BRAM reads are aligned with the corresponding B_NTT core
output before Pointwise multiplication. Pointwise data, address, job, bank, and
frame tags use the same 14-cycle delay. Post_INTT data and final bit-reversed
write addresses are also delayed by the selected Montgomery latency.

## Scheduler Model

The Python model tracks frame dependencies, context alternation, bank reuse,
core flush latency, and output collisions. For 60 jobs at N=4096:

| Job buffers | Steady product II | Steady core utilization | Finite-batch idle | Output collisions |
|---:|---:|---:|---:|---:|
| 1 | 10654.0 | 57.6685% | 268345 | 0 |
| 2 | 6247.5 | 98.3433% | 6210 | 0 |
| 3 | **6144.0** | **100.0000%** | 207 | 0 |

The model also passes a token-accurate N=16 case. Using the actual scheduler
boundary latency of 4318 cycles instead of the core-bound 4303 cycles preserves
the 6144-cycle steady II; only the finite batch tail changes from 207 to 222
idle cycles.

Three buffers are therefore the minimum tested configuration that reaches the
single-core compute lower bound for this dependency graph.

## Functional Verification

| Check | Result | Key measurement |
|---|---|---|
| Python scheduler model, N=16 | PASS | bank/context/token checks |
| Python scheduler model, N=4096, 60 jobs | PASS | 3-buffer steady II = 6144 |
| `tb_batch_frame_scheduler` | PASS | steady II = 6144, no state/tag failure |
| `tb_poly_mul_top_batch_wavefront` | PASS | five random jobs plus one directed job |
| Directed `x^(N-1) * x` | PASS | result[0] = Q-1 |
| Original dual-context wavefront regression | PASS | frozen path remains functional |

The full RTL testbench checks all 4096 coefficients of all six products against
an independent Python negacyclic golden model.

## Cycle Results

The full batch test preloads six jobs, then measures compute time:

| Metric | Cycles | At 100 MHz |
|---|---:|---:|
| Frozen single-job product latency | 10669 | 106.69 us |
| Six-job batch start-to-done | 39360 | 393.60 us |
| Six-job finite average | 6560/job | 65.60 us/job |
| Batch steady product initiation interval | **6144** | **61.44 us/product** |
| Theoretical one-core lower bound | 6144 | 61.44 us/product |

Relative to issuing independent single-job operations, the steady compute
throughput improves by:

```text
10669 / 6144 = 1.7365x  (about +73.65%)
```

This is a throughput result, not a claim that single-product latency became
6144 cycles. Startup and drain remain visible for a finite batch.

The measured B_NTT pipeline for every job is:

- first core output: 2241 cycles after first B core input;
- last core output: 4288 cycles after first B core input;
- final pointwise write: 4303 cycles after first B core input;
- scheduler-visible C readiness: frontend/control aligned at 4318 cycles.

The six-job RTL run observes 224 finite-batch idle core-input cycles. The
scheduler-only RTL has 209 idle cycles versus 207 in the idealized model; the
two-cycle difference comes from registered completion and frame-descriptor
handoff.

## Input Bandwidth Limit

The existing load interface accepts one coefficient per cycle. Loading A and B
for one job therefore requires:

```text
2 * N = 8192 cycles/job
```

Consequently, continuous live loading would cap system-level product II at 8192
cycles even though the compute engine sustains 6144 cycles. This first RTL
version intentionally preloads six jobs to isolate compute throughput.

A later dual A/B load interface could reduce loading to 4096 cycles/job, below
the 6144-cycle compute bound. That interface is not part of this experiment and
no 6144-cycle end-to-end I/O claim is made here.

## Synthesis and Implementation

### Batch top results

| Metric | 100 MHz synthesis | 100 MHz post-route |
|---|---:|---:|
| Slice LUT | 41555 | 40815 |
| LUT Memory | 2753 | 2753 |
| Registers | 38637 | 38789 |
| DSP48E1 | 400 | 400 |
| BRAM36 | 291 | 291 |
| WNS | +1.282 ns | **+0.283 ns** |
| TNS | 0.000 ns | 0.000 ns |
| WHS | +0.070 ns | **+0.023 ns** |
| THS | 0.000 ns | 0.000 ns |
| Estimated power | 2.159 W | 2.219 W |

The implementation has zero unrouted nets, zero partially routed nets, and zero
routing errors. Setup and hold both pass at 100 MHz.

### Comparison with frozen single-job wavefront top

| Metric | Single-job wavefront post-route | Batch wavefront post-route | Change |
|---|---:|---:|---:|
| Slice LUT | 73645 | 40815 | -32830 |
| LUT Memory | 30046 | 2753 | -27293 |
| Registers | 38492 | 38789 | +297 |
| DSP48E1 | 400 | 400 | 0 |
| BRAM36 | 35 | 291 | +256 |
| WNS | +0.317 ns | +0.283 ns | -0.034 ns |
| WHS | +0.012 ns | +0.023 ns | +0.011 ns |
| Estimated power | 2.454 W | 2.219 W | -0.235 W |
| Product metric | latency 10669 | steady II 6144 | 1.7365x throughput |

The large LUT Memory reduction is intentional: job/intermediate arrays moved
from LUTRAM-style storage into explicit synchronous BRAM-friendly banks. The
cost is high BRAM use, 291/365 tiles (79.73%). Vectorless power estimates for
different tops should be treated as directional rather than workload-accurate.

### Critical path

The post-route worst setup path is:

```text
u_core/g_stage[5].u_stage/u_butterfly/b_r_reg[1]
  -> 24 CARRY4 modular subtraction chain
  -> u_mul/g_wl.u_mul/u_intmul/p22_s1_reg/B[14]
```

- slack: +0.283 ns;
- data path: 9.299 ns;
- logic delay: 4.543 ns (48.853%);
- route delay: 4.756 ns (51.147%);
- levels: 27 (`24 CARRY4 + LUT3 + 2 LUT4`).

All ten reported worst setup endpoints are in the same Stage5
`butterfly b_r -> mod_sub -> WL partial-product register` path family. The
scheduler, frame-tag logic, and BRAM address generation do not become critical.
The path class is unchanged from the frozen wavefront baseline, although the
worst endpoint bit and exact routing changed.

The implementation flow is the previously selected legal e06 directive set:

```text
opt_design      Explore
place_design    AltSpreadLogic_medium
phys_opt_design AggressiveFanoutOpt
route_design    MoreGlobalIterations
```

## Conclusion

The boundary-tagged scheduler with three job buffers and two alternating MDC reorder contexts is functionally correct
and reaches the 6144-cycle theoretical compute II of one shared two-path core.
It improves sustained preloaded-batch compute throughput by about 73.65%
without adding DSPs or changing NTT arithmetic. Post-route timing still passes
at 100 MHz.

The tradeoff is explicit and significant: BRAM use rises from 35 to 291 tiles.
The experiment is therefore a valid high-throughput variant, not a universally
better replacement for the low-storage single-job top. For an end-to-end system,
the next controlled experiment should address A/B input bandwidth. Any memory
capacity reduction should preserve the measured 6144-cycle schedule before it
is accepted.

## Reproduction

```bat
scripts\run_batch_wavefront_regression.bat
scripts\run_synth_batch_wavefront.bat xc7a200tsbg484-1 10.0
scripts\run_impl_batch_wavefront_e06.bat
```

Primary reports are under:

```text
reports/batch_wavefront_scheduler/synth/
reports/batch_wavefront_scheduler/impl_e06/
```