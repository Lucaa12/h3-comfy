#!/usr/bin/env bash
# Runs on every pod start. Everything is idempotent: what is already on the volume is skipped, interrupted downloads resume.
# Env (set in the RunPod template):  HF_TOKEN (optional)  MODEL_SET=image,video,finish (default all)  I2V=1 (also photo-to-video model)
#   COMFY_ARGS (extra ComfyUI flags)   AUTO_STOP_MIN=30 (stop the pod after that many idle minutes; 0 = never)
#   Without a network volume everything below is fetched again on every start (the container disk is erased when the pod stops):
#   ICY_ZIP_URL (direct link to icynodes.zip)   LORA_URLS / INPUT_URLS (space-separated direct links -> models/loras and input)
#   For links on huggingface.co (also private repos) HF_TOKEN is used automatically.
set -uo pipefail
DATA=/workspace/comfy; M=$DATA/models; CN=$DATA/custom_nodes
MODEL_SET="${MODEL_SET:-image,video,finish}"
PY=/opt/venv/bin/python
mkdir -p "$M"/{diffusion_models,text_encoders,vae,vae_approx,loras,model_patches,checkpoints,geometry_estimation,upscale_models,clip_vision} \
         "$DATA"/{input,output,temp,user/default/workflows} "$CN"
echo "== $(date) bootstrap start; ComfyUI $(sed -n 's/^__version__ *= *"\(.*\)"/\1/p' /opt/ComfyUI/comfyui_version.py)"

# nodes baked into the image are made visible through symlinks (the volume copy of a node wins)
for d in /opt/baked/custom_nodes/*/; do n=$(basename "$d"); [ -e "$CN/$n" ] || ln -s "$d" "$CN/$n"; done

dl() { # dl <url> <dir>
  local url="$1" dir="$2" name; name="$(basename "${url%%\?*}")"
  if [ -s "$dir/$name" ] && [ ! -f "$dir/$name.part" ]; then return 0; fi
  echo "fetch $name"
  local ah=(); [[ "$url" == *huggingface.co* && -n "${HF_TOKEN:-}" ]] && ah=(--header="Authorization: Bearer $HF_TOKEN")
  touch "$dir/$name.part"
  if aria2c -c -x 16 -s 16 -k 8M --file-allocation=none --console-log-level=warn --summary-interval=30 "${ah[@]}" -d "$dir" -o "$name" "$url"; then
    rm -f "$dir/$name.part"
  else echo "FAILED $name (it resumes on the next start)"; return 1; fi
}

# files you supply by link (private things stay out of the image)
[ -n "${ICY_ZIP_URL:-}" ] && dl "$ICY_ZIP_URL" /workspace
for u in ${LORA_URLS:-}; do dl "$u" "$M/loras"; done
for u in ${INPUT_URLS:-}; do dl "$u" "$DATA/input"; done

# IcyNodes from the zip you keep on the volume (private, so not inside the image)
if [ ! -f "$CN/icynodes/__init__.py" ]; then
  Z="$(ls -t /workspace/*icynodes*.zip /workspace/comfy/*icynodes*.zip 2>/dev/null | head -1 || true)"
  if [ -n "$Z" ]; then
    $PY -m zipfile -e "$Z" "$CN/" && find "$CN/icynodes" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
    grep -vi '^torch' "$CN/icynodes/requirements.txt" > /tmp/icy_req.txt 2>/dev/null && $PY -m pip install -q -r /tmp/icy_req.txt
    echo "installed IcyNodes from $Z"
  else
    echo "NOTE: icynodes.zip not found in /workspace. Upload it once; first-frame / LoRA-tester workflows need it."
  fi
fi

# workflows from the image (overwritten each start; save your own edits under a new name)
cp -f /opt/h3/workflows/*.json "$DATA/user/default/workflows/" 2>/dev/null

# ComfyUI starts NOW (restarts itself if it crashes, e.g. after an out-of-memory kill). Models that are still downloading
# appear after the downloads finish: press R in ComfyUI (refresh node definitions) or reload the page.
[ "${AUTO_STOP_MIN:-0}" != "0" ] && nohup bash /opt/h3/autostop.sh > /workspace/h3_autostop.log 2>&1 &
( cd /opt/ComfyUI
  while true; do
    echo "== $(date) starting ComfyUI"
    $PY main.py --listen 0.0.0.0 --port 8188 --base-directory "$DATA" ${COMFY_ARGS:-}
    echo "ComfyUI exited ($?); restarting in 5 s"; sleep 5
  done ) &

touch /workspace/.h3_downloading
H=https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main
HI=https://huggingface.co/Comfy-Org/MiniMax-H3-Image/resolve/main
has() { [[ ",$MODEL_SET," == *",$1,"* ]]; }
if has image; then
  dl $HI/diffusion_models/minimax_h3_image_pruned_int8_convrot.safetensors "$M/diffusion_models"
  dl $HI/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors "$M/text_encoders"
  dl $HI/vae/minimax_h3_image_vae_fp16.safetensors "$M/vae"
  dl https://raw.githubusercontent.com/madebyollin/taehv/62f7591f59dfbb4c3c02b7a621d180a9eeaba26c/safetensors/taeh3.safetensors "$M/vae_approx"
fi
if has video; then
  dl $H/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors "$M/text_encoders"
  dl $H/vae/minimax_h3_audio_vae_fp32.safetensors "$M/vae"
  dl $H/vae/minimax_h3_video_vae_fp16.safetensors "$M/vae"
  dl $H/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors "$M/diffusion_models"
  dl $H/loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors "$M/loras"
  dl $H/model_patches/minimax_h3_fun_controlnet_union_pruned_int8_convrot.safetensors "$M/model_patches"
  dl https://huggingface.co/Comfy-Org/SDPose/resolve/main/checkpoints/sdpose_wholebody_fp16.safetensors "$M/checkpoints"
  dl https://huggingface.co/Comfy-Org/SDPose/resolve/main/diffusion_models/rt_detr_v4-x-hgnet_fp16.safetensors "$M/diffusion_models"
  dl https://huggingface.co/Comfy-Org/sam3.1/resolve/main/checkpoints/sam3.1_multiplex_fp16.safetensors "$M/checkpoints"
  dl https://huggingface.co/Comfy-Org/Depth-Anything-3/resolve/main/geometry_estimation/depth_anything_3_mono_large.safetensors "$M/geometry_estimation"
  if [ "${I2V:-0}" = "1" ]; then
    dl $H/vae/minimax_h3_video_vae_int8_convrot.safetensors "$M/vae"
    dl $H/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors "$M/diffusion_models"
    dl https://huggingface.co/lightx2v/Minimax-h3-Turbo/resolve/main/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors "$M/loras"
  fi
fi
if has finish || has video; then
  dl https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth "$M/upscale_models"
  dl https://huggingface.co/licyk/sd-upscaler-models/resolve/main/ESRGAN/1x-ITF-SkinDiffDetail-Lite-v1.pth "$M/upscale_models"
fi
rm -f /workspace/.h3_downloading
df -h /workspace | tail -1
echo "== $(date) all downloads finished. In ComfyUI press R (or reload the page) so the new models show up."
wait
