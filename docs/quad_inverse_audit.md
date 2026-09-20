# 双 Forward / 四路 INTT：验证记录

日期：2026-09-05。源码：`codex/q64-core-control-localization`，HEAD `085a46e325ccdd1636ebee526b363d3cb70e4f3c`。

核实对象是引用讨论“Pointwise写入布局”中的正确性、端口、周期与瓶颈问题。本次新增审计脚本、被动监测器、固定四路逆变换测试台和报告；生产 RTL、原测试台、mem 向量均未修改。

**结论：四-bank、FIFO 复用和一次跨核换向方案通过了数学/逐拍模型；固定四路 INTT 数据通路也通过现有 RTL 单元组成的 Questa 仿真。当前2-bank与候选四-bank微综合均为8 RAMB36。完整可切换顶层的 mode/计数/接口集成和布局布线仍待实现验证。**

## 证据边界

| 层级 | 本次完成 | 尚未包含 |
|---|---|---|
| 当前活动顶层 | 重编译现有RTL；连续加载随机、带气泡加载随机、定向负循环乘法全部PASS，均8623 compute cycles | 无生产RTL改动 |
| 内部数值轨迹 | 8192个A/B频域系数、4096个PW、4096个INTT输入、4096个INTT输出、4096个Post结果独立比对 | 全内部轨迹针对第一组随机连续加载 |
| bank映射 | N=8/16/32/4096穷举所有写入/四路读取、结果地址 | 新bank mapper尚未集成顶层 |
| C2模型 | 数值token/全局DIF位置、twiddle、两FIFO、逐拍flush，N=8/16/32/4096 | 没有建模整机可切换控制器 |
| 固定4-path INTT RTL | 现有BFU、同步twiddle ROM、mdc_stage、Post；三帧均4096点正确且无气泡；帧间无reset | 尚未把已有CoreA/CoreB运行时切到该拓扑；未验证Forward→4p INTT→Forward切换 |
| RAM物理资源 | Vivado 2026.1 / xc7vx485tffg1761-2，两个存储组织顺序独立微综合 | 非完整顶层综合，未包含bank mapper、Post重接与twiddle改造 |
| 时序 | 读取当前已布线150MHz报告 | 未对新可重构顶层布局布线，不能称6575拍/150MHz已测 |

## 当前源码与实测周期

`rtl/poly_mul_top_dual_forward.sv` 的 BRAM 分支使用 `u_ac_bank0/1` 保存原始A输入，随后覆盖为C_NTT。A_NTT直接流入Pointwise，当前活动架构没有独立整帧A_NTT缓存。

时间原点：接受 compute start 的上升沿为0。下表为仿真事件的首/末上升沿，窗口长度为`末-首+1`。

| 事件 | 首拍 | 末拍 | 拍数 |
|---|---:|---:|---:|
| A RAM读取请求 | 0 | 2047 | 2048 |
| Pre结果/Forward核心输入 | 15 | 2062 | 2048 |
| Forward核心输出/PW输入 | 2257 | 4304 | 2048 |
| PW结果/C RAM写入 | 2271 | 4318 | 2048 |
| INTT RAM读取请求 | 4318 | 6365 | 2048 |
| INTT核心输入 | 4319 | 6366 | 2048 |
| INTT核心输出 | 6561 | 8608 | 2048 |
| Post写结果 | 6575 | 8622 | 2048 |
| done | 8623 | 8623 | 1 |

因此：

- 第一笔C写比最后一次A RAM读晚224拍；比最后一笔A进入核心晚209拍。此配置下整块原始A已读完，顺序写或写时BR均安全。
- 最后C写与第一次INTT读请求同拍（4318），首个核心输入在下一拍（4319）。当前没有独立2048拍bit-reverse拷贝。
- 4318拍：最后C写地址2047，INTT首读地址0；各bank独立一读一写，且地址不同，符合`top_data_bram`的同地址读写禁令。
- PW第t拍输出逻辑索引为`rev11(t)`与`2048+rev11(t)`。这已经与独立自然序DIT参考数值逐项比对，不只是测试台打印索引公式。
- 现有地址为`C_write_addr=t`、`INTT_read_addr=rev11(k)`；BR是读地址线的重排。改成写时BR、读时顺序本身没有额外2048拍可省。

证据：`rtl/poly_mul_top_dual_forward.sv:267`、`:277`、`:340`、`:659`；`reports/quad_inverse_audit/rtl_trace.csv`与`layout_audit.json`。

## 四bank的两种等价布局

总有效容量一直是`4096×64 = 262144 bit = 32 KiB`。原两只2048深bank直接替换为四只1024深bank，原bank不再另外保留。

选择A：按旧物理地址奇偶拆分。

```text
PW第t拍：
  lane0 -> Q[t&1][t>>1]
  lane1 -> Q[2+(t&1)][t>>1]

4p INTT第k拍：四bank同时读 rev10(k)
  Q0,Q1,Q2,Q3 -> C[k],C[k+1024],C[k+2048],C[k+3072]
```

