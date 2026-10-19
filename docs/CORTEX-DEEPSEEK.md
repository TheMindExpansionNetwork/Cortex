# DeepSeek-V4.1-Flash-1017 in Cortex

> The model Cortex is being built around: a frontier-class, open-weights (MIT), multimodal
> Mixture-of-Experts model that is *architected* to be cheap to serve. This page is the single
> source of truth for numbers used across the repo. Last verified: 2026-10-19.

## The model

| Property | Value |
| --- | --- |
| Backbone | 552B MoE (1 shared + 384 routed experts/layer, 6 routed active per token) |
| Engram conditional memory | 196.6B params (~183 GiB FP8 / 110.6 GiB as IQ4_NL) — two hash tables (~384M rows × 256 dims), read by 2/3/4-gram hash |
| Active per token | **8B (prefill) / 16B (decode)** |
| Architecture | Causal encoder–decoder: 20-layer encoder + 20-layer decoder; decoder global KV projected from encoder final hidden state |
| Context / output | 1,048,576 / ≥256K recommended generation budget |
| Vision | native (32-layer ViT + aligner; `image-text-to-text`) |
| KV footprint | ≈ **890 bytes/token** global KV (≈¼ of V4-Flash, ~437× smaller than V1) |
| Checkpoint precision | MXFP4 routed experts, MXFP8 dense, BF16 embed/head, UE8M0 scales |
| DSpark | semi-autoregressive speculative drafting with confidence-scheduled verification (~+14B drafter params) |
| License | MIT |
| Checkpoint | [deepseek-ai/DeepSeek-V4.1-Flash-1017](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash-1017) (2026-10-17 weight update; same arch as 0909 launch) |

Native-checkpoint memory (per the vLLM recipe): routed+DSpark experts 259.5 GiB · Engram 183.1 GiB ·
attention/dense 6.9 GiB · embed/head 3.9 GiB · scales 21.9 GiB. Serving reference: vLLM ≥0.31.0 on
8× B200 (NVIDIA NVFP4) or MI300X/MI325X/MI355X class AMD parts. **Cortex's goal: 2× A100 instead.**

## GGUF quants (Unsloth Dynamic 3.0)

Source: [unsloth/DeepSeek-V4.1-Flash-1017-GGUF](https://huggingface.co/unsloth/DeepSeek-V4.1-Flash-1017-GGUF) ·
run guide: [unsloth.ai/docs/models/deepseek-v4.1-flash](https://unsloth.ai/docs/models/deepseek-v4.1-flash)

| Quant | Total (GB) | Engram format / GB | Non-Engram rest (GB) | Runs on (RAM+VRAM, Engram on SSD) | Top-1 agreement (wiki1100 / long17k) |
| --- | ---: | --- | ---: | --- | --- |
| UD-IQ1_S | 233.0 | IQ4_NL / 110.6 | 122.4 | 128–145 GB | 82.8 / 85.1% |
| **UD-IQ1_M** | **250.4** | IQ4_NL / 110.6 | **139.8** | **145 GB+** | 87.1 / 88.2% |
| UD-IQ2_XXS | 300.5 | Q5_K / 135.2 | 165.3 | 176–205 GB | 90.5 / 91.2% |
| UD-Q2_K_XL | 334.8 | Q5_K / 135.2 | 199.6 | 176–205 GB | 91.5 / 93.3% |
| UD-IQ3_XXS | 394.7 | Q6_K / 161.3 | 233.5 | 256–290 GB | 94.6 / 95.1% |
| UD-IQ3_S | 423.6 | Q6_K / 161.3 | 262.3 | 256–290 GB | 96.0 / 96.8% |
| UD-Q3_K_XL | 485.1 | MXFP8 / 202.8 | 282.3 | 290+ GB | 96.5 / 97.4% |
| UD-Q4_K_XL | 500.7 | MXFP8 / 202.8 | 297.9 | 305+ GB | 98.2 / 98.5% |
| UD-Q8_K_XL | 508.4 | MXFP8 / 202.8 | 305.6 | 315+ GB | 98.5 / 98.7% |

Extra assets in the same repo: `mmproj-F16.gguf` / `mmproj-BF16.gguf` (~0.93 GB) for vision input,
`dspark/DeepSeek-V4.1-Flash-1017-BF16.gguf` (8.5 GB) for speculative decoding, and standalone
`engram/*` tables (IQ4_NL 110.6 / Q5_K 135.2 / Q6_K 161.3 / MXFP8 202.8 GB) that can be **swapped**
into any quant's table slot (shard 5-of-5) with `engram/set_split.py`.

## What fits where

### 2× A100 80 GB (160 GB VRAM) — the Cortex target

The Engram table does **not** go in VRAM — it is an n-gram lookup read a few rows per token, streamed
through the OS page cache from NVMe (or RAM if the host has ≥128 GB free). What *must* be resident:

```
UD-IQ1_M:  139.8 GB weights + ~0.93 GB mmproj + 0.89 GB KV @1M ctx + runtime buffers
           ≈ 145 GB  →  fits 160 GB with ~15 GB headroom  ✅
UD-IQ1_S:  122.4 GB weights + same extras ≈ 128 GB      →  ~32 GB headroom  ✅ (recommended first run)
```

KV math: 890 B/token ⇒ 32K ctx = 29 MB, 1M ctx = 0.93 GB. Context is effectively free; NVMe bandwidth
and expert streaming dominate, not KV.

### Other tiers (Engram always on SSD)

| Host | Best quant | Notes |
| --- | --- | --- |
| Gaming PC, 32 GB RAM + 12–16 GB VRAM | IQ1_S | slower; that is the whole point of the engine design |
| Mac Studio 256–512 GB unified | IQ3_XXS / IQ3_S | no discrete GPU needed |
| 512 GB RAM + 1× 24 GB GPU | IQ2_XXS–Q2_K_XL | expert cache in RAM |
| 4× A100 640 GB | UD-Q3_K_XL/Q3_XXS class | near-frontier quality |
| 8× B200 / vLLM | native MXFP4 checkpoint | the reference node we are escaping |

## Running it (llama.cpp / Unsloth engine path)

Recommended sampling (DeepSeek): `temperature=1.0`, `top_p=1.0`, top-k/min-p disabled. Thinking is on
by default with `reasoning_effort=75`; integer 1–100, or `low/medium/high/max` = 50/62/75/100.

```sh
llama-server -m DeepSeek-V4.1-Flash-1017-UD-IQ1_M-00001-of-00005.gguf \
  --mmproj mmproj-BF16.gguf \
  --temp 1.0 --top-p 1.0 --min-p 0.0 \
  --chat-template-kwargs '{"reasoning_effort":75}' \
  --ctx-size 65536 -ngl 99 --split-mode layer \
  --host 0.0.0.0 --port 8080
```

Keep mmap **on** (default) so the Engram shard streams from NVMe. Our wrapper:
[`scripts/deepseek-2xa100.sh`](../scripts/deepseek-2xa100.sh) automates download + launch + sanity checks.

> Pseudocode/decompiled claims are cross-checked against assembly; the same honesty rule applies to
> every number in this file: anything not measured on our hardware is labeled an estimate.
