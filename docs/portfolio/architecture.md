# 双核生产路径架构

核验日期：2026-10-10。源码基于 `b608e02036b2ce541eb94bc0f0c3e05abd8b612f`；顶层 [poly_mul_top_dual_forward](../../rtl/poly_mul_top_dual_forward.sv)，配置以 [自然序自检测试台](../../sim/tb_poly_mul_top_dual_forward_natural_ab.sv) 为准。

## 数据与参数

N=4096，LOGN=12，QW=64；固定模数 Q=0x0fffffffffffc001=2^60−2^14+1，Montgomery R=2^64。64 位端口不代表任意 64 位模数支持。Pre/Post 是负循环因子处理，GS 核本身完成普通循环 NTT/INTT。

输入为 Montgomery 表示，不是普通整数系数。展示配置在同步 BRAM 读出后做 Pre_NTT；Post 可将 N^-1 与 psi^-i 合为一个因子，**这不等于将全部 Pre/Post 融入蝶形 twiddle**。

| 参数 | 展示配置 |
|---|---:|
| MUL_LAT | 14 |
| USE_WL_MONT / CORE / PRE_NTT / POINTWISE / POST_INTT | 各为 1 |
| USE_LOAD_PREPROCESS | 0 |
| USE_SHARED_PERIPH_MONT | 1 |
| FUSE_INTT_SCALE_IN_POST | 1 |
| USE_FINAL_UNIT_TWIDDLE_BYPASS | 1 |
| USE_TOP_DATA_BRAM / USE_NATURAL_AB_LOADER | 各为 1 |
| USE_BFU_BOUNDARY_PIPE / USE_STAGE_LOCAL_TWIDDLE | 各为 1 |
| TWIDDLE_BRAM_STAGES | 4 |

顶层中自然序 loader、顶层 BRAM、共享外围池等默认关闭，复现时必须按表覆盖。当前 `mont_mul_wl.REDUCTION_IMPL=2`，采用固定 Q 的融合 correction；历史 520 DSP 记录使用更早约减结构，不能直接赋给此默认源码。

## 数据流与存储

1. 自然序接口每次 `ab_in_valid && ab_in_ready` 接受 A[k]/B[k]；索引仅在握手成功时递增。4096 对加载完成后接受计算。
2. A 与 B 各用两个半区 bank；每拍读取 i 与 i+2048，经四路 Pre 送入两套 GS 核。
3. CoreA 和 CoreB 的锁步频域输出直接点乘，不设置独立 A_NTT 缓存。每拍产生两个 C_NTT 系数。
4. C_NTT 写入 A 的物理 bank 空间。A 原始输入生命周期结束后才允许覆写，断言检查读写所有权。
5. C_NTT 按位反序 pair 地址读取，供 CoreA 的全 GS INTT；CoreB 此阶段空闲。
6. Post 与地址标签对齐后写结果 RAM，外部使用 `result_addr/result_data` 读取。

| 存储 | 加载阶段 | 正变换 | 点乘阶段 | 逆变换 |
|---|---|---|---|---|
| u_ac_bank0/1 | A 输入 | 读取 A | 覆写为 C_NTT | 重排读取 C_NTT |
| u_b_bank0/1 | B 输入 | 读取 B | 不再使用 | 空闲 |
| result_bank0/1 | 不参与输入 | 不参与 | 不参与 | Post 写结果 |

bank 组织的详细地址模型见 [natural_ab_dual_loader](../natural_ab_dual_loader.md)。Pointwise 与 INTT 之间仍有帧边界；地址重排没有变成四路无缝逆变换。

## 工程边界

模乘流水 II=1 与整机任务吞吐不同。MDC 核按连续帧调度；自然序装载接口支持输入气泡，不等于蝶形流水支持任意反压。结果端是地址读口，没有 ready/valid 流式读回协议。

[固定四路 INTT](../../sim/tb_gs_quad_inverse_audit.sv) 是独立测试台中的固定拓扑；当前生产顶层没有运行时模式切换、完整四路 Post/写口闭合或新整机布局布线。6575/6576 拍仅为模型投影，不是生产实测。
