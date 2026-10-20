# AGENT HANDOFF — Cortex project

**Read this first if you are a fresh agent taking over this project.** It compresses everything
learned so far into verified facts, decisions, and the next moves. Last updated: 2026-10-20.

## ⚡ STATUS 2026-10-20 — read this block before anything else

**Test-ready. Tomorrow's procedure is `docs/RUNBOOK.md`** (dry run → real run → results in `bench/results/`).

Corrections to anything older in this file:
* **Engine = llama.cpp PR #30817** (`ggml-org/llama.cpp`, pinned `b72050d03ae14bb3cb5138ecefab3f3f65157d31`), built by
  `scripts/build-llama-dsv41.sh`. Mainline/release llama.cpp has NO `deepseek41` arch. The Unsloth `dsv41-all`
  branch mentioned below was a reference only; it is not what runs.
* Launch recipe (`scripts/deepseek-2xa100.sh`) = Unsloth's documented flags: Engram tensor
  `per_layer_token_embd.weight` pinned to CPU + `--load-mode mmap --lazy-mode on`; temp 1.0 / top-p 1.0 / top-k 0;
  `reasoning_effort` 75; DSpark is `--spec-type draft-dspark` (opt-in `--dspark`). All flags verified in the built binary;
  the real IQ1_S header loads as `deepseek41`.
* Pod rig rewritten (`hosting/boot-and-test.sh`): runpodctl v3 syntax, live stock/price/balance check,
  `--dry-run`, SSH on 22/tcp, budget refusal, watchdog + auto-delete. Dry run verified against the live API.
* Stock reality: A100/H100/H200 unavailable on 10-19 and 10-20. **2× RTX PRO 6000 Blackwell 96 GB at $3.38/hr
  was in stock** and is now plan `2xpro6000` (192 GB ≥ the 139.8 GB IQ1_M resident set).
* Image name is `ghcr.io/themindexpansionnetwork/cortex:latest` (lowercase; CI workflow `cortex-docker-image.yml`).
* CI fixes: nvcc path for the engine build; the flaky `NoLeakedSampler` test. 880/881 serve tests pass locally.
* Nothing has run on a GPU yet. No pods exist. Balance ≈ $8.50 → one 90-minute attempt.

## What this project is

**Cortex** (repo: `github.com/TheMindExpansionNetwork/Cortex`, MIT) is a rebrand and extension of
[Strata](https://github.com/Niko1221/Strata) by Niko1221 (MIT, ~28k stars: a llama.cpp-derived
inference engine + desktop app + `cortex` CLI built for Qwen3.8-Flash-Next on consumer hardware).
Our mission: run **DeepSeek-V4.1-Flash-1017** — a 552B-backbone MoE with 196B Engram conditional
memory, only 8B/16B active params per token, 1M context, native vision, MIT license — on
**2× A100 80GB** (~1 kW total vs ~8.3 kW for the 8×B200 reference node).

## Project owner

The user (GitHub/HF account `TheMindExpansionNetwork`) — prefers concise, no-nonsense updates,
likes verification-backed claims, and speaks with the agent by voice sometimes (expect transcripts).
The agent persona is defined in `~/.hermes/SOUL.md` on the build host (as of 2026-10-19 it reads
"MindBot"; older sessions may carry the prior "J1MSKY" persona).

## Verified ground truth (do not re-derive, cite these)

- GGUF `general.architecture` = **`deepseek41`** (probed from the real shard headers, 2026-10-19).
  Mainline ggml-org/llama.cpp has `deepseek4` but **not** `deepseek41`; the implementation lives in
  **unslothai/llama.cpp branch `dsv41-all`** @ `9d907b7cfe0e41b03272e952a57b933c9fa08757`, vendored
  read-only in `third_party/upstream-dsv41/reference/` (deepseek41.cpp 945 lines, dflash.cpp 1552,
  llama-kv-cache-dsv4.{h,cpp} 2864). A third independent implementation exists:
  Red-Weasel/machx-inference-engine (`deepseek41_engram.cpp`, `deepseek41_dspark.hpp`) — cross-check material.
