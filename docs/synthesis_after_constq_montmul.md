# Synthesis After Constant-Q Montgomery Reduction

## Run Configuration

- Tool: Vivado 2022.2
- Top: `poly_mul_top`
- Device: `xc7a200tsbg484-1`
- Requested clock: `10.000 ns` / `100 MHz`
- Command: `scripts/run_synth.bat xc7a200tsbg484-1 10.0`
- Active Montgomery multiplier latency: 9 cycles
- Initiation interval: 1 cycle

The active implementation starts from the Step A input-register multiplier and
replaces only the Montgomery reduction product `mq = m * Q`. For the current
modulus:

```text
Q = 64'h0fffffffffffc001 = 2^60 - 2^14 + 1
```

the product is computed as:

```text
mq = (m << 60) - (m << 14) + m
```

The shift terms, subtraction, and final addition are registered separately.
The preserved Step B split-product experiment is
`rtl/mont_mul_splitmul_experimental.sv` and is not part of the active design.

The preserved reports are:

- `reports/utilization_after_constq_montmul.rpt`
- `reports/timing_after_constq_montmul.rpt`
- `reports/power_after_constq_montmul.rpt`

## Functional Verification

| Test | Result |
|---|---|
| `tb_mont_mul` random/boundary values and exact 9-cycle valid delay | PASS |
| `tb_delay_memory` | PASS |
| `tb_gs_butterfly` | PASS |
| `tb_gs_mdc_core` | PASS |
| `tb_poly_mul_top` random negacyclic multiplication | PASS |
| Directed `x^(N-1) * x` negacyclic multiplication | PASS |

## Utilization Comparison

| Resource | Step A input register | Constant-Q pipeline | Change |
|---|---:|---:|---:|
| Slice LUTs | 85778 | 74236 | -11542 |
| LUT as memory | 27802 | 30362 | +2560 |
| Slice registers | 20408 | 24006 | +3598 |
| DSP48E1 | 700 | 520 | -180 |
| Block RAM tiles | 10 | 10 | 0 |

The constant-Q shift/add implementation reduces Slice LUT use by 13.46% and
DSP48E1 use by 25.71% relative to Step A. The longer global alignment delay
increases register and shift-register-LUT usage. The MDC delay memories remain
mapped to 10 block RAM tiles.

## Timing Comparison

| Metric | Step A input register | Constant-Q pipeline | Change |
|---|---:|---:|---:|
| WNS | -3.196 ns | -2.590 ns | +0.606 ns |
| TNS | -7653.512 ns | -2958.803 ns | +4694.709 ns |
| Worst data-path delay | 11.136 ns | 11.781 ns | +0.645 ns |
| Rough post-synthesis Fmax | about 89.8 MHz | about 84.9 MHz | lower |

The Step A `m_s1 -> mq_s2` constant-multiply path is no longer the worst path.
The new worst path is:

```text
Source:
feed_count_reg[10]/C

Destination:
u_core/g_stage[0].u_stage/u_butterfly/u_mul/t_s00/B[10]
```

The path starts at the top-level feed counter, passes through distributed
memory and the Stage0 butterfly subtraction logic, and ends at a DSP48E1 input
for the first `t = a*b` product. Its structure is:

```text
24 CARRY4 + LUT/MUX + 1 RAMD64E
```

The path contains 31 logic levels and has an 11.781 ns data-path delay:
5.619 ns logic plus 6.162 ns routing. It is not inside the new constant-Q
shift/subtract/add stages.

The 100 MHz synthesis target is not yet met. Because the remaining WNS is a
moderate `-2.590 ns` and the constant-Q path is no longer critical, no further
RTL restructuring is included in this step. A later implementation run or a
relaxed clock target can measure whether placement and routing close the
remaining gap.

## Power Estimate

| Metric | Step A input register | Constant-Q pipeline |
|---|---:|---:|
| Total on-chip power | 2.489 W | 1.955 W |
| Dynamic power | 2.344 W | 1.813 W |
| Static power | 0.145 W | 0.141 W |
| Junction temperature | not recorded | 31.5 C |

The power report is a vector-less post-synthesis estimate with Low confidence.

## Conclusion

The constant-Q Montgomery reduction is functionally correct, retains II=1,
removes the Step A `m * Q` critical path, and substantially reduces LUT and DSP
use. Post-synthesis WNS improves slightly to `-2.590 ns`, but the new worst
path is the upstream Stage0 input/subtraction path entering the first
Montgomery product. No fused Pre/Post, radix-4, or GS-MDC reorder change was
made.
