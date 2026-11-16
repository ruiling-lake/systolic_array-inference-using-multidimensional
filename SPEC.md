# 可执行架构规格说明书（SPEC）

- 版本：v0.2（草案；v0.1 经 2026-08-24 实地核查后修订，待用户确认后冻结）
- 日期：2026-08-24
- 状态：等待确认；确认前不写任何实现代码、不改任何文件
- 依据：步骤一（需求对齐）14 项决策 + 时钟统一 10ns（100MHz）
- v0.2 修订说明：对 Linux 工作区实际代码与测试做了实地核查，修正 §2.2/§2.4 基线描述、缩小 F3 范围、新增 M1 构建修复任务、关闭 R3、更正目录名

---

## 1. 题目目标

在 tiny-gpu（adam-maj/tiny-gpu）教学级 GPU 的 RTL 基础上，新增**脉动阵列（Systolic Array）协处理器子系统**，通过扩展的 `SYSTOLIC` 指令由 GPU 内核程序触发矩阵乘法，并在此基础上完成 **LeNet 在 MNIST 数据集上的端到端硬件推理**（真实图片 → 分类结果）。项目以**科研/毕业设计**标准交付：可复现、可量化、文档完备。

目标分解：

| 维度 | 目标 |
|---|---|
| 功能 | ① `SYSTOLIC Rs, Rt` 指令端到端可用（GPU 取指→解码→触发→脉动计算→内存回读→同步）；② 完整 LeNet 推理正确性：硬件结果与软件（torch/onnxruntime）逐层一致 |
| 性能 | 双口径指标：同硬件"纯软件 GEMM 内核 vs SYSTOLIC 内核"实测周期对比 + 绝对指标（单图推理周期、MAC/cycle、阵列利用率） |
| 架构 | GPU 数据路径 8→16bit（64KB 数据寻址）；脉动子系统参数化（4×4 打通闭环，16×16/32×32 为仿真配置） |
| 交付 | 单仓参数化工程、四层分层验证测试全 PASS、架构/量化文档、可选综合报告（4×4/16×16） |

---

## 2. 已有信息（基线）

### 2.1 基座 tiny-gpu（原版特性，均已核实）
- 2 个 core × 每核 4 线程（SIMD 同 PC 收敛模型，无分支发散）
- 数据内存：8bit 寻址（256B）× 8bit 数据 × 4 通道，内存控制器多消费者仲裁
- 程序内存：8bit 寻址（256 条指令）× 16bit 指令
- ISA（16bit 指令，4bit opcode）：NOP / BRnzp / CMP / ADD / SUB / MUL / DIV / LDR / STR / CONST / SYSTOLIC / RET
- 寄存器：R0–R12 可写，R13=%blockIdx、R14=%blockDim、R15=%threadIdx（只读）
- 数据路径全 8bit：寄存器（8bit）、ALU（8bit，CMP 输出 `{5'b0,gt,eq,lt}`）、LSU（地址/数据 8bit，地址来自 rs）、PC（8bit 程序地址）、CONST/BRnzp 立即数 8bit（`instruction[7:0]`）
- 执行流水：IDLE→FETCH→DECODE→REQUEST→WAIT→EXECUTE→UPDATE（单发射、无流水线）

### 2.2 脉动子系统现状（已核实）
- `systolic_array.sv`：SIZE 参数化，标准脉动连接（north→south、west→east），PE=block.sv
- `block.sv`（PE）：32bit×32bit 乘法 + 64bit 累加。**存在两个版本（2026-08-24 实测核实）**：
  - `4x4_systolic_array/src/block.sv`：**已是有符号修复版**（`$signed` 乘法 + signed 64bit acc），但残留调试 `$display` 打印
  - `benchmark-backup` 与 `tiny-gpu` 的 block.sv：**无符号版**（`{32'd0,*}×{32'd0,*}` 零扩展乘法，两者 MD5 一致）
  - `16x16` 与 `32x32`：有符号修复版（两者 MD5 一致）
