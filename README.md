# MDC-NTT 项目入口

**招聘查看请先打开：[双核生产 RTL 与验证证据展示版](https://github.com/mzybest/MDC-NTT/tree/portfolio-2026-10-10)。**

展示版面向数字 IC 验证、RTL 与 FPGA 岗位，基于源码快照 `b608e02036b2ce541eb94bc0f0c3e05abd8b612f` 整理；包含双核并行 NTT、CoreA 复用 INTT、A/C BRAM 生命周期复用及可核验测试导航。

- [生产双核顶层](https://github.com/mzybest/MDC-NTT/blob/portfolio-2026-10-10/rtl/poly_mul_top_dual_forward.sv)
- [架构与配置](https://github.com/mzybest/MDC-NTT/blob/portfolio-2026-10-10/docs/portfolio/architecture.md)
- [代码导航和复现](https://github.com/mzybest/MDC-NTT/blob/portfolio-2026-10-10/docs/portfolio/code_navigation.md)
- [验证与性能证据索引](https://github.com/mzybest/MDC-NTT/blob/portfolio-2026-10-10/docs/portfolio/evidence.md)

当前默认 `main` 保留早期单核基线，下面是原始说明；双核顶层不在 main。固定四路 INTT、12 拍 CSA 和 Karatsuba/200 MHz 记录按独立实验标注，未写成生产默认已集成功能。历史证据缺失项在展示版索引中公开说明。

---

# 2-path Radix-2 GS-MDC NTT/INTT baseline

This repository contains a first-stage, synthesizable SystemVerilog baseline
for a reusable 4096-point GS NTT/INTT core and a frame-oriented polynomial
negacyclic multiplier.

## Data convention

All core and top-level coefficient data is in Montgomery form. Twiddle ROMs are
also in Montgomery form. The Python generators create matching `.mem` files.
`poly_mul_top` computes negacyclic convolution modulo `x^N+1` using explicit
Montgomery-domain `psi^i` Pre_NTT and `psi^-i` Post_INTT multipliers. The
shared GS-MDC core remains an ordinary cyclic NTT/INTT engine.

## Generate files

```powershell
python scripts/gen_params.py
python scripts/gen_twiddle.py
python scripts/gen_psi.py
python scripts/gen_testvec.py
python scripts/ref_ntt.py
```

`mdc_stage` places a two-FIFO/C2 delay-commutator after each GS butterfly.
Polynomial A/B storage is split into lower-half bank 0 and upper-half bank 1,
allowing stage 0 to receive distance-N/2 butterfly operands without an input
delay; stage 0's output FIFOs then prepare the pairs required by stage 1.
