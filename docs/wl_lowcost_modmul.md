# 固定模数 WL 模乘器低成本实现

日期：2026-09-12。范围：当前生产 Q64 路径的模乘器；没有修改 NTT 数据顺序、Pre/Post、旋转因子、延迟 FIFO、C_NTT 缓冲或顶层调度。

## 实现与适用条件

当前 `Q = 0x0fffffffffffc001 = 2^60 - 2^14 + 1`，是 60 位模数、64 位接口。输入条件沿用原实现 `0 <= a,b < Q`，输出 `a*b*R^-1 mod Q`，`R=2^64`。

`mont_mul_wl.sv` 与 `wlmont_round16.sv` 新增 `REDUCTION_IMPL`：

| 参数 | 单轮实现 | 用途 |
|---|---|---|
| 0 | 原先的两个 DSP 常数乘法及低字进位 | 保留原始对照 |
| 1 | 合并 `m*(Q>>16)` 为短借位与拼接，保留独立低字进位 | 分离普通常数特化的收益 |
| 2（默认） | 把常数乘积与低字进位合成一项 correction | 当前候选实现 |

1/2 仅在 Q 等于上述固定模数时启用。其他低字仍为 `c001` 的 Q 静态选择原始分支；这不是任意 64 位模数支持，也未额外验证其他 Q。所有分支仍要求 `Q[15:0]=c001`。

顶层、`mont_mul_select` 没有增加参数；其 WL 实例自动使用 `mont_mul_wl` 的默认值。不能对现有顶层直接传 `-generic REDUCTION_IMPL=0`；该开关直接用于独立模乘器实验。恢复整个设计的原版可将 `mont_mul_wl` 的该参数默认值改回 0。

## 融合式的推导

设 `B=2^16`，`x=T mod B`。当前 `Q_low=B-2^14+1`，故 `Q_low^-1=(1+2^14) mod B`。

```text
m = -x*(1+2^14) mod B
Q_high = Q >> 16 = 2^44-1
T_next = (T >> 16) + m*Q_high + carry_low
```

由 `x = m*(2^14-1) mod B`，令

```text
d = floor(m*(2^14-1)/B)
m*(2^14-1) = d*B + x
carry_low = (x + m*Q_low)/B = m-d
```

得到精确恒等式：

```text
T_next = (T >> 16) + (m << 44) - d
```

对于16位 m，d 可用短比较和减法实现：

```text
d = (m >> 2) - [m > ((m & 3) << 14)]
0 <= d <= 16382
```

`correction=(m<<44)-d` 不使用60位减法器：d=0时直接拼接 m 和44个0；d非零时拼接 `(m-1)`、30个1、`~(d-1)`，长度为 `16+30+14=60` 位。

第一拍寄存 `T_high` 和 correction；第二拍只做 `T_high+correction`。普通移位版仍保留 `T_high+qh_product+carry_low` 三操作数。本次没有改变量整数乘法的12个 DSP 分块。

四轮仍各占两拍。完整流水保持：输入寄存1拍 + 整数乘法4拍 + 约减8拍 + 最终校正1拍 = 14拍，II=1。

## 正确性证据

新增独立自检台 `sim/tb_wlmont_lowcost.sv`，同时实例化三个单轮与三个完整模乘器。单轮参考直接计算130位 `(T+m*Q)>>16`；完整参考使用单次64位 REDC，未用原实现输出充当 golden。

- 五组113位高位模式，每组穷举65536个低字，另含reset前已完成事务：327687个单轮结果，三个实现均一致。
- 7388个有效完整模乘结果，包括12×12边界值、`(Q-1,Q-1)`、连续II=1、气泡、流水中复位和恢复。
- 检查单轮2拍与完整模乘14拍 valid 对齐；复位正确丢弃1个单轮和8个模乘未完成事务。
- PASS 日志：`reports/wl_lowcost_modmul/tests/sim_lowcost.log`。

已有回归通过 `scripts/run_wl_lowcost_regression.py` 运行，不重新生成输入文件，不修改原测试台和 golden。完整状态与顶层拍数见下方最终结果。

## Vivado 对照口径

脚本：`scripts/run_wl_lowcost_compare.tcl`。同一 Vivado 2026.1、`xc7vx485tffg1761-2`、6.667ns时钟，输入/输出延迟均为1ns。分别对实现0/1/2做独立 OOC 综合、优化、布局和布线。