- `systolic_adapter.sv`：状态机 IDLE→LOAD_INPUT→SETUP_SA→COMPUTE→WAIT_RESULT→READ_RESULT→STORE_OUTPUT→DONE。从 LSU 逐字节读取 A（行主序）+ B（B.T 列主序）拼 32bit word → skew 喂入（2S−1 周期）→ 等结果流出 → 逐字节写回 64bit 结果。两版（已核实）：4×4/benchmark-backup/tiny-gpu 三者 MD5 一致（固定 8bit 地址 128B 输入）；16/32 版参数化 ADDR_WIDTH=16、输入 2S²×4B
- **关键矛盾（已核实）**：五个目录的 core.sv/gpu.sv/decoder.sv/scheduler.sv 完全相同（MD5 一致），core 硬编码 `SA_SIZE=4`。即 16×16/32×32 目录下的"完整 GPU 路径"实际例化的仍是 4×4 阵列；16/32 阵列仅通过独立顶层 `systolic_test_top` 以子系统方式仿真，**从未被 GPU 指令调用**
- 容量矛盾：32×32 适配器需 8192B 输入，当前 256B 数据内存装不下

### 2.3 SYSTOLIC 指令现状（已核实）
- decoder：`SYSTOLIC = 4'b1110`，Rs=`instruction[11:8]`（input_base）、Rt=`instruction[7:4]`（output_base），输出 `decoded_systolic_enable`
- core：DECODE 阶段激活 `systolic_active`；REQUEST 阶段取 `rs[0]`/`rt[0]` 为基址并发出 `systolic_start_pulse`；UPDATE 阶段清除。每 core 实例化一套 `systolic_adapter`+`systolic_array`
- scheduler：WAIT 阶段等待 `!any_lsu_waiting && !systolic_active` 或 `systolic_active && systolic_done` 才进入 EXECUTE
- adapter 的 LSU 请求与 thread0 的 LSU 仲裁互斥（adapter 优先）
- **从未被任何测试端到端执行过**：test_matadd/test_matmul 是纯软件内核（无 SYSTOLIC 指令）

### 2.4 测试基线（2026-08-24 于 Linux 工作区实测核实，取代 v0.1 的"全部 PASS"说法）
| 测试 | 顶层 | 实测现状 | 说明 |
|---|---|---|---|
| test_matadd / test_matmul | gpu | **编译失败（阻塞）** | sv2v 输出缺尾部换行，Makefile `cat` 拼接产生 `` `default_nettype wire`default_nettype none``，iverilog 报错；全仓无任何 `build/sim.vvp` 产物，GPU 路径测试在当前环境疑似从未成功构建 |
| test_systolic_adapter（4×4） | systolic_test_top | **PASS**（TESTS=1 PASS=1） | 4×4 GEMM 单测 vs 硬编码期望值 |
| test_lenet（4×4） | systolic_test_top | **PASS**（TESTS=1 PASS=1，结果含负数如 `ffffffffffffcdba`，有符号路径真实生效） | 仅单次 4×4 GEMM（真实图块[10:14,10:14] × conv1 权重前 16 元素），非完整 LeNet；MNIST 数据已本地化于 `test/data/MNIST` |
| test_lenet（benchmark-backup） | systolic_test_top | **FAIL**（断言失败："LeNet 4x4 GEMM 硬件加速验证失败"） | 原因：无符号 PE vs numpy 有符号参考，真实权重含负值必错 |

