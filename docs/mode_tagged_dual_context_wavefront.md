# Mode-Tagged Dual-Context Wavefront GS-MDC Experiment

## 1. Scope and checkpoint

This experiment starts from commit `d41e463` on the frozen
`feature/stage_local_twiddle_bram` checkpoint. Development is isolated on
`feature/mode_tagged_dualctx_wavefront`.

The validated single-context modules remain unchanged:

- `rtl/mdc_stage.sv`
- `rtl/gs_mdc_core.sv`
- `rtl/poly_mul_top.sv`

The experiment adds parallel modules with `_dualctx` or `_wavefront` suffixes.
It keeps the radix-2 GS butterfly, full-WL Montgomery arithmetic, explicit
Pre/Post negacyclic factors, stage-local twiddle tables, and the existing
external bit-reversal convention.

## 2. Motivation

In the original stage, a transform owns one post-BFU C2 reorder state. After
the last BFU result arrives, that state must continue shifting for `DEPTH`
cycles to drain delayed V data. A second frame cannot reuse the same counters
and delay memories during this drain. At full-top level this contributes to
serial A_NTT then B_NTT execution.

The new architecture changes frame scheduling, not the NTT algorithm. Each
stage keeps one shared BFU and one shared stage-local twiddle ROM, but has two
independent reorder contexts:

```text
tagged two-lane input
        |
 shared GS BFU + twiddle ROM
        |
  frame_id[0] demultiplex
      /             \
 C2 context 0    C2 context 1
      \             /
       collision-free mux
        |
 tagged two-lane output
```

While context 0 drains frame A, context 1 can accept frame B's BFU results.
The contexts alternate by `frame_id[0]`. Each context owns its two delay
memories, reorder counter, flush counter, flushing state, mode, and frame ID.
The BFU, Montgomery multiplier, and twiddle ROM are not duplicated.

## 3. Mode and frame tagging

Every accepted pair carries `{mode, frame_id}`. `mdc_stage_dualctx` delays this
metadata by the exact BFU latency, `MUL_LAT + 1 = 15`, before selecting a
reorder context. The tag then travels through all 12 stages with the data.

At the final boundary, the delayed mode selects either the NTT bypass delay or
the INTT `N^-1` Montgomery scale result. This removes dependence on a single
global active-mode state when two transform frames occupy different stages.

The interface exposes `in_ready` and `out_ready`, but this first experiment is
a deterministic, stall-free pipeline: `in_ready` is always one and
`out_ready` is not yet used for backpressure. It is not a dynamic elastic
valid/ready network.

## 4. Full polynomial-multiply schedule

`poly_mul_top_wavefront` issues three tagged frames:

| Frame | Mode | Role | Context |
|---:|---|---|---:|
| 0 | NTT | A_NTT | 0 |
| 1 | NTT | B_NTT | 1 |
| 2 | INTT | C_INTT | 0 |

A and B Pre_NTT streams are issued back-to-back with no pair-level bubble.
A_NTT output is stored while B_NTT is still entering the core. B_NTT output is
multiplied immediately by the corresponding stored A_NTT value. Pointwise
results are written to C_NTT storage using the existing delayed-address rule.

C_INTT still starts after the complete pointwise result is available. This is
required by the current external bit-reversal read schedule and is not hidden
by the present experiment. Explicit Pre_NTT `psi^i` and Post_INTT `psi^-i`
paths are retained.

## 5. Verification

The cycle-only model tests both N=16 and N=4096 with four continuous frames
whose modes alternate NTT/INTT. For N=4096, the modeled final-stage frame
starts are `2227, 4275, 6323, 8371`: exactly 2048 cycles apart, with no output
bubbles or context collision.

| Check | Result | Evidence |
|---|---|---|
| N=16 dual-context cycle model | PASS | four alternating frames |
| N=4096 dual-context cycle model | PASS | four alternating frames |
| `tb_gs_mdc_core_dualctx` | PASS | NTT/INTT/NTT/INTT, no frame bubbles |
| `tb_poly_mul_top_wavefront` random | PASS | original negacyclic golden |
| `tb_poly_mul_top_wavefront` directed | PASS | `x^(N-1) * x = Q-1` at index 0 |
| Frozen Stage-local regression | PASS | all nine tests plus legacy twiddle mode |

The RTL core test observed output frame starts at cycles
`2241, 4289, 6337, 8385`, again exactly 2048 cycles apart. For the full-top
test, the measured tagged boundaries were:

| Frame | First input | Last input | First output | Last output | Done |
|---:|---:|---:|---:|---:|---:|
| A_NTT (0) | 8207 | 10254 | 10448 | 12495 | 12496 |
| B_NTT (1) | 10255 | 12302 | 12496 | 14543 | 14544 |
| C_INTT (2) | 14558 | 16605 | 16799 | 18846 | 18847 |

