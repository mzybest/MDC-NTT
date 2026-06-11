# 2-path Radix-2 GS-MDC NTT/INTT baseline

This repository contains a first-stage, synthesizable SystemVerilog baseline
for a reusable 4096-point GS NTT/INTT core and a frame-oriented polynomial
multiplier.

## Data convention

All core and top-level coefficient data is in Montgomery form. Twiddle ROMs are
also in Montgomery form. The Python generators create matching `.mem` files.
The current polynomial top computes cyclic convolution; `ref_ntt.py` also
provides a negacyclic reference for future pre/post-twist integration.

## Generate files

```powershell
python scripts/gen_params.py
python scripts/gen_twiddle.py
python scripts/gen_testvec.py
python scripts/ref_ntt.py
```

`mdc_stage` places a two-FIFO/C2 delay-commutator after each GS butterfly.
Polynomial A/B storage is split into lower-half bank 0 and upper-half bank 1,
allowing stage 0 to receive distance-N/2 butterfly operands without an input
delay; stage 0's output FIFOs then prepare the pairs required by stage 1.
