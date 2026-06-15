# Synthesis After Split First-Stage Montgomery Product

## Run Configuration

- Tool: Vivado 2022.2
- Top: `poly_mul_top`
- Device: `xc7a200tsbg484-1`
- Requested clock: `10.000 ns` / `100 MHz`
- Command: `scripts/run_synth.bat xc7a200tsbg484-1 10.0`
- Active Montgomery multiplier latency: 9 cycles

Step B rewrites only the first `t = a*b` operation. Each input is split into
four 16-bit limbs. Sixteen registered 16x16 partial products are compressed by
a carry-save tree, then a separately registered carry-propagate addition
produces the original 128-bit `t`. The later Montgomery reduction stages are
unchanged, and the multiplier continues to accept one input per cycle.

The preserved Step B reports are:

- `reports/utilization_after_montmul_splitmul.rpt`
- `reports/timing_after_montmul_splitmul.rpt`
- `reports/power_after_montmul_splitmul.rpt`

## Functional Verification

| Test | Result |
|---|---|
| `tb_mont_mul` random/boundary values and exact 9-cycle valid delay | PASS |
| `tb_delay_memory` | PASS |
| `tb_gs_butterfly` | PASS |
| `tb_gs_mdc_core` | PASS |
| `tb_poly_mul_top` random negacyclic multiplication | PASS |
| Directed `x^(N-1) * x` negacyclic multiplication | PASS |

## Three-Way Comparison

| Metric | 6-cycle full multiply | Step A: 7-cycle input register | Step B: 9-cycle split multiply |
|---|---:|---:|---:|
| Slice LUTs | 92987 | 85778 | 148459 |
| LUT as memory | 27726 | 27802 | 28143 |
| Slice registers | 21221 | 20408 | 30892 |
| DSP48E1 | 596 | 700 | 600 |
| Block RAM tiles | 10 | 10 | 10 |
| WNS | -10.814 ns | -3.196 ns | -2.502 ns |
| TNS | -48525.773 ns | -7653.512 ns | -1866.245 ns |
| Worst data-path delay | 19.234 ns | 11.136 ns | 11.781 ns |
| Rough post-synthesis Fmax | about 52.0 MHz | about 89.8 MHz | about 84.9 MHz |

Relative to Step A, Step B improves WNS by `0.694 ns` and TNS by
`5787.267 ns`, but its worst data-path delay increases by `0.645 ns`.

## Resource Finding

The explicit partial-product and CSA implementation consumes:

```text
148459 Slice LUTs / 134600 available = 110.30%
```

It exceeds the target device capacity by 13859 Slice LUTs and therefore is not
a placeable implementation for `xc7a200tsbg484-1`. Compared with Step A, it
adds 62681 Slice LUTs and 10484 registers. BRAM remains at 10, while DSP48E1
usage falls from 700 to 600.

The split first product is functionally correct and DSP-friendly at the
partial-product level, but the broad 128-bit carry-save compression network is
too LUT-expensive when replicated across every Montgomery multiplier.

## Timing Finding

The Step A internal `m_s1 -> mq_s2` path is no longer the worst path. The new
Step B worst path is:

```text
Source:
feed_count_reg[10]/C

Destination:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/pp_s0_reg[12]/A[13]
```

Its structure is:

```text
24 CARRY4 + LUT/MUX + 1 RAMD64E
```

The path terminates at a DSP48E1 input register for one 16x16 partial product,
but it contains no DSP48E1 combinational stage. It passes through the
distributed-RAM input stream and Stage0 butterfly subtraction logic. It does
not pass through the twiddle ROM.

This confirms that the original full 64x64 product chain has been removed.
However, synthesis absorbed/replicated the partial-product input structure such
that the upstream feed/subtraction path again becomes critical.

## Power Estimate

| Metric | Step A input register | Step B split multiply |
|---|---:|---:|
| Total on-chip power | 2.489 W | 4.047 W |
| Dynamic power | 2.344 W | 3.890 W |
| Static power | 0.145 W | 0.157 W |
| Junction temperature | not recorded | 38.4 C |

The power report is a vector-less post-synthesis estimate with Low confidence.

## Conclusion

Step A is the stronger resource/timing tradeoff: it nearly reaches the 100 MHz
target while remaining within device capacity. Step B removes the full-width
first multiply path and slightly improves WNS, but its current CSA
implementation exceeds available Slice LUTs and does not improve the worst
data-path delay.

No Pre/Post fusion, radix-4 change, GS-MDC reorder change, or wider Montgomery
reduction refactor was made. Further work should not expand this CSA tree as
implemented; it requires a more resource-efficient DSP cascade or a return to
the Step A implementation before targeting the measured remaining paths.

The Step B RTL is preserved as
`rtl/mont_mul_splitmul_experimental.sv`. It lowers DSP usage, but its 110.30%
Slice-LUT utilization exceeds the `xc7a200t` capacity, so it is explicitly not
the active mainline `mont_mul` implementation.
