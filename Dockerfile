# Riz face-swap image: ComfyUI + ReActor + FaceFusion, verified setup from 2026-10-24.
# Same torch 2.7.1 / CUDA 12.8 / cuDNN 9 as the verified runs, but the slim 'runtime' base
# (4.2 GB vs 9.4 GB compressed). Build tools are installed and removed inside install.sh.
FROM pytorch/pytorch:2.7.1-cuda12.8-cudnn9-runtime

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONUNBUFFERED=1
RUN mkdir -p /opt/faceswap /work
COPY scripts/install.sh /opt/faceswap/install.sh
RUN bash /opt/faceswap/install.sh

COPY scripts/job.sh scripts/srv.py scripts/run_workflow.py scripts/check_ort.py /opt/faceswap/
RUN chmod +x /opt/faceswap/job.sh
WORKDIR /work
