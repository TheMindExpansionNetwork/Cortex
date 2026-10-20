#!/usr/bin/env bash
# Cortex · hosting/boot-and-test.sh — one command: boot a RunPod GPU pod, build the deepseek41 runtime,
# download DeepSeek-V4.1-Flash, serve it, run real prompts, save tok/s + power, and DELETE the pod.
#
#   bash hosting/boot-and-test.sh --dry-run          # stock + prices + plan + cost check; creates NOTHING
#   bash hosting/boot-and-test.sh                    # PLAN=auto: cheapest available plan below
#   PLAN=2xpro6000 bash hosting/boot-and-test.sh     # 2x RTX PRO 6000 Blackwell 96GB + IQ1_M (192 GB; cheapest fit seen)
#   PLAN=h200 bash hosting/boot-and-test.sh          # 1x H200 141GB + IQ1_S  (fits on one GPU)
#   PLAN=2xh100 bash hosting/boot-and-test.sh        # 2x H100 80GB + IQ1_M
#   PLAN=2xa100 bash hosting/boot-and-test.sh        # 2x A100 SXM 80GB + IQ1_M
#   KEEP=1 bash hosting/boot-and-test.sh             # leave the pod running afterwards (you pay until you delete it)
#
# Needs: runpodctl >= 3 on PATH, RUNPOD_API_KEY + HF_TOKEN in the environment (or in ~/.hermes/.env), and an SSH
# key that is registered on the RunPod account (runpodctl ssh list-keys) at ~/.ssh/id_ed25519.
#
# Safety rails: --dry-run creates nothing; refuses to start if the balance cannot cover MAX_MINUTES at the plan's
# price; a watchdog deletes the pod after MAX_MINUTES no matter what; the EXIT trap deletes it on success, failure
# or Ctrl-C (unless KEEP=1). Engine = llama.cpp PR #30817 (scripts/build-llama-dsv41.sh); mainline cannot load it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PLAN="${PLAN:-auto}"
CTX="${CTX:-32768}"
MAX_MINUTES="${MAX_MINUTES:-90}"       # hard cap on billed time (watchdog)
KEEP="${KEEP:-0}"
CLOUD="${CLOUD:-COMMUNITY}"            # COMMUNITY (cheaper) or SECURE
IMAGE="${IMAGE:-runpod/base:1.5.0-rc.181-cuda1281-ubuntu2204}"
KEY="${KEY:-$HOME/.ssh/id_ed25519}"
NAME="cortex-test-$(date +%m%d-%H%M)"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1

# credentials: environment first, then the Hermes .env (never printed)
envget() { local v="${!1:-}"; [[ -z "$v" && -f "$HOME/.hermes/.env" ]] && v=$(grep -E "^$1=" "$HOME/.hermes/.env" | head -1 | cut -d= -f2- | tr -d '"'); echo "$v"; }
export RUNPOD_API_KEY="$(envget RUNPOD_API_KEY)"; HF_TOKEN="$(envget HF_TOKEN)"
[[ -n "$RUNPOD_API_KEY" ]] || { echo "[cortex] RUNPOD_API_KEY not set"; exit 1; }
[[ -n "$HF_TOKEN" ]] || { echo "[cortex] HF_TOKEN not set"; exit 1; }
command -v runpodctl >/dev/null || { echo "[cortex] runpodctl not on PATH"; exit 1; }

# plan table: name | gpuId | count | quant | CUDA arch
PLANS=$'2xpro6000|NVIDIA RTX PRO 6000 Blackwell Server Edition|2|IQ1_M|120\nh200|NVIDIA H200|1|IQ1_S|90\n2xh100|NVIDIA H100 80GB HBM3|2|IQ1_M|90\n2xa100|NVIDIA A100-SXM4-80GB|2|IQ1_M|80\n2xa100pcie|NVIDIA A100 80GB PCIe|2|IQ1_M|80'