选择B：写时放到逻辑四分区。令`j=rev11(t)`。

```text
PW第t拍：
  lane0 -> Q[j[10]][j[9:0]]
  lane1 -> Q[2+j[10]][j[9:0]]

4p INTT第k拍：四bank同时读 k
  Q0,Q1,Q2,Q3 -> C[k],C[k+1024],C[k+2048],C[k+3072]
```

两方案均已穷举：4096次系数写入无覆盖/遗漏，两路PW每拍写不同bank，1024拍四路读取全部对应正确逻辑索引。选择B中A加载用`bank=index[11:10]`、`address=index[9:0]`；Forward仍每拍读一对上下半A，A/C复用成立。位反转是地址位排列，无额外模算术或数据搬运。

微综合实测：

| 存储组织 | RAMB36E1 | RAMB18E1 | LUT cells | FF cells |
|---|---:|---:|---:|---:|
| 2×2048×64 | 8 | 0 | 2 | 2 |
| 4×1024×64 | 8 | 0 | 4 | 4 |
| 差值 | 0 | 0 | +2 | +2 |

这张表只统计存储包装。整机地址选择、输出重接、逆twiddle等逻辑不在其中。报告：`reports/quad_inverse_audit/bank_synth/summary.csv`及子目录utilization报告。

## 两核如何组成四路INTT

令`M=N/2`，`h=N/4`，逆根`w=omega_N^-1`。每拍两只全局Stage0蝶形：

```text
CoreA S0: (C[k],   C[k+M])   -> (U[k],   V[k]),   twiddle=w^k
CoreB S0: (C[k+h], C[k+3h])  -> (U[k+h], V[k+h]), twiddle=w^(k+h)

一次固定换向：
CoreA S1 <- (U[k], U[k+h])
CoreB S1 <- (V[k], V[k+h])
```

之后两核各自完成M点GS子变换，使用子根`w^2`；仍是全局Stage1～11，原stage twiddle的指数`2^s*j`正好匹配。后面各级无需继续跨核换向。

原两核每级FIFO深度`1024,512,256,...,1,0`，每核每级两条。双核已有`4×2047=8188`个64位逻辑delay words。逆模式旁路两核Stage0的四条1024深FIFO；后级复用`4×1023=4092` words。没有新增大FIFO；Stage0 FIFO仍保留供双Forward使用。

固定数据通路RTL测试台`sim/tb_gs_quad_inverse_audit.sv`直接复用现有`gs_butterfly`、`twiddle_rom_stage`、`mdc_stage`、`mont_mul_select`与fused Post表。Stage1～11保持全局LOGN/STAGE_ID，帧长参数设为N/2使每个子核接收1024对；两只Stage0使用对称boundary pipeline。

三帧：当前随机乘法C谱、该C谱乘2、全1频谱。帧间不reset，每帧4096项均正确。实测相对首个逆输入：

| 事件 | 首拍 | 末拍 | 窗口 |
|---|---:|---:|---:|
| 四路核心输出 | 1218 | 2241 | 1024 |
| 四路fused Post | 1232 | 2255 | 1024 |

该测试证明固定四路逆数据通路及同步ROM预取可工作，不证明运行时重构控制已经集成。

## 引用讨论遗漏的输出bank冲突

限定“一次Stage0换向、之后两个独立子核”时，第r拍全局物理DIF位置是：

`[2r,2r+1,M+2r,M+2r+1]`，而非`[4r,4r+1,4r+2,4r+3]`。

令`z=rev10(r)`，四路逻辑结果索引为：

`[2z,2048+2z,2z+1,2049+2z]`。

第一拍是`[0,2048,1,2049]`。若结果RAM按自然连续四分区写，0与1写同一bank、2048与2049也写同一bank。4096点穷举发现1024个结果拍全部冲突。

解决映射：

```text
result_bank = {logical_index[11], logical_index[0]}
result_addr = logical_index[10:1]
```

四路分别写bank0、2、1、3，各一次；1024拍零冲突，容量仍4×1024×64。外部自然序读接口按同一映射读回。

Post必须使用每路真实逻辑索引，并保持4096点的`N^-1 * psi^-index`。虽然尾部是两个2048点子变换，整体缩放仍是4096^-1。错用2048^-1会使全部结果乘2，数值负控制已检出。

## Pointwise与Post的实际带宽瓶颈

PW两路已经匹配两个Forward核产生对应频谱的速度。增加PW模乘数量不能增加前向每拍可配对的数据。当前整机按阶段复用核心，整机作业间隔不能直接当作独立流水各模块的最小瞬时速率：当前是8623 compute cycles/job，四路INTT可缩短这个间隔，即使PW仍为2系数/拍。

`rtl/peripheral_mont_pool.sv:108`～`:123`已实例化4个模乘，Pre用4路，PW/Post只用前2路。四路Post可以重接已有lane2/3，不必增加两个模乘。所需改动是：扩Post输入/因子/输出valid、修改请求路由，以及调整“非Pre时lane2/3不得valid”的断言；同步扩大Post地址tag与结果写口。当前接口不改则仍只有两路Post，会积压四路逆输出。

