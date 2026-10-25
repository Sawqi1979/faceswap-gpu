#!/bin/bash
# Build-time install: same verified steps as faceswap_onstart.sh (2026-10-24), minus GPU checks and models.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq git ffmpeg libgl1 libglib2.0-0 build-essential wget curl > /dev/null
rm -rf /var/lib/apt/lists/*

# --- ComfyUI + ReActor + Video Helper Suite (torch comes from the base image)
git clone -q https://github.com/comfyanonymous/ComfyUI.git /work/ComfyUI
cd /work/ComfyUI
grep -v -i -E '^(torch|torchvision|torchaudio)([<>=~ ;]|$)' requirements.txt > /tmp/req_comfy.txt
pip install -q --no-cache-dir -r /tmp/req_comfy.txt
cd custom_nodes
git clone -q https://github.com/Gourieff/ComfyUI-ReActor.git
git clone -q https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
pip install -q --no-cache-dir -r ComfyUI-VideoHelperSuite/requirements.txt
cd ComfyUI-ReActor
grep -v -i -E '^(torch|torchvision|torchaudio)([<>=~ ;]|$)' requirements.txt > /tmp/req_reactor.txt
pip install -q --no-cache-dir -r /tmp/req_reactor.txt
python3 install.py || echo "reactor install.py returned non-zero (continuing)"

# Speed fix: ReActor rebuilds its NSFW classifier for every frame. Build it once and reuse it (check unchanged).
python3 - <<'PY'
p = "scripts/reactor_sfw.py"
s = open(p).read()
old = "from transformers import pipeline\n"
new = ("from functools import lru_cache\n"
       "from transformers import pipeline as _hf_pipeline\n"
       "@lru_cache(maxsize=4)\n"
       "def _cached_pipeline(task, model=None, device=None):\n"
       "    return _hf_pipeline(task, model=model, device=device)\n"
       "def pipeline(task, model=None, device=None):\n"
       "    return _cached_pipeline(task, model=model, device=device)\n")
if old in s and "_cached_pipeline" not in s:
    open(p, "w").write(s.replace(old, new, 1)); print("reactor_sfw: classifier cached")
else:
    raise SystemExit("reactor_sfw: patch not applied (file layout changed)")
PY

# onnxruntime-gpu 1.24.4 is the CUDA 12 build (1.31 is CUDA 13 and falls back to CPU)
pip uninstall -y -q onnxruntime onnxruntime-gpu > /dev/null 2>&1 || true
pip install -q --no-cache-dir "onnxruntime-gpu==1.24.4"
python3 -c "import onnxruntime as o; print('onnxruntime', o.__version__); assert o.__version__ == '1.24.4'"

# --- FaceFusion (headless) in its own Python 3.12 environment
pip install -q --no-cache-dir uv
uv venv -q -p 3.12 /work/ffenv
git clone -q --depth 1 https://github.com/facefusion/facefusion /work/facefusion
grep -v -i '^onnxruntime' /work/facefusion/requirements.txt > /tmp/req_ff.txt
uv pip install -q --no-cache --python /work/ffenv/bin/python -r /tmp/req_ff.txt "onnxruntime-gpu==1.24.4"

# FaceFusion needs ffmpeg >= 5.1 (-fps_mode); Ubuntu's 4.4 makes it read black frames.
# Static ffmpeg 7.1 for FaceFusion only; ReActor/ComfyUI keep the system ffmpeg they were verified with.
conda create -q -y -p /opt/ffmpeg7 -c conda-forge --override-channels "ffmpeg=7.1" > /dev/null
conda clean -q -a -y > /dev/null
test -x /opt/ffmpeg7/bin/ffmpeg && test -x /opt/ffmpeg7/bin/ffprobe
/opt/ffmpeg7/bin/ffmpeg -hide_banner -version | head -1
/opt/ffmpeg7/bin/ffmpeg -hide_banner -f lavfi -i testsrc=size=64x64:rate=5 -frames:v 3 -fps_mode passthrough -pix_fmt bgr24 -f rawvideo -y /dev/null

# Record versions so every run can report exactly what is inside the image
{
  echo "built $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "ComfyUI $(git -C /work/ComfyUI rev-parse --short HEAD)"
  echo "ReActor $(git -C /work/ComfyUI/custom_nodes/ComfyUI-ReActor rev-parse --short HEAD)"
  echo "VHS $(git -C /work/ComfyUI/custom_nodes/ComfyUI-VideoHelperSuite rev-parse --short HEAD)"
  echo "FaceFusion $(git -C /work/facefusion rev-parse --short HEAD)"
  echo "FaceFusion $(/opt/ffmpeg7/bin/ffmpeg -hide_banner -version | head -1)"
} > /opt/faceswap/VERSIONS
cat /opt/faceswap/VERSIONS
rm -rf /root/.cache /tmp/*
