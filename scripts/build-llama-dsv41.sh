#!/usr/bin/env bash
# Cortex · scripts/build-llama-dsv41.sh — build the llama.cpp runtime that can load DeepSeek-V4.1-Flash.
#
# WHY THIS EXISTS: mainline ggml-org/llama.cpp does NOT have the `deepseek41` architecture (verified
# 2026-10-19). Support lives in the official PR ggml-org/llama.cpp#30817 ("model : add DeepSeek-V4.1-Flash
# (deepseek41)", by danielhanchen/Unsloth) — the exact recipe Unsloth's run guide documents. A llama-server
# built from mainline or a ggml-org release asset will REFUSE the model after a 250 GB download.
#
# We pin the PR head commit so tomorrow's build equals today's verified build. Bump LLAMA_DSV41_SHA
# deliberately (and re-run the CPU smoke build) when the PR moves or merges.
#
#   bash scripts/build-llama-dsv41.sh                 # CUDA build into ./llama.cpp-dsv41 (needs nvcc)
#   CUDA=OFF bash scripts/build-llama-dsv41.sh        # CPU-only build (used to verify the code compiles)
#   OUT=/opt/llama bash scripts/build-llama-dsv41.sh  # where llama-server/llama-cli end up
set -euo pipefail

LLAMA_DSV41_PR="${LLAMA_DSV41_PR:-30817}"
LLAMA_DSV41_SHA="${LLAMA_DSV41_SHA:-b72050d03ae14bb3cb5138ecefab3f3f65157d31}"  # PR #30817 head, verified 2026-10-19 (CPU build + flags + real GGUF header)
SRC="${SRC:-$PWD/llama.cpp-dsv41}"
OUT="${OUT:-$SRC}"
CUDA="${CUDA:-ON}"
# A100 = sm_80, H100 = sm_90, H200 = sm_90, L40S/4090 = sm_89, RTX PRO 6000 Blackwell/5090 = sm_120. Fewer archs = much faster compile.
CUDA_ARCHS="${CUDA_ARCHS:-80;89;90}"
JOBS="${JOBS:-$(nproc)}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "[build] missing '$1'"; exit 1; }; }
need git; need cmake

if [[ ! -d "$SRC/.git" ]]; then
  echo "[build] cloning llama.cpp + PR #$LLAMA_DSV41_PR"
  git clone -q --filter=blob:none https://github.com/ggml-org/llama.cpp "$SRC"
fi
# Fetch the pinned commit itself (by full SHA, so a later force-push to the PR cannot lose it), falling back
# to the PR head ref. No local branch is created, so re-running in an existing checkout is safe.
git -C "$SRC" fetch -q origin "$LLAMA_DSV41_SHA" 2>/dev/null || git -C "$SRC" fetch -q origin "pull/$LLAMA_DSV41_PR/head"
git -C "$SRC" checkout -q "$LLAMA_DSV41_SHA"
echo "[build] at $(git -C "$SRC" log --oneline -1)"
grep -q '"deepseek41"' "$SRC/src/llama-arch.cpp" || { echo "[build] this checkout has no deepseek41 arch — wrong commit?"; exit 1; }

EXTRA=()
if [[ "$CUDA" == "ON" ]]; then
  if ! command -v nvcc >/dev/null 2>&1; then
    for c in /usr/local/cuda/bin/nvcc /usr/local/cuda-*/bin/nvcc; do [[ -x "$c" ]] && export PATH="$(dirname "$c"):$PATH" && break; done
  fi
  need nvcc
  EXTRA+=(-DGGML_CUDA=ON "-DCMAKE_CUDA_ARCHITECTURES=$CUDA_ARCHS" "-DCMAKE_CUDA_COMPILER=$(command -v nvcc)")
else
  EXTRA+=(-DGGML_CUDA=OFF)
fi

cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=OFF "${EXTRA[@]}"
cmake --build "$SRC/build" --config Release -j"$JOBS" --target llama-server llama-cli llama-gguf-split

mkdir -p "$OUT"
cp "$SRC"/build/bin/llama-server "$SRC"/build/bin/llama-cli "$SRC"/build/bin/llama-gguf-split "$OUT"/ 2>/dev/null || true

# The flags the launch script depends on must exist in THIS build (fail now, not after the download).
for f in --load-mode --lazy-mode --override-tensor --chat-template-kwargs --split-mode --jinja; do
  "$OUT/llama-server" --help 2>&1 | grep -q -- "$f" || { echo "[build] llama-server lacks $f — launch would fail"; exit 1; }
done
echo "[build] OK: $OUT/llama-server (deepseek41-capable, flags verified)"