# ---- 1) live stock + price + balance -> choose a plan --------------------------------------------------------------
GPUS_JSON=$(runpodctl gpu list -o json)
BAL=$(runpodctl user -o json | python3 -c "import json,sys;print(json.load(sys.stdin).get('clientBalance',0))")
CHOICE=$(python3 - "$PLAN" "$CLOUD" "$BAL" "$MAX_MINUTES" "$GPUS_JSON" "$PLANS" <<'PY'
import json, sys
plan, cloud, bal, maxmin, gpus, plans = sys.argv[1], sys.argv[2], float(sys.argv[3]), int(sys.argv[4]), json.loads(sys.argv[5]), sys.argv[6]
rows = gpus if isinstance(gpus, list) else gpus.get("gpus", [])
by_id = {g.get("gpuId") or g.get("id"): g for g in rows}
key = "communityPricePerHr" if cloud == "COMMUNITY" else "securePricePerHr"
cands = []
for line in plans.splitlines():
    name, gid, n, quant, arch = line.split("|")
    g = by_id.get(gid)
    price = (g or {}).get(key) or 0
    ok = bool(g and g.get("available", True) and price)
    hr = price * int(n)
    print(f"  {name:11s} {gid:24s} x{n}  {quant:6s} " + (f"${hr:.2f}/hr  stock={g.get('stockStatus','?')}" if ok else "NOT AVAILABLE"), file=sys.stderr)
    if ok and plan in ("auto", name): cands.append((hr, name, gid, n, quant, arch))
if not cands:
    print("NONE"); sys.exit(0)
hr, name, gid, n, quant, arch = sorted(cands)[0]
need = hr * maxmin / 60
print(f"  -> plan {name}: ${hr:.2f}/hr; cap {maxmin} min = ${need:.2f}; balance ${bal:.2f}", file=sys.stderr)
print("POOR" if bal < need else f"{name}|{gid}|{n}|{quant}|{arch}|{hr:.2f}")
PY
)
[[ "$CHOICE" == "NONE" ]] && { echo "[cortex] no matching GPU plan is listed as available ($CLOUD). Try CLOUD=SECURE or later."; exit 2; }
[[ "$CHOICE" == "POOR" ]] && { echo "[cortex] balance too low for MAX_MINUTES=$MAX_MINUTES — top up, or lower MAX_MINUTES"; exit 2; }
IFS='|' read -r PNAME GPU_ID NGPU QUANT ARCH PRICE <<< "$CHOICE"
echo "[cortex] plan: $PNAME = $NGPU x $GPU_ID, $QUANT, ctx $CTX, ~\$$PRICE/hr, hard cap ${MAX_MINUTES} min"
[[ "$DRY" == 1 ]] && { echo "[cortex] --dry-run: nothing created."; exit 0; }

# ---- 2) create the pod (volume holds the 233-250 GB model; container disk holds the build) -------------------------
OUTDIR="$HERE/bench/results/$(date +%F)-cortex-$PNAME"; mkdir -p "$OUTDIR"
ENV_JSON=$(python3 -c "import json,sys;print(json.dumps({'HF_TOKEN':sys.argv[1],'HF_HUB_ENABLE_HF_TRANSFER':'1'}))" "$HF_TOKEN")
echo "[cortex] creating pod $NAME (waits until running, up to 20 min) ..."
CREATE_OUT=$(runpodctl pod create --name "$NAME" --gpu-id "$GPU_ID" --gpu-count "$NGPU" --cloud-type "$CLOUD" \
  --image "$IMAGE" --container-disk-in-gb 40 --volume-in-gb 280 --volume-mount-path /workspace \
  --ports "8080/http,22/tcp" --env "$ENV_JSON" --wait --wait-timeout 20m -o json 2>&1) || true
echo "$CREATE_OUT" | grep -v "hf_" > "$OUTDIR/pod-create.json" || true
POD_ID=$(python3 - "$CREATE_OUT" <<'PY'
import json, re, sys
s = sys.argv[1]
try:
    d = json.loads(s[s.index("{"):])
    if isinstance(d.get("pod"), dict): d = d["pod"]
    for k in ("id", "podId"):
        if d.get(k): print(d[k]); sys.exit()
except Exception: pass
m = re.search(r'"id"\s*:\s*"([a-z0-9]{8,})"', s)
print(m.group(1) if m else "")
PY
)
if [[ -z "$POD_ID" ]]; then
  # never blind-retry a launch: look it up by name, else report the real error and stop
  POD_ID=$(runpodctl pod list -o json | python3 -c "import json,sys;n=sys.argv[1];print(next((p['id'] for p in json.load(sys.stdin) if p.get('name')==n),''))" "$NAME")
fi
[[ -n "$POD_ID" ]] || { echo "[cortex] pod create failed:"; echo "$CREATE_OUT" | grep -v "hf_" | tail -5; exit 1; }
echo "[cortex] pod: $POD_ID"

cleanup() {
  [[ -n "${WATCHDOG:-}" ]] && kill "$WATCHDOG" 2>/dev/null || true
  if [[ "$KEEP" != "1" ]]; then
    echo "[cortex] deleting pod $POD_ID (billing stops)"; runpodctl pod delete "$POD_ID" >/dev/null 2>&1 || true
    runpodctl pod list -o json | grep -q "$POD_ID" && echo "[cortex] WARNING: pod $POD_ID still listed — delete it in the dashboard" || true
  else
    echo "[cortex] KEEP=1: pod $POD_ID left RUNNING (\$$PRICE/hr). Delete with: runpodctl pod delete $POD_ID"
  fi
}
trap cleanup EXIT
( sleep $(( MAX_MINUTES * 60 )); echo "[cortex] WATCHDOG: ${MAX_MINUTES} min reached — deleting $POD_ID"; runpodctl pod delete "$POD_ID" >/dev/null 2>&1 ) &
WATCHDOG=$!