- Shard 4 of UD-IQ1_M declares **266 backbone tensors**; **shard 5 IS the Engram table** — one tensor,
  `per_layer_token_embd.weight`, streamed via mmap (never resident). Backbone tensor families per block:
  `attn_kv*`, `attn_q_a/q_b` (MLA-style), `attn_sinks`, `exp_probs_b*`, `ffn_{up,gate,down}_exps` +
  `ffn_*_shexp`, `hc_{attn,ffn}_{base,fn,scale}` (hyper-connections), `indexer.{attn_q_b,proj}`.
- Quant matrix + fit math: `docs/CORTEX-DEEPSEEK.md`. Key numbers: UD-IQ1_M total 250.4 GB of which
  **139.8 GB resident** (fits 160 GB of 2×A100 with ~18 GB headroom); UD-IQ1_S 122.4 GB resident.
  Engram sizes: IQ4_NL 110.6 / Q5_K 135.2 / Q6_K 161.3 / MXFP8 202.8 GB. KV ≈ 890 B/token
  (1M ctx ≈ 0.93 GB). Sampling: temp 1.0, top_p 1.0, min_p 0; reasoning_effort 1–100 (default 75).
- PLE metadata keys (`LLM_KV_PLE_*`, `LLM_KV_ENGRAM_*`) are the **same PLE keys the Cortex engine
  already reads for Qwen** — P2 is a mapping to `include/cortex/ngram/ple_reader.hpp`, not a rewrite.
- Power/cost math (computed, sources linked): `docs/POWER-ANALYSIS.md`.

## Current state (commits on main)

| Phase | State |
| --- | --- |
| P0 rebrand + docs | done (rebrand touched 1,613 files; `bench/results/` + paper + upstream URLs deliberately preserved — see `NOTICE.md`) |
| P1 engine scaffold | **live**: `ModelFamily::DeepSeek41` in `include/cortex/artifact/model_family.hpp`; family switch in `src/program/generate.cpp` (guard `CORTEX_HAVE_DEEPSEEK41`); honest entry stub `src/deepseek41/ds41_engine.cpp` (exit 2 with plan); plan headers `include/cortex/deepseek41/{engine,engram,dspark}.hpp`. **The graph port is NOT written** — that's the next real work, and it needs a machine that can build+run to verify |
| P2/P3 | contracts live (`engram.hpp`, `dspark.hpp`); wiring pending |
| P4 | protocol ready (`docs/GPU-TEST-PLAN.md`); **needs actual 2×A100 hardware** |
| P5 | CI workflow `.github/workflows/cortex-engine-build.yml`, `scripts/make-cortex-feed.py` (Ed25519-signed `cortex-feed.json`), public key `cortex_control/cortex_feed_public_key.json` (key_id `30e36a95dd031cae`). Feed **switchover rule**: `cortex_control/feed.py` FEED_NAME + `cortex_cli/update_cmd.py` DEFAULT_FEED stay upstream until the first signed Cortex release ships; the rename + adding our key to `update_keys.json` happen in that same switchover commit. `CORTEX_UPDATE_FEED` env overrides meanwhile |
| P6 | `hosting/` — Dockerfile.cortex, RunPod template (2×A100), Modal app (`modal.gpu.A100(count=2, size="80GB")`), systemd unit, README. Not yet deployed (no hardware) |

## Credentials & local environment (build host: OVH VPS, `/home/ubuntu`)

- `~/.hermes/.env`: `GITHUB_TOKEN` (classic PAT, full scopes — use REST via curl; `gh` CLI is
  deliberately absent), `HF_TOKEN` (fineGrained, repo.write on `TheMindExpansionNetwork`),
  `COMFY_CLOUD_API_KEY` (Comfy Cloud; free-tier note: `/api/prompt` works, job execution needs paid tier).
