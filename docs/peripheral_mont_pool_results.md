# Peripheral Montgomery Pool Results

## Scope

This controlled experiment starts from the BRAM A/C scratch checkpoint on
branch `codex/bram_ac_scratch` and is implemented on the isolated branch
`codex/peripheral-mont-pool`. It keeps the following behavior unchanged:

- explicit Pre/Post negacyclic processing;
- two concurrent forward GS-MDC cores and one reused inverse core;
- radix-2, two-path, II=1 transform datapaths;
- 14-cycle WL Montgomery arithmetic;
- Stage11 unit-twiddle bypass and fused inverse scale/Post factor;
- synchronous BRAM A/B and reusable A/C banks;
- MDC reorder logic, point ordering, interfaces, and testbench golden data.

The only arithmetic-structure change is controlled by
`USE_SHARED_PERIPH_MONT`. A value of zero keeps the original four Pre_NTT,
two Pointwise, and two Post_INTT Montgomery instance paths. A value of one
replaces those eight instances with a four-lane shared pool.

## Pool Schedule

The top-level phases are mutually exclusive in the current single-job
schedule:

| Phase | Pool lanes in use | Operation |
|---|---:|---|
| Pre_NTT | 4 | `A0*psi0`, `A1*psi1`, `B0*psi0`, `B1*psi1` |
| Pointwise | 2 | `A_NTT0*B_NTT0`, `A_NTT1*B_NTT1` |
| Post_INTT | 2 | `INTT0*post_factor0`, `INTT1*post_factor1` |

Each lane remains a 14-cycle, II=1 `mont_mul_wl`. A two-bit operation tag is
delayed by the same 14 cycles and selects the Pre, Pointwise, or Post output
interface. Existing Pointwise and Post address delay lines are unchanged.
Simulation assertions reject phase overlap and tag/data latency mismatch.

The active XC7VX485T configuration is:

```text
MUL_LAT=14
USE_WL_CORE=1
USE_WL_PRE_NTT=1
USE_WL_POINTWISE=1
USE_WL_POST_INTT=1
USE_SHARED_PERIPH_MONT=1
FUSE_INTT_SCALE_IN_POST=1
USE_FINAL_UNIT_TWIDDLE_BYPASS=1
USE_TOP_DATA_BRAM=1
USE_LOAD_PREPROCESS=0
```

## Functional Verification

The complete Questa regression finished in 1657 seconds.

| Test/configuration | Result | Cycles |
|---|---:|---:|
| `tb_top_data_bram` | PASS | N/A |
| `tb_mont_mul_wl` | PASS | latency 14 |
| `tb_gs_butterfly` | PASS | N/A |
| `tb_gs_mdc_core` | PASS | core behavior unchanged |
| `tb_gs_mdc_core_ntt_only` | PASS | done 4290 |
| Legacy dual-forward parameter configurations | PASS | 8623 |
| BRAM raw Pre, shared pool, random negacyclic | PASS | 8623 |
| BRAM raw Pre, shared pool, directed `x^(N-1)*x` | PASS | 8623 |

The active shared-pool phase windows exactly match the 600-DSP baseline:

```text
start-to-done               8623 cycles
A/B forward input          8207..10254
A/B forward output        10449..12496
C INTT input              12511..14558
C INTT output             14753..16800
```

## Synthesis

Device: `xc7vx485tffg1761-2`
Tool: Vivado 2026.1
Clock constraint: 6.667 ns

| Metric | Shared pool synthesis |
|---|---:|
| Slice LUT | 59,204 |
| LUT Memory | 8,783 |
| Registers | 50,202 |
| DSP48E1 | 520 |
| BRAM tiles | 59 |
| WNS | +2.041 ns |
| Estimated power | 4.006 W |

The hierarchy report contains one `peripheral_mont_pool` with four Montgomery
children. Each child uses 20 DSP48E1 blocks, for 80 DSP48E1 blocks in the
pool. The removed direct Pre, Pointwise, and Post generate branches are absent
from the active netlist.

## XC7VX485T 150 MHz Post-Route Comparison

Both columns use Vivado 2026.1, `xc7vx485tffg1761-2`, 6.400 ns implementation
overconstraint restored to 6.667 ns for signoff, and the same
Explore/AltSpreadLogic/Aggressive physical-optimization flow.

| Metric | 600-DSP BRAM baseline | Shared pool | Change |
|---|---:|---:|---:|
| Slice LUT | 61,576 | 58,287 | -3,289 (-5.34%) |
| LUT Memory | 8,783 | 8,783 | 0 |
| Registers | 56,024 | 50,521 | -5,503 (-9.82%) |
| DSP48E1 | 600 | 520 | -80 (-13.33%) |
| BRAM tiles | 59 | 59 | 0 |
| Setup WNS | +0.736 ns | +0.550 ns | -0.186 ns |
| Setup TNS | 0.000 ns | 0.000 ns | unchanged |
| Hold WHS | +0.040 ns | +0.037 ns | -0.003 ns |
| Hold THS | 0.000 ns | 0.000 ns | unchanged |
| Estimated power | 4.571 W | 4.048 W | -0.523 W (-11.44%) |
| Full multiplication | 8623 cycles | 8623 cycles | unchanged |
| Compute latency at 150 MHz | 57.49 us | 57.49 us | unchanged |

The routed design has zero routing errors. The implementation runtime was
5967 seconds.

## Critical Path

The shared pool is not present in any of the reported top ten setup paths.
The worst path is:

```text
Core A stage-valid register u_core_a/g_stage_r_1
  -> one LUT2 stage gate
  -> Core A Stage10 mont_mul_wl round0 t_high_s1 register
```

Its signoff slack is `+0.550 ns`. The data path is 6.488 ns, consisting of
0.266 ns logic and 6.222 ns routing, so routing accounts for 95.90 percent.
The remaining top paths are predominantly the same stage-valid routes into
Core B Stage8 delay-memory storage. The bottleneck therefore remains
inter-stage control placement/routing rather than the new input muxes or
Montgomery arithmetic.

## Conclusion

The four-lane phase-shared Montgomery pool is functionally and physically
validated. It reduces DSP48E1 use from 600 to 520 without changing the
8623-cycle complete polynomial multiplication schedule, and it also lowers
routed LUT, register, and vectorless power estimates. The 150 MHz routed
design passes setup and hold with useful margin. This configuration is the
recommended resource-balanced full-polynomial-multiplier result for the
XC7VX485T paper comparison.

Further DSP reduction through load-time preprocessing would change the input
loading/accounting boundary and should be presented as a separate
area-oriented mode, not silently substituted for this raw-BRAM-input result.

## Files and Reports

- `rtl/peripheral_mont_pool.sv`
- `rtl/poly_mul_top_dual_forward.sv`
- `sim/tb_poly_mul_top_dual_forward.sv`
- `scripts/run_dual_forward_dsp_reduction_regression.bat`
- `scripts/run_synth_dual_forward_dsp_reduction.tcl`
- `scripts/run_xc7vx485t_peripheral_mont_pool_150mhz.bat`
- `reports/dual_forward_dsp_reduction/peripheral_mont_pool/xc7vx485t_150mhz/`
