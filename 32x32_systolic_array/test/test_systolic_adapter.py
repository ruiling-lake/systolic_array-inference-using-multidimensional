import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles
from cocotb.clock import Clock
from .helpers.logger import logger

async def lsu_memory_responder(dut, memory_dict):
    READ_BYTES  = len(dut.lsu_read_data)  // 8
    WRITE_BYTES = len(dut.lsu_write_data) // 8

    while True:
        await FallingEdge(dut.clk)

        if dut.lsu_read_req.value == 1:
            addr = int(dut.lsu_read_addr.value)
            dut.lsu_read_ready.value = 1
            read_data = 0
            for i in range(READ_BYTES):
                read_data |= (memory_dict.get(addr + i, 0) << (i * 8))
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
async def test_systolic_adapter_32x32(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    SA_SIZE = 32
    NUM_EL  = SA_SIZE * SA_SIZE          # 1024
    A_BYTES = NUM_EL * 4                 # 4096
    B_BYTES = NUM_EL * 4                 # 4096
    C_BYTES = NUM_EL * 8                 # 8192

    A_BASE  = 0x0000
    B_BASE  = A_BASE + A_BYTES           # 0x1000
    C_BASE  = B_BASE + B_BYTES           # 0x2000

    dut.reset.value         = 1
    dut.start_compute.value = 0
    dut.input_base.value    = A_BASE
    dut.output_base.value   = C_BASE
    dut.lsu_read_ready.value  = 0
    dut.lsu_read_data.value   = 0
    dut.lsu_write_ready.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # ---- 生成 32×32 测试矩阵 ----
    A = [[i * SA_SIZE + j + 1 for j in range(SA_SIZE)] for i in range(SA_SIZE)]
    B = [[(i * SA_SIZE + j + 1) * 2 for j in range(SA_SIZE)] for i in range(SA_SIZE)]

    # ---- Python 计算期望结果 C = A × B ----
    C = [[0] * SA_SIZE for _ in range(SA_SIZE)]
    for i in range(SA_SIZE):
        for j in range(SA_SIZE):
            for k in range(SA_SIZE):
                C[i][j] += A[i][k] * B[k][j]

    A_flat = [A[i][j] for i in range(SA_SIZE) for j in range(SA_SIZE)]
    B_flat = [B[i][j] for i in range(SA_SIZE) for j in range(SA_SIZE)]
    C_flat = [C[i][j] for i in range(SA_SIZE) for j in range(SA_SIZE)]

    # ---- 写入内存 (小端序) ----
    memory = {}
    for idx, val in enumerate(A_flat):
        base = A_BASE + idx * 4
        for b in range(4):
            memory[base + b] = (val >> (b * 8)) & 0xFF

    for idx, val in enumerate(B_flat):
        base = B_BASE + idx * 4
        for b in range(4):
            memory[base + b] = (val >> (b * 8)) & 0xFF

    cocotb.start_soon(lsu_memory_responder(dut, memory))

    # ---- 启动计算 ----
    dut.start_compute.value = 1
    await RisingEdge(dut.clk)
    dut.start_compute.value = 0

    cycles = 0
    while dut.done.value != 1:
        await RisingEdge(dut.clk)
        cycles += 1
        # 【关键修改】：32x32 需要约 16500 个周期，超时限制必须调大
        if cycles > 20000:   
            raise AssertionError("Timeout: done not asserted within 20000 cycles")

    # ---- 验证结果 ----
    all_passed = True
    for idx, expected in enumerate(C_flat):
        actual = 0
        for b in range(8):
            actual |= (memory.get(C_BASE + idx * 8 + b, 0) << (b * 8))
        if actual != expected:
            dut._log.error(f"Mismatch [{idx}]: expected={expected}, actual={actual}")
            all_passed = False

    assert all_passed, "32x32 GEMM verification FAILED"
    logger.info("32x32 Systolic Adapter test passed!")

    # ---- 性能报告 ----
    total_macs       = SA_SIZE ** 3          # 32768
    peak_throughput  = SA_SIZE ** 2          # 1024
    clock_period_ns  = 10
    time_us          = cycles * clock_period_ns / 1000.0
    status           = "PASS" if all_passed else "FAIL"

    print("\n========= Performance Report =========\n")
    print("Matrix:")
    print(f"{SA_SIZE}×{SA_SIZE} GEMM\n")
    print("Latency:")
    print(f"{cycles} cycles")
    print(f"({time_us:.2f} μs @100MHz)\n")
    print("Compute:")
    print(f"{total_macs} MAC operations\n")
    print("Architecture:")
    print(f"{SA_SIZE}×{SA_SIZE} PE Array")
    print("Peak:")
    print(f"{peak_throughput} MAC/cycle\n")
    print("Verification:")
    print(f"Bit-Accurate Match {status}\n")
    print("======================================\n")
