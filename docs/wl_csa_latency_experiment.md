# 两拍 CSA 整数乘法与 12 拍 WL 模乘实验

后续更新（2026-09-15）：完整双核集成和两组布局布线已完成，见 [整机集成报告](/D:/MDC-NTT/docs/wl_csa_full_top_integration.md)。本文保留独立模乘模块实验的原始结果；其中“尚未集成”描述的是当时状态。

日期：2026-09-14。状态：Questa 验证和四组 Vivado 布局布线全部完成，源码哈希校验通过。12 拍完整模乘候选满足本次 150 MHz 寄存器间时序；生产 NTT 默认仍为 14 拍。

运行目录：`D:/MDC-NTT/reports/wl_lowcost_modmul/csa_latency/20260914_220510/`。

## 实验范围与比较边界

本轮检查整数乘法由四拍改为两拍后，能否减少完整 WL 模乘延迟，并记录资源与时序代价。

| 项目 | 固定条件 |
|---|---|
| 器件 / 工具 | `xc7vx485tffg1761-2` / Vivado 2026.1 |
| 时钟 | 6.667 ns，约 150 MHz；四组均使用相同约束 |
| 整数乘法 | 64×64 位无符号输入、128 位输出，输入不限制为小于 Q |
| 完整模乘 | `Q=0x0fffffffffffc001=2^60-2^14+1`，64 位接口、60 位模数 |
| 模乘输入 / 输出 | `0<=a,b<Q`；输出 `a*b*R^-1 mod Q`，`R=2^64` |
| WL 约减 | 两组均采用当前 `REDUCTION_IMPL=2`，四轮各两拍，末尾校正一拍 |
| 吞吐 | 各核 II=1 |
| 实现流程 | OOC 综合、opt、place、phys_opt、route；共同 `HD.CLK_SRC=BUFGCTRL_X0Y0` |

`wl_csa_bench_top` 在每个被测核之外增加相同的一拍输入寄存和一拍输出寄存。**核延迟与整个测试包装延迟相差两拍**：整数乘法为 4/2 拍，包装后为 6/4 拍；完整模乘为 14/12 拍，包装后为 16/14 拍。共同包装不会消除完整模乘内部保留的那一拍输入寄存。

资源分别报告：`kernel` 是实现后 `u_kernel` 层次内的资源；`bench` 是含公共包装、valid 对齐逻辑的整个测试顶层。表中 FF 指 Slice Registers，不包含 DSP 内部寄存器。综合可将部分积寄存映射进 DSP，因此不能用 Slice FF 数直接反推全部流水寄存位数。

时序数字取包装顶层所有寄存器之间的路径，包含包装入口/出口与核之间的路径。OOC 外部端口没有绑定板级引脚；脚本设置的输入/输出延迟都是 1 ns，不能据此宣称板级接口签核。当前没有完整 NTT/多项式乘法顶层集成或布局布线，也没有 Fmax 搜索。

## 源文件与流水结构

| 文件 | 作用 |
|---|---|
| `rtl/intmul_64x64_24x17.sv` | 原四拍整数乘法基线 |
| `rtl/intmul_64x64_csa2_experimental.sv` | 新两拍整数乘法候选 |
| `rtl/params_pkg.sv`、`rtl/wlmont_round16.sv`、`rtl/mont_mul_wl.sv` | 固定参数、共享约减、原 14 拍完整模乘 |
| `sim/mont_mul_wl_csa12_experimental.sv` | 仅替换整数乘法部分的 12 拍完整模乘候选 |
| `sim/wl_csa_bench_top.sv` | 四组测试共同的寄存输入输出边界 |
| `sim/tb_wl_csa_latency.sv` | 独立参考模型、逐拍 valid 与复位检查 |
| `scripts/run_wl_csa_experiment.py`、`scripts/run_wl_csa_bench.tcl` | Questa 与四组 Vivado 执行、结果汇总 |

两拍候选保留原有 12 个 24×17 DSP 分块及 `use_dsp="yes"`。第一拍寄存部分积；第二拍经过五级 3:2 CSA（`12→8→6→4→3→2`，共十个压缩器）与最终 CPA 后寄存乘积。CSA 宽度为 132 位，最终加法为 133 位，先扩展部分积再移位，最后取数学上完整的低 128 位结果。

