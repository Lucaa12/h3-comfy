#!/usr/bin/env bash
# container start: our setup + ComfyUI run in the background, the RunPod base image keeps SSH / Jupyter / logs alive in the foreground
mkdir -p /workspace
nohup bash /opt/h3/bootstrap.sh > /workspace/h3_bootstrap.log 2>&1 &
if [ -x /start.sh ]; then exec /start.sh; else exec sleep infinity; fi
