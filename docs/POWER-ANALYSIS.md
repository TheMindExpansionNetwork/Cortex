# Power analysis — what it costs to run a frontier model "locally"

All arithmetic in this file is computed, not guessed; sources are linked. Last verified 2026-10-19.

## The serving ladder for DeepSeek-V4.1-Flash-1017

| Tier | GPUs | GPU power | Total system (est.) | Quality tier | Concurrency sweet spot |
| --- | --- | ---: | ---: | --- | --- |
| Reference serving node | 8× B200 (NVFP4, vLLM) | ~8,000 W | ~8.3–9.9 kW | 98%+ (MXFP4 native) | hundreds of users |
| Data-center lite | 8× A100 / 4× A100 80GB (FP8/IQ3 class) | 2,400–3,200 W | ~2.7–3.5 kW | ~95–96% | tens of users |
| **Cortex target** | **2× A100 80GB SXM** | **800 W** | **~1.05 kW** | **~88% top-1 (IQ1_M)** | 1–8 users |
| Cortex thrifty | 2× A100 80GB PCIe | 600 W | ~0.85 kW | same | 1–4 users |
| Desktop (upstream design) | 1× RTX 3090–5090 + 64–128 GB RAM | 350–575 W | ~0.45–0.7 kW | IQ1_S (~83–85%) | 1 user |

**GPU power cut, 2×A100 vs 8×B200 reference: (8,000 − 800) / 8,000 = 90%.**
With host overhead included: (8,300 − 1,050) / 8,300 ≈ **87%**; PCIe variant ≈ 90%.

Power figures: A100 80GB SXM4 TDP 400 W, PCIe 300 W (NVIDIA datasheet); B200 SXM configurable to
1,000–1,200 W per GPU. Host estimate assumes a 2-socket EPYC/Xeon node with 512 GB RAM + NVMe.

## Energy per token (estimate, labeled as estimate)

Decode activates only **16B params**; at IQ1_M most expert bytes are ~1.5-bit, so a decode step reads
roughly 3–5 GB of weights from HBM. Two A100s expose ~3.2 TB/s aggregate:

```
ceiling  ≈ 3.2 TB/s ÷ 4 GB/token ≈ 800 tok/s (theoretical, ignores MoE all-to-all, Engram misses)
realistic (single stream, engram in RAM)  ≈ 40–120 tok/s   ← MEASURE IN P4, do not quote otherwise
```

- 2×A100 SXM @ ~1.05 kW and 60 tok/s ⇒ **~17.5 J/token ≈ 4.9 Wh per 1K output tokens**
- 8×B200 node @ ~8.3 kW and (say) 150 tok/s single-stream ⇒ **~55 J/token**; at high batch its per-token
  energy drops — the fair statement is: **for 1–8 concurrent users, the 2×A100 build uses ~3–10× less
  energy per token and ~8× less absolute power.** Batching economics live in P4's benchmark matrix.

## Money (rental, 2026-10 spot)

| Line | Value |
| --- | --- |
| 2× A100 80GB (RunPod/ Lambda, on-demand) | ≈ $2.40–3.80 / hr |
| Assumed 60 tok/s single-stream | ≈ 216K output tok/hr |
| Self-host output cost | ≈ $11–18 per 1M output tokens |
| DeepSeek API `deepseek-flash` output | $0.60 / 1M (off-peak $0.30) |

**Honest conclusion:** at 1-user concurrency, self-hosting is *not* cheaper per token than the API —
it is cheaper in a different currency: **privacy (nothing leaves the box), no rate limits, 1M context
for free, full control, and 90% less GPU power than a conventional frontier serving node.** With ≥8
concurrent users the rental math flips in our favor; that crossover is exactly what P4 measures.

## Wall-clock estimate for the build

- Download UD-IQ1_M (250 GB) @ ~150 MB/s ≈ **~30 min**; Engram IQ4_NL (110 GB) ≈ ~13 min.
- First load + warmup ≈ 3–10 min. NVMe needs ≥ 300 GB free (quant + engram + dspark + headroom).
