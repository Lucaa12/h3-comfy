# H3 ComfyUI image: ComfyUI (new), custom nodes, helper scripts. NO models inside (they live on the network volume).
# Build: push this folder to GitHub, the Action in .github/workflows builds and pushes ghcr.io/<you>/h3-comfy:latest
# BASE_IMAGE: a RunPod PyTorch image with CUDA 12.8+ (RTX 5090 / Blackwell needs it). 1.0.3-cu1290-torch291-ubuntu2204 = CUDA 12.9, torch 2.9.1.
ARG BASE_IMAGE=runpod/pytorch:1.0.3-cu1290-torch291-ubuntu2204
FROM ${BASE_IMAGE}

ARG COMFY_REF=master
ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends aria2 git ffmpeg libgl1 libglib2.0-0 curl && rm -rf /var/lib/apt/lists/*

# ComfyUI in its own venv that still sees the base image's torch
RUN git clone --depth 1 --branch ${COMFY_REF} https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
 && python3 -m venv --system-site-packages /opt/venv \
 && ( /opt/venv/bin/python -c "import torch" 2>/dev/null || /opt/venv/bin/pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu129 ) \
 && /opt/venv/bin/python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda)" \
 && /opt/venv/bin/pip install -r /opt/ComfyUI/requirements.txt

# custom nodes (open source). IcyNodes is NOT here: it is installed at start from /workspace/icynodes.zip
RUN mkdir -p /opt/baked/custom_nodes && cd /opt/baked/custom_nodes \
 && git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git \
 && git clone --depth 1 https://github.com/Lucaa12/upscale.git upscale_node \
 && git clone --depth 1 https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git \
 && for r in ComfyUI-KJNodes/requirements.txt upscale_node/requirements.txt ComfyUI-Frame-Interpolation/requirements-no-cupy.txt; do \
      [ -f "$r" ] && /opt/venv/bin/pip install -r "$r" || true; done \
 && mkdir -p open_engine_tools
COPY scripts/open_engine_tools.py /opt/baked/custom_nodes/open_engine_tools/__init__.py
RUN mkdir -p /opt/baked/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife \
 && aria2c -x8 -s8 -d /opt/baked/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife -o rife49.pth https://huggingface.co/marduk191/rife/resolve/main/rife49.pth || true

COPY workflows /opt/h3/workflows
COPY scripts/entry.sh scripts/bootstrap.sh scripts/autostop.sh /opt/h3/
RUN chmod +x /opt/h3/*.sh
EXPOSE 8188
CMD ["/opt/h3/entry.sh"]
