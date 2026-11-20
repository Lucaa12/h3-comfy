#!/usr/bin/env bash
# container start: our setup + ComfyUI run in the background, the RunPod base image keeps SSH / Jupyter / logs alive in the foreground
mkdir -p /workspace
( bash /opt/h3/bootstrap.sh 2>&1 | tee /workspace/h3_bootstrap.log ) &   # progress also shows in the pod's Container logs
if [ -x /start.sh ]; then exec /start.sh; else exec sleep infinity; fi
