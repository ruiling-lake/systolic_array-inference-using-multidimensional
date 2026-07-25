import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock
from .helpers.logger import logger

# =========================================================================
# 后台任务：模拟 tiny-gpu 的 8-bit LSU 内存响应 (修复阻塞问题)
# =========================================================================
async def lsu_memory_responder(dut, memory_dict):
    while True:
        await RisingEdge(dut.clk)
        
        # 处理读请求：只要 req 为高，立即在同一周期响应，保持 ready 为高
        if dut.lsu_read_req.value == 1:
            addr = int(dut.lsu_read_addr.value)
            dut.lsu_read_ready.value = 1
            dut.lsu_read_data.value = memory_dict.get(addr, 0)
        else:
            dut.lsu_read_ready.value = 0

        # 处理写请求：只要 req 为高，立即在同一周期响应，保持 ready 为高
        if dut.lsu_write_req.value == 1:
            addr = int(dut.lsu_write_addr.value)
            print("WRITE =", dut.lsu_write_data.value)
            data = int(dut.lsu_write_data.value)
            dut.lsu_write_ready.value = 1
            memory_dict[addr] = data
        else:
            dut.lsu_write_ready.value = 0


@cocotb.test()
async def test_systolic_adapter_4x4(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    dut.reset.value = 1
    dut.start_compute.value = 0
    dut.input_base.value = 0x00
    dut.output_base.value = 0x40
    
    dut.lsu_read_ready.value = 0
    dut.lsu_read_data.value = 0
    dut.lsu_write_ready.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    memory = {}
    # memory[0x00] = 1; memory[0x01] = 2; memory[0x02] = 3; memory[0x03] = 4
    # memory[0x04] = 10; memory[0x05] = 20; memory[0x06] = 30; memory[0x07] = 40
    # for addr in range(0x08, 0x20):
    #     memory[addr] = 0
    # A矩阵 16 byte
    A = [
        1,2,3,4,
        5,6,7,8,
        9,10,11,12,
        13,14,15,16
    ]

    # B矩阵 16 byte
    B = [
        10,20,30,40,
        20,30,40,50,
        30,40,50,60,
        40,50,60,70
    ]

    for i, val in enumerate(A):
        memory[0x00+i] = val

    for i, val in enumerate(B):
        memory[0x10+i] = val

    cocotb.start_soon(lsu_memory_responder(dut, memory))

    t_start = cocotb.utils.get_sim_time(units="ns")
    dut.start_compute.value = 1
    await RisingEdge(dut.clk)
    dut.start_compute.value = 0

    cycles = 0
    while dut.done.value != 1:
        await RisingEdge(dut.clk)
        cycles += 1
        # 【修复 Bug 3】: 放宽超时限制，完整流程约需 170 周期
        if cycles > 300:
            raise AssertionError("Timeout: done signal did not go high within 300 cycles")

    t_end = cocotb.utils.get_sim_time(units="ns")
    total_time_ns = t_end - t_start
    logger.info(f"Computation completed in {cycles} cycles ({total_time_ns} ns)")

    expected_results = [
        10, 20, 30, 40, 20, 40, 60, 80,
        30, 60, 90, 120, 40, 80, 120, 160
    ]

    all_passed = True
    base_write_addr = 0x40

    for idx, expected_64bit in enumerate(expected_results):
        actual_64bit = 0
        for byte_idx in range(8):
            addr = base_write_addr + (idx * 8) + byte_idx
            byte_val = memory.get(addr, 0)
            actual_64bit |= (byte_val << (byte_idx * 8))
        
        logger.info(f"Result {idx:2d}: Expected = {expected_64bit:4d}, Actual = {actual_64bit:4d}")
        if actual_64bit != expected_64bit:
            logger.error(f"Mismatch at index {idx}!")
            all_passed = False

    assert all_passed, "Systolic Adapter result verification failed!"
    logger.info("4x4 Systolic Adapter test passed successfully!")