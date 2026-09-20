# Karatsuba 双核版本的物理提频实验

日期：2026-09-17。器件 xc7vx485tffg1761-2，Vivado 2026.1。

最终结果：160、170、180 MHz 三个频点的内部时序、完整布线、检查点完整性和结果审计均已通过。180 MHz 为本轮最高已通过测试频点，不是已测出的全局 Fmax。相对原 150 MHz 候选，180 MHz 的计算时间约减少 16.7%，DSP 和 BRAM 不变，占用 Slice 增加约 1.03%。

本轮按“先验证 160 MHz，再处理高扇出并尝试 170/180 MHz”执行。沿用 20260915_115811 的已验证 Karatsuba 双核候选，未实施 4-path，未改变 RTL、数据顺序、模乘流水、C_NTT 缓存、Pre/Post 或测试黄金数据。完整模乘仍为 14 拍、II=1；完整计算的 8623 拍继承自相同 RTL 的既有回归，本轮没有重复运行 RTL 仿真，也没有上板计时。

## 已完成的结果

| 目标频率 | 实现方式 | 最终内部 WNS / WHS，ns | LUT | FF | Slice | DSP / BRAM36 | 内部验收 |
|---|---|---:|---:|---:|---:|---:|---|
| 150 MHz | 原候选检查点 | +0.414 / +0.040 | 56664 | 43637 | 17779 | 246 / 59 | 原已通过结果 |
| 160 MHz | 原布线上的物理优化 | +0.182 / +0.005 | 56664 | 43637 | 17779 | 246 / 59 | 通过 |
| 170 MHz | 布线前复制驱动，再布线和物理优化 | +0.160 / +0.043 | 56664 | 43646 | 17780 | 246 / 59 | 通过 |
| 180 MHz | 定向复制、进一步物理优化及独立布线 | +0.161 / +0.036 | 56734 | 44612 | 17962 | 246 / 59 | 通过 |

按照标称频率计算，8623 拍在 150/160/170 MHz 下分别约为 57.49/53.89/50.72 μs，不包含输入装载与结果读回。170 MHz 相对 150 MHz 频率提高约 13.3%，计算时间减少约 11.8%。170 MHz 的实际约束周期为 5.882 ns，来自工具的 1 ps 精度取整；报告同时保留标称频点和实际周期。180 MHz 使用 5.556 ns 约束，8623 拍对应 47.909388 μs，约 47.91 μs；相对标称 150 MHz，频率提高约 20%，计算时间减少约 16.7%。这些是基于周期数的计算值，不是上板计时。

180 MHz 相对原 Karatsuba 150 MHz 的资源变化为：LUT +70（约 0.12%）、Slice FF +975（约 2.23%）、占用 Slice +183（约 1.03%）；DSP 仍为 246，BRAM36 仍为 59。170 MHz 则只增加 9 个 FF 和 1 个 Slice，可作为资源代价更小的备选。180 MHz 的 FF 增量不只来自原控制驱动的 9 个副本，还包括地址驱动复制和工具将部分 DSP 内部寄存器移到 Slice FF；寄存器位置变化不等于新增流水拍。资源统计中的 FF 是 Slice Registers，不包含 DSP 内部寄存器。

## 原瓶颈与优化依据

先对同一份原始已布线检查点更改时钟、重新分析，其他设计内容不变。150/160/170/180 MHz 的 WNS 依次为 +0.414、−0.003、−0.371、−0.697 ns，WHS 均为 +0.040 ns。因此原布线在 160 MHz 差 3 ps，不能把此前根据余量推算的约 160 MHz 当成已通过的结果。

共同关键路径从 `u_core_a/g_stage_r_11` 到 CoreA Stage2 的 sum_delay 数据寄存器。路径数据延迟 6.328 ns，其中布线 5.966 ns，约 94.3%；时序报告的扇出为 705。

综合网表追踪确认：`g_stage_r` 的 D 接常数 1，随后依次移入 `g_stage_r_0` 至 `g_stage_r_11`；各级 CE 为常数 1，共同受 rst_n 派生的同步复位控制。它是一个复位后逐拍填充的控制链，输出被多个延迟数据门控共用。不能仅凭综合保留的 FILE_NAME 属性，把该寄存器解释为 mod_add 的算术寄存器；mod_add 原 RTL 本身是组合逻辑。

160 MHz 使用布线后 Explore 优化与路由清理。关键数据路径仍为 6.328 ns，时钟路径偏斜由 +0.045 ns 改善为 +0.230 ns，因而建立余量提高；这一轮不是缩短乘法器组合链，也没有减少原控制网的扇出。保持余量为 +0.005 ns，应和建立余量一起呈现。

