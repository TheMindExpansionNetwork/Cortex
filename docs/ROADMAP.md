# Cortex roadmap

**Mission:** run DeepSeek-V4.1-Flash-1017 — a 552B-backbone frontier MoE with 196B Engram memory — on
two GPUs, at ~1 kW, through an interface a normal person can use.

| Phase | What | Exit criteria |
| --- | --- | --- |
| **P0 — Foundation** *(published)* | Repo, rebrand from Strata, model docs, quant matrix, power analysis, GPU test plan, launch script | published |
| **P1 — Engine arch port** *(scaffolded 2026-10-19)* | Bring `deepseek41` GGUF arch into the Cortex engine from upstream llama.cpp (encoder–decoder KV projection, two-tier sparse attention, indexer, hyper-connections); keep the Qwen path green. Family recognition + engine entry stub **live**; reference vendored (`third_party/upstream-dsv41/`); the port map is [PORTING-DSV41.md](PORTING-DSV41.md) | model loads; greedy short-gen logits ≈ upstream llama.cpp on same GGUF |
| **P2 — Engram on SSD** *(contract live 2026-10-19)* | Wire the 196B Engram tables (IQ4_NL/Q5_K/Q6_K/MXFP8) into Strata's proven n-gram SSD reader: mmap on-demand rows, page-cache friendly, swap-in-RAM mode for hosts with ≥128 GB free. The GGUF ground truth is verified: the table is one tensor, `per_layer_token_embd.weight`, in the final shard | prefill+decode correct with Engram streaming from NVMe; measured Engram hit-rate telemetry |
| **P3 — DSpark drafting** *(contract live 2026-10-19)* | Map DSpark semi-autoregressive draft (8.5 GB BF16 drafter) onto Strata's coupled-draft/MTP machinery with confidence-scheduled verification | ≥1.6× decode speedup vs undrafted, identical outputs on greedy checks |
| **P4 — 2× A100 bring-up** *(ready, awaits hardware)* | Run [GPU-TEST-PLAN.md](GPU-TEST-PLAN.md): IQ1_M on 2×A100, split-layer tensor sharding, vision via mmproj, benchmarks + power traces | ≥40 tok/s, ≤900 W, 30-min soak clean; results committed |
| **P5 — Our own builds** | CI (GitHub Actions, CUDA runner) builds signed Cortex engine packages + our own update feed; drop the upstream feed dependency | `cortex update` serves from TheMindExpansionNetwork feed |
| **P6 — Hosting recipe** | One-command deployment: RunPod/Modal A100 template → OpenAI-compatible endpoint (vLLM path for the MXFP4 native checkpoint as the quality option), documented | fresh rental to working API in ≤20 min |
| **P7 — Super-easy interface** | Desktop app preset: "DeepSeek-V4.1-Flash (2-GPU)" with auto-fit detection (extends `versionFit` for the new memory model); one-click download of quant+engram+mmproj | user installs, picks model, chats |

## Risks & honest notes

- P1 is the real engineering lift: the arch port touches attention (sparse compressed), router, and
  the KV projection path. We port from upstream llama.cpp rather than reinvent, then re-apply Strata's
  expert-memory optimizations.
- Per-token power math favors us at low concurrency (1–8 users); at high batch, data-center nodes win
  on energy/token. The crossover is measured in P4, not assumed.
- Quality: IQ1_M is ~88% top-1 agreement vs DeepSeek's F32 reference — good for agents/chat, not for
  frontier-max reasoning. If that trade disappoints, P6's vLLM-native route (8×B200-class, rented) is
  the quality fallback while the desktop tier stays the "cheap and private" lane.
