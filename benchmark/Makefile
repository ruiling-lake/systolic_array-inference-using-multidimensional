.PHONY: test compile_all test_systolic_adapter test_matadd test_matmul test_lenet show_%

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

# ==========================================
# 1. 新增：LeNet 推理测试
# ==========================================
test_lenet: build/sim_systolic.vvp
	@echo "=========================================="
	@echo "Running LeNet Inference Test (Cocotb)"
	@echo "=========================================="
	MODULE=test.test_lenet vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim_systolic.vvp

# ==========================================
# 2. 优化：提取 systolic 子系统的独立编译目标
#    (供 test_systolic_adapter 和 test_lenet 共享，避免重复编译)
# ==========================================
build/sim_systolic.vvp: compile_all
	@echo "Compiling systolic subsystem (sv2v + iverilog)..."
	sv2v -w build/systolic_test_top_tmp.v \
	    src/systolic_test_top.sv \
	    src/systolic_adapter.sv \
	    src/systolic_array.sv \
	    src/block.sv

	echo '`timescale 1ns/1ns' > build/systolic_test_top.v
	cat build/systolic_test_top_tmp.v >> build/systolic_test_top.v
	rm -f build/systolic_test_top_tmp.v
	
	iverilog -o build/sim_systolic.vvp -s systolic_test_top -g2012 build/systolic_test_top.v

# ==========================================
# 3. 原有的 systolic adapter 测试 (现在复用编译产物)
# ==========================================
test_systolic_adapter: build/sim_systolic.vvp
	@echo "Running Systolic Adapter Test..."
	MODULE=test.test_systolic_adapter vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim_systolic.vvp

# ==========================================
# 4. 原有的 matadd 测试
# ==========================================
test_matadd: compile_all
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	MODULE=test.test_matadd vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

# ==========================================
# 5. 原有的 matmul 测试
# ==========================================
test_matmul: compile_all
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	MODULE=test.test_matmul vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

# ==========================================
# 6. 统一的编译规则 (保持不变)
# ==========================================
compile_all:
	@echo "Converting SystemVerilog to Verilog using sv2v..."
	sv2v -w build/alu.v src/alu.sv
	sv2v -w build/block.v src/block.sv
	sv2v -w build/systolic_array.v src/systolic_array.sv
	sv2v -w build/systolic_adapter.v src/systolic_adapter.sv
	sv2v -I src -w build/gpu.v src/gpu.sv src/core.sv src/decoder.sv src/scheduler.sv src/fetcher.sv src/lsu.sv src/registers.sv src/pc.sv src/dcr.sv src/controller.sv src/dispatch.sv
	
	@echo "Merging Verilog files..."
	echo '`timescale 1ns/1ns' > build/temp.v
	cat build/alu.v >> build/temp.v
	cat build/block.v >> build/temp.v
	cat build/systolic_array.v >> build/temp.v
	cat build/systolic_adapter.v >> build/temp.v
	cat build/gpu.v >> build/temp.v
	mv build/temp.v build/gpu.v

# ==========================================
# 7. 波形查看规则
# ==========================================
show_%: %.vcd %.gtkw
	gtkwave $^
