# Verification Record

The explicit Pre/Post negacyclic baseline has passed the following Questa
tests:

| Test | Result |
|---|---|
| `tb_gs_butterfly` | PASS |
| `tb_gs_mdc_core` | PASS |
| `tb_poly_mul_top` random negacyclic multiplication | PASS |
| Directed `x^(N-1) * x` negacyclic multiplication | PASS |

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
