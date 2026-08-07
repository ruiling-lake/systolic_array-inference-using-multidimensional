

# SV-File: 基于脉动阵列的Tiny-GPU实现

## 项目简介

SV-File 是一个基于 SystemVerilog 实现的轻量级 GPU 项目，采用脉动阵列（Systolic Array）架构进行矩阵运算加速。该项目源自 tiny-gpu 项目，旨在提供一个可用于学习和研究目的的简化 GPU 实现，支持矩阵加法、矩阵乘法等基础运算，并能够运行简单的神经网络推理任务（如 LeNet 模型在 MNIST 数据集上的推理）。

## 项目架构

### 核心组件

项目采用模块化设计，包含以下核心组件：

**1. 处理核心（Core）**
- **调度器（Scheduler）**：负责任务调度和线程管理
- **取指器（Fetcher）**：从指令内存中获取指令
- **解码器（Decoder）**：解析指令操作码和操作数
- **寄存器文件（Register Files）**：存储线程的寄存器状态
- **算术逻辑单元（ALU）**：执行算术和逻辑运算
- **加载存储单元（LSU）**：处理内存访问请求
- **程序计数器（PC）**：跟踪指令执行位置

**2. 脉动阵列系统**
- **脉动适配器（Systolic Adapter）**：将通用指令转换为脉动阵列操作
- **脉动阵列（Systolic Array）**：执行高效的矩阵乘法运算，支持 4×4、16×16 和 32×32 三种规模

**3. 存储系统**
- **全局内存**：存储输入数据、权重和输出结果
- **内存控制器**：管理数据读写访问

### ISA 支持

项目定义了自定义指令集架构，支持以下操作：
- 内存加载/存储指令
- 算术运算指令
- 矩阵运算指令（通过脉动阵列）

## 项目结构

```
sv-file/
├── 4x4_systolic_array/     # 4×4 脉动阵列实现
├── 16x16_systolic_array/   # 16×16 脉动阵列实现
├── 32x32_systolic_array/   # 32×32 脉动阵列实现
└── 文档与图片资源
```

每个脉动阵列子项目包含以下结构：
- `src/` - SystemVerilog 源代码
- `test/` - Python 测试文件（基于 cocotb）
- `docs/images/` - 架构示意图
- `gds/` - 布局布线后的 GDS 文件
- `data/` - MNIST 数据集

## 环境要求

- **仿真工具**：支持 SystemVerilog 的仿真器（如 ModelSim、VCS、Xcelium）
- **测试框架**：cocotb（Python 包）
- **Python 环境**：Python 3.7+
- **构建工具**：Make

## 快速开始

### 1. 安装依赖

```bash
# 安装 Python 依赖
pip install cocotb

# 确保仿真器已正确安装并配置在 PATH 中
```

### 2. 运行测试

进入对应的子项目目录运行测试：

```bash
# 测试 4×4 脉动阵列
cd 4x4_systolic_array
make test

# 测试 16×16 脉动阵列
cd 16x16_systolic_array
make test

# 测试 32×32 脉动阵列
cd 32x32_systolic_array
make test
```

### 3. 可用测试

项目提供以下测试用例：

| 测试文件 | 功能描述 |
|---------|---------|
| `test_matadd.py` | 验证矩阵加法功能 |
| `test_matmul.py` | 验证矩阵乘法功能 |
| `test_systolic_adapter.py` | 测试脉动阵列适配器 |
| `test_lenet.py` | LeNet 模型推理测试 |

## 使用示例

### 矩阵乘法测试

每个子项目都包含矩阵乘法测试，示例代码位于 `test/test_matmul.py`：

```python
# 配置测试参数
A = [[1, 2, 3, 4],
     [5, 6, 7, 8],
     [9, 10, 11, 12],
     [13, 14, 15, 16]]
     
B = [[1, 0, 0, 0],
     [0, 1, 0, 0],
     [0, 0, 1, 0],
     [0, 0, 0, 1]]

# 预期结果为矩阵 A 本身（单位矩阵相乘）
```

### MNIST 推理测试

使用 LeNet 模型进行手写数字识别测试：

```bash
# 进入测试目录
cd 32x32_systolic_array/test

# 运行推理测试
python test_lenet.py
```

## 硬件配置

### 脉动阵列规格

| 配置 | 阵列规模 | 适用场景 |
|-----|---------|---------|
| 4×4 | 最小配置 | 快速验证和调试 |
| 16×16 | 中等配置 | 平衡性能和资源 |
| 32×32 | 最大配置 | 高性能推理任务 |

### 数据精度

当前实现使用定点数运算，默认量化缩放因子为 1000.0，可根据需要调整精度。

## 开发指南

### 添加新测试

在 `test/` 目录下创建新的测试文件，使用 cocotb 提供的测试装饰器：

```python
import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def my_new_test(dut):
    # 测试代码
    await Timer(100, units="ns")
```

### 修改脉动阵列配置

1. 在 `src/systolic_array.sv` 中调整阵列规模参数
2. 更新对应的适配器配置
3. 修改测试用例中的矩阵尺寸以匹配新配置

## 技术文档

### 文件说明

| 文件 | 功能 |
|-----|------|
| `gpu.sv` | GPU 顶层模块 |
| `core.sv` | 处理核心模块 |
| `systolic_array.sv` | 脉动阵列运算单元 |
| `systolic_adapter.sv` | 脉动阵列接口适配器 |
| `alu.sv` | 算术逻辑单元 |
| `lsu.sv` | 加载存储单元 |
| `scheduler.sv` | 线程调度器 |
| `decoder.sv` | 指令解码器 |

### 信号定义

详细信号说明请参考源代码中的注释文档。

## 许可证

本项目遵循开源许可证协议。

## 贡献指南

欢迎提交 Issue 和 Pull Request 贡献代码。

## 参考资料

- 原始 tiny-gpu 项目：https://github.com/adam-maj/tiny-gpu
- cocotb 文档：https://docs.cocotb.org/
- SystemVerilog 标准：IEEE 1800-2017