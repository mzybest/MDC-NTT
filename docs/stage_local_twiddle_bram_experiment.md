# Stage-Local Twiddle Compression and Early-Stage BRAM Experiment

## 1. Scope and baseline

This controlled experiment changes only the GS-MDC twiddle storage structure.
The arithmetic, explicit Pre/Post negacyclic flow, WL Montgomery pipeline,
MDC reorder network, interfaces, clock constraint, and transform schedule are
unchanged.

- Source branch: `experiment/impl_directive_sweep_100mhz`
- Source commit: `00574a2a8f99d9bf468807f83bf85ad46d4876ce`
- Experiment branch: `feature/stage_local_twiddle_bram`
- RTL baseline commit: `89460f5` (Stage D full-WL)
- Top/device: `poly_mul_top`, `xc7a200tsbg484-1`
- Vivado/clock: 2022.2, 10.000 ns / 100 MHz
- Comparison implementation flow: e06 (`Explore`,
  `AltSpreadLogic_medium`, `AggressiveFanoutOpt`,
  `MoreGlobalIterations`)

The e06 routed baseline was 77,111 LUT, 37,258 registers, 400 DSP,
10 BRAM, 2.427 W, WNS +0.384 ns, and WHS +0.020 ns.

## 2. Architecture change

The legacy `twiddle_rom` holds two full stage-major tables of 24,576 words
each. Every `mdc_stage` instantiates the same asynchronous structure and Vivado
constant-prunes the unused stage ranges. Twiddle storage consumes LUT logic,
not the reported `LUT as Memory` resource.

`scripts/gen_twiddle_stage_local.py` extracts only the unique twiddles used by
each stage and checks every generated value against both the legacy `.mem`
files and `scripts/gen_twiddle.py`. NTT words are followed by INTT words in
each local file.

| Stage | Unique words/mode | Combined words | Implementation |
|---:|---:|---:|---|
| 0 | 2048 | 4096 | synchronous BRAM, 8 RAMB36 |
| 1 | 1024 | 2048 | synchronous BRAM, 4 RAMB36 |
| 2 | 512 | 1024 | synchronous BRAM, 2 RAMB36 |
| 3 | 256 | 512 | synchronous BRAM, 1 RAMB36 |
| 4 | 128 | 256 | stage-local distributed ROM |
| 5 | 64 | 128 | stage-local distributed ROM |
| 6 | 32 | 64 | stage-local distributed ROM |
| 7 | 16 | 32 | stage-local distributed ROM |
| 8 | 8 | 16 | stage-local distributed ROM |
| 9 | 4 | 8 | stage-local distributed ROM |
| 10 | 2 | 4 | stage-local distributed ROM |
| 11 | 1 | 2 | constant `R_MOD_Q` |

The table image shrinks from 49,152 to 8,190 64-bit words, a 6.001x
compression (83.34% fewer stored words).

### Zero-visible-latency prefetch

A naive synchronous ROM would add one cycle to every early stage. Instead,
`mdc_stage` presents the next accepted butterfly index to the BRAM on the
current edge. The registered BRAM output is therefore ready for the next input
sample. If `in_valid` is low, the current index remains prefetched. The
butterfly latency and global `MUL_LAT=14` are unchanged.

The full top can assert INTT `start` with the first INTT input. On that edge,
the first twiddle is the common Montgomery one, but the BRAM must already
prefetch INTT sample 1. `gs_mdc_core` therefore drives the stages with
`start ? mode : active_mode`. This fixes the mode boundary without adding a
cycle or changing any table entry.

The old path remains selectable with `USE_STAGE_LOCAL_TWIDDLE=0`; the new path
uses `USE_STAGE_LOCAL_TWIDDLE=1` and `TWIDDLE_BRAM_STAGES=4`.

## 3. Functional verification

| Test | Result | Notes |
|---|---|---|
| Python legacy/formula/table comparison | PASS | all 8,190 local words checked |
| `tb_twiddle_rom_stage` | PASS | full Stage0/3/4 NTT and INTT table reads |
| `tb_twiddle_prefetch_equiv` | PASS | legacy vs local Stage0, random bubbles, NTT and INTT |
| `tb_mont_mul_wl` | PASS | WL latency remains 14 |
| `tb_delay_memory` | PASS | depths 1, 2, 8, 64, 1024 |
| `tb_gs_butterfly` | PASS | 32 vectors |
| `tb_gs_mdc_core` | PASS | forward NTT |
| `tb_gs_mdc_core_roundtrip` | PASS | NTT/INTT roundtrip |
| `tb_poly_mul_top` local ROM | PASS | random and directed negacyclic |
| `tb_poly_mul_top` legacy ROM | PASS | parameter fallback, same golden |
| `tb_poly_mul_top_phase_cycles` | PASS | result and cycle counters |

