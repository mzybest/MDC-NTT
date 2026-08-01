# Dual-Forward Core 100 MHz Timing Closure

## 1. Objective and constraints

This experiment closes post-route timing for the asymmetric dual-forward
GS-MDC polynomial multiplier on Vivado 2022.2 and
`xc7a200tsbg484-1`.

The constraints were:

- keep the radix-2 GS equations and MDC reorder unchanged;
- keep the full-WL Montgomery datapath at `MUL_LAT=14` and II=1;
- keep the clock constraint at 10.000 ns;
- do not add multicycle, false-path, or other timing exceptions;
- retain the existing direct BFU path as a selectable default.

The original dual-forward e06 implementation was fully routed but failed
setup timing with WNS `-0.325 ns`.

## 2. Selective BFU boundary pipeline

`gs_butterfly` now has an optional register boundary after `mod_add` and
`mod_sub` and before the sum delay and WL Montgomery multiplier:

```text
a_r/b_r -> mod_add/mod_sub -> boundary registers
         -> sum delay / mont_mul_wl
```

The boundary remains default-disabled in the reusable butterfly and stage
modules. The dual-forward top enables it only at the two path families that
were critical in the original implementation:

- full CoreA: Stage11 only;
- NTT-only CoreB: Stage0 only.

Both branches of a selected butterfly are registered together, including
the twiddle and valid signal. The datapath therefore remains aligned and
accepts one pair every cycle. Each selected transform gains one cycle, and
the full polynomial-multiply latency changes from 8,621 to 8,623 cycles.

## 3. Functional verification

The final active RTL was recompiled and tested after implementation:

| Testbench | Result | Measured result |
|---|---|---|
| `tb_mont_mul_wl` | PASS | old latency 12, WL latency 14 |
| `tb_gs_butterfly` | PASS | 32 vectors |
| `tb_gs_mdc_core` | PASS | full GS-MDC core |
| `tb_gs_mdc_core_ntt_only` | PASS | first latency 2,242; done latency 4,290 |
| `tb_poly_mul_top_wavefront` | PASS | random and directed negacyclic; 10,669 cycles |
| `tb_poly_mul_top_dual_forward` | PASS | random and directed negacyclic; 8,623 cycles |

At 100 MHz, the dual-forward compute latency is 86.23 us. Relative to the
10,669-cycle wavefront top, this is 2,046 cycles or 19.18% lower latency,
equivalent to a 1.237x operation-rate increase for isolated products.

## 4. Implementation progression

| Version | WNS | TNS | WHS | Full-mul cycles | Result |
|---|---:|---:|---:|---:|---|
| Original dual-forward e06 | -0.325 ns | -3.893 ns | +0.050 ns | 8,621 | setup FAIL |
| Selective boundary pipeline e06 | +0.162 ns | 0.000 ns | +0.014 ns | 8,623 | PASS |
| Route-only 9.8 ns, signoff 10 ns | +0.129 ns | 0.000 ns | +0.014 ns | 8,623 | PASS, rejected |
| Post-route Explore at 10 ns | +0.164 ns | 0.000 ns | +0.015 ns | 8,623 | optimization skipped |
| Forced post-route Explore at 9.8 ns, signoff 10 ns | **+0.201 ns** | **0.000 ns** | **+0.014 ns** | 8,623 | **PASS** |

The final physical-optimization run temporarily used a 9.8 ns implementation
target so that the two marginal paths became actual violations. Vivado
adjusted clock skew on two existing critical nets, added no cells, removed
no cells, and closed the 9.8 ns target at WNS `+0.001 ns`. The clock was then
restored to 10.0 ns for signoff, producing WNS `+0.201 ns`.

No RTL, arithmetic, clock period, or timing exception was changed by this
physical optimization.

## 5. Final post-route result

| Metric | Original dual-forward | Final selective-pipe result | Change |
|---|---:|---:|---:|
| Slice LUT | 86,039 | 86,069 | +30 |
| LUT Memory | 25,361 | 25,354 | -7 |
| Registers | 63,548 | 63,704 | +156 |
| DSP48E1 | 680 | 680 | 0 |
| BRAM | 43 | 43 | 0 |
| Setup WNS | -0.325 ns | **+0.201 ns** | **+0.526 ns** |
| Setup TNS | -3.893 ns | 0.000 ns | PASS |
| Hold WHS | +0.050 ns | +0.014 ns | PASS |
| Hold THS | 0.000 ns | 0.000 ns | PASS |
| Estimated power | 3.764 W | 3.745 W | -0.019 W |

All 146,899 routable nets are fully routed, with zero routing errors.

The routed checkpoint and reports are under:

```text
reports/dual_forward_bfu_selective_pipe/postroute_physopt_explore_oc9p8/
```

The recommended flow is:

```text
opt_design       -directive Explore
place_design     -directive AltSpreadLogic_medium
phys_opt_design  -directive AggressiveFanoutOpt
route_design     -directive MoreGlobalIterations

# From the legal 10 ns routed checkpoint:
set clock to 9.8 ns
phys_opt_design  -directive Explore
route_design     -directive MoreGlobalIterations -tns_cleanup
restore clock to 10.0 ns for signoff
```

## 6. Final worst path

The final worst setup path is:

```text
CoreB Stage8 b_r_reg[3]
-> mod_sub carry chain
-> mont_mul_wl intmul p31_s1 partial-product register
```

Its slack is `+0.201 ns`, with a 9.110 ns data path:

- logic: 4.179 ns (45.88%);
- routing: 4.931 ns (54.12%);
- 23 logic levels: 20 CARRY4, one LUT3, and two LUT4.

The original CoreA Stage11 sum path and CoreB Stage0 diff path are no longer
in the failing-path set. The remaining top paths are distributed across
ordinary BFU stages and are approximately half logic and half routing delay.

## 7. Conclusion

The selective BFU boundary pipeline plus the forced 9.8 ns post-route
physical optimization achieves the requested 100 MHz routed checkpoint with
WNS `+0.201 ns`, TNS `0.000 ns`, and passing hold timing. It preserves the
algorithm, II=1 datapath, and all existing selectable paths.

This is a valid dual-forward 100 MHz checkpoint. The margin is positive but
small, and DSP utilization is 91.89%, so a higher-frequency version should
target the remaining subtract-to-partial-product path structurally rather
than duplicate more arithmetic.
