# Tiny-GPU with systolic

一个轻量级的 GPU / 脉动阵列加速器设计，使用 SystemVerilog 编写，并包含完整的 Python (Cocotb) 验证环境。

## 📖 项目简介
本项目旨在实现一个精简但功能完整的 GPU 核心架构，重点探索脉动阵列（Systolic Array）在矩阵运算（如矩阵加法、矩阵乘法）中的硬件加速效果。项目包含从 RTL 设计、仿真验证到 GDS 版图输出的完整流程。

## 📂 项目结构
```text
tiny-gpu/
├── src/                  # SystemVerilog 源码目录
│   ├── core.sv           # GPU 核心控制逻辑
│   ├── alu.sv            # 算术逻辑单元
│   ├── systolic_array.sv # 脉动阵列核心实现
│   ├── decoder.sv        # 指令解码器
│   └── ...               # 其他模块 (fetcher, dispatcher, lsu 等)
├── test/                 # Python 验证环境 (基于 Cocotb)
│   ├── test_matmul.py    # 矩阵乘法测试用例
│   ├── test_matadd.py    # 矩阵加法测试用例
│   └── helpers/          # 测试辅助脚本 (内存模型、日志、格式化等)
├── gds/                  # 综合后生成的 GDSII 版图文件
├── docs/images/          # 架构文档与波形截图
│   ├── gpu.png           # 整体架构图
│   ├── core.png          # Core 模块细节
│   └── isa.png           # 指令集架构说明
├── Makefile              # 编译与仿真自动化脚本
└── README.md             # 本说明文件

🛠️ 环境依赖
在 Ubuntu 22.04 环境下，请确保已安装以下工具：
Icarus Verilog (iverilog) : RTL 仿真器
Cocotb : 基于 Python 的硬件验证框架
Python 3.x : 运行测试脚本
GTKWave : (可选) 用于查看生成的 sim.vcd 波形文件

与github tiny-gpu部署方式相同  https://github.com/adam-maj/tiny-gpu
sudo apt update
sudo apt install iverilog gtkwave
pip3 install cocotb

⚡ 快速开始
1. 编译与仿真
需要使用者在根目录下自行创建build文件夹
在项目文件根目录下终端中运行：
make test_systolic_adapter
即可得到运行结束的详细信息
2. 查看波形
仿真完成后，会在build目录下生成systolic_test.vcd, 可以看到脉动矩阵计算波形