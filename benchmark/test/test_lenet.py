# test/test_lenet.py
import cocotb
from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.clock import Clock
import numpy as np
import os
import sys

current_dir = os.path.dirname(os.path.abspath(__file__))
# 将该目录强制加入 Python 的搜索路径中
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

import lenet_parser


# ==========================================
# 1. 保留原有的LSU Memory Responder
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
# 2. 核心：符合你 RTL 布局要求的 4x4 GEMM 硬件调用函数
# ==========================================
async def run_hw_4x4_gemm(dut, memory_dict, A_4x4, B_4x4, input_base=0x00, output_base=0x80):
    """
    A_4x4: numpy array (4, 4), int32
    B_4x4: numpy array (4, 4), int32
    严格按照 systolic_adapter 的 input_buffer 布局要求写入内存
    """
    # 1. 准备 A (行主序展平) -> 16 个 32-bit 整数
    A_flat = A_4x4.flatten().astype(np.int32)

    # 2. 准备 B (列主序展平，即 B.T 的行主序) -> 16 个 32-bit 整数
    B_flat = B_4x4.T.flatten().astype(np.int32)

    # 3. 按 32-bit 小端序写入 memory_dict (前 64 字节给 A，后 64 字节给 B)
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

    # 4. 触发硬件计算
    dut.input_base.value = input_base
    dut.output_base.value = output_base
    dut.start_compute.value = 1
    await RisingEdge(dut.clk)
    dut.start_compute.value = 0

    # 5. 等待完成
    cycles = 0
    while dut.done.value != 1:
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > 500:
            raise TimeoutError("Hardware GEMM Timeout!")

    # 6. 从 memory_dict 中读回 16 个 64-bit 结果
    C_result = np.zeros((4, 4), dtype=np.int64)
    for idx in range(16):
        actual_64bit = 0
        for byte_idx in range(8):
            addr = output_base + (idx * 8) + byte_idx
            byte_val = memory_dict.get(addr, 0)
            actual_64bit |= (byte_val << (byte_idx * 8))

        # 处理有符号 64 位整数
        if actual_64bit & (1 << 63):
            actual_64bit -= (1 << 64)

        row = idx // 4
        col = idx % 4
        C_result[row, col] = actual_64bit

    return C_result


# ==========================================
# 3. LeNet 端到端推理测试
# ==========================================
@cocotb.test()
async def test_lenet_inference(dut):
    dut._log.info("=== 开始 LeNet 硬件加速推理测试 ===")

    # 1. 初始化
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.reset.value = 1
    dut.start_compute.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    memory = {}
    cocotb.start_soon(lsu_memory_responder(dut, memory))

    # 2. 模拟 LeNet 第一层卷积的一个切片 (为了演示，我们只跑一次 4x4 GEMM)
    # 真实场景中，这里会是 lenet_parser 提取的权重和 im2col 后的图像块
    dut._log.info("准备 4x4 测试数据 (模拟 Conv1 的一个分块)...")

    # 模拟 A (输入特征图 im2col 块): 4x4
    A_sim = np.array([
        [1, 2, 3, 4],
        [5, 6, 7, 8],
        [9, 10, 11, 12],
        [13, 14, 15, 16]
    ], dtype=np.int32)

    # 模拟 B (卷积核权重): 4x4
    B_sim = np.array([
        [1, 0, -1, 0],
        [0, 1, 0, -1],
        [-1, 0, 1, 0],
        [0, -1, 0, 1]
    ], dtype=np.int32)

    # 3. 调用硬件加速
    dut._log.info("调用硬件执行 4x4 GEMM...")
    hw_C = await run_hw_4x4_gemm(dut, memory, A_sim, B_sim, input_base=0x00, output_base=0x80)

    # 4. 软件 Golden Reference 验证
    sw_C = np.dot(A_sim, B_sim)

    dut._log.info("验证结果:")
    all_passed = True
    for i in range(4):
        for j in range(4):
            hw_val = hw_C[i, j]
            sw_val = sw_C[i, j]
            status = "✅" if hw_val == sw_val else "❌"
            dut._log.info(f"  C[{i},{j}]: HW={hw_val:4d}, SW={sw_val:4d} {status}")
            if hw_val != sw_val:
                all_passed = False

    assert all_passed, "LeNet 4x4 GEMM 硬件加速验证失败！"
    dut._log.info("LeNet 4x4 GEMM 硬件加速验证通过！架构完美运行！")
