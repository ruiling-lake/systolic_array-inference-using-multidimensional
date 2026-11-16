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
# 1. LSU Memory Responder
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
# 2. 核心：16x16 GEMM 硬件调用函数
# ==========================================
async def run_hw_16x16_gemm(dut, memory_dict, A_16x16, B_16x16,
                            input_base=0x0000, output_base=0x0800):
    SA_SIZE = 16
    NUM_EL = SA_SIZE * SA_SIZE          # 256
    A_BASE = input_base
    B_BASE = A_BASE + NUM_EL * 4        # 0x0400
    C_BASE = output_base

    A_flat = A_16x16.flatten().astype(np.int32)
    B_flat = B_16x16.flatten().astype(np.int32)

    for i in range(NUM_EL):
        val_a = int(A_flat[i]) & 0xFFFFFFFF
        base = A_BASE + i * 4
        for b in range(4):
            memory_dict[base + b] = (val_a >> (b * 8)) & 0xFF

        val_b = int(B_flat[i]) & 0xFFFFFFFF
        base = B_BASE + i * 4
        for b in range(4):
            memory_dict[base + b] = (val_b >> (b * 8)) & 0xFF

    dut.input_base.value = A_BASE
    dut.output_base.value = C_BASE
    dut.start_compute.value = 1
    await RisingEdge(dut.clk)
    dut.start_compute.value = 0

    cycles = 0
    while dut.done.value != 1:
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > 30000:
            raise TimeoutError("Hardware GEMM Timeout!")

    C_result = np.zeros((SA_SIZE, SA_SIZE), dtype=np.int64)
    for idx in range(NUM_EL):
        actual_64bit = 0
        for byte_idx in range(8):
            addr = C_BASE + (idx * 8) + byte_idx
            byte_val = memory_dict.get(addr, 0)
            actual_64bit |= (byte_val << (byte_idx * 8))
        if actual_64bit & (1 << 63):
            actual_64bit -= (1 << 64)
        C_result[idx // SA_SIZE, idx % SA_SIZE] = actual_64bit

    return C_result, cycles


# ==========================================
# 3. 真实 MNIST 图片 + 真实训练权重
# ==========================================
@cocotb.test()
async def test_lenet_inference(dut):
    dut._log.info("="*60)
    dut._log.info("开始 LeNet 真实数据端到端硬件验证 (16x16 脉动阵列)")
    dut._log.info("="*60)

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.reset.value = 1
    dut.start_compute.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    memory = {}
    cocotb.start_soon(lsu_memory_responder(dut, memory))

    dut._log.info("正在加载真实 MNIST 数据集...")
    transform = transforms.Compose([transforms.ToTensor()])
    dataset = torchvision.datasets.MNIST(root='./data', train=False, download=True, transform=transform)
    real_image_tensor, true_label = dataset[0]
    dut._log.info(f"获取到真实图片，其真实标签为: {true_label}")

    image_int32 = np.round(real_image_tensor.numpy() * 256.0).astype(np.int32)  # (1, 28, 28)

    # 提取 16x16 的真实图像块
    A_real = image_int32[0, 6:22, 6:22]
    dut._log.info(f"提取的真实 16x16 图像块 (INT32):\n{A_real}")

    weights = lenet_parser.parse_and_save_weights()
    conv_weights = weights['conv1.weight']  # (4, 1, 3, 3)

    # 36 个权重重排成 16x16（零填充）
    w_pad = np.zeros(16 * 16, dtype=np.int32)
    w_pad[:conv_weights.size] = conv_weights.flatten()
    B_real = w_pad.reshape(16, 16).astype(np.int32)
    dut._log.info(f"提取的真实 16x16 权重块 (INT32):\n{B_real}")

    dut._log.info("⚙️  调用 16x16 硬件执行真实数据 GEMM...")
    hw_C, cycles = await run_hw_16x16_gemm(dut, memory, A_real, B_real,
                                           input_base=0x0000, output_base=0x0800)

    sw_C = np.dot(A_real.astype(np.int64), B_real.astype(np.int64))

    dut._log.info("验证结果对比 (真实图片 vs 真实权重):")
    all_passed = True
    for i in range(16):
        for j in range(16):
            hw_val = hw_C[i, j]
            sw_val = sw_C[i, j]
            status = "✅" if hw_val == sw_val else "❌"
            dut._log.info(f"  C[{i},{j}]: HW={hw_val:6d}, SW={sw_val:6d} {status}")
            if hw_val != sw_val:
                all_passed = False

    assert all_passed, "真实数据 16x16 GEMM 硬件加速验证失败！"
    dut._log.info("="*60)
    dut._log.info("验证通过！16x16 脉动阵列完美处理了真实的 MNIST 图像和训练权重！")
    dut._log.info("="*60)

    clock_period_ns = 10
    time_us = cycles * clock_period_ns / 1000.0
    print("\n========= Performance Report (16x16 LeNet GEMM) =========")
    print(f"Latency: {cycles} cycles ({time_us:.2f} μs @100MHz)")
    print(f"Compute: {16*16*16} MAC operations")
    print(f"Verified: Bit-Accurate Match")
    print("========================================================\n")