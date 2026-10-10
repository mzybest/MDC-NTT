# 简历项目描述与源码核对

核验日期 2026-10-10。两版简历的项目入口统一为 [portfolio-2026-10-10](https://github.com/mzybest/MDC-NTT/tree/portfolio-2026-10-10)，源码锚点 [b608e020](https://github.com/mzybest/MDC-NTT/commit/b608e02036b2ce541eb94bc0f0c3e05abd8b612f)。展示分支仅添加文档与 Python 检查结果；main 保留早期基线。

本页仅核验 MDC-NTT 项目措辞与公开工程证据，不对学历、雇佣、其他项目或个人独立贡献比例作推断。代码存在和测试结果不能单独证明作者对每个模块的独立设计程度。

| 原简历措辞 | 核验与校准 |
|---|---|
| 4096 点、约 60-bit、Radix-2、2-path 全 GS | 与 params_pkg 和核心结构一致；补充固定模数/64 位接口，避免暗示任意 64 位模数 |
| A/B 双核并行 NTT，2 点/拍逐点乘，复用 CoreA 做 INTT | 生产顶层实例化及状态机支持；CoreB 仅正变换 |
| C_NTT 复用 A_NTT 存储 | 改为“C_NTT 覆写已读完的 A 输入 BRAM”；双核版无独立 A_NTT 缓存 |
| 通过读地址重排后 INTT | 与 bit_reverse/同步 BRAM 预取路径一致；不是四路无缓存对接 |
| BRAM/LUTRAM/SRL 分层组织延迟存储 | 代码有对应组织与选择；不据此主张研究首创 |
| 使用 Vivado 开展功能仿真 | 仓库回归工具为 Questa；改为“Questa 自检仿真、Vivado 综合及时序分析” |
| 降低重复硬件开销 | 改为具体机制“CoreA 与 A/C BRAM 分阶段复用”，不写缺少同条件基线支持的总面积收益 |
| 未写四路 INTT/200 MHz/246 DSP | 保持简历不加入这些实验指标；它们可在项目文档中按独立实验核验 |

## 校准后的半导体版项目要点

- 面向 4096 点、固定约 60-bit 模数，开发 2-path Radix-2 全 GS NTT/INTT 流水线，接口宽度 64 位。
- 围绕模运算、蝶形交换与延迟对齐开展 RTL 开发，分层组织 BRAM、LUTRAM 与 SRL 延迟存储。
- 集成 A/B 双核并行 NTT 和 2 点/拍逐点模乘；C_NTT 覆写已读完的 A 输入 BRAM，经地址重排后复用 CoreA 执行 INTT。
- 使用 Questa 自检仿真与 Python 参考比对，覆盖连续/带气泡装载、定向负循环乘法；结合 Vivado 综合及时序报告迭代。

## 校准后的央国企版项目要点

- 面向同态加密多项式运算，开展 4096 点、固定约 60-bit 模数的 NTT/INTT 与 FPGA 实现研究。
- 实现双核并行 NTT、逐点模乘及地址重排；复用 CoreA 做 INTT，C_NTT 覆写已读完的 A 输入 BRAM。
- 使用 Questa 自检仿真和 Python 参考比对，检查装载气泡、数据顺序及结果；结合 Vivado 综合及时序报告优化。

简历仅列有证据支撑的生产功能，不列 UVM、数字后端签核、上板成果、四路运行时重构或未经统一口径的性能突破。
