# Upstream deepseek41 reference (vendored)

This directory holds a **read-only copy** of the reference implementation of the
`deepseek41` GGUF architecture (DeepSeek-V4.1-Flash, 748B-A16B) used to spec the
Cortex engine port (ROADMAP Phase P1). These files are **not built** into the
Cortex engine — they are the port source.

## Source

- Repository: `https://github.com/unslothai/llama.cpp`
- Branch: `dsv41-all`
- Pinned commit: see `PINNED_SHA`
- License: MIT (llama.cpp). Upstream notice headers preserved in the files.

## What the branch implements

| File | Contents |
| --- | --- |
| `reference/deepseek41.cpp` | The model builder: causal encoder–decoder (20+20 layers), two-tier sparse attention (128-token SWA + compressed KV latents + indexer keep-512 with 2048 blocks × 8 candidates), hyper-connections (4 residual copies, Sinkhorn-doubly-stochastic combine), MoE (1 shared + 384 routed, 6 active), Engram conditional memory (2 tables, 2/3/4-gram hash, PLE-style KV metadata), reasoning-effort (1–100) template kwargs |
| `reference/dflash.cpp` | The DSpark drafter (`dflash` = DSpark Flash): semi-autoregressive draft generation with confidence-scheduled verification; loads `dspark/*.gguf` as a second GGUF |
| `reference/llama-kv-cache-dsv4.h/.cpp` | The compressed KV cache: ≈890 B/token global KV, only 4 layers (2, 8, 14, 20) compress their own KV; `dsv41_kv_src`/`dsv41_topk_src` hparam wiring; token-history cells for the Engram n-gram hash (`dsv41_tok_hist`, `dsv41_hist_len`) |

## Why this branch (not mainline llama.cpp)

Mainline `ggml-org/llama.cpp` has `deepseek4` but **not** `deepseek41` (verified
2026-10-19). The `deepseek41` arch and the Engram on-demand loading live in
Unsloth's fork — the same fork whose runtime the Unsloth Dynamic GGUFs target,
and the same PLE n-gram machinery Cortex's engine already carries for the Qwen
families (`include/cortex/ngram/ple_reader.hpp`, `include/cortex/kernels/ple.hpp`,
`include/cortex/kernels/ngram.hpp`). A third independent implementation exists
(Red-Weasel/machx-inference-engine: `deepseek41_engram.cpp`, `deepseek41_dspark.hpp`)
and is a useful cross-check for Phase P2/P3.

## Port mapping

See [`docs/PORTING-DSV41.md`](../../docs/PORTING-DSV41.md) — upstream
function/module → Cortex engine module, layer plan, memory plan (what lives in
VRAM vs RAM vs NVMe) and the Engram/DSpark wiring plan.