A/B input frames and A/B output frames are both contiguous.

## 6. Cycle improvement

| Metric | Stage-local single context | Dual-context wavefront | Change |
|---|---:|---:|---:|
| Full polynomial multiply | 12,925 cycles | 10,669 cycles | -2,256 (-17.45%) |
| Latency at 100 MHz | 129.25 us | 106.69 us | -22.56 us |
| Relative operation speed | 1.000x | 1.211x | +21.15% |
| Core transform-frame initiation interval | 4,303 cycles | 2,048 cycles | -2,255 (-52.40%) |

The latency of one transform wavefront is not shortened; the gain comes from
overlapping A_NTT and B_NTT in different MDC stages while keeping one shared
arithmetic datapath.

## 7. 100 MHz synthesis

Target: Vivado 2022.2, `xc7a200tsbg484-1`, 10.000 ns.

| Metric | Stage-local single context | Dual-context wavefront | Change |
|---|---:|---:|---:|
| Slice LUT | 68,874 | 74,449 | +5,575 (+8.09%) |
| LUT Memory | 27,823 | 30,047 | +2,224 (+7.99%) |
| Registers | 35,720 | 38,163 | +2,443 (+6.84%) |
| DSP48E1 | 400 | 400 | 0 |
| BRAM | 25 | 35 | +10 |
| WNS | +1.282 ns | +1.282 ns | 0 |
| TNS | 0.000 ns | 0.000 ns | 0 |
| Estimated power | 2.066 W | 2.190 W | +0.124 W (+6.00%) |

The RAM report confirms that both contexts in Stages 0-3 infer RAMB36 storage.
The added contexts therefore do not turn the large 1024/512/256/128 delays
back into registers. The DSP count is unchanged because all BFUs and WL
Montgomery multipliers remain shared.

The synthesis worst path is unchanged in character:

`Stage0 gs_butterfly b_r -> mod_sub (24 CARRY4) -> mont_mul_wl p02_s1`

It has 7.909 ns data-path delay and +1.282 ns slack. The context selector and
frame metadata are not on the worst path.

## 8. Post-route result

The isolated e06 implementation uses `Explore`,
`AltSpreadLogic_medium`, `AggressiveFanoutOpt`, and
`MoreGlobalIterations`.

| Metric | Stage-local e06 | Dual-context wavefront e06 | Change |
|---|---:|---:|---:|
| Slice LUT | 68,415 | 73,645 | +5,230 (+7.64%) |
| LUT Memory | 27,823 | 30,046 | +2,223 (+7.99%) |
| Registers | 36,370 | 38,492 | +2,122 (+5.83%) |
| DSP48E1 | 400 | 400 | 0 |
| BRAM | 25 | 35 | +10 |
| Setup WNS | +0.151 ns | +0.317 ns | +0.166 ns |
| Setup TNS | 0.000 ns | 0.000 ns | 0 |
| Hold WHS | +0.008 ns | +0.012 ns | +0.004 ns |
| Hold THS | 0.000 ns | 0.000 ns | 0 |
| Estimated power | 2.298 W | 2.454 W | +0.156 W (+6.79%) |
| Routing errors | 0 | 0 | 0 |

The 100 MHz implementation passes setup and hold with all 102,186 routable
nets fully routed. Implementation runtime was 2,403 seconds. Power is a
vectorless Vivado estimate and is suitable for relative comparison only.

The routed worst path moves from Stage11 to Stage5 but retains the same
arithmetic structure:

`Stage5 gs_butterfly b_r -> mod_sub (24 CARRY4) -> mont_mul_wl p22_s1`

Its data path is 8.986 ns: 4.512 ns logic and 4.474 ns routing. The new
context memories, context selector, and mode/frame tag do not appear on the
critical path. Despite higher storage density, routed WNS improves by
0.166 ns relative to the Stage-local e06 checkpoint.

## 9. Current conclusion

The experiment proves the functional and physical feasibility of a
mode-tagged, dual-context GS-MDC wavefront at Python-cycle, RTL-core, full
polynomial, synthesis, and routed-implementation levels. It improves full
multiplication latency by 17.45% without adding DSP arithmetic or changing the
mathematical result, and still passes 100 MHz with +0.317 ns setup slack. The
cost is duplicated reorder state: +10 BRAM, moderate LUT/FF overhead, and a
6.79% increase in vectorless post-route power estimate.

The next architectural question is not another multiplier replacement. It is
whether a banked/dual-port implementation can pack the two reorder contexts
more efficiently, or whether the C_NTT bit-reversal boundary can be scheduled
to launch C_INTT earlier. Neither extension is part of this checkpoint.
