#!/usr/bin/env bash
# Cortex · hosting/boot-and-test.sh — the one-command A100 test rig.
# Boots a temporary RunPod pod (2 GPUs), installs the runtime, downloads the model,
# launches it, hits the OpenAI-compatible API with a real prompt, and reports tok/s.
#
#   bash hosting/boot-and-test.sh                          # 2x A100 SXM community, IQ1_M
#   bash hosting/boot-and-test.sh --quant IQ1_S --destroy-on-exit
#
# Requirements: runpodctl on PATH + RUNPOD_API_KEY in the env; an SSH key pair at
# ~/.ssh/id_ed25519(.pub) (the PUBLIC key is injected into the pod).
set -euo pipefail

GPU="${GPU:-NVIDIA A100-SXM4-80GB}"
COUNT="${COUNT:-2}"
CLOUD="${CLOUD:---communityCloud}"        # or --secureCloud
QUANT="${QUANT:-IQ1_M}"
CTX="${CTX:-65536}"
NAME="${NAME:-cortex-flash-test}"
DISK="${DISK:-300}"
REPO_DIR="/models/dsv41"
DESTROY="${DESTROY_ON_EXIT:-0}"
TIMEOUT_MIN="${TIMEOUT_MIN:-90}"

KEY_NAME="${KEY_NAME:-id_ed25519}"
PUB=$(cat ~/.ssh/$KEY_NAME.pub)
envs=(
  --env "PUBLIC_KEY=$PUB"
  --env "HF_TOKEN=${HF_TOKEN:?set HF_TOKEN in the environment}"
  --env "HF_HUB_ENABLE_HF_TRANSFER=1"
)

echo "[cortex] creating pod: $COUNT x $GPU ($CLOUD)"
POD_JSON=$(runpodctl create pod --name "$NAME" --gpuType "$GPU" --gpuCount "$COUNT" $CLOUD \
  --containerDiskSize "$DISK" --volumeSize 10 --ports "8080/http" "${envs[@]}" \
  --imageName "runpod/base:1.5.0-rc.181-cuda1281-ubuntu2204" --startSSH -o json)
POD_ID=$(echo "$POD_JSON" | python3 -c "import json,sys;d=json.load(sys.stdin);print((d.get('data') or d).get('pod',{}).get('id') or (d.get('data') or d).get('id',''))")
echo "[cortex] pod id: $POD_ID"

cleanup() {
  if [[ "$DESTROY" == "1" && -n "${POD_ID:-}" ]]; then
    echo "[cortex] destroying pod $POD_ID"
    runpodctl pod terminate "$POD_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# --- wait for SSH (RunPod assigns a mapped TCP port for 22) ---
echo "[cortex] waiting for the pod to come online..."
SSH_IP=""; SSH_PORT=""
deadline=$(( $(date +%s) + TIMEOUT_MIN * 60 / 3 ))
while true; do
  STATUS=$(runpodctl pod get "$POD_ID" -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
p=d.get('pod',d)
print(p.get('desiredStatus',''), p.get('port') if isinstance(p,dict) else '')
" 2>/dev/null || echo "")
  RUNTIME=$(runpodctl pod get "$POD_ID" -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
p=d.get('pod',d)
ports=(p.get('runtime',{}) or {}).get('ports',[]) if isinstance(p,dict) else []
for pt in ports:
    if pt.get('privatePort')==22: print(f\"{pt.get('ip')} {pt.get('port')}\"); break
" 2>/dev/null || true)
  if [[ -n "$RUNTIME" ]]; then
    SSH_IP=$(echo "$RUNTIME" | cut -d' ' -f1); SSH_PORT=$(echo "$RUNTIME" | cut -d' ' -f2)
    [[ "$SSH_IP" != "0.0.0.0" && -n "$SSH_PORT" ]] && break
  fi
  sleep 15
done
echo "[cortex] ssh root@$SSH_IP:$SSH_PORT"

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i ~/.ssh/$KEY_NAME root@$SSH_IP -p $SSH_PORT"

# --- bootstrap the runtime, then hand off to the launch script ---
$SSH 'bash -s' <<REMOTE
set -euo pipefail
apt-get update -qq && apt-get install -y -qq git curl >/dev/null
pip install -q --break-system-packages -U huggingface_hub hf_transfer 2>/dev/null || pip install -q -U huggingface_hub hf_transfer
# llama.cpp prebuilt CUDA binary (matches the container's CUDA 12.x runtime)
if [ ! -x /opt/llama/llama-server ]; then
  mkdir -p /opt/llama && cd /opt/llama
  URL=\$(curl -s https://api.github.com/repos/ggml-org/llama.cpp/releases/latest | python3 -c "import json,sys;rs=json.load(sys.stdin)['assets'];print([a['browser_download_url'] for a in rs if 'ubuntu-x64' in a['name'] and 'cuda' in a['name'].lower() and '12.4' in a['name']][0])")
  curl -sL "\$URL" | tar xz --strip-components=1
fi
git clone --depth 1 https://github.com/TheMindExpansionNetwork/Cortex /opt/cortex || true
REMOTE

echo "[cortex] downloading the model ($QUANT) and launching — this takes a while (250 GB class)..."
$SSH "bash /opt/cortex/scripts/deepseek-2xa100.sh --quant $QUANT --ctx $CTX --repo $REPO_DIR > /var/log/cortex.log 2>&1 &
sleep 5; echo 'launcher running in background (tail /var/log/cortex.log)'"

# --- wait for the API, then test ---
echo "[cortex] waiting for llama-server to answer on :8080 ..."
deadline=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
until curl -s -m 5 "http://$SSH_IP:8080/health" >/dev/null 2>&1; do
  sleep 20
  [[ $(date +%s) -gt $deadline ]] && { echo "[cortex] TIMEOUT waiting for the server"; $SSH "tail -30 /var/log/cortex.log" || true; exit 1; }
done

echo "[cortex] SERVER UP — running the smoke test:"
curl -s -m 300 "http://$SSH_IP:8080/v1/chat/completions" -H "Content-Type: application/json" -d '{
  "model": "cortex", "max_tokens": 128,
  "messages": [{"role":"user","content":"In one short paragraph: what are you, and what does your Engram memory do?"}]
}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
ch=d.get('choices',[{}])[0].get('message',{}).get('content','')[:600]
u=d.get('usage',{})
print('reply:', ch)
print('tokens:', u.get('completion_tokens'), '| prompt:', u.get('prompt_tokens'))
"
echo "[cortex] tok/s + power: run on the pod:"
$SSH "grep -E 'tokens per second|tokens/sec' /var/log/cortex.log | tail -4; nvidia-smi --query-gpu=name,power.draw,memory.used --format=csv" || true
echo "[cortex] done. (pod $POD_ID; DESTROY_ON_EXIT=$DESTROY)"
