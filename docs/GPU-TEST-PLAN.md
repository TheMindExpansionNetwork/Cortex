# GPU test plan — DeepSeek-V4.1-Flash on 2× A100 80GB

Protocol for Phase P4. Every number lands in `bench/results/<date>-cortex-2xa100/` following the
upstream `bench/` conventions (`summary.json` + per-run JSON), so results stay comparable with the
existing community tables.

## Environment

- 2× NVIDIA A100 80GB (SXM or PCIe; record which), PCIe Gen4/5, NVLink preferred
- Host: ≥512 GB RAM (Engram in RAM) or ≥300 GB free NVMe + 128 GB RAM (Engram on NVMe)
- Ubuntu 22.04/24.04, CUDA ≥12.8, latest driver; llama.cpp built with CUDA (or upstream engine once P1 lands)
- `HF_TOKEN` with read access (model is MIT, no gate expected)

## Step 1 — Download (≈25–45 min)

```sh
hf download unsloth/DeepSeek-V4.1-Flash-1017-GGUF \
  --include "UD-IQ1_M/*" "mmproj-BF16.gguf" \
  --local-dir models/dsv41-iq1_m          # 250.4 GB total (shard 5 = Engram IQ4_NL)
hf download unsloth/DeepSeek-V4.1-Flash-1017-GGUF \
  --include "dspark/*" --local-dir models/dsv41-iq1_m    # optional, 8.5 GB
```

Verify: SHA totals match the HF tree sizes in [CORTEX-DEEPSEEK.md](CORTEX-DEEPSEEK.md); `nvidia-smi` shows both GPUs.

## Step 2 — Baseline run (llama.cpp path)

```sh
bash scripts/deepseek-2xa100.sh --quant IQ1_M --ctx 65536 --port 8080
```

Sanity gates, in order (record PASS/FAIL):

1. Loads without OOM: per-GPU `used ≈ 68–72 GB` (layer split), host RSS ≈ Engram size + 8–16 GB
2. Vision: send a small PNG via OpenAI-compatible `image_url`; decoder must return text about it
3. `reasoning_effort` kwarg accepted (50/75/100), thinking visible in response metadata
4. Throughput: short chat (500 in / 500 out), 64K ctx and 1M ctx read speed
5. Stability: 30-min soak at 8 concurrent requests, zero crashes, VRAM stable

## Step 3 — Measurements to collect

| Metric | How |
| --- | --- |
| tok/s decode, single stream | 500-token generation, report median of 3 |
| tok/s prefill | 32K and 128K prompts |
| tok/s decode, batch 8 | concurrency 8 × 500 tokens |
| Engram hit mode | record: RAM-resident vs NVMe-streamed (page-cache stats) |
| Power | `nvidia-smi --query-gpu=power.draw --format=csv -l 1` averaged over run |
| Quality smoke | identical 20-question agentic coding set vs DeepSeek API answers, spot-scored |

Pass criteria for P4: single-stream decode ≥ 40 tok/s sustained, ≤ 900 W total draw, no thermal throttle,
vision + reasoning-effort paths working. Below that: diagnose (PCIe transfer? Engram page thrash?
expert split balance) and iterate.

## Step 4 — Report

Commit `bench/results/<date>-cortex-2xa100/` with `summary.json`, per-run files, and the `nvidia-smi`
power traces. Numbers without a measurement method don't get published — estimates live only in
[POWER-ANALYSIS.md](POWER-ANALYSIS.md) and are labeled as such.