完整模乘的比较是：

```text
原版：输入寄存 1 + 整数乘法 4 + WL 约减 8 + 最终校正 1 = 14 拍
候选：输入寄存 1 + 整数乘法 2 + WL 约减 8 + 最终校正 1 = 12 拍
```

## Questa 正确性与延迟

独立测试台已通过，实际发出 28,227 笔有效输入，运行 29,515 拍。参考值采用完整整数乘法和单次 64 位 Montgomery REDC，不使用原实现输出作为候选的 golden。刺激包含边界组合、全部 64×64 个单比特输入组合、随机连续输入、气泡、流水中复位及复位后恢复。既有测试台和 golden 未改动。

| 被测核 | 延迟 / 拍 | 检查通过 | 复位丢弃 | 两者之和 |
|---|---:|---:|---:|---:|
| 原整数乘法 | 4 | 28,224 | 3 | 28,227 |
| CSA 整数乘法 | 2 | 28,226 | 1 | 28,227 |
| 原完整模乘 | 14 | 28,217 | 10 | 28,227 |
| CSA 完整模乘 | 12 | 28,217 | 10 | 28,227 |

日志：本轮目录下 `sim/compile.log`、`sim/simulation.log` 与 `sim/transcript.log`。最终标记为 `tb_wl_csa_latency PASS integer_latency=4/2 mont_latency=14/12 II=1`。

## 已完成的布局布线结果

以下 WNS/WHS 均为共同包装边界内的寄存器间结果。

| 测试目录 | 核 | 核拍数 | kernel LUT / FF / DSP | bench LUT / FF / DSP | WNS / ns | WHS / ns | 状态 |
|---|---|---:|---|---|---:|---:|---|
| `kind0_impl0` | 原整数乘法 | 4 | 325 / 645 / 12 | 325 / 907 / 12 | +2.917 | +0.096 | 已完成 |
| `kind0_impl1` | CSA 整数乘法 | 2 | 549 / 128 / 12 | 549 / 388 / 12 | +1.928 | +0.155 | 已完成 |
| `kind1_impl0` | 原完整模乘 | 14 | 917 / 1557 / 12 | 917 / 1751 / 12 | +1.773 | +0.094 | 已完成 |
| `kind1_impl1` | CSA 完整模乘 | 12 | 1134 / 1039 / 12 | 1134 / 1233 / 12 | +1.953 | +0.094 | 已完成 |

两组整数乘法均使用 0 BRAM。与四拍基线相比，两拍候选的 kernel 增加 224 LUT、减少 517 Slice FF，DSP 仍为 12。其最差寄存器间路径由部分积 DSP 寄存器到乘积输出寄存器，数据延迟 4.665 ns，其中逻辑 2.399 ns、布线 2.266 ns；路径包含 21 个 CARRY4。该实现证明两拍整数乘法在本次测量条件下满足 150 MHz 寄存器间时序，同时付出了更多 LUT 和较小 setup 裕量的代价。

依据为各测试目录中的 `kernel_route_utilization.rpt`、`route_utilization.rpt`、`internal_paths.rpt` 和 `hold_paths.rpt`；`timing.csv` 是已完成组的增量记录。四组完整结果已写入 `comparison.csv` / `comparison.json`。完整模乘的 12 拍延迟和 II=1 已经仿真验证；这些模块实验结果尚不能替代 NTT/多项式乘法系统顶层结果。

## 完整模乘结论与 Slice 口径

完整模乘由 14 拍降到 12 拍，按本次 6.667 ns 时钟周期换算为 93.338 ns → 80.004 ns，单次模块延迟减少 14.29%，II 保持 1。DSP 保持 12；kernel LUT 增加 217（23.66%），Slice FF 减少 518（33.27%）。这体现了延迟、组合逻辑和寄存器之间的取舍，不能概括为所有资源都减少。

两组完整模乘的最差寄存器间路径仍在后端融合约减：从第三轮的输出到第四轮修正数寄存器。原版数据路径延迟 4.410 ns，候选 4.230 ns；本次两组 setup 裕量相差 0.180 ns，可能受到布局布线差异影响，不能据此宣称算法必然提高 Fmax。

