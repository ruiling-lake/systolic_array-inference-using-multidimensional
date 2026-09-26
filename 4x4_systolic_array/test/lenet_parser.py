# test/lenet_parser.py
import os
import onnx
import numpy as np

def get_model_path():
    return os.path.join(os.path.dirname(__file__), 'models', 'lenet_simple.onnx')

def parse_and_save_weights(onnx_path=None, quantize_scale=1000.0):
    if onnx_path is None:
        onnx_path = get_model_path()
        
    model = onnx.load(onnx_path)
    weights_dict = {}
    
    for initializer in model.graph.initializer:
        name = initializer.name
        weight_array = onnx.numpy_helper.to_array(initializer)
        
        # 先乘以量化系数，再转为 int32
        # 这样 0.05 就会变成 50，-0.12 就会变成 -120
        weight_array_int = np.round(weight_array * quantize_scale).astype(np.int32)
        
        weights_dict[name] = weight_array_int
        
    return weights_dict

if __name__ == "__main__":
    weights = parse_and_save_weights()
    print("权重解析成功，包含的张量:", list(weights.keys()))
    # 打印一下看看是不是有非零值了
    for k, v in weights.items():
        print(f"{k}: 最大值={v.max()}, 最小值={v.min()}")
