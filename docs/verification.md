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

## Montgomery Input Register, Split-Product, And Constant-Q Regression

Step A added a Montgomery multiplier input register and changed `MUL_LAT` to
7. Step B then replaced only the first `t = a*b` operation with registered
16x16 partial products and a carry-save compression tree, changing `MUL_LAT`
to 9. Both configurations passed the complete functional regression. Step B
is preserved as `rtl/mont_mul_splitmul_experimental.sv` but is not active
because it exceeds the target device's Slice-LUT capacity.

The active constant-Q implementation returns to the Step A input-register
structure and replaces `m * Q` with a three-stage shift/subtract/add pipeline.
It retains `MUL_LAT=9` and II=1. Its regression result is:

| Test | Result |
|---|---|
| `tb_mont_mul` random/boundary values and exact 9-cycle valid delay | PASS |
| `tb_delay_memory` | PASS |
| `tb_gs_butterfly` | PASS |
| `tb_gs_mdc_core` | PASS |
| `tb_poly_mul_top` random negacyclic multiplication | PASS |
| Directed `x^(N-1) * x` negacyclic multiplication | PASS |

Step A and Step B synthesis measurements are recorded in
`docs/synthesis_after_montmul_inputreg.md` and
`docs/synthesis_after_montmul_splitmul.md`. The active constant-Q result is
recorded in `docs/synthesis_after_constq_montmul.md`.

## GS Butterfly Input Register Regression

An input register stage was added before the `gs_butterfly` modular
add/subtract logic. The registered valid signal feeds both the sum delay and
the Montgomery multiplier, so the butterfly total latency increases by one
cycle while `MUL_LAT=9` and the Montgomery multiplier II=1 remain unchanged.

The complete regression passed:

| Test | Result |
|---|---|
| `tb_mont_mul` random/boundary values and exact 9-cycle valid delay | PASS |
| `tb_delay_memory` | PASS |
| `tb_gs_butterfly` | PASS |
| `tb_gs_mdc_core` | PASS |
| `tb_poly_mul_top` random negacyclic multiplication | PASS |
| Directed `x^(N-1) * x` negacyclic multiplication | PASS |

The passing core and top-level tests confirm that the additional butterfly
latency remains correctly controlled by `bf_valid` and does not change the
MDC reorder output sequence. The synthesis result is recorded in
`docs/synthesis_after_bfu_inputreg.md`.
