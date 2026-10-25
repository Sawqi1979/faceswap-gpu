#!/bin/bash
# Runtime job for the prebuilt image: nothing is installed here, only models are downloaded.
# Started by the Vast onstart with FS_TOKEN set.
mkdir -p /work/in /work/out
cd /work
exec > >(tee -a /work/job.log) 2>&1
st() { echo "$1" > /work/status; echo "=== STAGE $1 $(date -u +%H:%M:%S)"; }
fail() { st "error: $1"; exit 1; }
st starting
[ -n "${FS_TOKEN:-}" ] || fail "FS_TOKEN not set"
echo "--- image contents"; cat /opt/faceswap/VERSIONS
nohup python3 /opt/faceswap/srv.py > /work/srv.log 2>&1 &
cp /opt/faceswap/run_workflow.py /work/run_workflow.py
cd /work/ComfyUI

st "downloading face models"
HF=https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models
mkdir -p models/insightface models/facerestore_models
[ -s models/insightface/inswapper_128.onnx ] || wget -q -O models/insightface/inswapper_128.onnx $HF/inswapper_128.onnx || fail "inswapper download"
[ -s models/facerestore_models/codeformer-v0.1.0.pth ] || wget -q -O models/facerestore_models/codeformer-v0.1.0.pth $HF/facerestore_models/codeformer-v0.1.0.pth || echo "codeformer download failed"
[ -s models/facerestore_models/GFPGANv1.4.pth ] || wget -q -O models/facerestore_models/GFPGANv1.4.pth $HF/facerestore_models/GFPGANv1.4.pth || echo "gfpgan download failed"
mkdir -p models/hyperswap models/reswapper
wget -q -O models/hyperswap/hyperswap_1b_256.onnx https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1b_256.onnx || { rm -f models/hyperswap/hyperswap_1b_256.onnx; echo "hyperswap download failed"; }
wget -q -O models/reswapper/reswapper_256.onnx $HF/reswapper_256.onnx || { rm -f models/reswapper/reswapper_256.onnx; echo "reswapper download failed"; }
wget -q -O models/facerestore_models/GPEN-BFR-1024.onnx $HF/facerestore_models/GPEN-BFR-1024.onnx || { rm -f models/facerestore_models/GPEN-BFR-1024.onnx; echo "GPEN-1024 download failed"; }
wget -q -O models/facerestore_models/GPEN-BFR-512.onnx $HF/facerestore_models/GPEN-BFR-512.onnx || { rm -f models/facerestore_models/GPEN-BFR-512.onnx; echo "GPEN-512 download failed"; }
ls -la models/insightface models/facerestore_models models/hyperswap models/reswapper
python3 -c "import torch;print('torch', torch.__version__, torch.cuda.is_available())"

st "checking GPU for face swapper"
cp /opt/faceswap/check_ort.py /work/check_ort.py
ORT_OK=0; python3 /work/check_ort.py && ORT_OK=1
[ "$ORT_OK" = 1 ] || echo "WARNING: ReActor cannot use the GPU - ReActor will be skipped"

# FaceFusion's own venv has no cuDNN/cuBLAS: reuse the CUDA 12 libraries that PyTorch already installed
NVLIBS=$(find /opt/conda -type d -path "*site-packages/nvidia/*/lib" 2>/dev/null | tr '\n' ':')
export LD_LIBRARY_PATH="${NVLIBS}${LD_LIBRARY_PATH}"
echo "LD_LIBRARY_PATH set with $(echo "$NVLIBS" | tr ':' '\n' | grep -c lib) nvidia lib dirs"
FF_OK_SETUP=0; /work/ffenv/bin/python /work/check_ort.py && FF_OK_SETUP=1
[ "$FF_OK_SETUP" = 1 ] || echo "WARNING: FaceFusion cannot use the GPU - FaceFusion will be skipped"
[ "$ORT_OK" = 1 ] || [ "$FF_OK_SETUP" = 1 ] || fail "neither ReActor nor FaceFusion can use the GPU"

st "starting ComfyUI"
nohup python3 main.py --listen 127.0.0.1 --port 8188 > /work/comfy.log 2>&1 &
nohup tail -n 0 -F /work/comfy.log >> /work/job.log 2>/dev/null &
for i in $(seq 1 120); do curl -s http://127.0.0.1:8188/system_stats > /dev/null && break; sleep 5; done
curl -s http://127.0.0.1:8188/system_stats > /dev/null || { tail -50 /work/comfy.log; fail "comfyui did not start"; }
grep -i -E "reactor|videohelper|import failed|error" /work/comfy.log | tail -20

st "waiting for inputs"
while [ ! -f /work/in/ready ]; do sleep 3; done
cp /work/in/swap_input.mp4 /work/in/swap_face.jpg /work/ComfyUI/input/

R_OK=0; F_OK=0
if [ "$ORT_OK" = 1 ]; then
  st "ReActor swapping"
  T=$(date +%s)
  if python3 /work/run_workflow.py && [ -s /work/out/result.mp4 ]; then R_OK=1; echo "ReActor took $(( $(date +%s) - T ))s"; else tail -60 /work/comfy.log; fi
fi
if [ "$FF_OK_SETUP" = 1 ]; then
  st "FaceFusion swapping"
  T=$(date +%s)
  cd /work/facefusion
  if /work/ffenv/bin/python facefusion.py headless-run \
      -s /work/in/swap_face.jpg -t /work/in/swap_input.mp4 -o /work/out/facefusion.mp4 \
      --processors face_swapper face_enhancer \
      --face-swapper-model hyperswap_1b_256 --face-swapper-pixel-boost 512x512 \
      --face-enhancer-model gpen_bfr_1024 --face-enhancer-blend 80 \
      --execution-providers cuda --execution-thread-count 16 \
      --output-video-quality 90 && [ -s /work/out/facefusion.mp4 ]; then
    F_OK=1; echo "FaceFusion took $(( $(date +%s) - T ))s"
  fi
fi
echo "RESULTS reactor=$R_OK facefusion=$F_OK"
[ "$R_OK" = 1 ] || [ "$F_OK" = 1 ] || fail "both face swaps failed"
st done
