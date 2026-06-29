# Word-Level Montgomery Multiplier Experiment

This note records an experimental Proteus-inspired word-level Montgomery multiplier for the current 64-bit modulus:

```text
Q = 64'h0fffffffffffc001
```

The active datapath is unchanged. The experiment adds `mont_mul_wl` as a standalone comparison target with the same external handshake as `mont_mul`.

## Motivation

The current active Montgomery multiplier computes:

```text
t = a * b
m = low64(t_low * QINV)
mq = (m << 60) - (m << 14) + m
u = (t + mq) >> 64
```

The optimized active design already removes the full `m * Q` multiply by using `Q = 2^60 - 2^14 + 1`, but it still needs a truncated `t_low * QINV` path.

The word-level experiment reduces the Montgomery result through four 16-bit rounds. For this modulus:

```text
Q[15:0] = 16'hc001
-Q[15:0]^-1 mod 2^16 = 16'hbfff
```

Each round cancels the current low 16-bit word and shifts the accumulator by one word.

## Added RTL

- `rtl/intmul_64x64_24x17.sv`: experimental 64x64 product built from 24x17-style DSP-friendly partial products.
- `rtl/wlmont_round16.sv`: one 16-bit word-level Montgomery reduction round for the project modulus.
- `rtl/mont_mul_wl.sv`: standalone Montgomery multiplier using the tiled input multiplier plus four word-level reduction rounds.

`mont_mul_wl` keeps the same ports as `mont_mul`:

```text
clk, rst_n, in_valid, a, b, out_valid, y
```

The measured standalone latency is 13 cycles. It is not wired into the active core yet, so global `MUL_LAT` is unchanged by this experiment.

## Verification

`sim/tb_mont_mul_wl.sv` compares both the active `mont_mul` and the experimental `mont_mul_wl` against the same SystemVerilog Montgomery reference.

Result:

```text
tb_mont_mul_wl PASS: mont_mul latency=12, mont_mul_wl latency=13
```

## Standalone Vivado Synthesis

Part and clock:

```text
xc7a200tsbg484-1
10.0 ns
```

Reports:

- `reports/utilization_mont_mul_current.rpt`
- `reports/timing_mont_mul_current.rpt`
- `reports/power_mont_mul_current.rpt`
- `reports/utilization_mont_mul_wl.rpt`
- `reports/timing_mont_mul_wl.rpt`
- `reports/power_mont_mul_wl.rpt`

| Metric | Active `mont_mul` | Experimental `mont_mul_wl` | Delta |
|---|---:|---:|---:|
| Slice LUT | 1100 | 926 | -174 |
| LUT as Memory | 129 | 2 | -127 |
| Slice Registers | 1166 | 1496 | +330 |
| DSP48E1 | 26 | 20 | -6 |
| BRAM | 0 | 0 | 0 |
| WNS at 10 ns | +0.733 ns | +2.695 ns | +1.962 ns |
| TNS | 0.000 ns | 0.000 ns | 0.000 ns |
| Total Power | 0.281 W | 0.275 W | -0.006 W |
| Latency | 12 cycles | 13 cycles | +1 cycle |

The original standalone worst path is DSP-cascade dominated inside the active multiplier. The experimental `mont_mul_wl` worst path moves to the first word-level reduction round input logic:

```text
u_intmul/p_reg[0] -> u_round0/qh0_prod_s1_reg/B[14]
Data Path Delay: 3.410 ns
Logic Levels: 5 (CARRY4=4 LUT1=1)
```

## Interpretation

The experiment confirms that a word-level Montgomery structure can reduce per-multiplier DSP usage and improve standalone synthesis slack for this design point. The main tradeoff is one extra cycle of latency and higher register count.

Before replacing the active multiplier, the next step should be a controlled integration branch:

1. Replace `mont_mul` with `mont_mul_wl` or add a selectable parameterized wrapper.
2. Update `MUL_LAT` from 12 to 13.
3. Rerun `tb_mont_mul`, `tb_gs_butterfly`, `tb_gs_mdc_core`, and full polynomial multiplication regressions.
4. Rerun full top-level synthesis/implementation, because standalone savings may shift once 20 BFU multipliers are instantiated and routed.
