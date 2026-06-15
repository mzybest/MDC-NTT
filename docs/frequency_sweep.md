# Synthesis Frequency Sweep

## Configuration

- Baseline: `optimized_baseline_bfu_inputreg_constq`
- Tool: Vivado 2022.2
- Top: `poly_mul_top`
- Device: `xc7a200tsbg484-1`
- Command form: `scripts/run_synth.bat xc7a200tsbg484-1 <period_ns>`
- Evaluation stage: post-synthesis timing, before implementation

No RTL was modified during the sweep. SHA256 hashes of every `rtl/*.sv` file
were recorded before and after the six runs and matched exactly.

## Results

| Target period | Target frequency | WNS | Timing | Worst path |
|---:|---:|---:|---|---|
| 12.5 ns | 80.0 MHz | +0.764 ns | PASS | Stage0 `mont_mul`: `t_s0 -> m_s1` (`t_low * QINV`) |
| 12.0 ns | 83.3 MHz | +0.264 ns | PASS | Stage0 `mont_mul`: `t_s0 -> m_s1` (`t_low * QINV`) |
| 11.5 ns | 87.0 MHz | -0.236 ns | FAIL | Stage0 `mont_mul`: `t_s0 -> m_s1` (`t_low * QINV`) |
| 11.0 ns | 90.9 MHz | -0.736 ns | FAIL | Stage0 `mont_mul`: `t_s0 -> m_s1` (`t_low * QINV`) |
| 10.5 ns | 95.2 MHz | -1.236 ns | FAIL | Stage0 `mont_mul`: `t_s0 -> m_s1` (`t_low * QINV`) |
| 10.0 ns | 100.0 MHz | -1.736 ns | FAIL | Stage0 `mont_mul`: `t_s0 -> m_s1` (`t_low * QINV`) |

All six runs report the same worst-path endpoints:

```text
Source:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/t_s0_reg[16]__4/C

Destination:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/m_s1_reg/PCIN[0]
```

The reported data-path delay remains `10.156 ns`, with 4 logic levels:

```text
1 CARRY4 + 3 DSP48E1
```

## Supported Frequency

The highest tested frequency with non-negative post-synthesis WNS is:

```text
83.3 MHz at a 12.0 ns target period
```

The `87.0 MHz` point is close but does not pass, with WNS `-0.236 ns`.
Consequently, **83.3 MHz is the current synthesis-verified usable frequency**.
This is not yet a post-implementation timing guarantee.

## Timing Reports

- `reports/timing_sweep_12p5ns.rpt`
- `reports/timing_sweep_12p0ns.rpt`
- `reports/timing_sweep_11p5ns.rpt`
- `reports/timing_sweep_11p0ns.rpt`
- `reports/timing_sweep_10p5ns.rpt`
- `reports/timing_sweep_10p0ns.rpt`

The earlier standalone 100 MHz BFU-input-register report remains available as
`reports/timing_after_bfu_inputreg.rpt`.
