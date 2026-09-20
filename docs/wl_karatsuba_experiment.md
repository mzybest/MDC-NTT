# 14 拍 Karatsuba 模乘实验

后续的 160/170/180 MHz 物理提频实验另见 [提频实验记录](D:/MDC-NTT/docs/wl_karatsuba_frequency_experiment.md)，本页保留 2026-09-15 的原始 150 MHz 对照结果。

日期：2026-09-15。单元实验、整机 RTL 回归和整机布局布线均已完成。只在独立快照中替换 22 个核内模乘前端，外围四路保留原完整 64 位前端。生产默认、旧测试及原始黄金文件保持原样。

**结论：完整乘法仍为 8623 拍，14 拍模乘、II=1 和 150 MHz 目标下的内部时序均保持。整机 DSP 减少 21.15%、FF 减少 12.22%，占用 Slice 减少 0.60%（基本持平）；LUT 增加 4.72%，BRAM 不变。** 这条路线适合继续作为保持吞吐率的低 DSP 实现。LUT 代价、固定模数适用范围和时序余量应与收益一起呈现。Karatsuba 是已有方法，论文创新性仍需另行论证。

## 最终整机结果

同器件、同配置、同工具和实现策略，引用经源文件及实际命令核对一致的前次 14 拍基线。以下均为布局布线后的完整顶层数据。

| 指标 | 原 14 拍融合版 | 核内 Karatsuba 14 拍版 | 变化 |
|---|---:|---:|---:|
| DSP | 312 | 246 | -21.15% |
| LUT | 54,111 | 56,664 | +4.72% |
| FF | 49,713 | 43,637 | -12.22% |
| 占用 Slice | 17,887 | 17,779 | -0.60% |
| BRAM36 | 59 | 59 | 不变 |
| 完整模乘延迟 / II | 14 / 1 拍 | 14 / 1 拍 | 不变 |
| 完整乘法计算周期 | 8,623 | 8,623 | 不变 |
| 连续装载加计算 | 12,719 | 12,719 | 不变；均不含结果读回 |
| 内部 WNS，ns | +0.549 | +0.414 | 均通过，候选建立余量减少 0.135 ns |
| 内部 WHS，ns | +0.019 | +0.040 | 均通过 |

6.667 ns 时钟下计算延迟约 57.49 μs；该数值由已验证周期与约束周期相乘，不是上板计时。未进行 Fmax 搜索，不将 WNS 转换成已实测最高频率。

候选最差路径为 CoreA 的 g_stage_r_11 寄存器到 Stage2 sum_delay 的 data_pipe 寄存器。数据路径 6.328 ns，其中布线 5.966 ns（94.279%），扇出 705，仅经过一级 LUT2；没有经过新整数乘法前端。此处只记录综合网表路径，尚未把该寄存器精确回溯命名为某个 RTL reset/valid 信号。当前目标频率已经满足；若下一轮追求更高频率，应先查这条高扇出路径，而不能假定乘法器加法链是整机瓶颈。

完整布线、受约束的建立/保持时间检查、内部未约束端点检查均通过。源文件及不可变快照哈希与运行前一致。仍有 132 个输入、68 个输出缺少板级延迟约束，以及 NSTD/UCIO、CFGBVS 和 DSP 寄存器配置警告；这里没有宣称板级时序签核、功耗或上板验证。

严格最终审计共 163 项，唯一失败是保留的原综合目录错误，其他 162 项通过、无缺失证据。针对同一错误与同一检查点的单独复核通过 323 项证据检查，记录为 accepted_with_recorded_synthesis_console_error，并明确 strict_audit_pass=false；原严格审计没有被覆写。异常及独立重开的证据见后文。

- [完整整机测量 JSON](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/comparison.json)
- [最终资源报告](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/candidate/impl/utilization.rpt)
- [最终内部时序](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/candidate/impl/internal_timing.csv)
- [原严格审计](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/final_audit.json)
- [保留原错误的最终独立复核](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/reviewed_final_audit.json)


## 实测单元结果

器件 xc7vx485tffg1761-2，Vivado 2026.1，6.667 ns 时钟；四个案例均重新综合和布局布线。下表资源是 u_kernel 层级，WNS/WHS 是整个公共测试包装内的寄存器间路径，包含包装与内核边界，不能称为只测内核内部路径。

