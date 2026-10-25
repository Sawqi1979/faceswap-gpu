import sys
try:
    import torch  # loads CUDA/cuDNN libs when available
except Exception:
    pass
import onnxruntime as ort
try:
    ort.preload_dlls()
except Exception:
    pass
s = ort.InferenceSession("/work/ComfyUI/models/insightface/inswapper_128.onnx",
                         providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
print("onnxruntime", ort.__version__, "providers:", s.get_providers())
sys.exit(0 if s.get_providers()[0] == "CUDAExecutionProvider" else 1)
