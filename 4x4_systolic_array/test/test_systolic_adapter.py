import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles
from cocotb.clock import Clock
from .helpers.logger import logger

# ... 其他保持不变

async def lsu_memory_responder(dut, memory_dict):
    READ_BYTES = len(dut.lsu_read_data) // 8
    WRITE_BYTES = len(dut.lsu_write_data) // 8

    while True:
        # 【核心修复】：将 RisingEdge 改为 FallingEdge！
        # 这保证了 Python 采样时，Verilog 在上升沿的赋值已经彻底稳定，消除竞争错位。
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


@cocotb.test()
async def test_systolic_adapter_4x4(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    dut.reset.value = 1
    dut.start_compute.value = 0
    dut.input_base.value = 0x00
    dut.output_base.value = 0x80  # 结果写入起始地址
    
    dut.lsu_read_ready.value = 0
    dut.lsu_read_data.value = 0
    dut.lsu_write_ready.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    memory = {}
    A = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    B = [10, 20, 30, 40, 20, 30, 40, 50, 30, 40, 50, 60, 40, 50, 60, 70]

    # 【修复4】：按 32-bit (4 字节) 小端序 (Little-Endian) 写入内存
    # A 占用 0x00 ~ 0x3F (64 字节)
    for i, val in enumerate(A):
        memory[0x00 + i*4 + 0] = (val >> 0) & 0xFF
        memory[0x00 + i*4 + 1] = (val >> 8) & 0xFF
        memory[0x00 + i*4 + 2] = (val >> 16) & 0xFF
        memory[0x00 + i*4 + 3] = (val >> 24) & 0xFF

    # B 占用 0x40 ~ 0x7F (64 字节)
    for i, val in enumerate(B):
        memory[0x40 + i*4 + 0] = (val >> 0) & 0xFF
        memory[0x40 + i*4 + 1] = (val >> 8) & 0xFF
        memory[0x40 + i*4 + 2] = (val >> 16) & 0xFF
        memory[0x40 + i*4 + 3] = (val >> 24) & 0xFF

    cocotb.start_soon(lsu_memory_responder(dut, memory))

    t_start = cocotb.utils.get_sim_time(units="ns")
    dut.start_compute.value = 1
    await RisingEdge(dut.clk)
    dut.start_compute.value = 0

    cycles = 0
    while dut.done.value != 1:
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > 300:
            raise AssertionError("Timeout: done signal did not go high within 300 cycles")

    t_end = cocotb.utils.get_sim_time(units="ns")
    total_time_ns = t_end - t_start
    logger.info(f"Computation completed in {cycles} cycles ({total_time_ns} ns)")

    expected_results = [
        300, 400, 500, 600,
        700, 960, 1220, 1480,
        1100, 1520, 1940, 2360,
        1500, 2080, 2660, 3240
    ]

    all_passed = True
    base_write_addr = 0x80

    for idx, expected_64bit in enumerate(expected_results):
        actual_64bit = 0
        for byte_idx in range(8):
            addr = base_write_addr + (idx * 8) + byte_idx
            byte_val = memory.get(addr, 0)
            actual_64bit |= (byte_val << (byte_idx * 8))
        
        logger.info(f"Result {idx:2d}: Expected = {expected_64bit:4d}, Actual = {actual_64bit:4d}")
        if actual_64bit != expected_64bit:
            dut._log.error(f"Mismatch at index {idx}!") 
            all_passed = False

    assert all_passed, "Systolic Adapter result verification failed!"
    logger.info("4x4 Systolic Adapter test passed successfully!")
