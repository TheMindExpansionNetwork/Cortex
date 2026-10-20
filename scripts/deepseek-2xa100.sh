#!/usr/bin/env bash
# Cortex · scripts/deepseek-2xa100.sh — download + serve DeepSeek-V4.1-Flash-1017 (Unsloth GGUF).
# (Name kept for compatibility; it is GPU-count agnostic: 2× A100/H100 80GB, or 1× H200 141GB with IQ1_S.)
#
# Recipe = Unsloth's documented llama.cpp path (unsloth.ai/docs/models/deepseek-v4.1-flash), verified flags:
#   * runtime: llama-server built from ggml-org/llama.cpp PR #30817 — see scripts/build-llama-dsv41.sh.
#     Mainline llama.cpp CANNOT load this model (no `deepseek41` arch).
#   * the Engram table (tensor per_layer_token_embd.weight, ~110.6 GB, the last shard) is pinned OFF the GPUs:
#       --override-tensor "per_layer_token_embd.weight=CPU" --load-mode mmap --lazy-mode on
#     Rows then stream from disk through the page cache. Without this, -ngl would try to put 250 GB on the GPUs.
#   * sampling: temp 1.0, top-p 1.0, top-k 0, min-p 0; reasoning_effort 75 (1–100 / low|medium|high|max).
#
# Usage:
#   bash scripts/deepseek-2xa100.sh --quant IQ1_M --ctx 32768
#   bash scripts/deepseek-2xa100.sh --quant IQ1_S --ctx 32768          # 1× H200 141GB
# Options:
#   --quant IQ1_M|IQ1_S   IQ1_M = 139.8 GB on GPU (needs 2×80GB); IQ1_S = 122.4 GB (fits 1× H200 or 2×80GB)
#   --ctx N               context (default 32768; model max 1048576; KV ≈ 890 bytes/token)
#   --port N              API port (default 8080; OpenAI-compatible /v1/chat/completions)
#   --repo DIR            model folder (default /workspace/models/dsv41 if /workspace exists, else ./models/dsv41)
#   --server PATH         llama-server binary (default: llama-server on PATH, else ./llama.cpp-dsv41/llama-server)
#   --vision              also load the vision encoder (mmproj-BF16.gguf, ~0.93 GB). Off by default for run #1.
#   --dspark              EXPERIMENTAL draft-model speed-up (DSpark Q8_0, 7.4 GB): -md + --spec-type draft-dspark
#   --no-download         use files already in --repo
#   --force               start even if the VRAM check says it will not fit
set -euo pipefail

QUANT="IQ1_M"; CTX=32768; PORT=8080; VISION=0; DSPARK=0; DOWNLOAD=1; FORCE=0; SERVER=""
REPO_DIR=""; [[ -d /workspace ]] && REPO_DIR="/workspace/models/dsv41" || REPO_DIR="models/dsv41"
while [[ $# -gt 0 ]]; do case "$1" in
  --quant) QUANT="$2"; shift 2;; --ctx) CTX="$2"; shift 2;; --port) PORT="$2"; shift 2;;
  --repo) REPO_DIR="$2"; shift 2;; --server) SERVER="$2"; shift 2;;
  --vision) VISION=1; shift;; --dspark) DSPARK=1; shift;; --no-download) DOWNLOAD=0; shift;;
  --force) FORCE=1; shift;;
  --engram) shift 2;;   # accepted for old command lines; Engram placement is now always CPU/mmap (official recipe)
  *) echo "unknown option $1"; exit 1;;
esac; done

case "$QUANT" in
  IQ1_M) NEED_GB=139.8; SHARDS=5;;
  IQ1_S) NEED_GB=122.4; SHARDS=5;;
  *) echo "[cortex] only IQ1_M / IQ1_S fit 160 GB-class GPU memory — see docs/CORTEX-DEEPSEEK.md"; exit 1;;
esac
HF_QUANT="UD-$QUANT"   # the HF folder carries the Unsloth Dynamic prefix: UD-IQ1_M/...-UD-IQ1_M-00001-of-00005.gguf
REPO="unsloth/DeepSeek-V4.1-Flash-1017-GGUF"

