# Proteus 与本地模乘器的三拍差额核对

核对日期：2026-09-14。仅源码、历史报告和上游综合日志审计；本次没有修改生产 RTL，也没有运行 Vivado。

上游固定提交：`1afe896673487fbbb343c54ff411991d329a6613`。

## 结论

| 模块边界内的阶段 | Proteus WL 配置 | 本地当前 WL |
|---|---:|---:|
| 独立输入寄存 | 0 | 1 |
| 64×64 整数乘法 | 2 | 4 |
| 四轮 W=16 约减 | 8 | 8 |
| 最终条件减 q | 1 | 1 |
| 合计 | 11 | 14 |

三拍差额全部在约减前：整数乘法多两拍，独立入口寄存多一拍。当前资源优化没有改变这部分流水。

## 上游直接证据

[OP5/6 64-bit WL 综合日志](https://github.com/florianhirner/proteus/blob/1afe896673487fbbb343c54ff411991d329a6613/toolchain/build/64bit/proteus_mdc_op_5_6/proteus_mdc.runs/synth_2/runme.log#L23-L40)：LOGQ=64，LOGN=12，TYPE_RED=1，DELAY_MUL=2，W=16，L=4，MULLAT=1，ADDPIP=0，DELAY_RED=9。

同目录 synth_1/runme.log 为 TYPE_RED=0、DELAY_RED=3，因此 add-shift 模乘为 2+3=5 拍。其 TOTAL_LATENCY=9 是保留的 WL 参数，不能误认为当前激活的 add-shift 约减延迟。

[整数乘法源码](https://github.com/florianhirner/proteus/blob/1afe896673487fbbb343c54ff411991d329a6613/toolchain/hw/common/intmul/intmul.sv)：第58–59行寄存12个24×17分块部分积；第82–89行调用无时钟端口的组合CSA树；第100–101行寄存最终两项和。总计两级寄存。

[模乘封装](https://github.com/florianhirner/proteus/blob/1afe896673487fbbb343c54ff411991d329a6613/toolchain/hw/common/mod/modmul.v#L39-L66) 直接将整数乘法输出连接到WL约减，没有额外入口寄存。

[WL约减](https://github.com/florianhirner/proteus/blob/1afe896673487fbbb343c54ff411991d329a6613/toolchain/hw/common/wlmont/wlmont.sv) 使用四轮，每轮乘法寄存一拍、CSA后的加法寄存一拍，末尾条件减q再一拍。

## 本地差异与历史原因

`rtl/intmul_64x64_24x17.sv`：第47–61行寄存部分积；第63–66行寄存四组部分积和；第68–69行寄存两组和；第70行寄存最终乘积。虽然分块尺寸和12个部分积与Proteus相同，求和结构及流水划分不同，不能称为模乘RTL完全相同。

`rtl/mont_mul_wl.sv`：第66–68行有a_r、b_r、valid_r入口寄存；第53–56行四轮约减；第70–73行最终条件减q。

`docs/mont_mul_wl_experiment.md` 原先独立模块记录为13拍。`docs/mont_mul_wl_core_replacement.md` 第79–101行记录了后来增加入口寄存的原因：旧Artix-7、100MHz综合时序中，Stage0蝶形寄存器经过mod_sub/diff到部分积DSP输入的路径WNS为−1.990ns。增加入口寄存后，最差路径转移且综合时序通过。这是历史集成补救，不是现在不能降到13/12/11拍的证明。

没有找到证明本地四拍整数乘法为必要下限、或与两拍/三拍版本同条件比较的实验记录。

两边模数也不同：Proteus此WL日志为64位模数，低16位为1；本地为q=2^60−2^14+1，64位数据通路，低16位为c001。原Proteus的m=−x公式不能直接用于本地模数；但两边约减流水目前同为9拍，所以这不是三拍差额的来源。

## 调整后的实验优先级

1. 先单独比较本地四拍整数乘法与Proteus式两拍CSA整数乘法；使用相同64×64→128定义、12个部分积、器件工具和时钟边界，测正确性、II、DSP、LUT、FF与布线时序。
2. 若两拍整数乘法满足要求，先保留入口寄存和九拍约减，形成1+2+9=12拍候选；同步调整valid和系统标签后验证。12拍是候选级数，不是已获得的时序结果。
3. 再核查蝶形到模乘的整体寄存边界，研究能否去掉或重新安排入口寄存以达到11拍。仅把寄存器挪出模块不等于端到端加速。
4. 在强的整数乘法基线上继续低成本/直接生成修正数约减研究；复用已有CSA树只能作为实现基线，不能当作新的论文贡献。

原始上游文件及两份日志保存在 `reports/wl_lowcost_modmul/proteus_latency_audit/upstream/`；树清单也保留在该审计目录。