# ---- 3) SSH connection (direct TCP; the ssh.runpod.io proxy cannot run remote commands) -----------------------------
SSH_LINE=""
for _ in $(seq 1 40); do
  SSH_LINE=$(runpodctl ssh info "$POD_ID" -o json 2>/dev/null | python3 -c "
import json,sys,re
s=json.dumps(json.load(sys.stdin))
m=re.search(r'root@([0-9.]+)[^0-9]+-p\s*([0-9]+)', s) or re.search(r'\"ip\":\s*\"([0-9.]+)\".*?\"port\":\s*([0-9]+)', s)
print(f'{m.group(1)} {m.group(2)}' if m else '')" 2>/dev/null || true)
  [[ -n "$SSH_LINE" ]] && break; sleep 15
done
[[ -n "$SSH_LINE" ]] || { echo "[cortex] no direct SSH address (community pods may lack a public port 22). Try CLOUD=SECURE."; exit 1; }
read -r IP PORT <<< "$SSH_LINE"
SSH=(ssh -i "$KEY" -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o ServerAliveInterval=30 "root@$IP")
for _ in $(seq 1 20); do "${SSH[@]}" true 2>/dev/null && break; sleep 10; done
echo "[cortex] ssh root@$IP -p $PORT  (connected)"

# ---- 4) on the pod: deps, engine build, download + serve (background) --------------------------------------------
"${SSH[@]}" "bash -s" <<REMOTE | tee "$OUTDIR/setup.log"
set -euo pipefail
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
apt-get update -qq && apt-get install -y -qq git curl build-essential python3-pip >/dev/null
pip3 install -q "cmake>=3.28" "huggingface_hub[cli]" hf_transfer 2>/dev/null || pip3 install -q --break-system-packages "cmake>=3.28" "huggingface_hub[cli]" hf_transfer
export PATH="/usr/local/cuda/bin:\$PATH"
git clone -q --depth 1 https://github.com/TheMindExpansionNetwork/Cortex /workspace/cortex 2>/dev/null || git -C /workspace/cortex pull -q
cd /workspace && SRC=/workspace/llama.cpp OUT=/workspace/bin CUDA=ON CUDA_ARCHS="$ARCH" bash /workspace/cortex/scripts/build-llama-dsv41.sh 2>&1 | tail -3
nohup bash /workspace/cortex/scripts/deepseek-2xa100.sh --quant $QUANT --ctx $CTX --repo /workspace/models/dsv41 \
  --server /workspace/bin/llama-server > /workspace/cortex.log 2>&1 &
echo "launcher started (pid \$!)"
REMOTE

# ---- 5) wait for the API (health is checked ON the pod — port 8080 is only exposed via the RunPod HTTP proxy) -------
echo "[cortex] downloading + loading (watch: ssh ... tail -f /workspace/cortex.log)"
T0=$(date +%s)
until "${SSH[@]}" "curl -sf -m 5 localhost:8080/health" >/dev/null 2>&1; do
  sleep 30
  "${SSH[@]}" "tail -c 400 /workspace/cortex.log | tr '\r' '\n' | tail -1; du -sh /workspace/models 2>/dev/null | cut -f1" 2>/dev/null | sed 's/^/   /' || true
  "${SSH[@]}" "pgrep -f llama-server >/dev/null || pgrep -f 'hf download' >/dev/null" 2>/dev/null \
    || { echo "[cortex] launcher died — last log lines:"; "${SSH[@]}" "tail -25 /workspace/cortex.log" | tee "$OUTDIR/failure.log"; exit 1; }
done
echo "[cortex] SERVER UP after $(( ($(date +%s) - T0) / 60 )) min"

# ---- 6) real prompts + measurements --------------------------------------------------------------------------------
"${SSH[@]}" "bash -s" <<'REMOTE' | tee "$OUTDIR/results.txt"
ask() {
  curl -s -m 900 localhost:8080/v1/chat/completions -H 'Content-Type: application/json' -d "$1" > /tmp/r.json
  python3 - <<'PY'
import json
d = json.load(open('/tmp/r.json'))
m = d.get('choices', [{}])[0].get('message', {})
t = d.get('timings', {})
print('reply   :', (m.get('content') or '')[:500].replace('\n', ' '))
print('thinking:', len(m.get('reasoning_content') or ''), 'chars')
print(f"speed   : prompt {t.get('prompt_per_second', 0):.1f} tok/s | generate {t.get('predicted_per_second', 0):.1f} tok/s | {t.get('predicted_n')} tokens")
PY
}
echo "=== 1) identity (reasoning low) ==="
ask '{"model":"x","max_tokens":300,"chat_template_kwargs":{"reasoning_effort":"low"},"messages":[{"role":"user","content":"In two sentences: who made you and what is your Engram memory?"}]}'
echo "=== 2) code (reasoning default 75) ==="
( sleep 8; nvidia-smi --query-gpu=index,power.draw,memory.used,utilization.gpu --format=csv > /tmp/power.csv ) &
ask '{"model":"x","max_tokens":700,"messages":[{"role":"user","content":"Write a Python function that returns the n-th Fibonacci number in O(log n) time, with a one-line explanation."}]}'
wait; echo "=== GPU during generation ==="; cat /tmp/power.csv
echo "=== memory ==="; free -g | head -2; nvidia-smi --query-gpu=memory.used,memory.total --format=csv
REMOTE
"${SSH[@]}" "cat /workspace/cortex.log" > "$OUTDIR/server.log" 2>/dev/null || true
echo "[cortex] results saved in $OUTDIR"