| 实例 | 整数拍数 / 完整模乘拍数 | DSP | LUT | FF | 占用 Slice | 寄存器间 WNS / WHS，ns |
|---|---:|---:|---:|---:|---:|---:|
| 原整数核 | 4 / — | 12 | 325 | 645 | 150 | +2.691 / +0.086 |
| Karatsuba 整数核 | 4 / — | 9 | 465 | 301 | 153 | +2.716 / +0.082 |
| 原融合约减模乘 | 4 / 14 | 12 | 917 | 1,557 | 409 | +1.534 / +0.094 |
| Karatsuba + 同一融合约减 | 4 / 14 | 9 | 1,042 | 1,278 | 437 | +1.794 / +0.076 |

两版都使用相同的 60 位外部操作数：原 64 位整数核输入高四位接零，新整数核接完整 60 位。两版有相同输入、输出寄存包装，统一额外增加两拍，未计入表中内核延迟。这样避免把单纯收窄输入端口产生的优化误称为 Karatsuba 收益。

公共包装总资源依次为：

| 实例 | LUT | FF | DSP | 占用 Slice |
|---|---:|---:|---:|---:|
| 原整数核包装 | 325 | 899 | 12 | 215 |
| Karatsuba 整数核包装 | 465 | 547 | 9 | 195 |
| 原完整模乘包装 | 917 | 1,743 | 12 | 444 |
| Karatsuba 完整模乘包装 | 1,043 | 1,464 | 9 | 467 |

层级 LUT 可能共享，Slice 存在合并放置，不能用父子层级的 Slice 相减来计算精确包装面积。FF 指 Slice Registers，不包括 DSP 内部寄存器；本实验没有测量总晶体管面积或功耗。

两种完整模乘的最差寄存器间路径都位于融合约减轮次之间，目的端是 correction_s1 的复位端。单元时序通过并不意味着整机一定通过；两次 WNS 差异也不是 Fmax 测量。

## 正确性与限制

独立参考使用直接整数乘法和单次 64 位 Montgomery REDC 计算。每版检查 28,107 个整数乘法结果、28,097 个完整模乘结果，包含 576 个边界配对、3,600 个单比特配对、20,000 个连续随机输入、插空及流水中复位。整数核覆盖全部 60 位数值范围，并实际覆盖 155 个大于等于 Q 的整数输入；完整模乘输入按规范范围生成。仿真确认整数 4 拍、完整模乘 14 拍及 II=1。复位丢弃的在途事务单独计数，未当作已检查结果。

模数 Q=0x0fffffffffffc001，约 60 位；接口保持 64 位，Montgomery 基数仍是 R=2^64。前端输出完整 120 位积，再补零送入原四轮 16 位约减。整数前端拆为两层 Karatsuba，共五个 15×15、三个 16×16、一个 17×17 叶乘法。四拍分别为操作数预加寄存、叶乘法寄存、三个子积重构和最终重构。

所有案例内部无未约束端点、无布线错误。外部端口采用相同 1 ns 输入/输出延迟，但 OOC 端口没有 HD.PARTPIN_LOCS，Vivado 明确提示其外部时序不准确。四例全路径 WHS 分别为 −0.193、−0.194、−0.046、−0.253 ns，对应 121、121、49、121 个保持时间失败端点；不能把寄存器间通过写成全路径或板级时序签核通过。未进行板级约束、Fmax 搜索或功耗测量。

## 整机集成方法

只在实验快照中将 gs_butterfly 的两个模乘选择位置切至独立 core-only selector。当前最终单位旋转旁路及 Post 融合归一化配置下，两核各有 11 个实际模乘，共 22 个。四路外围池继续使用原完整 64 位整数前端；不改变 MUL_LAT=14、FIFO、调度、Pre/Post 因子、点乘或 C 的存储与重排。