OOC的外部端口未绑定物理位置，Vivado会报告 `Route 35-198`。汇总WNS可能由外部复位端口主导，不能据此判断算术流水的速度。脚本 `scripts/report_wl_lowcost_internal_timing.tcl` 从已布线checkpoint额外提取寄存器到寄存器路径；本文用该内部路径评价模乘器时序，外部接口和复位分发仍需整机检查。本次未设置 `HD.CLK_SRC`，工具另提示OOC时钟延迟/偏斜估计受限；下表裕量仅用于该OOC条件下的内部路径评估，不构成真实时钟树签核或Fmax结果。

比较的是整个 `mont_mul_wl`，包含变量整数乘法、四轮约减及最终校正；不是只报约减模块。时序为单次该约束下的布局布线结果，不是扫频 Fmax，也不是完整双核顶层的时序签核。

报告：`reports/wl_lowcost_modmul/vivado/impl_{0,1,2}/`；`summary.csv` 的 LUT/FF 为原语计数，Slice LUT 口径应以 `route_utilization.rpt` 为准。源码与测试 SHA256、参数见 `reports/wl_lowcost_modmul/metadata.json`。

当前完整顶层有26个通用WL模乘器；若每个从20DSP降至12DSP，按实例数量推算520→312（节省208，40%）。这是整机推算，必须在完整顶层综合后才能标作整机实测。完整顶层后布局布线的LUT、FF、WNS和Fmax没有由本次单模块结果替代。

## 新颖性边界与后续研究

Proteus 的公开WL子模块使用 `m=-T_low mod 2^W`，依赖低字为1；本地W=16、低字c001，原实现已采用广义低字消除和显式carry，并非源码逐字相同。