| 核 | kernel 所触及的 Slice | 整个 bench 的 Slice |
|---|---:|---:|
| 原四拍整数乘法 | 146 | 218 |
| 两拍 CSA 整数乘法 | 169 | 182 |
| 原 14 拍完整模乘 | 408 | 454 |
| 12 拍完整模乘 | 398 | 418 |

层次之间可能共享一个物理 Slice，因此 kernel 与包装的 Slice 不能直接相加或相减。整数乘法的 kernel Slice 增加，但整个 bench Slice 减少，说明包装寄存器的放置和共享会影响结果，不能只选下降的口径称为核面积降低。

完整模乘在本次布局中，kernel 所触及的 Slice 减少约 2.45%，整个 bench 减少约 7.93%。这些是此测量边界下的物理占用，不代表完整双核系统面积或跨器件的标准单元面积。

当前结论：两拍整数乘法可替代原四拍实现作为低延迟候选；保留入口寄存的完整模乘可做到 12 拍并通过本次模块时序。下一步应在独立配置中同步调整蝶形旁路和顶层标签，验证完整 NTT 集成；生产配置本轮保持不变。进一步到 11 拍需要单独解决入口与蝶形之间的寄存边界。CSA 结构来自已有方法，本轮属于实现基线改进。
## 全路径保持时间限制

四组寄存器间 setup/hold 均满足约束，但包含外部接口的全路径 hold 并未通过。报告观察到外部输入到公共入口寄存器的保持时间违例：

| 测试目录 | 全路径 WNS / ns | 全路径 WHS / ns | hold 违例端点数 |
|---|---:|---:|---:|
| kind0_impl0 | +2.917 | -0.184 | 129 |
| kind0_impl1 | +1.928 | -0.195 | 129 |
| kind1_impl0 | +1.773 | -0.012 | 32 |
| kind1_impl1 | +1.918 | -0.195 | 129 |

例如原 14 拍完整模乘最差 hold 是外部 a[23] 到公共 a_r[23]，12 拍版本是 a[0] 到公共 a_r[0]。这是当前 OOC 外部时钟/输入延迟模型下实际存在的违例；本轮没有改约束消除或屏蔽它们。因此，“通过150 MHz”在本报告中仅指共同包装内的寄存器间时序，不能扩展为整个OOC所有路径通过，更不能视为系统/板级接口签核。

四组均没有未约束内部端点，未约束路径表为空；DRC 无 Error/Critical，只有配置电压和DSP流水相关警告。进入真实顶层后，需要按实际数据驱动与时钟路径重新检查接口setup/hold。
## 快照与重跑

本次输入源文件 SHA256 清单：

```text
D:/MDC-NTT/reports/wl_lowcost_modmul/csa_latency/20260914_220510/metadata.json
```

基线和候选的源码快照：

```text
D:/MDC-NTT/reports/wl_lowcost_modmul/csa_latency/20260914_220510/source_snapshot/
```

其中包括 `source_snapshot/rtl/intmul_64x64_24x17.sv` 与 `source_snapshot/rtl/mont_mul_wl.sv` 两个生产基线，以及候选和本轮 Tcl。实验脚本已完成前后 9 个源文件 SHA256 比对，`source_unchanged_during_run=true`。运行开始于 22:05:10，结束于 22:34:31，包含仿真和四组综合布线；这不是硬件运算延迟。后续仅扩充了汇总器的 Slice 统计，没有改变 HDL 或重新运行实现。

在 PowerShell 中重跑仿真和四组实现：

```powershell
python D:/MDC-NTT/scripts/run_wl_csa_experiment.py
```

只重跑仿真：

```powershell
python D:/MDC-NTT/scripts/run_wl_csa_experiment.py --sim-only
```

四组结果齐全后重新生成本轮汇总：

```powershell
python D:/MDC-NTT/scripts/run_wl_csa_experiment.py --collect D:/MDC-NTT/reports/wl_lowcost_modmul/csa_latency/20260914_220510
```

脚本默认运行当前工作区源码并建立新的时间戳目录。复现本次输入时，应先对照本轮 `metadata.json` 的 hash 和 `source_snapshot`；不要将后来变更的源码运行误记为同一基线。
