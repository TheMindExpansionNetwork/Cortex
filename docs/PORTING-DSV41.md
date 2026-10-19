# Porting `deepseek41` into the Cortex engine (Phase P1 map)

This is the working map for ROADMAP P1–P3. The reference implementation is vendored read-only at
[`third_party/upstream-dsv41/`](../third_party/upstream-dsv41/README.md) (unslothai/llama.cpp, branch
`dsv41-all` @ `9d907b7cfe0e41b03272e952a57b933c9fa08757`, MIT). Do not edit the reference in place —
port into Cortex's modules and keep this document as the checklist.

## What already exists in this repo (this commit)

| Piece | File | State |
| --- | --- | --- |
| Family recognition | `include/cortex/artifact/model_family.hpp` — `ModelFamily::DeepSeek41`, arch string `deepseek41` | **live** (unit-checked: `model_family_from_arch("deepseek41")` returns the family) |
| Family switch | `src/program/generate.cpp` (top of main) — `deepseek41` files hand to `src/deepseek41` behind `CORTEX_HAVE_DEEPSEEK41` | **live** (wired in CMake next to `cortex_qwen35`) |
| Engine entry stub | `src/deepseek41/ds41_engine.cpp` — refuses honestly with the geometry + memory plan, exit 2 | **live** (compiles; verified) |
| Plan headers | `include/cortex/deepseek41/{engine,engram,dspark}.hpp` — the geometry, memory plan and P2/P3 contracts | **live** (compiles) |
| Upstream reference | `third_party/upstream-dsv41/reference/` — `deepseek41.cpp` (945 lines), `dflash.cpp` (1552), `llama-kv-cache-dsv4.{h,cpp}` (2864) | vendored |

## Ground truth (verified from the GGUF, 2026-10-19)

- `general.architecture = deepseek41`; size label `748B-A16B`.
- Shard 4 of UD-IQ1_M declares **266 backbone tensors**; shard 5 is the Engram table itself —
  **one tensor, `per_layer_token_embd.weight`** (that IS the 196B table, streamed, never resident).
- Backbone tensor families per block (10–11 × per layer): `attn_kv*` (compressed KV + norm),
  `attn_q_a/q_b` (MLA-style low-rank), `attn_sinks`, `exp_probs_b*`, `ffn_{up,gate,down}_exps` +
  `ffn_*_shexp` (384 routed + 1 shared), `hc_{attn,ffn}_{base,fn,scale}` (hyper-connections),
  `indexer.{attn_q_b,proj}` on the compressing layers (2 of 20 — the keep-512 side attention).
- KV metadata keys the loader must honour: `LLM_KV_PLE_NGRAM_SIZE`, `LLM_KV_PLE_HEADS_PER_NGRAM`,
  `LLM_KV_EMBEDDING_LENGTH_PER_LAYER`, `LLM_KV_PLE_LAYER_MULTIPLIERS`, `LLM_KV_PLE_HEAD_OFFSETS`,
  `LLM_KV_PLE_HEAD_VOCAB_SIZES`, `LLM_KV_ENGRAM_PAD_TOKEN_ID`, `LLM_KV_ENGRAM_TOKEN_MAP`.
  These are the **same PLE keys** the Cortex engine already reads for the Qwen n-gram table — that is
  the whole reason P2 is a mapping, not a rewrite.

## P1 — arch port (upstream → Cortex)