## 提前启动能带来多少

以第一笔PW写入为t=0，4-path自然顺序第k组的四项最晚在

`ready(k)=2*rev10(k)+1`

写完。无气泡启动时刻S须满足`S+k >= ready(k)`，1024组穷举得：

`S_min=1954`，极值k=31、63；S=1953恰在这两组欠一拍。

当前RAM同址读写禁止且同步读1拍：首读请求至少1955，首个核心输入1956。当前全帧等完首个核心输入是2048，因此可争取约92拍；位逆序的到达约束令收益远少于“提前半帧”。有足够预存后，单帧可以连续吃4路，不需要不断停顿。

当前`delay_memory`每时钟推进、core无backpressure，不能将`valid=0`当作停机。因此“group_ready一组就喂一组”不能直接用于现有MDC。

按当前各stage实测时刻、蝶形与delay深度计算，这个提前方案各stage旧帧均先排空，最小间隔约614拍；不要求复制每级FIFO。它仍需要stage-local mode/帧长/拓扑标签，因为开始时旧Forward还在后级，不能立即切全局active_mode。完整该控制尚未实现，首版建议等PW全帧完成。

## 周期收益应如何记账

当前核心首输入到首输出2242拍，输出窗2048拍；固定4路RTL分别为1218和1024拍。

`首结果延迟减少1024 + 输出窗减少1024 = 2048 cycles`。

因此保持现有外围边界时，完整compute投影为`8623-2048=6575`。如果保留当前A@Stage11/B@Stage0的不对称boundary位置并加对齐寄存器，模型给出6576拍。两种模型均通过配对/数值检查。

这2048拍来自逆变换的MDC重排延迟和输出窗口，不能再加一个不存在的2048拍BR拷贝收益。仅计算输入窗口得到“只省1024”也漏掉了首结果延迟改善。

150MHz若保持：57.49us -> 约43.83/43.84us，计算率约+31%；自然A/B loader保持4096拍时，first-input-to-done投影12719 -> 10671/10672拍。外部结果逐项读出均未计入。

## 尚需顶层集成验证的四项

1. **可变帧长与模式恢复。** 当前`mdc_stage.PAIRS=N/2`为常量。逆模式每个物理核只接收1024对，bf_count、reorder_count、flush触发与done/output_count必须按帧配置；否则少flush尾部或下次Forward计数失相。等所有valid/flush排空再改模式时可以共用一套上下文，不需清空整块RAM数据。必须跑Forward→4p INTT→Forward完整序列验证。
2. **CoreB逆twiddle和第一拍。** S1以后两核指数一致可共享/broadcast；S0需指数k与k+1024。CoreB首个逆因子不是1，不能沿用原`start`同拍切表且首因子为1的捷径，必须提前prefetch或明确首值旁路。固定4路测试台已验证提前预取做法。广播/ROM重bank后的物理代价仍需综合。
3. **四路Post/写口完整闭合。** 固定测试已验证四路Post数值，生产pool接口和结果bank mapper仍需集成；不应靠深FIFO把4路重新串成2路。
4. **完整顶层Fmax/资源。** 当前已有报告150MHz WNS=+0.705ns，最差路径CoreB stage-valid→Stage2 WL valid，5.729ns中5.463ns为布线（95.357%）。新模式MUX/跨核线可能改变路径。优先Stage0成对布局、局部valid与短寄存边界。微综合8→8不保证整机仍59 BRAM、也不保证520 DSP/150MHz全都保持。

## 可复现文件

- `scripts/run_quad_inverse_audit.ps1`：隔离Questa库；当前完整顶层回归/被动轨迹、独立布局/数值审计、C2模型、固定四路逆RTL测试；RTL SHA256校验。
- `scripts/quad_inverse_layout_audit.py`：参考变换、内部数值比对、两种bank映射、输出冲突与最早启动穷举。
- `scripts/quad_inverse_cycle_model.py`：逐拍数值C2/flush模型，基线与实测逐stage校准。
- `sim/tb_quad_inverse_audit_monitor.sv`：被动监测当前原测试台。
- `sim/tb_gs_quad_inverse_audit.sv`：固定四路逆数据通路，不修改生产RTL。
- `scripts/run_quad_inverse_bank_synth.tcl`、`sim/bank_layout_micro_synth.sv`：同一Vivado会话中顺序综合两种bank组织。

运行：

```powershell
& .\scripts\run_quad_inverse_audit.ps1
```

Vivado以batch模式执行`-source scripts/run_quad_inverse_bank_synth.tcl`可重做bank微综合。所有产物位于`reports/quad_inverse_audit/`。

固定四路测试台的初次开发运行曾误用`mont_mul_select`默认12拍Post后端，被valid/tag断言捕获；已显式选择当前WL14拍后端后通过。该失败日志保留为`questa_quad_wrong_post_config.log`，最终有效日志为`questa_quad.log`。