The first full-top attempt exposed 2,048 odd-address mismatches because the
synchronous ROM prefetched INTT sample 1 with the previous transform mode.
The `start ? mode : active_mode` boundary fix removed all mismatches. No golden
data or arithmetic behavior was changed.

| Phase | Baseline cycles | Experiment cycles | Change |
|---|---:|---:|---:|
| A_NTT | 4303 | 4303 | 0 |
| B_NTT | 4303 | 4303 | 0 |
| INTT | 4289 | 4289 | 0 |
| Full polynomial multiply | 12925 | 12925 | 0 |
| Core first input to first output | 2241 | 2241 | 0 |

At 100 MHz, the full multiplication latency remains 129.25 us.

## 4. Synthesis results

| Metric | Stage D full-WL | Stage-local BRAM | Change |
|---|---:|---:|---:|
| Slice LUT | 77,613 | 68,874 | -8,739 (-11.26%) |
| LUT Memory | 27,823 | 27,823 | 0 |
| Registers | 36,165 | 35,720 | -445 (-1.23%) |
| DSP48E1 | 400 | 400 | 0 |
| BRAM | 10 | 25 | +15 |
| WNS | +1.282 ns | +1.282 ns | 0 |
| TNS | 0.000 ns | 0.000 ns | 0 |
| Estimated power | 2.147 W | 2.066 W | -0.081 W (-3.77%) |

The RAM report confirms exact early-stage inference:

- Stage0: 4096x64, 8 RAMB36
- Stage1: 2048x64, 4 RAMB36
- Stage2: 1024x64, 2 RAMB36
- Stage3: 512x64, 1 RAMB36

The corresponding routed twiddle hierarchy uses only 34 LUTs across Stage0-3
(10 + 9 + 8 + 7), compared with 7,200 LUTs for the four legacy twiddle ROM
instances (3,840 + 1,920 + 960 + 480).

## 5. Post-route e06 comparison

| Metric | e06 baseline | Stage-local BRAM e06 | Change |
|---|---:|---:|---:|
| Slice LUT | 77,111 | 68,415 | -8,696 (-11.28%) |
| LUT Memory | 27,823 | 27,823 | 0 |
| Registers | 37,258 | 36,370 | -888 (-2.38%) |
| DSP48E1 | 400 | 400 | 0 |
| BRAM | 10 | 25 | +15 |
| Setup WNS | +0.384 ns | +0.151 ns | -0.233 ns |
| Setup TNS | 0.000 ns | 0.000 ns | 0 |
| Hold WHS | +0.020 ns | +0.008 ns | -0.012 ns |
| Hold THS | 0.000 ns | 0.000 ns | 0 |
| Estimated power | 2.427 W | 2.298 W | -0.129 W (-5.32%) |
| Routing errors | 0 | 0 | 0 |

Both setup and hold pass at 100 MHz. Power values are vectorless Vivado
estimates and should be treated as relative estimates, not measured board
power.

The baseline worst path was a Stage3 flush-control route into reorder BRAM:

`Stage3 flushing_reg -> fifo_a_delay BRAM input`

It had 9.201 ns data delay, of which 93.74% was routing. The experiment worst
path moves to the final GS butterfly:

`Stage11 a_r -> mod_sub/carry -> mont_mul_wl intmul p02_s1`

The new path has 9.343 ns data delay: 4.724 ns logic and 4.619 ns routing
(49.44% routing). The twiddle ROM is not on the new worst path.

## 6. Conclusion

The experiment is functionally successful and keeps exactly the same
100 MHz throughput and cycle counts. It provides a substantial area and
estimated-power improvement: 11.28% fewer routed LUTs and 5.32% lower
vectorless power, while DSP usage remains 400.

It does not improve timing margin. WNS remains positive but falls from
+0.384 ns to +0.151 ns, so this result should be presented as a
memory-architecture and resource-efficiency optimization, not as a frequency
optimization. The original e06 checkpoint remains the higher-margin variant;
this branch is the lower-LUT/lower-power variant.

Reports are isolated under `reports/twiddle_bram_experiment/`. The routed
checkpoint is `reports/twiddle_bram_experiment/impl_e06/routed.dcp` and is
ignored by Git. Final regression SHA256 records report `RTL_HASH_MATCH=YES`.
