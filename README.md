# H3 ComfyUI RunPod template

One image with ComfyUI (current), all custom nodes and the Model 2 workflows. **No models inside**: they sit on a RunPod *network volume*, are downloaded once, and every later pod start only checks that they are there. No installers, no ComfyUI update, no restart dance.

## One-time setup
1. Make a GitHub repository (private is fine) and push this folder to it. The Action **build-image** builds and pushes `ghcr.io/<your-github-name>/h3-comfy:latest` (Actions tab -> run it once; takes ~15-25 min).
   In GitHub -> your profile -> Packages -> h3-comfy -> Package settings: either make it public, or add your GitHub token as registry credentials in RunPod (Settings -> Container Registry Auth).
2. RunPod -> Storage -> **New network volume**, size **150 GB**, in a datacenter that has the GPUs you want (pods can only use the volume in its own datacenter).
3. RunPod -> Templates -> New template:
   - Container image: `ghcr.io/<your-github-name>/h3-comfy:latest`
   - Container disk: 20 GB. Volume mount path: `/workspace` (attach the network volume when you deploy)
   - Expose HTTP ports: `8188` (ComfyUI), `8888` (Jupyter, optional). TCP `22` (SSH, optional)
   - Environment variables (all optional): `HF_TOKEN`, `MODEL_SET` (default `image,video,finish`), `AUTO_STOP_MIN` (e.g. `30`), `COMFY_ARGS`, `I2V=1`
4. Deploy a pod with the volume. Upload `icynodes.zip` to `/workspace` once (Jupyter or `runpodctl`), then restart the pod once. First start downloads ~75 GB (watch `/workspace/h3_bootstrap.log`); after that starts take about a minute.
5. Put your `ine3ss_*.safetensors` LoRAs in `/workspace/comfy/models/loras` and `model2_anchor.png` in `/workspace/comfy/input` (also kept on the volume).

## What you save
- No installer / ComfyUI update / manual restart on any pod.
- The pod bills only while it runs: **AUTO_STOP_MIN=30** stops it after 30 idle minutes (nothing queued, GPU below 5%). Opening or editing a workflow does not count as activity, so keep it at 30 or more. Test once that `runpodctl stop pod $RUNPOD_POD_ID` works in a pod terminal.
- A volume costs only a few cents per GB per month, much less than leaving a GPU idle.

## Notes
- Workflows are copied from the image at every start (they overwrite the same names). Save your own edits under a new name.
- ComfyUI restarts itself if it is killed by out-of-memory.
- To update ComfyUI: run the Action again (pulls the latest ComfyUI), then redeploy.
- MiniMax H3 weights have their own licence (not valid in the EU, UK, USA, South Korea). Read it on Hugging Face first.
- Do not put tokens into the repo; use the template environment variables.