- `~/.cortex-keys/`: the feed signing keypair (**chmod 600, never commit — .gitignore guard verified**;
  back it up offline). If lost, regenerate + re-sign nothing (no release shipped yet).
- Working clones: `~/jimsky/projects/strata-src` (= the Cortex repo working tree),
  `~/jimsky/projects/llama-dsv41` (unsloth dsv41-all), `~/jimsky/projects/llama-upstream` (mainline
  llama.cpp), `~/jimsky/projects/llama-unsloth` (unsloth default branch — lacks dsv41).
- Local art: `~/jimsky/assets/cortex-img/` (repo copies in `docs/media/`).

## Decisions already made (don't relitigate)

1. **No `setup.py` catalog wiring yet.** `install_own_path` is Qwen3.6-shaped (single-GPU warning,
   262144-token cap, per-file SHA pins) — wrong for DeepSeek's 2-GPU/1M model. Half-wiring it would
   download 250 GB then refuse. DeepSeek's install path is `scripts/deepseek-2xa100.sh` until P1
   completes; then a new own-path installer branch with multi-GPU + 1M context.
2. Engine stub refuses honestly (exit 2) — never half-run the model.
3. Upstream `bench/results/`, the paper PDF, donation links, and upstream URLs are preserved on
   purpose (provenance + credit). `NOTICE.md` is the authority on what changed.
4. Translate docs: upstream's non-English READMEs were removed; English-only is intentional.
5. Per-token self-hosting is NOT cheaper than the DeepSeek API at 1-user concurrency — the pitch is
   privacy, no rate limits, 1M context, and ~90% less GPU power. Say so honestly.

## Verify the state in one minute

```sh
cd /home/ubuntu/jimsky/projects/strata-src
git log --oneline -6                      # expect: feed switchover doc, P5-P6, P1-P3 scaffold, avatar, banner, rebrand
g++ -std=c++17 -I include -fsyntax-only src/deepseek41/ds41_engine.cpp   # clean
python3 scripts/make-cortex-feed.py --help
python3 -c "import json;print(len(json.load(open('data/gguf_fingerprints.json'))))"  # 15 rows
```

## Next moves (in order)

1. **P4 hardware**: rent 2× A100 80GB (RunPod template in `hosting/runpod-template.json`; ~$2.40–3.80/hr),
   run `scripts/deepseek-2xa100.sh --quant IQ1_M --ctx 65536`, follow `docs/GPU-TEST-PLAN.md`,
   commit results to `bench/results/<date>-cortex-2xa100/`. This validates the launch path end-to-end
   even before the Cortex engine port (llama.cpp/unsloth runtime works today with these GGUFs).
2. **P1 graph port** on that same machine (or any CUDA box): follow `docs/PORTING-DSV41.md` — port
   `src/models/deepseek41.cpp` graph into a `src/deepseek41/ds41_engine.cu` in the Cortex engine,
   wire Engram → PLE reader (P2), DSpark → spec controller (P3), verify against the vendored reference.
3. **P5 switchover**: first signed Cortex release → rename FEED_NAME/DEFAULT_FEED + merge the public
   key into `update_keys.json` in one commit.
4. Branding polish: repo social preview = `docs/media/cortex-profile.png`; avatar = `cortex-avatar.png`.

## Image generation recipe (for future art)

FLUX.2 Klein 9B on Comfy Cloud: use the official template `image_flux2_text_to_image_9b.json` from
Comfy-Org/workflow_templates (editor format → convert to API: keep dotted keys, skip Reroutes, add a
SaveImage terminal). Klein pairs with `qwen_3_8b_fp8mixed.safetensors` (CLIPLoader type `flux2`) and
VAE `full_encoder_small_decoder.safetensors` — NOT mistral_3_small (that's flux2-dev; shape-mismatch
errors if you mix them). Submit via the comfyui skill's `run_workflow.py --host https://cloud.comfy.org`.
