# 验证与性能证据索引

日期：2026-10-10。源码锚点 `b608e02036b2ce541eb94bc0f0c3e05abd8b612f`。本页区分公开文件的内容、历史运行记录与本次复跑，未把缺失的原始文件制造成新证据。

## 本次执行

| 检查 | 结果 | 公开记录 |
|---|---|---|
| Python 4096 点 NTT/INTT 往返 | PASS | [reference_roundtrip.txt](../../reports/portfolio_20261010/reference_roundtrip.txt) |
| N=16 pair 地址映射 | PASS | [mapping.txt](../../reports/portfolio_20261010/mapping.txt) |
| 4096 个 Post 因子、10000 次数值等价 | PASS | [fused_post.txt](../../reports/portfolio_20261010/fused_post.txt) |
| 已提交 A/B 黄金负循环乘法向量，4096 项逐项比对 | PASS | [golden_vectors.txt](../../reports/portfolio_20261010/golden_vectors.txt) |
| RTL/测试/mem 相对源码锚点 | 无修改 | [核验清单](../../reports/portfolio_20261010/audit.json) |

黄金向量检查将 input_a/input_b 从 Montgomery 域转换、调用 ref_ntt.negacyclic_mul、转换回域后与 golden_result 比较。以上均为 Python 检查，不能替代 RTL 仿真。RTL/仿真源文件 SHA256 清单随核验记录提交。

## 历史功能验证

| 范围 | 已有证据 | 公开完整程度 |
|---|---|---|
| 生产自然序双核，连续随机、同组带气泡、定向 x^(4095)·x | [测试台](../../sim/tb_poly_mul_top_dual_forward_natural_ab.sv)、[历史记录](../natural_ab_dual_loader.md)、[回归入口](../../scripts/run_q64_core_control_localization_regression.bat) | 代码与文字记录已提交；q64/natural-loader 原始 Questa 日志未提交 |
| 未修改原自然序测试的后续历史运行 | [simulation.json 的 unchanged_natural_ab](../../reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/candidate/simulation.json) | 已提交提取的 PASS/周期观察；不是完整日志或本次 RTL 重跑 |
| Karatsuba 独立快照，含全 64 位输入规范化与往返 | 同一 [simulation.json](../../reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/candidate/simulation.json) 的其他项 | 有摘要；派生快照与原始日志未完整提交 |
| 固定四路 INTT 三帧 | [实验审计记录](../quad_inverse_audit.md)、[固定测试台](../../sim/tb_gs_quad_inverse_audit.sv) | 记录声称 PASS；reports/quad_inverse_audit 的日志/trace 未提交，尚无生产可切换顶层 |

生产自然序测试检查加载握手、bank 边界、C 写入与 INTT 地址映射、全部 4096 个结果、结果数量和阶段周期；随机数据为已有固定向量，不能宣称大规模随机覆盖收敛。

## 周期与统计口径

| 配置与工作负载 | 计算 start→done | 加载 + 计算 | 范围 |
|---|---:|---:|---|
| 自然序双核 14 拍，连续加载 | 8623 | 12719 | 历史 RTL 周期记录；加载 4096 对 |
| 同配置带气泡加载 | 8623 | 14045 | 加载耗时 5422 拍 |
| 12 拍 CSA 独立快照 | 8565 | 12661 | [历史对照文档](../wl_csa_full_top_integration.md)，未选入生产默认 |
| 四路 INTT 候选 | 6575/6576 投影 | 10671/10672 投影 | 数值/逐拍模型，不是可切换整机实测 |

上述均不含逐项结果读回；`done` 表示结果写入完成。不能将 8623 与论文独立 NTT 的周期直接比较。NTT-only 核历史 4290 拍也不是完整乘法延迟。

## FPGA 性能版本归属

均为 xc7vx485tffg1761-2、Vivado 2026.1 的历史记录，除非原文另有说明；不宣称流片、板级签核或上板实测。

| 实现版本 | 历史 routed 结果 | 对应证据与限制 |
|---|---|---|
| 早期 q64 控制局部化，20 DSP/模乘 | 150 MHz；LUT 53866 / FF 47998 / DSP 520 / BRAM36 59；WNS +0.705 ns | [q64 文档](../q64_core_control_localization.md)；原始该目录报告未提交；约减更新前版本 |
| 14 拍融合约减基线，REDUCTION_IMPL=2 | 约 150 MHz，6.667 ns；LUT 54111 / FF 49713 / DSP 312 / BRAM36 59；WNS +0.549，WHS +0.019 ns | [CSA 对照文档](../wl_csa_full_top_integration.md)；lat14 原始报告/快照未提交；与当前生产算术配置相符，但不能仅凭一致参数证明历史源码逐字相同 |
| Karatsuba 14 拍独立快照 | 150 MHz；LUT 56664 / FF 43637 / DSP 246 / BRAM36 59；WNS +0.414，WHS +0.040 ns | [实验文档](../wl_karatsuba_experiment.md)、[已提交复核 JSON](../../reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/reviewed_final_audit.json)；严格审计仍为 false，保留综合目录错误与单次复核例外 |
| Karatsuba reroute200 独立检查点 | 200 MHz，5 ns；DSP 246 / BRAM36 59；WNS +0.008，WHS +0.036 ns | [result.json](../../reports/wl_lowcost_modmul/karatsuba_frequency/20260917_high/reroute200/result.json)、[实验记录](../wl_karatsuba_high_frequency_experiment.md)；JSON 是摘要，完整 timing/utilization/DCP/快照未提交；board_signoff=false |

200 MHz 记录对应 8623 拍 × 5 ns = 43.115 μs，仅为静态时序支持的周期换算；8 ps 建立余量很小，不作为稳健 Fmax 声明。历史 +0.705 ns 不能和 246 DSP/200 MHz 拼成一套配置。520→312 为约减变化，312→246 为核内 Karatsuba 前端变化，比较基线不同。

## 后续待补证据

优先补齐受版本/哈希约束的生产 natural-ab 回归日志、生产融合约减版本的原始 routed 时序/资源/约束报告，以及实验 snapshot 清单。需完成板级引脚/IO delay 后才能讨论板级签核；四路可切换版本还需完整 Forward→INTT→Forward、flush、四路 Post/写口和整机 PPA。

历史文档保留时间顺序，部分使用 D:/MDC-NTT 本地链接或描述当时未完成的工作；本索引提供实际存在的公开入口。缺失文件没有生成占位“通过报告”，旧失败记录未改写。
