#!/bin/bash
# Vast template onstart (manual use): ComfyUI + ReActor on port 8188, FaceFusion web UI on port 7860.
mkdir -p /work
exec >> /work/ui.log 2>&1
echo "=== template start $(date -u)"; cat /opt/faceswap/VERSIONS
cd /work/ComfyUI
fail() { echo "ERROR: $1"; }
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
nohup python3 main.py --listen 0.0.0.0 --port 8188 > /work/comfy.log 2>&1 &
NVLIBS=$(find /opt/conda -type d -path "*site-packages/nvidia/*/lib" 2>/dev/null | tr '\n' ':')
cd /work/facefusion
LD_LIBRARY_PATH="${NVLIBS}${LD_LIBRARY_PATH}" PATH="/opt/ffmpeg7/bin:$PATH" \
  GRADIO_SERVER_NAME=0.0.0.0 GRADIO_SERVER_PORT=7860 \
  nohup /work/ffenv/bin/python facefusion.py run --execution-providers cuda > /work/facefusion_ui.log 2>&1 &
echo "=== ComfyUI :8188 and FaceFusion :7860 starting"