170 MHz 从原先已布局、未布线的 `pre_route_physopt_oc.dcp` 开始，针对 `g_stage_r_11` 执行驱动复制，再完成 AggressiveExplore、完整布线及布线后优化。实际增加 9 个寄存器副本，连同原寄存器共 10 个驱动；705 个叶级输入引脚被划分为 64、1、92、144、116、94、66、18、46、64，最大单驱动负载为 144。它们处于同一个逻辑流水级，没有插入新流水拍。

170 MHz 最终最差路径已经转移：CoreA Stage0 FIFO 的 BRAM 输出 → Stage1 整数乘法前端的 DSP 输入。数据延迟 5.322 ns，其中逻辑 2.486 ns、布线 2.836 ns；路径包含 22 个 CARRY4 和两个 LUT。原高扇出控制路径不再是首要瓶颈，但不能因此推断任意更高频率都能通过。

180 MHz 最终最差路径从 CoreA Stage2 FIFO BRAM 到 Stage3 sum_delay 的 SRL 输入，数据延迟 5.243 ns，其中逻辑 2.349 ns（44.799%）、布线 2.894 ns（55.201%），包含 16 个 CARRY4 和两个 LUT。此时瓶颈已经位于 BRAM 读出到下一级蝶形数据通路，不能继续把原来的 705 扇出信号视为唯一问题。进一步提频需要另做这段路径的研究，本轮没有尝试 185/190/200 MHz，也不据正 WNS 宣称这些频点通过。

## 验证与限制

三个完成案例均检查了全部可布线网络、路由错误、内部建立/保持/脉宽违例端点、未约束内部端点、时钟检查、前后约束一致性、受保护输入文件哈希以及归档脚本哈希、检查点 ZIP CRC 和 DRC 错误分类。180 MHz 的 93600 个可布线网络全部完成，布线错误为零，内部建立/保持/脉宽失败端点均为零，未约束内部端点为零。结果和检查点均保留。没有添加假路径、多周期路径等例外，也没有降低验收要求。

工程仍有 132 个输入、68 个输出缺少外部延迟约束，板级 IO 标准和引脚约束未完成。本报告只认可内部静态时序，不宣称板级签核、实测功耗或全局 Fmax。模数仍为固定 60 位 Q=0x0fffffffffffc001、64 位接口，Montgomery R=2^64，不能推广为任意 64 位模数。

原基线综合日志中已复核的 `Failed to create directory 'C'` 错误继续保留，本轮没有重新综合或清除该记录。本轮两次未完成尝试也原样保留：第一次探查使用了不支持的 Tcl redirect 命令；第一次定向复制在布线后调用，被 Vivado 明确拒绝。随后修正探查脚本，并将定向复制移到未布线检查点上执行；未通过的尝试不作为成功测量值。

## 文件与复现

- [汇总与验收 JSON](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_frequency/20260917/summary.json)
- [原布线各频点复查](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_frequency/20260917/probe_retry/baseline_recheck.csv)
- [160 MHz 时序](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_frequency/20260917/inc160/timing.rpt)
- [170 MHz 时序](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_frequency/20260917/targeted170_retry/timing.rpt)
- [180 MHz 时序](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_frequency/20260917/targeted180/timing.rpt)
- [180 MHz 最终资源](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_frequency/20260917/targeted180/utilization.rpt)
- [180 MHz 最差内部路径](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_frequency/20260917/targeted180/internal_setup.rpt)
- [180 MHz 已布线检查点](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_frequency/20260917/targeted180/routed.dcp)
- [170 MHz 驱动复制记录](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_frequency/20260917/targeted170_retry/targeted_fanout.txt)
- [实验入口](D:/MDC-NTT/scripts/run_karatsuba_frequency.py)
- [实现流程](D:/MDC-NTT/scripts/implement_karatsuba_frequency.tcl)
- [定向复制与控制链追踪](D:/MDC-NTT/scripts/karatsuba_targeted_fanout.tcl)
- [结果审计](D:/MDC-NTT/scripts/audit_karatsuba_frequency.py)

在 D:\MDC-NTT 下运行入口脚本，指定 `impl --mhz 170 --strategy targeted --output reports/新的目录` 可复现实验流程；输出目录必须不存在。`incremental` 使用原已布线检查点，`targeted` 使用原已布局未布线检查点。每次运行保存其具体输入检查点、脚本版本、命令、哈希和日志；`source_scripts` 为该次源脚本的归档。旧生产实现脚本仍保持原配置，不会自动套用本轮提频流程。
