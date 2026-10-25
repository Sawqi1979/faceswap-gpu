#!/bin/bash
# Riz FaceSwap on vastai/comfy: first boot adds ReActor + VHS + face models + FaceFusion, then runs Vast's normal boot.
# Log: /var/log/riz-install.log   FaceFusion UI log: /var/log/facefusion.log
L=/var/log/riz-install.log
if [ ! -f /.riz_installed ]; then
(
set -x
. /venv/main/bin/activate
C=/opt/workspace-internal/ComfyUI; [ -d /workspace/ComfyUI ] && C=/workspace/ComfyUI
command -v gcc >/dev/null || { apt-get update -qq && apt-get install -y -qq build-essential >/dev/null; }
uv pip install -q pip
cd $C/custom_nodes
[ -d ComfyUI-ReActor ] || git clone -q https://github.com/Gourieff/ComfyUI-ReActor.git
[ -d ComfyUI-VideoHelperSuite ] || git clone -q https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
uv pip install -q -r ComfyUI-VideoHelperSuite/requirements.txt
cd ComfyUI-ReActor
grep -v -i -E '^(torch|torchvision|torchaudio)([<>=~ ;]|$)' requirements.txt > /tmp/rq.txt
uv pip install -q -r /tmp/rq.txt
python install.py || true
python - <<'PY'
p="scripts/reactor_sfw.py"; s=open(p).read(); o="from transformers import pipeline\n"
n=("from functools import lru_cache\nfrom transformers import pipeline as _hf_pipeline\n@lru_cache(maxsize=4)\n"
   "def _cached_pipeline(task, model=None, device=None):\n    return _hf_pipeline(task, model=model, device=device)\n"
   "def pipeline(task, model=None, device=None):\n    return _cached_pipeline(task, model=model, device=device)\n")
if o in s and "_cached_pipeline" not in s: open(p,"w").write(s.replace(o,n,1)); print("NSFW classifier cached")
PY
uv pip uninstall -q onnxruntime onnxruntime-gpu; uv pip install -q "onnxruntime-gpu==1.24.4"
cd $C/models
H=https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models
mkdir -p insightface facerestore_models hyperswap reswapper
wget -q -O insightface/inswapper_128.onnx $H/inswapper_128.onnx
wget -q -O facerestore_models/codeformer-v0.1.0.pth $H/facerestore_models/codeformer-v0.1.0.pth
wget -q -O facerestore_models/GPEN-BFR-1024.onnx $H/facerestore_models/GPEN-BFR-1024.onnx
wget -q -O facerestore_models/GPEN-BFR-512.onnx $H/facerestore_models/GPEN-BFR-512.onnx
wget -q -O reswapper/reswapper_256.onnx $H/reswapper_256.onnx
wget -q -O hyperswap/hyperswap_1b_256.onnx https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1b_256.onnx
deactivate
git clone -q --depth 1 https://github.com/facefusion/facefusion /opt/facefusion
uv venv -q -p 3.12 /opt/ffenv
grep -v -i '^onnxruntime' /opt/facefusion/requirements.txt > /tmp/rf.txt
uv pip install -q --python /opt/ffenv/bin/python -r /tmp/rf.txt "onnxruntime-gpu==1.24.4"
mkdir -p /opt/ffmpeg-new
wget -q -O /tmp/ff.tar.xz https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz
tar -xJf /tmp/ff.tar.xz -C /opt/ffmpeg-new --strip-components=1 && rm -f /tmp/ff.tar.xz
touch /.riz_installed
echo "RIZ INSTALL DONE"
) >> $L 2>&1
fi
# FaceFusion web UI behind the Instance Portal (port 7860, token-protected)
nohup bash -c 'NV=$(find /venv/main -type d -path "*site-packages/nvidia/*/lib" | tr "\n" ":"); cd /opt/facefusion && \
  LD_LIBRARY_PATH="$NV$LD_LIBRARY_PATH" PATH="/opt/ffmpeg-new/bin:$PATH" GRADIO_SERVER_NAME=127.0.0.1 GRADIO_SERVER_PORT=17860 \
  /opt/ffenv/bin/python facefusion.py run --execution-providers cuda' > /var/log/facefusion.log 2>&1 &
exec entrypoint.sh
