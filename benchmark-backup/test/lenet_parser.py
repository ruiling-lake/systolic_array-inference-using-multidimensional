# test/lenet_parser.py
import os
import onnx
import numpy as np

def get_model_path():
    # 获取当前脚本所在目录，拼接出 models/lenet_simple.onnx 的绝对路径
    return os.path.join(os.path.dirname(__file__), 'models', 'lenet_simple.onnx')

def parse_and_save_weights(onnx_path=None):
    if onnx_path is None:
        onnx_path = get_model_path()
        
    model = onnx.load(onnx_path)
    weights_dict = {}
    
    for initializer in model.graph.initializer:
        name = initializer.name
        # 转换为 32-bit 有符号整数 (匹配block.sv 中的 32'd0)
        weight_array = onnx.numpy_helper.to_array(initializer).astype(np.int32)
        weights_dict[name] = weight_array
        
    return weights_dict

if __name__ == "__main__":
    # 测试运行
    weights = parse_and_save_weights()
    print("权重解析成功，包含的张量:", list(weights.keys()))
