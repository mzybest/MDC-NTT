# 代码导航与复现

## 从角色关心的问题进入

| 问题 | 代码或文档 |
|---|---|
| 整机状态机、数据流、A/C 复用及地址标签 | [poly_mul_top_dual_forward.sv](../../rtl/poly_mul_top_dual_forward.sv) |
| 双模式 CoreA、仅 Forward CoreB | [gs_mdc_core.sv](../../rtl/gs_mdc_core.sv)、[gs_mdc_core_ntt_only.sv](../../rtl/gs_mdc_core_ntt_only.sv) |
| GS 蝶形、加法/模乘对齐、C2 重排 | [gs_butterfly.sv](../../rtl/gs_butterfly.sv)、[mdc_stage.sv](../../rtl/mdc_stage.sv) |
| 分层 FIFO 延迟存储、同步顶层 BRAM | [delay_memory.sv](../../rtl/delay_memory.sv)、[top_data_bram.sv](../../rtl/top_data_bram.sv) |
| 14 拍 WL Montgomery 与固定 Q 约减 | [mont_mul_wl.sv](../../rtl/mont_mul_wl.sv)、[wlmont_round16.sv](../../rtl/wlmont_round16.sv) |
| Pre/PW/Post 外围模乘复用 | [peripheral_mont_pool.sv](../../rtl/peripheral_mont_pool.sv) |
| 自然序输入、加载气泡、4096 项比对、映射与周期检查 | [tb_poly_mul_top_dual_forward_natural_ab.sv](../../sim/tb_poly_mul_top_dual_forward_natural_ab.sv) |
| 不同顶层参数组合 | [tb_poly_mul_top_dual_forward.sv](../../sim/tb_poly_mul_top_dual_forward.sv) |
| 单元与完整核心 | [tb_mont_mul_wl.sv](../../sim/tb_mont_mul_wl.sv)、[tb_gs_butterfly.sv](../../sim/tb_gs_butterfly.sv)、[tb_gs_mdc_core.sv](../../sim/tb_gs_mdc_core.sv) |
| 算法参考与黄金向量生成 | [ref_ntt.py](../../scripts/ref_ntt.py)、[gen_testvec.py](../../scripts/gen_testvec.py) |
| 固定四路实验、被动内部轨迹监测 | [tb_gs_quad_inverse_audit.sv](../../sim/tb_gs_quad_inverse_audit.sv)、[tb_quad_inverse_audit_monitor.sv](../../sim/tb_quad_inverse_audit_monitor.sv) |
| 保留单核与双上下文基线 | [poly_mul_top.sv](../../rtl/poly_mul_top.sv)、[poly_mul_top_wavefront.sv](../../rtl/poly_mul_top_wavefront.sv) |

验证能力由实际自检、断言和参考比对支持；没有 UVM 环境或覆盖率百分比的证据。注释中的 experimental 命名保留历史语义，判断是否生产选中应看实例化路径和参数。

## 无商业 EDA 的检查

在仓库根目录，Python 3：

```sh
python scripts/ref_ntt.py
python scripts/natural_ab_mapping_model.py
python scripts/validate_fused_post_factors.py
```

以上检查分别覆盖算法往返、N=16 pair 地址关系、Post 因子/数值等价；它们不运行 RTL 仿真。2026-10-10 执行记录见 [证据索引](evidence.md)。

## RTL 回归

历史环境为 Windows、Questa 2020.4；[q64 回归脚本](../../scripts/run_q64_core_control_localization_regression.bat) 含编译顺序、测试台、参数、PASS 检查，并在独立 work 库运行。先把脚本中的 `QUESTA_BIN` 改为实际安装目录，按 [架构参数](architecture.md) 运行自然序顶层。

```bat
scripts\run_q64_core_control_localization_regression.bat
```

脚本会重新生成部分 ROM 文件；需要严格核验已有向量时，在独立 checkout 运行并检查 diff。PASS 要与错误日志、输出数量、全部系数比对和周期检查一起查看；不是仅以进程退出码判定。

固定四路审计入口为 [run_quad_inverse_audit.ps1](../../scripts/run_quad_inverse_audit.ps1)。它先生成当前生产顶层轨迹，再执行模型及固定四路测试；不能在缺少 trace 时直接把模型历史 PASS 当成新运行结果。

## FPGA 与实验复现条件

[双核综合入口](../../scripts/run_synth_dual_forward_dsp_reduction.tcl) 有多种环境变量配置；器件、顶层参数和时钟必须逐项与目标实验匹配。历史 150 MHz 生产记录与 200 MHz Karatsuba 快照分别索引，不跨版本拼资源/频率。

[Karatsuba 整机脚本](../../scripts/run_wl_karatsuba_full_top.py) 创建独立 snapshot 并局部替换核内前端，不编辑生产源码。它依赖指定基线结果目录及本地 Questa/Vivado 路径；当前公开仓库没有完整基线/DCP/快照，因此从公开 checkout 无法一条命令复现历史 200 MHz 检查点。需补齐原始归档，或建立新的受控实验并重新报告，不能把新结果归为旧版本。

本次展示整理环境未安装 Questa/Vivado；未重新运行 RTL 回归、综合、布局布线或上板测试。