# ---- runtime binary --------------------------------------------------------------------------------------
if [[ -z "$SERVER" ]]; then
  if command -v llama-server >/dev/null 2>&1; then SERVER=$(command -v llama-server)
  elif [[ -x ./llama.cpp-dsv41/llama-server ]]; then SERVER=./llama.cpp-dsv41/llama-server
  else echo "[cortex] no llama-server found — run: bash scripts/build-llama-dsv41.sh"; exit 1; fi
fi
"$SERVER" --help 2>&1 | grep -q -- "--lazy-mode" || { echo "[cortex] $SERVER is not the deepseek41 build (no --lazy-mode). Run scripts/build-llama-dsv41.sh"; exit 1; }

# ---- GPU fit check (resident weights + KV + ~6 GB buffers vs total VRAM) --------------------------------
if command -v nvidia-smi >/dev/null 2>&1; then
  NGPU=$(nvidia-smi --list-gpus | wc -l)
  VRAM_GB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | awk '{s+=$1} END {printf "%.1f", s/1024}')
  python3 - "$NEED_GB" "$CTX" "$VRAM_GB" "$NGPU" "$FORCE" <<'PY'
import sys
need, ctx, vram, ngpu, force = float(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), sys.argv[5] == "1"
kv = 890 * ctx / 1e9
total = need + kv + 6.0
print(f"[cortex] GPUs: {ngpu}, VRAM {vram:.1f} GB | needs ≈ {need:.1f} weights + {kv:.2f} KV + 6.0 buffers = {total:.1f} GB")
if total > vram and not force:
    print("[cortex] will NOT fit — pick IQ1_S, more GPUs, or pass --force"); sys.exit(1)
PY
else
  echo "[cortex] WARN: nvidia-smi not found — no GPU fit check"
fi

# ---- disk check + download -------------------------------------------------------------------------------
mkdir -p "$REPO_DIR"
if [[ "$DOWNLOAD" == 1 ]]; then
  command -v hf >/dev/null 2>&1 || { echo "[cortex] need 'hf' — pip install -U 'huggingface_hub[cli]' hf_transfer"; exit 1; }
  FREE_GB=$(df -BG --output=avail "$REPO_DIR" | tail -1 | tr -dc '0-9')
  WANT_GB=$([[ "$QUANT" == IQ1_M ]] && echo 252 || echo 235)
  (( FREE_GB >= WANT_GB )) || { echo "[cortex] only ${FREE_GB} GB free in $REPO_DIR, need ~${WANT_GB} GB"; exit 1; }
  INC=("$HF_QUANT/*")
  [[ "$VISION" == 1 ]] && INC+=("mmproj-BF16.gguf")
  [[ "$DSPARK" == 1 ]] && INC+=("dspark-DeepSeek-V4.1-Flash-1017-Q8_0.gguf")
  echo "[cortex] downloading ${INC[*]} into $REPO_DIR (≈250 GB for IQ1_M; resumable — just re-run)"
  HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}" hf download "$REPO" --include "${INC[@]}" --local-dir "$REPO_DIR"
fi

MODEL="$REPO_DIR/$HF_QUANT/DeepSeek-V4.1-Flash-1017-$HF_QUANT-00001-of-0000$SHARDS.gguf"
[[ -f "$MODEL" ]] || { echo "[cortex] missing $MODEL"; exit 1; }
N_HAVE=$(ls "$REPO_DIR/$HF_QUANT/"*.gguf 2>/dev/null | wc -l)
(( N_HAVE == SHARDS )) || { echo "[cortex] have $N_HAVE of $SHARDS shards — re-run to finish the download"; exit 1; }

ARGS=(
  -m "$MODEL"
  --ctx-size "$CTX"
  -ngl 999 --split-mode layer
  --override-tensor "per_layer_token_embd.weight=CPU"
  --load-mode mmap --lazy-mode on
  --temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0
  --chat-template-kwargs '{"reasoning_effort":75}'
  --jinja --metrics
  --host 0.0.0.0 --port "$PORT"
)
[[ "$VISION" == 1 ]] && ARGS+=(--mmproj "$REPO_DIR/mmproj-BF16.gguf")
[[ "$DSPARK" == 1 ]] && ARGS+=(-md "$REPO_DIR/dspark-DeepSeek-V4.1-Flash-1017-Q8_0.gguf" --spec-type draft-dspark)

echo "[cortex] launching: $SERVER ${ARGS[*]}"
exec "$SERVER" "${ARGS[@]}"
