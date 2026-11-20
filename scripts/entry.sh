#!/usr/bin/env bash
# container start: our setup + ComfyUI run in the background, the RunPod base image keeps SSH / Jupyter / logs alive in the foreground
mkdir -p /workspace

# JupyterLab: the RunPod base image only starts it when JUPYTER_PASSWORD is set -> make sure it always has one
if [ -z "${JUPYTER_PASSWORD:-}" ]; then
  export JUPYTER_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)"
  echo "$JUPYTER_PASSWORD" > /workspace/jupyter_password.txt
  echo "[h3] JUPYTER_PASSWORD was not set -> generated: $JUPYTER_PASSWORD   (set the JUPYTER_PASSWORD env var in the template to choose your own)"
fi

( bash /opt/h3/bootstrap.sh 2>&1 | tee /workspace/h3_bootstrap.log ) &   # progress also shows in the pod's Container logs

# safety net: if the base image did not bring up Jupyter within 45 s, start it ourselves on 8888
(
  sleep 45
  if ! (exec 3<>/dev/tcp/127.0.0.1/8888) 2>/dev/null; then
    echo "[h3] Jupyter not listening on 8888 -> starting it"
    command -v jupyter >/dev/null 2>&1 || python3 -m pip install -q --break-system-packages jupyterlab
    cd /workspace && exec jupyter lab --allow-root --no-browser --ip=0.0.0.0 --port=8888 \
      --ServerApp.token="$JUPYTER_PASSWORD" --ServerApp.allow_origin='*' --ServerApp.root_dir=/workspace \
      >> /workspace/jupyter.log 2>&1
  fi
) &

if [ -x /start.sh ]; then exec /start.sh; else exec sleep infinity; fi
