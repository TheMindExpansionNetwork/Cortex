#!/usr/bin/env bash
# Cortex · scripts/deepseek-2xa100.sh
# One-command bring-up for DeepSeek-V4.1-Flash-1017 (Unsloth GGUF) on 2× A100 80GB.
# Downloads the quant shards + vision encoder (+ optional DSpark drafter), then launches
# llama-server with the recommended settings. Engram table (shard 5) stays on NVMe via mmap.
#
# Usage:
#   bash scripts/deepseek-2xa100.sh --quant IQ1_M --ctx 65536 --port 8080
# Options:
#   --quant IQ1_M|IQ1_S      (default IQ1_M; the only quants that fit 160 GB VRAM)
#   --ctx 65536              context size (model max 1048576)
#   --port 8080              API port (OpenAI + Anthropic compatible)
#   --engram ram|ssd         ram = keep Engram in host RAM if >=128 GB free (default: auto)
#   --dspark                 also download the speculative drafter (8.5 GB)
#   --repo DIR               where to put files (default ./models/dsv41)
set -euo pipefail

QUANT="IQ1_M"; CTX=65536; PORT=8080; ENGRAM=auto; DSPARK=0; REPO_DIR="models/dsv41"
while [[ $# -gt 0 ]]; do case "$1" in
  --quant) QUANT="$2"; shift 2;; --ctx) CTX="$2"; shift 2;; --port) PORT="$2"; shift 2;;
  --engram) ENGRAM="$2"; shift 2;; --dspark) DSPARK=1; shift;; --repo) REPO_DIR="$2"; shift 2;;
  *) echo "unknown option $1"; exit 1;;
esac; done

case "$QUANT" in IQ1_M|IQ1_S) ;; *) echo "Only IQ1_M / IQ1_S fit 2× A100 80GB. See docs/CORTEX-DEEPSEEK.md"; exit 1;; esac
# HF folder name carries the "UD-" prefix (unsloth Dynamic): UD-IQ1_M/DeepSeek-V4.1-Flash-1017-UD-IQ1_M-00001-of-00005.gguf
HF_QUANT="UD-$QUANT"

REPO="unsloth/DeepSeek-V4.1-Flash-1017-GGUF"
command -v hf >/dev/null 2>&1 || { echo "Need 'hf' (pip install -U huggingface_hub)"; exit 1; }
nvidia-smi --list-gpus | wc -l | grep -qE "^2$" || echo "WARN: expected exactly 2 GPUs, found $(nvidia-smi --list-gpus | wc -l)"

echo "[cortex] downloading $HF_QUANT shards + mmproj into $REPO_DIR ..."
HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}" hf download "$REPO" \
  --include "$HF_QUANT/*" "mmproj-BF16.gguf" --local-dir "$REPO_DIR"
[[ "$DSPARK" == 1 ]] && hf download "$REPO" --include "dspark/*" --local-dir "$REPO_DIR"

MODEL=$(ls "$REPO_DIR/$HF_QUANT/"*-00001-of-00005.gguf 2>/dev/null | head -1)
MMPROJ="$REPO_DIR/mmproj-BF16.gguf"

if command -v python3 >/dev/null; then
python3 -c "
need = {'IQ1_M': 139.8, 'IQ1_S': 122.4}['$QUANT']
kv  = 0.00000089 * $CTX
print(f'[cortex] resident weights ≈ {need:.1f} GB | KV@{$CTX}ctx ≈ {kv:.2f} GB | 2×A100 = 160.0 GB')
"
fi

# Engram placement: the last shard IS the Engram table. "ram" = ensure host has room and let the
# page cache hold it (fast); "ssd"/auto = let mmap stream rows on demand (NVMe recommended).
echo "[cortex] engram mode: $ENGRAM (table = $QUANT shard 00005; ~110.6 GB IQ4_NL)"

echo "[cortex] launching llama-server on 0.0.0.0:$PORT ..."
# -ngl 99: everything resident on GPU; --split-mode layer: split across both A100s
exec llama-server \
  -m "$MODEL" \
  --mmproj "$MMPROJ" \
  --ctx-size "$CTX" \
  -ngl 99 --split-mode layer --tensor-split 1,1 \
  --temp 1.0 --top-p 1.0 --min-p 0.0 \
  --chat-template-kwargs '{"reasoning_effort":75}' \
  --host 0.0.0.0 --port "$PORT" \
  --jinja --metrics