- 测试基础设施：cocotb + iverilog + sv2v + Makefile；`helpers/memory.py`（字节寻址内存模型）、`helpers/setup.py`（GPU 测试初始化，**时钟 25μs**）
- 工具链产物：build/（sv2v 转换 + 合并 .v）、sim.vcd、results.xml、test/logs/*.txt

### 2.5 数据表示现状（已核实）
- PE 输入 int32、输出 int64（累加）
- 量化：README 称缩放 1000.0；test_lenet 用 ×256（2⁸）模拟 INT8/INT32——**不一致**
- 无激活函数实现（LeNet 需要 ReLU）
- 模型文件：benchmark-backup/16/32 各含 `models/lenet_simple.onnx` 与 `lenet_parser.py`（onnx 权重解析）；test_lenet 用 torchvision 加载真实 MNIST（4×4 目录数据已本地化）

---

## 3. 功能点拆解

### F1 · 单仓参数化重构
**做什么**：将 5 个含 RTL 的重复目录（4×4/16×16/32×32/benchmark-backup/tiny-gpu）收敛为**单一仓库**（以 `4x4_systolic_array` 为代码基准）：
- `src/` 一份 RTL，所有模块参数化（`SA_SIZE`、`DATA_MEM_ADDR_BITS=16`、`DATA_MEM_DATA_BITS=16`、`PROGRAM_MEM_ADDR_BITS=10`）
- **修复构建 bug（阻塞项）**：sv2v 输出缺尾部换行导致 Makefile `cat` 拼接后 `` `default_nettype`` 指令粘连、iverilog 编译失败；统一 Makefile 时根治（cat 间补换行或改用 sv2v 单趟合并）
- 删除 `*_old.sv`、`a.out`、`Each`、`Retrieves`、`sim.vcd`、build/ 等杂项与产物
- 统一 Makefile：`SA_SIZE` 通过环境变量/命令行传入（如 `make test SA_SIZE=4`），16/32 为配置而非目录
- 测试收敛到 `test/` 一份，helpers 同步
- **涉及文件**：目录结构、全部 .sv、Makefile、test/、README
- **产出**：可 `make` 的单仓工程，`SA_SIZE` 可切换

### F2 · GPU 数据路径 8→16bit
**做什么**：
- 寄存器文件：8bit→16bit（`registers.sv`，DATA_BITS 参数化；只读寄存器 13/14/15 保留）
- ALU：8bit→16bit（`alu.sv`；CMP 输出位宽同步 `{13'b0,gt,eq,lt}`）
- LSU：地址/数据 8bit→16bit（`lsu.sv`）
- 数据内存：16bit 寻址（64KB）、16bit 数据 × 4 通道（`gpu.sv`/`controller.sv` 参数）
- 立即数：CONST 与 BRnzp 的立即数 8bit→12bit（`decoder.sv`，取 `instruction[11:0]`；CONST 覆盖 0–4095，BRnzp 分支目标同）
- 程序地址：PC/Fetcher/Scheduler 程序地址 8bit→10bit（1024 条指令；`pc.sv`/`fetcher.sv`/`scheduler.sv` 参数化，fetcher 的 `current_pc` 硬编码 8bit 改参数化）
- 内存模型与测试助手：`helpers/memory.py` 支持 16bit 行、16bit 寻址
- **涉及文件**：registers/alu/lsu/decoder/pc/fetcher/scheduler/gpu/controller/dispatch/core + helpers + 全部既有测试的数据与断言
- **产出**：16bit 数据路径全链路编译通过，原 test_matadd/test_matmul 在 16bit 适配后仍 PASS

### F3 · PE 有符号统一 + ReLU 旁路
**做什么**：
- `block.sv` 统一为有符号版本（以 4×4 现有修复版为基准）。**注：4×4 的符号 bug 已修复（实测核实），剩余工作为：去除调试 `$display`、将统一版同步为全仓唯一实现（废弃 benchmark-backup/tiny-gpu 的无符号版）**
- `systolic_adapter.sv` 新增可选 ReLU 旁路：STORE_OUTPUT 写回前，若 64bit 结果 <0 则写 0（由 `relu_enable` 控制，默认关）
- SYSTOLIC 指令新增控制位：`instruction[3:0]` 中取 1bit 作 `relu_enable`，decoder→core→adapter 传递
- **涉及文件**：block.sv、systolic_adapter.sv、decoder.sv、core.sv
- **产出**：负权重/负输入计算正确；LeNet 层间 ReLU 可由指令按需开启

### F4 · 脉动子系统参数化升级（16bit 内存适配）
**做什么**：
- `systolic_array.sv`/`systolic_adapter.sv` 统一为参数化（SA_SIZE、ADDR_WIDTH=16）
- adapter 内存读写改为 **16bit 半字**：int32 word = 2 个 16bit 半字，int64 结果 = 4 个 16bit 半字；LOAD_INPUT/STORE_OUTPUT 按半字序列寻址（4×4 输入 128B=64 半字，加载 64 周期）
- adapter 的 `input_base/output_base` 16bit；LSU 仲裁逻辑位宽同步
- **涉及文件**：systolic_array.sv、systolic_adapter.sv、systolic_test_top.sv、core.sv（基址信号 16bit）
- **产出**：子系统测试在 16bit 内存模型下 PASS

### F5 · SYSTOLIC 指令端到端闭环
**做什么**：
- core 的 `systolic_input_base/output_base` 扩到 16bit；REQUEST 阶段取 16bit `rs[0]/rt[0]`
- 常量装载：CONST 12bit 立即数覆盖 0–4095；**数据布局限定 4KB 内**（见 F6），超过 4KB 再评估高位装载机制（本阶段不做）
- scheduler 同步时序验证（`systolic_done` 单拍脉冲与 WAIT 状态竞态）
- 新增端到端测试：GPU 内核程序含 SYSTOLIC 指令 → 验证 done 与内存回读（见 §5 测试 T3）
- **涉及文件**：core.sv、decoder.sv、scheduler.sv、新测试
- **产出**：SYSTOLIC 指令从取指到回读全链路正确，这是本项目**最高风险、最高价值**的一环

### F6 · LeNet 端到端推理
**做什么**：
- 模型结构：以 `lenet_simple.onnx` 实际结构为准（conv1 已知 4×1×3×3；conv2/FC 以 onnx 解析结果为准）
- 量化管线：浮点→int32 定点（缩放 2⁸=256，`lenet_parser.py` 扩展）；推理后反量化在主机侧
- im2col + 分块：卷积转为 4×4 GEMM 分块（3×3 核补零映射到 4×4 或按实际尺寸分块）；全连接层同理分块
- 数据内存布局（限 4KB 内）：图像（784B）/ 权重 / 中间特征图 / 输出分区规划，M3 阶段定精确地址表
- GPU 内核程序（16bit 汇编）：串行调度所有 SYSTOLIC 调用 + ReLU 旁路开关；softmax 在主机侧
- MNIST 数据：`test/data/` 本地化（避免运行时下载依赖网络）
- **涉及文件**：新内核程序、lenet_parser.py 扩展、test_lenet 重写、数据布局文档
- **产出**：单张真实 MNIST 图硬件推理，分类结果与软件推理逐层一致

### F7 · 四层分层验证
**做什么**：建立四层测试体系（见 §5 T1–T4），每层独立 golden reference：
- T1 PE/阵列层：随机有符号矩阵（含负值）vs numpy
- T2 Adapter 层：随机 GEMM（多组尺寸/种子）vs numpy
- T3 指令层：SYSTOLIC 端到端（GPU 程序触发）vs 软件期望
- T4 应用层：完整 LeNet vs torch/onnxruntime 逐层比对
- 恢复/新增性能采集：results.xml 解析与 viz 更新
- **涉及文件**：test/ 下新测试 + 既有测试改造

### F8 · 双口径性能测量
**做什么**：
- 口径 A（同硬件对比）：同一 GPU 上"纯��件 GEMM 内核" vs "SYSTOLIC 内核"，相同数据/线程数，实测周期
- 口径 B（绝对指标）：单图推理周期、MAC/cycle、阵列利用率、加载/计算/写回三阶段周期占比（如实呈现 IO 瓶颈）
- 统一 10ns 时钟；输出报告（文本 + 图）
- **涉及文件**：性能测试、viz_systolic_perf.py 重写为实测数据源
- **产出**：论文可用性能表/图

### F9 · 综合报告（可选）
**做什么**：环境允许（Linux/OpenLane）时，对 4×4（可选 16×16）做综合，产出面积/最高频率报告；环境受限则以 RTL 门数估算替代。不做流片 GDS 交付。

### F10 · 文档与可复现性
**做什么**：README 重写（单仓运行指南）、架构文档（集成图、ISA 扩展说明）、量化说明、数据布局表、spec 落地核对清单。

---

## 4. 实现思路（M1–M5 阶段）

| 阶段 | 内容 | 出口验收（PASS 即里程碑完成） |
|---|---|---|
| **M1** | F1 单仓重构（**含构建换行 bug 修复，为最前置阻塞项**）+ F2 数据路径 16bit + F3 符号统一/ReLU + F4 子系统参数化 | 单仓 `make test_matadd/test_matmul/test_systolic_adapter`（16bit 适配后）全部 PASS；修复构建 bug 前该出口无法达成（T0 现状编译失败，暂不能作安全网） |
| **M2** | F5 SYSTOLIC 指令端到端 | 新测试 T3 PASS（含负数、多轮触发、基址 ≥256） |
| **M3** | F6 LeNet 全网络 + F7 T4 测试 | T4 PASS：硬件推理与软件逐层一致，分类正确 |
| **M4** | F8 双口径性能 + 规模对比（4/16/32 配置） | 性能报告产出，口径 A/B 数据齐 |
| **M5** | F9 综合（可选）+ F10 文档 | 报告 + 文档齐全，全量回归 PASS |

关键实现决策（随 spec 一并确认）：
1. **数据布局限 4KB 内**：CONST 12bit 立即数直接可装载全部基址，**不新增高位装载指令**（ISA 最小改动）
2. **内存数据 16bit×4 通道，PE 输入仍 int32**：int32 由 2 个 16bit 半字组装，PE 内部逻辑（32bit×32bit→64bit）不变
3. **ReLU 旁路在 adapter 写回前**，由 SYSTOLIC 指令控制位按层开启；softmax 留在主机侧
4. **每核一阵列**维持现状（双核并行），不做全局共享仲裁
5. **时钟统一 10ns**；helpers/setup.py 与全部测试同步

---

## 5. 测试与验收方式

统一命令（Linux，项目根目录，SA_SIZE 可切换）：
```bash
make test          # 全部回归
make test_matadd   # T0a 纯软件矩阵加法（GPU 路径回归）
make test_matmul   # T0b 纯软件 GEMM（GPU 路径回归）
make test_systolic_adapter  # T1/T2 脉动子系统
make test_systolic_instr    # T3 SYSTOLIC 指令端到端（新增）
make test_lenet             # T4 LeNet 全网络端到端（新增/重写）
make perf                    # T5 双口径性能报告（新增）
```

| 编号 | 场景 | 判定标准 |
|---|---|---|
| T0a/T0b | 回归：16bit 升级后的原 GPU 软件内核 | 与 16bit 适配后的期望一致，断言全过，无 timeout |
| T1 | PE/阵列随机有符号（含负值、多种子） | HW == numpy（int64 精确） |
| T2 | adapter 随机 GEMM（多尺寸、多基址，含 ≥256 基址验证 16bit 寻址） | HW == numpy |
| T3 | SYSTOLIC 指令端到端：程序含 1+ 次 SYSTOLIC，验证 done、内存回读、scheduler 同步 | 结果正确；`done` 时序正确；连续两次 SYSTOLIC 无死锁 |
| T4 | 完整 LeNet：真实 MNIST 图 × 真实权重（onnx） | 硬件输出与 torch/onnxruntime 逐层一致；最终 argmax 分类正确（golden 图片） |
| T5 | 双口径性能 | 输出周期分解表 + 加速比（口径 A）+ 绝对指标（口径 B），10ns 口径 |

验收总标准：**M1–M5 各出口测试全 PASS + 单仓干净（无 *_old/杂项）+ README 可按指南复现**。

---

## 6. 明确不做什么（Out of Scope）

1. **不写实现代码/不改文件**（本阶段，确认前）
2. **不做 32×32 的 GPU 集成**：32×32 仅作为参数化配置做子系统仿真与性能/面积对比
3. **不做流片 GDS 交付**：综合报告可选，不做 TinyTapeout 流程
4. **不引入 DMA / 专用宽总线**：沿用 core 内 LSU 仲裁通路（位宽随 16bit 升级）
5. **不实现 softmax 等非线性硬件**：收尾层在主机/测试侧处理
6. **不做训练**：只做推理；权重直接来自 lenet_simple.onnx
7. **不实现 tiny-gpu 缺失的高级特性**：cache、warp 调度、流水线、分支发散、内存合并
8. **不做全局共享阵列重构**：维持每核一阵列
9. **不新增 ISA 高位装载指令**（除非 M3 布局超出 4KB，届时单独评估）
10. **不维护 5 份重复目录**：重构后仅单仓

---

## 7. 风险点与缓解

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | **16bit 数据路径波及面广**：registers/alu/lsu/decoder/pc/fetcher/scheduler/controller + 全部测试断言，改动面大 | M1 周期拉长、回归失败 | 参数化 + 分层改造（先 RTL 后 helpers 再测试）；T0 回归作安全网 |
| R2 | **SYSTOLIC 端到端从未验证**：decoder/core/scheduler 接线正确性未知，`systolic_done` 单拍脉冲存在竞态风险 | 端到端死锁/错误结果 | T3 专门覆盖时序；仿真波形核对（sim.vcd）；必要时 adapter done 改为持续一拍以上或加同步寄存器 |
| R3 | ~~**PE 符号性不一致的历史版本**~~ **已关闭（2026-08-24 实地核实）**：4×4 已是有符号修复版且 test_lenet PASS；无符号版仅存于 benchmark-backup（其 test_lenet 实测 FAIL）与 tiny-gpu | 无 | 以 4×4 有符号版为唯一基准；M1 统一后删除无符号副本 |
| R11 | **新增：GPU 路径构建失败**：sv2v 输出缺尾部换行 + Makefile `cat` 拼接 → `` `default_nettype`` 粘连，iverilog 编译错误；test_matadd/test_matmul 当前不可运行，T0 安全网暂失效 | M1 出口无法达成 | F1 首项修复：拼接时补换行或改用 sv2v 单趟合并输出；修复后立即回归 T0 验证 |
| R4 | **CONST 12bit 立即数限制**：基址 >4095 时无法装载 | LeNet 数据放不下 4KB | 布局规划严格限 4KB（图像 784B+权重+特征图足够）；超限再评估 CONSTHI |
| R5 | **程序内存 256→1024 条**：PC/BRnzp 立即数位宽联动，分支目标范围 | 分支错误 | BRnzp 立即数随 CONST 扩到 12bit（≥10bit 目标）；M2 回归覆盖分支 |
| R6 | **时钟统一 10ns**：原 25μs 设定下的日志/周期数据全部失效，需重跑 | 历史数据不可比 | 以 M4 实测为准重建性能基线；旧 results.xml 仅参考 |
| R7 | **IO 瓶颈下加速比可能不显著**：4×4 计算 ~15 周期，加载/写回各 ~64+ 周期（16bit 半字） | 口径 A 数据难看 | 如实报告三阶段周期占比；口径 B 提供绝对指标；论文叙事聚焦"指令级协处理器集成"而非纯加速比 |
| R8 | **依赖环境**：torch/torchvision/onnx、MNIST 数据下载、OpenLane（可选） | 测试无法运行 | MNIST 本地化到 test/data/（**部分缓解已就位**：4×4 目录 `test/data/MNIST` 已有本地数据，可直接迁入单仓）；依赖清单写入 README；综合为可选 |
| R9 | **ReLU 旁路边界**：负结果置零与 golden 的截断/舍入一致性；量化溢出 | 逐层比对失败 | T4 逐层比对定位；量化统一 2⁸ 并用 int64 中间量；溢出在 layout 阶段通过权重缩放范围控制 |
| R10 | **cocotb/Python 版本**：仓库含 pyc（cpython-38），环境版本差异 | 测试运行异常 | README 固定依赖版本；Linux 环境实测为准 |

---

## 8. 待确认清单

1. 本 SPEC v0.2（含 2026-08-24 实地核查修订）是否认可（可提出增删改）
2. ~~R3 核对请求~~ **已完成**：实测确认 4×4 block.sv 为有符号版、其 test_lenet PASS；benchmark-backup 为无符号版、test_lenet FAIL；另发现 GPU 路径构建 bug（R11），已纳入 M1
3. 若存在正式"题目说明"文档（课程/竞赛），请提供以校准 §1 目标

确认后进入 M1 实现阶段。
