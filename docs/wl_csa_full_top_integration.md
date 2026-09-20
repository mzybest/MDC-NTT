# 12 拍 CSA 模乘器完整双核集成实验

实验于 2026-09-14 启动，2026-09-15 完成。两组 Questa 回归、完整顶层 Vivado 综合及布局布线均已完成；最终源文件与快照审计通过。生产默认仍为 14 拍，12 拍修改保存在独立实验快照中。

**结论：12 拍是可用的低寄存器候选，但本轮没有实现整体面积下降或显著整机加速。** 相比 14 拍融合约减版，12 拍减少 28.67% FF，同时增加 10.53% LUT；Slice 基本持平，增加 0.45%。DSP、BRAM 不变，完整计算仅减少 58 拍（0.67%）。两版均满足本次约 150 MHz 的内部 setup/hold 约束。

针对当前“降低资源成本”的目标，建议暂留 14 拍融合版为主线，保留 12 拍候选供 FF 更紧张的配置使用；下一轮优先验证减少整数乘法 DSP 的候选。本次实现不能将“模乘少两拍”写成整体面积和速度突破。

## 同条件完整顶层布局布线结果

| 指标 | 14 拍融合基线 | 12 拍 CSA + 同一融合约减 | 12 拍相对变化 |
|---|---:|---:|---:|
| LUT | 54,111 | 59,809 | +5,698（+10.53%） |
| Slice FF | 49,713 | 35,458 | −14,255（−28.67%） |
| 实际占用 Slice | 17,887 | 17,968 | +81（+0.45%） |
| DSP48E1 | 312 | 312 | 0 |
| RAMB36 | 59 | 59 | 0 |
| RAMB18 | 0 | 0 | 0 |
| 内部 WNS / ns，6.667 ns 时钟 | +0.549 | +0.363 | −0.186 ns |
| 内部 WHS / ns | +0.019 | +0.014 | −0.005 ns |
| setup / hold 违例端点 | 0 / 0 | 0 / 0 | 均满足 |
| 未约束内部端点 | 0 | 0 | 0 |
| 可布线网络 / 已全部布通 | 93,238 / 是 | 92,945 / 是 | 布线错误均为 0 |
| 完整乘法 compute / 拍 | 8,623 | 8,565 | −58（−0.67%） |
| 连续自然顺序装载 + compute / 拍 | 12,719 | 12,661 | −58（−0.46%） |

按相同 6.667 ns 周期换算，compute 为 57.490 → 57.103 微秒，减少约 0.387 微秒。装载加计算不包含结果读回；不能将这些数字当成包含全部主机传输的应用延迟。模乘 II=1，也不代表完整多项式乘法可以每拍接受新任务。

LUT、FF、Slice 分别反映不同资源占用，不能只选 FF 下降来宣称面积全面下降。两组同器件、DSP/BRAM 相同条件下，辅助指标 Slice×compute 仅减少约 0.22%；每版只运行了一次本配置实现，未进行多种布局结果的统计，不能用这一微小差异主张稳定的架构优势。

依据：本轮 lat14/impl 与 lat12/impl 中的 utilization.rpt、timing.rpt、internal_timing.csv、route_status.rpt；汇总见 [comparison.csv](/D:/MDC-NTT/reports/wl_lowcost_modmul/csa_full_top/20260914_230139/comparison.csv)。

## 固定条件与改动范围

| 条件 | 两组共同设置 |
|---|---|
| 顶层 / 配置 | poly_mul_top_dual_forward / natural_ab_raw_pre_shared |
| 点数与接口 | N=4096，LOGN=12，64 位接口，2-path |
| 模数 / Montgomery 基数 | Q=0x0fffffffffffc001=2^60−2^14+1；R=2^64 |
| 工具 / 器件 | Vivado 2026.1 / xc7vx485tffg1761-2 |
| 约减 | REDUCTION_IMPL=2，四轮各两拍，末端校正一拍 |
| 架构 | CoreA 复用 NTT/INTT，CoreB 仅 Forward；四路共享外围模乘池 |
| 其他配置 | 自然序装载、A/C BRAM 生命周期复用、Post 融合缩放、末级单位旋转旁路、局部 twiddle、蝶形边界寄存器均相同 |
| 实现 | 4 线程；6.400 ns 进行优化/布局/布线；最终恢复 6.667 ns 报告 |

此处是 64 位接口、固定 60 位素数实验，不代表任意 64 位模数能力。输入输出沿用原始 Montgomery 表示，未改变 Pre/Post、旋转因子、重排或缓存结构。

