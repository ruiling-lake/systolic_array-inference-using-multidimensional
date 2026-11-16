.PHONY: test compile_all test_systolic_adapter test_matadd test_matmul

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

# 1. 专门用于测试 systolic 的规则 (使用新的顶层模块)
test_systolic_adapter: compile_all
	sv2v -w build/systolic_test_top_tmp.v \
	    src/systolic_test_top.sv \
	    src/systolic_adapter.sv \
	    src/systolic_array.sv \
	    src/block.sv

	echo '`timescale 1ns/1ns' > build/systolic_test_top.v
	cat build/systolic_test_top_tmp.v >> build/systolic_test_top.v
	rm build/systolic_test_top_tmp.v
	iverilog -o build/sim_systolic.vvp -s systolic_test_top -g2012 build/systolic_test_top.v
	MODULE=test.test_systolic_adapter vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim_systolic.vvp

# 2. 原有的 matadd 测试
test_matadd: compile_all
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	MODULE=test.test_matadd vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

# 3. 原有的 matmul 测试
test_matmul: compile_all
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	MODULE=test.test_matmul vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

# 4. 统一的编译规则
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

# 5. 波形查看规则
show_%: %.vcd %.gtkw
	gtkwave $^
