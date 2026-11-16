# test/cuda_tiling_model.py
import numpy as np
import lenet_parser
import torchvision.transforms as transforms
from torchvision import datasets

def cuda_style_tiled_matmul(A_global, B_global, tile_size=4):
    """
    基于 4x4 Tiling 策略的 GEMM 并行计算模型 (CUDA 架构映射)
    
    在真实的 CUDA C++ 代码中，外层的两个 for 循环会被替换为:
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    
    这里我们用 Python 循环来模拟这种“分块 (Block) 调度”的逻辑，
    用于在 CPU 上快速生成大规模矩阵乘法的 Golden Reference。
    """
    M, K = A_global.shape
    K_b, N = B_global.shape
    
    # 初始化结果矩阵 (使用 INT64 防止累加溢出，严格匹配硬件行为)
    C_global = np.zeros((M, N), dtype=np.int64)
    
    # 模拟 CUDA 的 Grid 循环 (遍历所有的 4x4 输出块)
    for i in range(0, M, tile_size):
        for j in range(0, N, tile_size):
            
            # 1. 提取当前 Block 需要处理的数据切片
            # (相当于 CUDA 中从 Global Memory 加载数据到 Shared Memory)
            A_tile = A_global[i:i+tile_size, :]
            B_tile = B_global[:, j:j+tile_size]
            
            # 2. 执行块内计算
            # (相当于 CUDA 中每个 Thread 执行的 MAD: Multiply-Add)
            # 强制转换为 int32 进行乘法，然后累加到 int64，完美复刻你的 Verilog 硬件行为
            C_tile = np.dot(A_tile.astype(np.int32), B_tile.astype(np.int32)).astype(np.int64)
            
            # 3. 将块结果写回全局内存
            # (相当于 CUDA 中将 Shared Memory 的结果写回 Global Memory)
            C_global[i:i+tile_size, j:j+tile_size] = C_tile
            
    return C_global

if __name__ == "__main__":
    print("="*70)
    print("🚀 启动基于 4x4 Tiling 策略的 GEMM 并行计算参考模型")
    print("="*70)
    
    # 1. 准备真实数据 (模拟 LeNet Conv1 层 im2col 展开后的规模)
    # 假设输入特征图展开后为 676 行 (26x26)，每个 patch 9 个元素 (3x3)
    # 权重矩阵为 9 行 (3x3)，4 列 (4个输出通道)
    print("📥 正在生成模拟的大规模矩阵数据 (676 x 9) * (9 x 4)...")
    
    # 使用你之前量化的逻辑，生成 -128 到 127 之间的随机 INT32 数据
    np.random.seed(42)
    A_large = np.random.randint(-128, 127, size=(676, 9), dtype=np.int32)
    B_large = np.random.randint(-128, 127, size=(9, 4), dtype=np.int32)
    
    # 2. 使用“CUDA 分块逻辑”进行计算
    print("⚙️  正在使用 4x4 Tiling 逻辑计算全局结果...")
    C_tiling_result = cuda_style_tiled_matmul(A_large, B_large, tile_size=4)
    
    # 3. 使用标准 NumPy 全局矩阵乘法作为绝对基准 (Ground Truth)
    print("📏 正在计算标准 NumPy 全局结果用于对比...")
    C_numpy_result = np.dot(A_large.astype(np.int64), B_large.astype(np.int64))
    
    # 4. 验证一致性
    print("-" * 70)
    if np.array_equal(C_tiling_result, C_numpy_result):
        print("✅ 验证通过！Tiling 分块计算结果与全局计算结果 100% Bit-Accurate 一致！")
        print(f"📊 生成的全局特征图形状: {C_tiling_result.shape}")
        print(f"📊 结果数值范围: [{C_tiling_result.min()}, {C_tiling_result.max()}]")
        print("\n💡 结论：")
        print("   该模型成功模拟了 CUDA 的并行分块调度逻辑。")
        print("   在未来验证中，可瞬间生成完整网络的 Golden Reference，")
        print("   并抽取任意 4x4 分块与 Cocotb 硬件仿真结果进行严格对比。")
    else:
        print("❌ 验证失败！结果不一致，请检查分块逻辑或数据类型。")
    print("="*70)
