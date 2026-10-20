# Cortex — Test-Day Runbook (DeepSeek-V4.1-Flash on rented GPUs)

_Last verified: 2026-10-20. Everything marked ✅ was actually executed; ⏳ has never run on a GPU yet._

## TL;DR — the three commands

```bash
cd ~/jimsky/projects/strata-src        # (or a fresh clone of TheMindExpansionNetwork/Cortex)
bash hosting/boot-and-test.sh --dry-run    # 1. free: live stock, price, balance check. Creates NOTHING.
bash hosting/boot-and-test.sh              # 2. the real run (auto-picks the cheapest plan in stock)
ls bench/results/                          # 3. results: setup.log, results.txt (replies, tok/s, watts), server.log
```

The script **deletes the pod by itself** at the end, on failure, on Ctrl-C, and via a watchdog after
`MAX_MINUTES` (default 90). Double-check afterwards anyway: `runpodctl pod list` should print `[]`.

## Money

| Item | Value (2026-10-20) |
|---|---|
| RunPod balance | ≈ $8.50 (plus an existing $0.021/hr charge — probably a storage volume) |
| 2× RTX PRO 6000 Blackwell 96 GB (community) | **$3.38/hr — the only fitting plan in stock on 10-20** |
| 2× A100 80 GB / 2× H100 / 1× H200 | **out of stock** all day 10-19 and 10-20 |
| 90-minute cap at $3.38/hr | ≈ $5.07 → one full attempt fits the balance; a second needs a top-up |

Expected timeline on the pod: setup + CUDA build of llama.cpp ≈ 10–20 min · download ≈ 250 GB (≈ 5–30 min, depends
on the host's network) · model load ≈ 5–15 min · prompts ≈ 2–5 min. **90 min is enough if the network is decent;**
if the log shows the download crawling (< 100 MB/s), stop early (Ctrl-C deletes the pod) rather than burn the cap.

## Plans the script knows (`PLAN=...`)

| PLAN | GPUs | Quant | GPU memory | Notes |
|---|---|---|---|---|
| `2xpro6000` | 2× RTX PRO 6000 Blackwell 96 GB | UD-IQ1_M | 192 GB | cheapest fit seen; sm_120 |
| `h200` | 1× H200 141 GB | UD-IQ1_S | 141 GB | single GPU, slightly smaller quant |
| `2xh100` | 2× H100 80 GB | UD-IQ1_M | 160 GB | |
| `2xa100` / `2xa100pcie` | 2× A100 80 GB | UD-IQ1_M | 160 GB | the original target |

Knobs: `CLOUD=SECURE` (pricier, more stock), `MAX_MINUTES=120`, `CTX=65536`, `KEEP=1` (leave it running — you pay).

## What the run does (and how each part was verified)

| Step | File | Status |
|---|---|---|
| Pick plan from live stock/price/balance | `hosting/boot-and-test.sh` | ✅ dry-run executed for real against the RunPod API |
| Create pod (volume at `/workspace`, ports 8080/http + 22/tcp) | same | ⏳ flags taken from `runpodctl pod create --help` (v3 CLI) |
| SSH in with `~/.ssh/id_ed25519` | same | ✅ that key is registered on the RunPod account |
| Build llama.cpp **PR #30817** (the only engine with `deepseek41`) | `scripts/build-llama-dsv41.sh` | ✅ CPU build on the VPS, pinned commit `b72050d03ae1…`; ⏳ CUDA build |
| Download `UD-IQ1_M` (5 shards) + launch | `scripts/deepseek-2xa100.sh` | ✅ every flag exists in that build; ✅ real model header loads (arch `deepseek41`) |
| Engram table (110 GB) kept OFF the GPUs | `--override-tensor per_layer_token_embd.weight=CPU --load-mode mmap --lazy-mode on` | ✅ Unsloth's documented recipe; ⏳ never run |
| Two real prompts, tok/s, watts, memory → `bench/results/` | `boot-and-test.sh` step 6 | ⏳ |
| Delete pod | trap + watchdog | ⏳ (logic reviewed; delete command from `runpodctl pod delete`) |

## If something breaks

| Symptom | Likely cause → fix |
|---|---|
| `no matching GPU plan is listed as available` | Stock is gone. `CLOUD=SECURE bash hosting/boot-and-test.sh --dry-run`, or wait. Not a bug. |
| `pod create failed:` + message | Printed verbatim from RunPod. "no longer any instances" = stock vanished between check and create; just re-run. |
| `no direct SSH address` | Community host without public port 22 → `CLOUD=SECURE`. |
| build step fails on the pod | Look at `bench/results/<date>-*/setup.log`. The pinned PR commit can be overridden: `LLAMA_DSV41_SHA=<newer>`. If PR #30817 has merged, mainline will work too. |
| `will NOT fit` | Wrong plan for the quant; use IQ1_S or more VRAM. `--force` to override. |
| launcher died during load | `failure.log` — usually out-of-memory: lower `CTX`, or confirm the Engram override line is in the launch command. |
| very slow generation | expected-ish on IQ1 + mmap Engram on a network volume; record the number — that *is* the result. |

**Manual cleanup if anything is left:** `runpodctl pod list` → `runpodctl pod delete <id>`.

## Container / template path (no script)

* `hosting/Dockerfile.cortex` → image `ghcr.io/themindexpansionnetwork/cortex:latest`, built by CI
  (`.github/workflows/cortex-docker-image.yml`). ⏳ The GHCR package starts **private**: make it public once
  (GitHub → Packages → cortex → settings) or RunPod cannot pull it.
* `hosting/runpod-template.json` → paste into RunPod "New Template". Set `HF_TOKEN`. Volume at `/workspace`.
* `hosting/modal_app.py` → `modal deploy hosting/modal_app.py` (2× A100-80GB; needs the `cortex-hf` secret).

## Honest record of what went wrong before (so nobody repeats it)

1. The first hosting files downloaded **mainline** llama.cpp release binaries. Those cannot load `deepseek41`
   — the run would have failed after the 250 GB download. Fixed: everything builds PR #30817 via one script.
2. The old pod rig exposed only 8080 (no SSH), used the deprecated `runpodctl create pod`, and polled
   the pod's private IP for health. Rewritten.
3. A 40-minute stock poller on 10-19 hid its error output; its "no stock" result was real but unverified then.
   On 10-20 the stock list was checked directly: A100/H100/H200 genuinely unavailable.
4. On 10-20, while the new rig was being written, the **old** script was accidentally run once in "dry run"
   mode (it had no such mode) and asked RunPod for a pod; RunPod refused (no stock). `pod list` confirmed nothing
   was created and nothing was billed.
5. CI: `cortex-engine-build` failed because CMake couldn't find `nvcc` (fixed: explicit `CMAKE_CUDA_COMPILER`);
   the server test suite had a flaky thread-count test (fixed: waits for earlier samplers to exit — 5/5 passes).
   Locally 880/881 serve tests pass; `test_lifeline` hangs on this VPS only (process-kill test; passes in CI).
