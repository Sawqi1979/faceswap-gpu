# faceswap-gpu

Private image for face swaps on rented GPUs (Vast.ai / RunPod).

- Image: `ghcr.io/sawqi1979/faceswap-gpu:latest`, built by GitHub Actions on every push to `main`.
- Contains ComfyUI, ReActor (NSFW classifier cached), Video Helper Suite, FaceFusion (own Python 3.12 env), onnxruntime-gpu 1.24.4.
- Models (~2 GB) download at start; see `scripts/job.sh`.
- `onstart.sh` is the Vast onstart; the controller on the PC fills in the token.
