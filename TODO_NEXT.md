# Next Optimization Steps

The current explicit Pre/Post negacyclic baseline is functionally verified.
Keep the algorithm and GS-MDC core behavior stable while applying the following
optimizations in order.

## A. Replace MDC FIFO Arrays

Use `rtl/delay_memory.sv` as the starting point for replacing the large
`fifo_a` and `fifo_b` arrays in `mdc_stage`.

- Map large delays to BRAM-friendly circular buffers.
- Keep small delays in registers, SRLs, or LUTRAM.
- Preserve the existing two-FIFO/C2 scheduling and valid alignment.
- Re-run all existing functional tests after each replacement.

## B. Run Vivado Synthesis

Run `scripts/run_synth.bat` and record:

- LUT usage
- FF usage
- DSP usage
- BRAM usage
- Worst slack and achieved Fmax
- Power estimate

Use these reports to identify the actual implementation bottlenecks before
changing arithmetic or transform structure.

The first baseline run is complete and recorded in
`docs/synthesis_baseline.md`. It identified distributed-memory usage and the
Montgomery multiplier critical path as the main implementation bottlenecks.

## C. Consider Fused Pre/Post

Only after the baseline resource and timing results are recorded, evaluate
whether explicit `psi` Pre/Post multipliers should be fused into transform
twiddles.

## D. Consider Mixed Radix-4

Mixed radix-4 is the final architectural optimization step. Do not introduce it
before the radix-2 baseline and fused/non-fused comparison are documented.
