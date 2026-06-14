# Verification Record

After replacing the behavioral MDC reorder arrays in `mdc_stage.sv` with
`delay_memory`, the explicit Pre/Post negacyclic baseline passed the following
Questa regressions on June 14, 2026:

| Test | Result |
|---|---|
| `tb_delay_memory` (`DEPTH=1,2,8,64,1024`) | PASS |
| `tb_gs_butterfly` | PASS |
| `tb_gs_mdc_core` | PASS |
| `tb_poly_mul_top` random negacyclic multiplication | PASS |
| Directed `x^(N-1) * x` negacyclic multiplication | PASS |

The core and top-level regressions confirm that the streaming delay-memory
flush preserves the original reorder output sequence and cycle behavior,
including the large Stage0 (`DEPTH=1024`) and Stage1 (`DEPTH=512`) memories.

The directed test checks:

```text
x^(N-1) * x = -1 mod (x^N + 1)
```

RTL inputs and outputs remain in Montgomery form. Therefore, the directed
test's `-1 mod Q` result is represented as:

```text
Q - R_MOD_Q
```

The random top-level test compares the complete RTL result against
`scripts/ref_ntt.py::negacyclic_mul`.

## Baseline Verification Commands

Generate constants, ROMs, and vectors:

```powershell
python scripts/gen_params.py
python scripts/gen_twiddle.py
python scripts/gen_psi.py
python scripts/gen_testvec.py
python scripts/ref_ntt.py
```

The current verification confirms functional correctness. Vivado synthesis,
resource usage, timing closure, and post-synthesis simulation remain separate
next-stage tasks. The subsequent Vivado baseline synthesis is recorded in
`docs/synthesis_baseline.md`.

## Six-Cycle Montgomery Multiplier Regression

After changing `mont_mul` from three cycles to six cycles and updating the
global `MUL_LAT`, the following regression passed:

| Test | Result |
|---|---|
| `tb_mont_mul` random/boundary values and exact 6-cycle valid delay | PASS |
| `tb_delay_memory` | PASS |
| `tb_gs_butterfly` | PASS |
| `tb_gs_mdc_core` | PASS |
| `tb_poly_mul_top` random negacyclic multiplication | PASS |
| Directed `x^(N-1) * x` negacyclic multiplication | PASS |

The complete post-pipeline synthesis result is recorded in
`docs/synthesis_after_montmul_pipe.md`.