- Proteus：[论文](https://eprint.iacr.org/2023/267.pdf)，[公开WL源码](https://github.com/florianhirner/proteus/blob/1afe896673487fbbb343c54ff411991d329a6613/toolchain/hw/common/wlmont/wlmont_sub.sv)。
- [Optimized FPGA Architecture for Modular Reduction in NTT](https://eprint.iacr.org/2024/1890)（2025-08修订）研究Montgomery-Shift、K2RED-Shift和WLM-Mixed；移位加减约减和DSP/LUT折中已有先例。
- [FHE.org 2025官方资源页](https://fhe.org/conferences/conference-2025/resources.html)收录 *DSP Optimized Fully Pipelined NTT Architecture for FHE Applications* poster。其11DSP完整模乘对应8DSP整数乘法+3DSP约减，不能把3DSP当成完整模乘成本；所用混合字长法的模数条件与当前Q不同。

[Montgomery-friendly primes and applications to cryptography](https://eprint.iacr.org/2020/665.pdf)（2020，§2.1–2.2）已将特殊模数代入WL递推并用稀疏加减替代常乘。本轮还核对了2024/1890作者的 [montgomery_shift.sv](https://github.com/cisec-su/modmul-hdl/blob/main/src/monty/montgomery_shift.sv) 与 [wordred.sv](https://github.com/cisec-su/modmul-hdl/blob/main/src/monty/wordred.sv)：这些实现保留独立carry相加，没有直接使用本次短借位拼接。只能据此区分这些已核对的实现，不能扩大为所有文献都没有。

本次可以主张“完成固定Q的等价低成本实现并给出实测收益”；尚不能主张“提出全新的Montgomery算法”或“已经形成可发表创新”。普通稀疏常数乘法替换本身不构成充分新颖性证据。

候选研究问题是：对一类 `q=2^n-2^s+1` 的模数，在保持Montgomery表示和吞吐要求下，联合设计低字抵消、进位融合、短借位表示与流水切分。需要证明适用条件，核对最近似已有约减算法，扩展多个可用NTT模数并用普通移位版作消融对照。最后再测完整MDC系统，证明收益能够保留，而非只转移DSP成本到逻辑和布线。

## 模数族筛选（仅数学评估，未实现RTL）

对于w=16、n=55..64、s=13..15，`q=2^n-2^s+1` 共30个候选，仅2个素数。扩大为 `q=2^n-c*2^s+1`，c取1、3、5、7、9、11、13、15，240个候选中有11个素数，均满足4096点负循环NTT的8192阶根条件。采用适用于64位整数的七基确定性Miller–Rabin枚举。这不证明具体同态参数集的安全性或应用性能。

令k=16-s，扩展式为：

```text
m = -x*(1+c*2^s) mod 2^16
d = (c*m >> k) - [m > ((c*m mod 2^k) << s)]
T_next = (T >> 16) + (m << (n-16)) - d
```

全部24组(s,c)×65536个m、两个n边界和两组高位共6,291,456次算术检查通过。c*m最大需20位，d最大需19位；当前RTL的14位d和m生成式不可直接复用。c*2^s超过2^16时，独立carry推导需使用κ*m-d，κ=ceil((c*2^s-1)/2^16)，κ项在融合式中抵消。

扩展引入小常数乘法和额外位宽，尚未综合验证成本；它是后续候选研究路线，不属于本次已完成的硬件能力。

## 本次最终结果

Vivado 2026.1，XC7VX485T-2，6.667ns约束，同一独立模乘器边界，三版均已完成布局布线。下面LUT采用正式路由报告的Slice LUT统计，区别于前面的综合快照和CSV中的LUT原语计数。

| 指标 | 0 原DSP版 | 1 普通稀疏版 | 2 融合版（默认） |
|---|---:|---:|---:|
| DSP48E1 | 20 | 12 | 12 |
| Slice LUT | 911 | 993 | 917 |
| Slice寄存器 | 1497 | 1629 | 1557 |
| 实际占用Slice | 401 | 380 | 384 |
| 内部寄存器路径WNS/ns（OOC评估） | +1.746 | +2.691 | +1.683 |
| 模乘延迟/拍 | 14 | 14 | 14 |
| II/拍 | 1 | 1 | 1 |

融合版相对原DSP版：DSP减少40%；LUT增加6个（0.659%）；寄存器增加60个（4.008%）；本次布局占用Slice减少17个（4.239%）。内部WNS少0.063ns，没有证明频率提升。以上占用Slice是一次具体布局的结果，不能按实例线性外推整机面积。

融合本身的消融结果应比较版本2与版本1：在同为12DSP下，LUT减少76个（7.653%）、寄存器减少72个（4.420%）；内部WNS少1.008ns，本次占用Slice多4个。融合版没有全面支配普通稀疏版，选择取决于逻辑资源与更高频率的需求。本轮默认采用融合版，目标是在维持当前流水接口和150MHz设计约束的条件下尽量少用逻辑资源；若后续整机更看重频率余量，应保留版本1作为对照。

内部最差路径定位：原版是round2输出到round3的DSP输入；普通稀疏版是round2输出到round3的qh寄存器控制；融合版是round2输出到round3的correction寄存器控制。融合版第一拍的m生成、借位和修正数构造，已成为需要关注的时序链，不能只看第二拍宽加法减少就声称提速。

三版专用测试以及8项原有回归全部通过。自然A/B顶层连续输入、气泡输入和负循环定向案例均为8623个计算周期；连续输入的首输入到done仍为12719拍（包括4096拍加载，结果读出不计入）。原始测试台、输入memory和golden未修改。

正式汇总：`reports/wl_lowcost_modmul/comparison.csv`、`comparison.json`。三版原始报告在 `vivado/impl_*/route_utilization.rpt`、`internal_paths.rpt`；实际源文件与测试哈希在 `metadata.json`，实验前后完全一致。新RTL在当前完整顶层的功能已验证；完整顶层的综合、布局布线、功耗和Fmax未在本轮重测，520→312 DSP仍仅是26实例的推算。

重现本轮实验（同一台机器，保持当前Q与memory文件）：

```powershell
& 'D:\Program Files (x86)\Python3119\python.exe' scripts/run_wl_lowcost_regression.py
& 'D:\Vivado\2026.1\Vivado\bin\vivado.bat' -mode batch -notrace -source scripts/run_wl_lowcost_compare.tcl -log reports/wl_lowcost_modmul/vivado/run.log -journal reports/wl_lowcost_modmul/vivado/run.jou
& 'D:\Vivado\2026.1\Vivado\bin\vivado.bat' -mode batch -notrace -source scripts/report_wl_lowcost_internal_timing.tcl -log reports/wl_lowcost_modmul/vivado/internal_audit.log -journal reports/wl_lowcost_modmul/vivado/internal_audit.jou
& 'D:\Program Files (x86)\Python3119\python.exe' scripts/summarize_wl_lowcost.py
```

若继续整机验证，使用现有 `run_synth_dual_forward_dsp_reduction.tcl` 的 `natural_ab_raw_pre_shared` 配置、`xc7vx485tffg1761-2`、6.667ns和一个新的报告子目录。该现有脚本在综合后创建时钟，与旧整机基线一致；仍需后续实际布局布线才能判断整机频率。

