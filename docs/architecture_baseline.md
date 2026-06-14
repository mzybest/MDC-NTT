# Architecture Baseline

This document freezes the current verified architecture before resource-oriented
implementation work begins.

## Transform Core

- Transform length: `N = 4096`
- Data path width: 64-bit Montgomery-domain coefficients
- Architecture: 2-path radix-2 Gentleman-Sande MDC
- Core: one shared `gs_mdc_core` for NTT and INTT
- Stage structure: GS butterfly followed by a two-FIFO/C2 reorder network
- External bit-reversal reads and writes are intentionally retained

The GS-MDC core itself implements an ordinary cyclic NTT/INTT transform. NTT
and INTT share the same butterfly and MDC hardware. The mode selects the
forward or inverse twiddle table. During INTT, `gs_mdc_core` also applies the
final Montgomery-domain scaling by `N^-1`.

## Negacyclic Multiplication

The current polynomial multiplier computes:

```text
c(x) = a(x) * b(x) mod (x^N + 1)
```

Negacyclic behavior is implemented explicitly around the shared GS-MDC core:

```text
Pre_NTT:   a_i <- a_i * psi^i
           b_i <- b_i * psi^i

Core:      cyclic NTT / pointwise multiplication / cyclic INTT

Post_INTT: c_i <- c_i * psi^-i
```

The `psi^i` and `psi^-i` factors and all polynomial data are represented in
Montgomery form.

## Baseline Boundary

This baseline deliberately uses explicit Pre_NTT and Post_INTT multiplier
stages. It is not a fused-twiddle implementation. It also does not use
radix-4 or mixed-radix butterflies.

The next implementation work should preserve this mathematical behavior while
improving how memories and arithmetic map onto FPGA resources.

## MDC Delay Memory

The MDC reorder memory in `mdc_stage.sv` has been changed from the behavioral
`fifo_a` and `fifo_b` arrays to two streaming `delay_memory` instances. The
first instance delays the butterfly V path by `DEPTH` cycles. The second
instance delays either the phase-0 U path or the phase-1 delayed V path,
preserving the original two-FIFO/C2 output order and cycle behavior.

After the butterfly input stream ends, each stage advances both delay memories
for another `DEPTH` dummy-valid cycles. This flushes the final V-first/V-second
pair with continuous `out_valid`. The final stage `DEPTH=0` bypass remains
unchanged.

`delay_memory` uses implementation selection intended to map efficiently onto
FPGA resources:

- `DEPTH >= 128`: RAM/BRAM-friendly synchronous circular buffer
- `DEPTH < 128`: SHIFT/SRL/register implementation
- Data and valid are delayed together
