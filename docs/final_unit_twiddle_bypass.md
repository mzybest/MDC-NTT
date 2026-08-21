# Final-Stage Unit-Twiddle Bypass

## Scope

This experiment starts from commit be2e973 on branch
codex/final_unit_twiddle_bypass. The frozen 580-DSP Virtex-7 checkpoint remains
unchanged under reports/dual_forward_dsp_reduction/virtex7_v2026_1.

The experiment changes only the final GS stage implementation. It does not
change N, q, radix, the MDC reorder network, MUL_LAT, II, the explicit
negacyclic flow, or the 6.667 ns clock constraint.

## Mathematical basis

For both transform engines, the only Stage11 twiddle is the Montgomery identity:

- params_pkg::R_MOD_Q = 64'h000000000003fff0
- mem/twiddle_stage11.mem contains R_MOD_Q for NTT and INTT
- mem/twiddle_ntt_stage11.mem contains R_MOD_Q

Therefore MontgomeryMul(diff, R_MOD_Q) equals diff. The final-stage
twiddle multiplication can be replaced by an equal-latency data delay without
changing the mathematical result.

## RTL implementation

The new controls default to zero, so the previous multiplier path remains
selectable:

- gs_butterfly.BYPASS_TWIDDLE_MUL
- mdc_stage.BYPASS_TWIDDLE_MUL
- gs_mdc_core.BYPASS_FINAL_UNIT_TWIDDLE
- gs_mdc_core_ntt_only.BYPASS_FINAL_UNIT_TWIDDLE
- poly_mul_top_dual_forward.USE_FINAL_UNIT_TWIDDLE_BYPASS

Only stage LOGN-1 receives the bypass parameter. In bypass mode, the lower
butterfly result diff uses a delay_line with DEPTH=MUL_LAT instead of
mont_mul_select. Both the boundary-pipelined and direct BFU variants are
covered. MUL_LAT remains 14 and II remains one.

## Functional regression

| Test | Configuration | Result |
|---|---|---|
| tb_mont_mul_wl | Existing WL multiplier | PASS |
| tb_gs_butterfly | Multiplier path | PASS |
| tb_gs_butterfly | Unit-twiddle bypass | PASS |
| tb_gs_mdc_core | Multiplier path | PASS |
| tb_gs_mdc_core | Final-stage bypass | PASS |
| tb_gs_mdc_core_ntt_only | Multiplier path | PASS |
| tb_gs_mdc_core_ntt_only | Final-stage bypass | PASS |
| tb_poly_mul_top_wavefront | Existing wavefront top | PASS |
| tb_poly_mul_top_dual_forward | Baseline/load-pre/fused-post/combined | PASS |
| tb_poly_mul_top_dual_forward | Combined plus final-stage bypass | PASS |

The full bypass configuration passes both the random negacyclic case and the
directed x^(N-1) times x case. Timing behavior is unchanged:

- NTT-only first latency: 2242 cycles
- NTT-only done latency: 4290 cycles
- Full polynomial multiplication: 8623 cycles
- Full multiplication time at 150 MHz: about 57.49 us

## Virtex-7 150 MHz results

Device: xc7vx330tffg1157-1
Tool: Vivado 2026.1
Clock: 6.667 ns

| Metric | 580-DSP baseline | Unit-twiddle bypass | Change |
|---|---:|---:|---:|
| Slice LUT | 78,510 | 76,681 | -1,829 (-2.33%) |
| LUT Memory | 25,304 | 25,302 | -2 |
| Registers | 55,742 | 53,355 | -2,387 (-4.28%) |
| DSP48E1 | 580 | 540 | -40 (-6.90%) |
| BRAM tiles | 50 | 50 | 0 |
| WNS | +0.101 ns | +0.089 ns | -0.012 ns |
| TNS | 0.000 ns | 0.000 ns | 0 |
| WHS | +0.032 ns | +0.023 ns | -0.009 ns |
| THS | 0.000 ns | 0.000 ns | 0 |
| Estimated power | 5.152 W | 4.997 W | -0.155 W (-3.01%) |
| Full-mul cycles | 8623 | 8623 | 0 |

The routed hierarchy reports 220 DSP48E1 in CoreA and 220 DSP48E1 in CoreB.
The remaining 100 DSP48E1 are the load-time Pre_NTT multiplier, two Pointwise
multipliers, and two fused Post_INTT multipliers.

Synthesis completed in 2323 seconds. Implementation completed in 6452 seconds.
All 124,761 routable nets are fully routed and the route report contains zero
routing errors.

## Worst-path comparison

The old worst setup path was a load-metadata delay register to a b_bank1
LUTRAM write address. The new worst path is:

u_mul_addr_delay/g_delay.data_pipe_reg[13][5]_rep__3/C
to
c_ntt_odd_reg_1024_1087_60_62/RAMA/WADR5

Its data-path delay is 6.071 ns: 0.269 ns logic and 5.802 ns routing. Routing
accounts for 95.57 percent of the data-path delay. The path is in Pointwise
result-address distribution to C_NTT LUTRAM, not in the bypassed Stage11 BFU.

The fifth reported setup path is a load-time preprocess multiplier output to
an a_bank1 LUTRAM data input. No top-five setup path passes through the removed
final-stage Montgomery multipliers.

## Reports and scripts

- scripts/run_dual_forward_dsp_reduction_regression.bat
- scripts/run_synth_dual_forward_dsp_reduction.tcl
- scripts/run_virtex7_final_unit_twiddle_bypass_150mhz.bat
- reports/dual_forward_dsp_reduction/final_unit_twiddle_bypass/virtex7_v2026_1/synth_150mhz
- reports/dual_forward_dsp_reduction/final_unit_twiddle_bypass/virtex7_v2026_1/impl_150mhz

## Conclusion

The controlled bypass is functionally equivalent and reaches the intended
540-DSP result without adding cycles. It also reduces LUT, register, and power
estimates. The 150 MHz routed design passes setup and hold timing, although its
WNS is 0.012 ns below the placement-specific 580-DSP baseline result. The
optimization should be kept as the DSP-oriented variant; it is not evidence of
a timing improvement.

The current limiter is high-fanout routing from Pointwise address delay logic
to distributed C_NTT memory. Any next timing experiment should target the
C_NTT bank/address distribution or BRAM-friendly storage, not the final-stage
butterfly or Montgomery arithmetic.