| Upstream (reference file) | Cortex target | Notes |
| --- | --- | --- |
| `src/llama-arch.cpp` DEEPSEEK41 entries (tensor↔id, hyper-params) | `include/cortex/core/family_layout.hpp` + the geometry reader in the deepseek41 engine module | Cortex carries its own layout tables (synthetic); add `deepseek41` beside `qwen4exp`/`qwen35moe` |
| `src/models/deepseek41.cpp` `create_models_*` (graph) | `src/deepseek41/ds41_engine.cu` — the decode/prefill graph | Split: encoder half runs prefill-only (8B active); decoder half autoregressive (16B). Hyper-connections reuse the gated-residual machinery (`include/cortex/kernels/*`) |
| `src/llama-kv-cache-dsv4.*` | `include/cortex/kernels/kv_q4.hpp`-class stream + a new `include/cortex/deepseek41/kv_plan.hpp` | ~890 B/token global KV; 4 layers (2, 8, 14, 20) compress their own KV; others read via `dsv41_kv_src`/`dsv41_topk_src`. Keep the `dsv41_*` hparam names verbatim from upstream to stay reviewable against the reference |
| `src/llama-hparams.h` dsv41 fields | the engine's geometry struct (`include/cortex/deepseek41/engine.hpp::Geometry` is the contract) | `dsv41_kv_src`, `dsv41_topk_src`, `dsv41_cand_*`, `dsv41_tok_hist`, `dsv41_hist_len` |
| vocab/chat template (`reasoning_effort` 1–100) | the engine's chat template path; kwarg default 75 | low/medium/high/max = 50/62/75/100 |
| `tools/` tokenizer utilities | `tools/cortex_tokenizer.py` (already exists for Qwen) | extend for deepseek41's BPE if it differs |

## P2 — Engram → the PLE SSD reader

| Upstream | Cortex target |
| --- | --- |
| Engram tensor `per_layer_token_embd.weight` (mmap, on-demand rows) | `include/cortex/ngram/ple_reader.hpp` — the proven on-demand reader (Qwen n-gram table, 28.8 GB, same access pattern) |
| 2/3/4-gram hash + bucket ranges (`engram_primes`, `engram_offsets`) | `include/cortex/kernels/ngram.hpp` |
| Learned gate into the residual stream | `include/cortex/kernels/ple.hpp` |
| Table precision swap (IQ4_NL/Q5_K/Q6_K/MXFP8 as shard 5) | `include/cortex/deepseek41/engram.hpp::EngramPlacement` — `ssd` (default) / `ram` (needs ≥ table size free RAM) |

Exit criteria: prefill+decode bit-identical to the upstream branch on a fixed prompt set with the table
on NVMe vs in RAM; Engram hit-rate telemetry surfaced in the monitor (the expert cache already has this
pattern: `apps/host` monitor → `expertCache`).

## P3 — DSpark → the spec controller

| Upstream | Cortex target |
| --- | --- |
| `reference/dflash.cpp` (drafter GGUF `dspark/*.gguf`, 8.5 GB BF16, +~14B drafter params) | `include/cortex/deepseek41/dspark.hpp::DSparkPlan` → `include/cortex/spec/controller.hpp` (the same acceptance loop Qwen's MTP uses) |
| Confidence-scheduled verification | `include/cortex/spec/draft_policy.hpp` — the schedule's shape is the only new piece |

Exit criteria: ≥1.6× decode vs undrafted, greedy outputs identical on the check set; engine runs fine
without the drafter (DSpark is an accelerator, not a requirement).

## What deliberately is NOT done in this commit (and why)

- **No `setup.py` catalog wiring.** `install_own_path` (the own-file install path) is Qwen3.6-shaped:
  one-GPU warning, 262144-token context cap, per-file SHA-256 pins, no multi-GPU tensor split. DeepSeek
  needs 2-GPU splits and 1M context. Half-wiring it now would produce an installer that downloads
  250 GB and then refuses at launch. DeepSeek's install path until P1 completes is
  [`scripts/deepseek-2xa100.sh`](../scripts/deepseek-2xa100.sh); catalog wiring lands with P1
  completion (a new own-path installer branch with multi-GPU + 1M context support).
- **No engine graph code.** Porting the graph without the ability to run it (no GPU on the build host)
  would be unverifiable code. The scaffold + reference + this map make the port mechanical on the
  bring-up machine; `tools/qwen35/`-style cross-check harnesses get added with the first runnable build.
