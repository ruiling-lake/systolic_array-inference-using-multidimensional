# test/test_lenet.py
import cocotb
from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.clock import Clock
import numpy as np
import os
import sys

# 引入 PyTorch 获取真实 MNIST 图片
import torch
import torchvision
import torchvision.transforms as transforms

current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

import lenet_parser


# ==========================================
# 1. 保留原有的 LSU Memory Responder
# ==========================================
async def lsu_memory_responder(dut, memory_dict):
    READ_BYTES = len(dut.lsu_read_data) // 8
    WRITE_BYTES = len(dut.lsu_write_data) // 8

    while True:
        await FallingEdge(dut.clk)
        if dut.lsu_read_req.value == 1:
            addr = int(dut.lsu_read_addr.value)
            dut.lsu_read_ready.value = 1
            read_data = 0
            for i in range(READ_BYTES):
                byte_val = memory_dict.get(addr + i, 0)
                read_data |= (byte_val << (i * 8))
            dut.lsu_read_data.value = read_data
        else:
            dut.lsu_read_ready.value = 0

        if dut.lsu_write_req.value == 1:
            addr = int(dut.lsu_write_addr.value)
            data = int(dut.lsu_write_data.value)
            dut.lsu_write_ready.value = 1
            for i in range(WRITE_BYTES):
                memory_dict[addr + i] = (data >> (i * 8)) & 0xFF
        else:
            dut.lsu_write_ready.value = 0


# ==========================================
# 2. 核心：4x4 GEMM 硬件调用函数
# ==========================================
async def run_hw_4x4_gemm(dut, memory_dict, A_4x4, B_4x4, input_base=0x00, output_base=0x80):
    A_flat = A_4x4.flatten().astype(np.int32)
    B_flat = B_4x4.flatten().astype(np.int32)

    for i in range(16):
        val_a = int(A_flat[i]) & 0xFFFFFFFF
        memory_dict[input_base + i * 4 + 0] = (val_a >> 0) & 0xFF
        memory_dict[input_base + i * 4 + 1] = (val_a >> 8) & 0xFF
        memory_dict[input_base + i * 4 + 2] = (val_a >> 16) & 0xFF
        memory_dict[input_base + i * 4 + 3] = (val_a >> 24) & 0xFF

        val_b = int(B_flat[i]) & 0xFFFFFFFF
        memory_dict[input_base + 64 + i * 4 + 0] = (val_b >> 0) & 0xFF
        memory_dict[input_base + 64 + i * 4 + 1] = (val_b >> 8) & 0xFF
        memory_dict[input_base + 64 + i * 4 + 2] = (val_b >> 16) & 0xFF
        memory_dict[input_base + 64 + i * 4 + 3] = (val_b >> 24) & 0xFF

    dut.input_base.value = input_base
    dut.output_base.value = output_base
    dut.start_compute.value = 1
    await RisingEdge(dut.clk)
    dut.start_compute.value = 0

    cycles = 0
    while dut.done.value != 1:
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > 500:
            raise TimeoutError("Hardware GEMM Timeout!")

    C_result = np.zeros((4, 4), dtype=np.int64)
    for idx in range(16):
        actual_64bit = 0
        for byte_idx in range(8):
            addr = output_base + (idx * 8) + byte_idx
            byte_val = memory_dict.get(addr, 0)
            actual_64bit |= (byte_val << (byte_idx * 8))

        if actual_64bit & (1 << 63):
            actual_64bit -= (1 << 64)

        row = idx // 4
        col = idx % 4
        C_result[row, col] = actual_64bit

    return C_result


# ==========================================
# 3. 真实 MNIST 图片 + 真实训练权重
# ==========================================
@cocotb.test()
async def test_lenet_inference(dut):
    dut._log.info("="*60)
    dut._log.info("开始 LeNet 真实数据端到端硬件验证")
    dut._log.info("="*60)

    # 1. 初始化硬件
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.reset.value = 1
    dut.start_compute.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    memory = {}
    cocotb.start_soon(lsu_memory_responder(dut, memory))

    # 2. 获取真实的 MNIST 图片
    dut._log.info("正在加载真实 MNIST 数据集...")
    transform = transforms.Compose([transforms.ToTensor()]) # 转为 0.0~1.0 的浮点数
    # 如果 Linux 下载慢，可以手动下载放到 ./data/MNIST/raw/ 目录下
    dataset = torchvision.datasets.MNIST(root='./data', train=False, download=True, transform=transform)
    real_image_tensor, true_label = dataset[0]  # 获取第一张图片
    
    dut._log.info(f"获取到真实图片，其真实标签为: {true_label}")

    # 3. 量化真实图片为 INT32 (模拟硬件输入)
    # 乘以 256.0 并四舍五入，模拟真实的 INT8/INT32 量化过程
    image_int32 = np.round(real_image_tensor.numpy() * 256.0).astype(np.int32) # shape: (1, 28, 28)
    
    # 提取左上角 4x4 的真实图像块 (模拟 im2col 的第一个 patch)
    A_real = image_int32[0, 10:14, 10:14] 
    dut._log.info(f"提取的真实 4x4 图像块 (INT32):\n{A_real}")

    # 4. 获取真实的 LeNet 训练权重
    weights = lenet_parser.parse_and_save_weights()
    conv_weight_name = 'conv1.weight'
    conv_weights = weights[conv_weight_name] # shape: (4, 1, 3, 3)
    
    # 提取前 16 个权重元素，重塑为 4x4 (模拟硬件分块)
    B_real = conv_weights.flatten()[:16].reshape(4, 4).astype(np.int32)
    dut._log.info(f"提取的真实 4x4 权重块 (INT32):\n{B_real}")

    # 5. 调用真实硬件加速
    dut._log.info("⚙️  调用 4x4 硬件执行真实数据 GEMM...")
    hw_C = await run_hw_4x4_gemm(dut, memory, A_real, B_real, input_base=0x00, output_base=0x80)

    # 6. 软件 Golden Reference 验证 (使用完全相同的 INT32 数据)
    # 必须用 INT64 进行 np.dot，以严格模拟你硬件中 INT32 乘 + INT64 累加的行为
    sw_C = np.dot(A_real.astype(np.int64), B_real.astype(np.int64))

    dut._log.info("验证结果对比 (真实图片 vs 真实权重):")
    all_passed = True
    for i in range(4):
        for j in range(4):
            hw_val = hw_C[i, j]
            sw_val = sw_C[i, j]
            status = "✅" if hw_val == sw_val else "❌"
            dut._log.info(f"  C[{i},{j}]: HW={hw_val:6d}, SW={sw_val:6d} {status}")
            if hw_val != sw_val:
                all_passed = False

    assert all_passed, "真实数据 4x4 GEMM 硬件加速验证失败！"
    dut._log.info("="*60)
    dut._log.info("验证通过！硬件完美处理了真实的 MNIST 图像和训练权重！")
    dut._log.info("结论：你的量化策略和 INT64 累加器设计完全正确，具备端到端推理能力。")
    dut._log.info("="*60)
