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

## Current MDC FIFO Synthesis Assessment

`mdc_stage.sv` currently declares `fifo_a` and `fifo_b` as unpacked logic
arrays. They are written in `always_ff` but read combinationally by the C2
reorder logic. This asynchronous-read behavior is functionally correct, but
large depths such as 1024, 512, 256, and 128 are unlikely to infer the most
efficient synchronous block RAM structure. Vivado may implement them as
distributed RAM, LUTs, or registers.

`rtl/delay_memory.sv` is provided as an isolated, verified preparation module:

- `DEPTH >= 128`: BRAM-friendly circular-buffer implementation
- `DEPTH < 128`: register/SRL-friendly shift implementation
- Data and valid are delayed together

It is intentionally not connected to `mdc_stage` in this baseline. Replacing
the C2 FIFOs requires careful preservation of read/write and commutator timing
and is the first task in `TODO_NEXT.md`.
