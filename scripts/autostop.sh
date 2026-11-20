#!/usr/bin/env bash
# Stops THIS pod (so billing stops) when nothing has run for AUTO_STOP_MIN minutes.
# Idle = ComfyUI queue empty AND GPU below 5% AND no download running. Editing a workflow in the browser does NOT count as activity.
# The stop command is runpodctl (comes with RunPod pods); the volume and everything on it stays.
LIMIT="${AUTO_STOP_MIN:-30}"; idle=0
sleep 300
while true; do
  sleep 60
  busy=0
  [ -f /workspace/.h3_downloading ] && busy=1
  q=$(curl -s --max-time 5 http://127.0.0.1:8188/queue || echo "")
  if [ -z "$q" ] || echo "$q" | grep -q '"queue_running": \[\[' || echo "$q" | grep -q '"queue_pending": \[\['; then busy=1; fi
  u=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
  [ -n "$u" ] && [ "$u" -ge 5 ] && busy=1
  if [ $busy = 1 ]; then idle=0; else idle=$((idle+1)); fi
  echo "$(date +%H:%M) idle ${idle}/${LIMIT} min"
  if [ "$idle" -ge "$LIMIT" ]; then
    echo "idle limit reached: stopping pod ${RUNPOD_POD_ID:-?}"
    runpodctl stop pod "${RUNPOD_POD_ID}" || echo "runpodctl stop failed (check it works in a terminal: runpodctl stop pod \$RUNPOD_POD_ID)"
    sleep 120
  fi
done
