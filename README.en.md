# SV-File: Tiny-GPU Implementation Based on Systolic Array

## Project Introduction

SV-File is a lightweight GPU project implemented in SystemVerilog, adopting a Systolic Array architecture for matrix operation acceleration. This project originates from the tiny-gpu project and aims to provide a simplified GPU implementation suitable for learning and research purposes. It supports basic operations such as matrix addition and matrix multiplication, and can run simple neural network inference tasks (such as LeNet model inference on the MNIST dataset).

## Project Architecture

### Core Components

The project utilizes a modular design and includes the following core components:

**1. Processing Core (Core)**
- **Scheduler**: Responsible for task scheduling and thread management
- **Fetcher**: Retrieves instructions from instruction memory
- **Decoder**: Parses instruction opcodes and operands
- **Register Files**: Stores thread register states
- **Arithmetic Logic Unit (ALU)**: Executes arithmetic and logical operations
- **Load Store Unit (LSU)**: Handles memory access requests
- **Program Counter (PC)**: Tracks instruction execution location

**2. Systolic Array System**
- **Systolic Adapter**: Converts general instructions into systolic array operations
- **Systolic Array**: Performs efficient matrix multiplication operations, supporting three scales: 4×4, 16×16, and 32×32

**3. Memory System**
- **Global Memory**: Stores input data, weights, and output results
- **Memory Controller**: Manages data read/write access

### ISA Support

The project defines a custom Instruction Set Architecture (ISA) and supports the following operations:
- Memory load/store instructions
- Arithmetic operation instructions
- Matrix operation instructions (via Systolic Array)

## Project Structure

```
sv-file/
├── 4x4_systolic_array/     # 4×4 Systolic Array implementation
├── 16x16_systolic_array/   # 16×16 Systolic Array implementation
├── 32x32_systolic_array/   # 32×32 Systolic Array implementation
└── Documentation & Image Resources
```

Each systolic array sub-project contains the following structure:
- `src/` - SystemVerilog source code
- `test/` - Python test files (based on cocotb)
- `docs/images/` - Architecture diagrams
- `gds/` - GDS files after place and route
- `data/` - MNIST dataset

## Environment Requirements

- **Simulation Tools**: Simulators supporting SystemVerilog (e.g., ModelSim, VCS, Xcelium)
- **Test Framework**: cocotb (Python package)
- **Python Environment**: Python 3.7+
- **Build Tools**: Make

## Quick Start

### 1. Install Dependencies

```bash
# Install Python dependencies
pip install cocotb

# Ensure the simulator is correctly installed and configured in PATH
```

### 2. Run Tests

Enter the corresponding sub-project directory to run tests:

```bash
# Test 4×4 Systolic Array
cd 4x4_systolic_array
make test

# Test 16×16 Systolic Array
cd 16x16_systolic_array
make test

# Test 32×32 Systolic Array
cd 32x32_systolic_array
make test
```

### 3. Available Tests

The project provides the following test cases:

| Test File | Function Description |
|---------|---------|
| `test_matadd.py` | Verify matrix addition functionality |
| `test_matmul.py` | Verify matrix multiplication functionality |
| `test_systolic_adapter.py` | Test Systolic Array Adapter |
| `test_lenet.py` | LeNet model inference test |

## Usage Examples

### Matrix Multiplication Test

Each sub-project includes a matrix multiplication test. Example code is located at `test/test_matmul.py`:

```python
# Configure test parameters
A = [[1, 2, 3, 4],
     [5, 6, 7, 8],
     [9, 10, 11, 12],
     [13, 14, 15, 16]]
     
B = [[1, 0, 0, 0],
     [0, 1, 0, 0],
     [0, 0, 1, 0],
     [0, 0, 0, 1]]

# Expected result is the matrix A itself (multiplication by identity matrix)
```

### MNIST Inference Test

Use the LeNet model for handwritten digit recognition testing:

```bash
# Enter test directory
cd 32x32_systolic_array/test

# Run inference test
python test_lenet.py
```

## Hardware Configuration

### Systolic Array Specifications

| Configuration | Array Scale | Application Scenario |
|-----|---------|---------|
| 4×4 | Minimum Configuration | Rapid verification and debugging |
| 16×16 | Medium Configuration | Balance performance and resources |
| 32×32 | Maximum Configuration | High-performance inference tasks |

### Data Precision

The current implementation uses fixed-point arithmetic. The default quantization scaling factor is 1000.0, which can be adjusted according to precision requirements.

## Development Guide

### Add New Tests

Create a new test file in the `test/` directory, using the test decorators provided by cocotb:

```python
import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def my_new_test(dut):
    # Test code
    await Timer(100, units="ns")
```

### Modify Systolic Array Configuration

1. Adjust array scale parameters in `src/systolic_array.sv`
2. Update the corresponding adapter configuration
3. Modify matrix dimensions in test cases to match the new configuration

## Technical Documentation

### File Description

| File | Function |
|-----|------|
| `gpu.sv` | GPU Top-level Module |
| `core.sv` | Processing Core Module |
| `systolic_array.sv` | Systolic Array Compute Unit |
| `systolic_adapter.sv` | Systolic Array Interface Adapter |
| `alu.sv` | Arithmetic Logic Unit |
| `lsu.sv` | Load Store Unit |
| `scheduler.sv` | Thread Scheduler |
| `decoder.sv` | Instruction Decoder |

### Signal Definitions

Please refer to the comment documentation within the source code for detailed signal descriptions.

## License

This project follows an open-source license agreement.

## Contribution Guidelines

Issues and Pull Requests are welcome to contribute code.

## References

- Original tiny-gpu project: https://github.com/adam-maj/tiny-gpu
- cocotb documentation: https://docs.cocotb.org/
- SystemVerilog Standard: IEEE 1800-2017