核心输入必须是已知且小于 Q 的规范数；候选在有效拍检查该条件及输出范围。完整宽度 Pre 的系数 a<R、因子 b<Q，保证 ab<QR，经过原约减和一次修正后输出小于 Q，因此再进入 60 位核心是安全的。已用全 64 位 A 输入与 Montgomery 单位多项式相乘，检查全部结果逐项等于 a mod Q；2^60 输入实际得到 16383，未被截断成零。

原先的 DSP 结构预算 22×9+4×12=246 已由综合和布线报告确认；整机计算周期实测仍为 8623。本次前端优化没有消除点乘与 INTT 之间的等待。

## 可复核文件

- [单元测量 JSON](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba4/20260915_113434/comparison.json)
- [单元仿真记录](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba4/20260915_113434/simulation.json)
- [单元源文件与运行完整性记录](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba4/20260915_113434/metadata.json)
- [新整数核](D:/MDC-NTT/rtl/intmul_60x60_karatsuba4_experimental.sv)
- [新完整模乘包装](D:/MDC-NTT/sim/mont_mul_wl_karatsuba14_experimental.sv)
- [单元运行脚本](D:/MDC-NTT/scripts/run_wl_karatsuba_experiment.py)
- [数学与输入范围推导](D:/MDC-NTT/docs/wl_karatsuba_feasibility.md)

## 整机回归与综合结果

运行目录为 reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811。引用前次 csa_full_top/20260914_230139/lat14 基线，未重新跑基线；23 个实际生产 RTL 和 37 个不可变 mem 与当前文件及旧快照清单全部一致。Vivado 2026.1、15 个综合参数、7 条实现命令，以及 6.4 ns 实现、6.667 ns 最终检查条件均匹配。

8 项整机回归全部通过：原外围模乘、普通蝶形、单位旋转旁路蝶形、NTT 核、NTT/INTT 往返、仅 Forward 核、含新增范围检查的完整乘法、未修改的原自然序完整乘法测试。新范围用例包含 3,831 个 A 系数使用高四位，4096 个结果全部正确，2^60 输入实际输出 16383。此用例验证固定 Q 下 A 的全 64 位输入规范化；它不是任意 64 位模数测试。

完整乘法的四组用例均为 8623 计算拍；连续加载加计算为 12719 拍，结果读回另计。PW 输出 2271..4318、INTT 输入 4319..6366、INTT 输出 6561..8608、Post 输出 6575..8622，与基线完全一致。

| 综合资源 | 前次 14 拍融合基线 | 当前核心 Karatsuba 候选 | 变化 |
|---|---:|---:|---:|
| LUT | 55,576 | 57,964 | +4.30% |
| FF | 48,902 | 43,466 | −11.12% |
| DSP | 312 | 246 | −21.15% |
| BRAM36 | 59 | 59 | 0 |

综合层级确认 CoreA/CoreB 各 stage0..10 使用 11 个新整数前端，每核 99 DSP；外围四个原整数前端合计 48 DSP，其他 DSP 为零、黑盒为零。外围池仍为 8025 LUT、6191 FF，其他顶层资源也未变化；综合 LUT/FF 差异来自两个核心。

本次综合控制台第 998 行出现“ERROR: [Common 17-1257] Failed to create directory 'C'.”，主 Vivado 日志没有 ERROR，Vivado 以 0 退出并保存完整检查点。原严格脚本仍因此停止，不能称为无错误运行。错误来源未确定，进程私有 TEMP/TMP 未阻止它出现。

随后对这一个检查点执行独立验证：ZIP 全体条目 CRC 通过；新 Vivado 进程重新打开；器件、唯一时钟 6.667 ns、黑盒检查及 22+4 前端归属正确；LUT、FF、DSP、BRAM 与原综合报告完全一致；重开日志没有新错误，检查点哈希未改变。原失败 metadata、两份日志、验证脚本、检查点和复核记录均保留并绑定哈希。只有完成该验证后才继续原实现流程，没有弱化通用错误检查规则。

- [整机回归结果](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/candidate/simulation.json)
- [综合资源](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/candidate/synth/utilization.rpt)
- [综合实例归属](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/candidate/synth/isolation_audit.txt)
- [检查点独立验证记录](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/candidate/checkpoint_audit/review.json)
- [快照修改明细](D:/MDC-NTT/reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811/candidate/snapshot_changes.patch)