原整数乘法四拍，CSA 候选两拍，均使用 12 个 DSP：

    14 拍 = 入口寄存 1 + 整数乘法 4 + WL 约减 8 + 最终校正 1
    12 拍 = 入口寄存 1 + 整数乘法 2 + WL 约减 8 + 最终校正 1

12 拍快照仅修改 7 个 RTL 文件：params_pkg、mont_mul_wl、poly_mul_top_dual_forward，以及 gs_butterfly、mdc_stage、gs_mdc_core、gs_mdc_core_ntt_only 的默认延迟参数。前端换成 intmul_64x64_csa2_experimental，同步调整旁路、valid 与地址标签的延迟依赖。原生产 RTL、本轮运行前的原测试和 golden 均未改变。

沿用原实现流程：综合后建立 6.667 ns 时钟；实现阶段使用 6.400 ns，opt Explore、place AltSpreadLogic_medium、既定 phys_opt 与两轮 MoreGlobalIterations 布线，再恢复报告时钟。没有通过改约束来只放宽候选。

## 综合资源及归属

| 同阶段综合指标 | 14 拍 | 12 拍 |
|---|---:|---:|
| LUT | 55,576 | 61,556 |
| FF | 48,902 | 35,502 |
| DSP / RAMB36 | 312 / 59 | 312 / 59 |

综合阶段 LUT 增量为 5,980：CoreA +2,530、CoreB +2,530、共享池 +920；其余顶层均为 12,044 LUT。综合与布线后计数分开记录，不能混用为同一阶段比较。

26 个实际模乘分别为 CoreA 11 个、CoreB 11 个、外围池 4 个；两组均为 26×12=312 DSP。59 BRAM36 为 A/B/C 共享银行 16、MDC FIFO 20、旋转因子 ROM 23。CSA 没有消除 C_NTT 缓存或重排。

此前融合约减相对历史 20 DSP/模乘的资源节省，与本轮 CSA 改写是不同变化。历史顶层 520 DSP 不作为本轮受控 14/12 拍差值的基线。

## 独立周期推导与功能验证

令 L 为模乘拍数，P=N/2。当前两核各保留一个蝶形边界周期：

    核心首输出 C = (P−1) + LOGN×(L+1) + 1 + L
                 = 2060 + 13L
    compute = 2C + 3L + 2P + 1
            = 8217 + 29L

运行前推导得到 8623 / 8565，仿真均严格匹配。14 拍时随 L 变化的部分为 406 拍，占总 compute 的 4.71%，解释了只压缩模乘流水的整机收益有限；这不表示 L=0 是可实现硬件。

| 相对 compute_start 的窗口 | 14 拍实测 | 12 拍实测 |
|---|---:|---:|
| Pre 输入 | 1..2048 | 1..2048 |
| Forward 输入 | 15..2062 | 13..2060 |
| Forward 输出 | 2257..4304 | 2229..4276 |
| 点乘输出 / C_NTT 写入 | 2271..4318 | 2241..4288 |
| INTT 输入 | 4319..6366 | 4289..6336 |
| INTT 输出 | 6561..8608 | 6505..8552 |
| Post 结果 | 6575..8622 | 6517..8564 |
| done | 8623 | 8565 |

各数据窗口均为 2048 对。核心首输入至首输出为 2242 / 2216 拍；带气泡装载均为 5422 拍，装载加 compute 为 14045 / 13987。点乘到逆变换仍保留完整帧的生产/消费边界。

14 拍 8 项、12 拍 7 项测试全部通过：独立数学参考的 WL 模乘及 valid，蝶形普通/单位旁路，4096 点 NTT，同核 NTT→INTT 往返，Forward-only 与统一核逐拍同步，以及自然序完整乘法。14 拍额外原样运行原 natural_ab 测试以交叉核对新周期模型。

完整乘法覆盖连续随机输入、同组随机输入带装载气泡、定向负循环卷积及硬件重复使用。每组检查全部 4096 个输出、原 golden、存储映射、各阶段首末周期和数量。定向例 a=x^(N−1)、b=x，逻辑输出 c[0]=Q−1，其余为零。

## 最差路径和时序边界

14 拍最差 setup 是共享池 u_mul0 的 y_reg[31] 到结果 LUTRAM 写端；数据延迟 5.377 ns，其中布线 5.154 ns（95.9%）。

12 拍最差 setup 是 CoreA 的 g_stage_r_9 到第 6 级 sum_delay 寄存器输入；数据延迟 6.192 ns，其中布线 5.890 ns（95.1%）。报告第 47 行显示该网络扇出为 705，随后仅经过一级 LUT2，最差路径没有穿过 CSA 或模乘算术。这里保留综合网名，不单凭重命名判断其精确信号来源。

本次两版最差路径均主要受布线影响，不能根据独立模乘模块的裕量直接推断整机 Fmax。最终两版内部建立、保持时间均满足 6.667 ns，但未做 Fmax 搜索、功耗测量或板级接口签核。

两版均有 132 个输入、68 个输出缺少 IO delay；全部 213 个逻辑端口未指定引脚和 IO 标准，DRC 保留 NSTD-1、UCIO-1 两项 Critical Warning，以及 CFGBVS 和 DSP 流水相关 Warning。没有降低这些规则的严重性，没有生成板级 bitstream。内部时序通过不能写成所有接口已签核。

## 控制台异常与独立检查点审计

两组综合均返回 exit 0、主 vivado.log 记录成功并生成 DCP，但合并控制台出现来源未定位的路径错误：14 拍两条 Common 17-354（无法写入 C），12 拍一条 Common 17-1257（无法创建目录 C）。严格批处理分别停止，未直接忽略错误文本。

两组控制台与主日志的相关差异均位于 Part Resource Summary 后、Cross Boundary and Area Optimization 前；主日志对应行为 No constraint files found.，没有这些 ERROR。当前没有确定错误来源进程或触发代码；不能归因于临时目录、中文用户名或多线程。12 拍使用进程专用 ASCII TEMP/TMP 后仍发生异常。

每组均完成 DCP 压缩成员 CRC 检查，并在新的 Vivado 进程中独立重开，确认器件、6.667 ns 时钟、黑盒为 0、黑盒 DRC 和完整 LUT/FF/DSP/BRAM 计数一致后，才从原检查点继续布局布线。没有重跑或改写原 RTL、参考结果，也没有放宽原始全局 ERROR 检查。

证据分别保存在 lat14/checkpoint_audit、lat12/checkpoint_audit。两个恢复脚本和最终审计脚本归档于本轮 control_source。最终 [final_audit.json](/D:/MDC-NTT/reports/wl_lowcost_modmul/csa_full_top/20260914_230139/final_audit.json) 确认生产源文件、快照 RTL/TB/golden 未改变，测试通过、布线错误为 0、内部 setup/hold 通过；metadata.json 保存前后源文件 SHA256。

## 下一轮建议与复现入口

优先验证只替换 22 个核心整数乘法前端的 Karatsuba 候选，四路外围池保留完整 64 位处理能力。当前固定模数下，规范核心输入为 60 位；若每个候选最终映射为 9 DSP，则预算为 22×9+4×12=246 DSP，比 312 少 66（21.15%）。这是未完成 RTL/Vivado 验证的预算；LUT、FF、实际 Slice、时序和完整功能必须同时比较。Karatsuba 是已有方法，不能据此直接宣称论文创新。

先保持完整模乘 14 拍，可避免再次调整全局调度；若要进一步降低拍数，再作为独立变量评估。位宽、范围、外围保留方案和越界输入反例见 [wl_karatsuba_feasibility.md](/D:/MDC-NTT/docs/wl_karatsuba_feasibility.md)。

本轮运行目录：[20260914_230139](/D:/MDC-NTT/reports/wl_lowcost_modmul/csa_full_top/20260914_230139)。主脚本为 [run_wl_csa_full_top.py](/D:/MDC-NTT/scripts/run_wl_csa_full_top.py)、[run_wl_csa_full_top.tcl](/D:/MDC-NTT/scripts/run_wl_csa_full_top.tcl)。每版保留快照、差异补丁、SHA256、仿真日志、综合/布局/布线 DCP 与报告。

使用当前源码创建新的时间戳实验：

    python D:/MDC-NTT/scripts/run_wl_csa_full_top.py --phase all

只重新汇总本轮已有报告，不修改原始运行元数据：

    python D:/MDC-NTT/reports/wl_lowcost_modmul/csa_full_top/20260914_230139/control_source/collect_existing_results.py

复现历史输入时应使用本轮 snapshot、control_source 和哈希清单，不能将后来变化的工作区源码误记为本次基线。上述原脚本仍保留严格错误检查；若出现其他错误，需独立判断，不能自动套用本次例外。