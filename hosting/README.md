> **Test day:** follow [`docs/RUNBOOK.md`](../docs/RUNBOOK.md). Engine = llama.cpp PR #30817 via `scripts/build-llama-dsv41.sh`.

# Hosting Cortex Flash — one-command 2× A100 80GB

Bring up DeepSeek-V4.1-Flash-1017 (Unsloth GGUF) behind llama-server's OpenAI-compatible API on
**2× A100 80GB**. Pick one option below; every one of them ends at the same endpoint:

```
http://<host>:8080/v1/chat/completions     # OpenAI-compatible (vision via image_url)
http://<host>:8080/health                  # readiness
```

| Requirement | Value |
| --- | --- |
| GPUs | 2× A100 80GB (160 GB total) — a single A100-80 cannot fit the model (see below) |
| Model | `unsloth/DeepSeek-V4.1-Flash-1017-GGUF`, **UD-IQ1_M** (250.4 GB total) or **UD-IQ1_S** (233.0 GB) |
| Resident (VRAM) | IQ1_M ≈ 145 GB · IQ1_S ≈ 128 GB — the Engram table (shard 5, ~110.6 GB IQ4_NL) stays on NVMe/RAM |
| Storage | ≥ 320 GB NVMe for the model (500 GB volume recommended); Engram mmap-streams from it |
| Credentials | `HF_TOKEN` (read access; the model is MIT, no gate expected) |
| Numbers / protocol | [docs/CORTEX-DEEPSEEK.md](../docs/CORTEX-DEEPSEEK.md) · [docs/GPU-TEST-PLAN.md](../docs/GPU-TEST-PLAN.md) |

All options run the same launcher, [`scripts/deepseek-2xa100.sh`](../scripts/deepseek-2xa100.sh): it
downloads the shards + vision projector, sanity-checks the GPU count and prints the VRAM/KV math, then
starts llama-server with the recommended sampling (`temp=1.0`, `top_p=1.0`, `reasoning_effort=75`).
Quant knobs: `--quant IQ1_M|IQ1_S`, `--ctx` (default 65536, model max 1048576), `--engram ram|ssd`,
`--dspark` (speculative drafter, +8.5 GB).

---

## Option A — RunPod (template import)

1. Build and push the image once: `docker build -f hosting/Dockerfile.cortex -t cortex-flash .`
   `docker tag cortex-flash ghcr.io/themindexpansionnetwork/cortex:latest && docker push ...`
   (or point `imageName` at a mirror).
2. RunPod Console → **Templates → Import template** → upload [`runpod-template.json`](runpod-template.json).
3. Edit after import: `imageName` if you pushed elsewhere; `env.HF_TOKEN` with the token
   (the template ships it empty — passthrough only, nothing is baked into the image).
4. Deploy a **pod** from the template: 2× A100 80GB, containerDisk 20 GB (image + pip cache only —
   the shards go to the volume), 500 GB network volume mounted at `/models`.
5. Open port 8080 (HTTP). First start downloads ~250 GB into the volume (25–45 min on pod network);
   the endpoint answers once `llama-server` is up.

Why those disks: the container disk holds only the image (llama-server + python); the volume holds the
model. Do **not** shrink the volume below 320 GB — the Engram shard needs NVMe, not page-cache eviction.

## Option B — Modal (`cortex-flash`)

```sh
pip install modal && modal setup                     # once
modal secret create hf-token HF_TOKEN=hf_xxx         # once
modal deploy hosting/modal_app.py                    # serves the endpoint; web URL printed
```

- The image is built by Modal from [`Dockerfile.cortex`](Dockerfile.cortex) (no GPU needed to build);
  swap to `Image.from_registry` if you prefer a pushed image.
- GPU request is `modal.gpu.A100(count=2, size="80GB")` — keep the count at 2. A single A100-80GB cannot
  hold the resident weights, so this is not a knob to trim.
- Models go to the `cortex-models` volume (elastic; only stored bytes are billed). There is no fixed
  500 GB figure to set on Modal — storage follows usage.
- One credential: the `hf-token` secret. `modal run` (dev mode) works too, but `deploy` is the
  always-on shape; `scaledown_window=15m` stops the GPUs between lulls.

## Option C — plain Docker on any 2× A100 box

```sh
docker build -f hosting/Dockerfile.cortex -t cortex-flash .
docker run --rm --gpus all -p 8080:8080 \
  -e HF_TOKEN=hf_xxx \
  -v /data/models:/models \
  cortex-flash                                # defaults: --quant IQ1_M --ctx 65536 --port 8080
```

Append script args after the image name (`cortex-flash --quant IQ1_S --ctx 65536`). The Engram table
streams from the mounted volume — mount local NVMe, not a network filesystem, or throughput collapses.

## Option D — bare metal (no container)

Install CUDA 12.8+, the driver, `pip install huggingface_hub` (for `hf`) and a CUDA-built `llama-server`
on the box (the builder stage of [`Dockerfile.cortex`](Dockerfile.cortex) is the recipe), then install the
unit: [`systemd/cortex.service`](systemd/cortex.service) — copy it to
`/etc/systemd/system/`, put `HF_TOKEN` in `/etc/cortex/cortex.env` (0600), `systemctl enable --now cortex.service`.
Logs: `journalctl -u cortex.service -f`.

---

## Verify a bring-up (before running the P4 protocol)

```sh
curl -s http://localhost:8080/v1/models | head          # model listed
curl -s http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"dsv41","messages":[{"role":"user","content":"ping"}],"max_tokens":8}'
```

Then run the sanity gates of [docs/GPU-TEST-PLAN.md](../docs/GPU-TEST-PLAN.md): per-GPU VRAM ≈ 68–72 GB,
vision round-trip through `image_url`, `reasoning_effort` accepted, 30-min soak at 8 concurrent.

## Notes

- **Do not expose 8080 publicly without auth.** The launcher has no API key; put a proxy (RunPod's
  gateway, a TLS terminator, or `--api-key` added to the script's llama-server flags) in front.
- A100-40 pairs do **not** fit any of these quants resident; 4× A100-40 (240 GB) fits IQ1_M — pass
  `--tensor-split 1,1,1,1` and adjust the script, or see the tier table in [CORTEX-DEEPSEEK.md](../docs/CORTEX-DEEPSEEK.md).
- First-run downloads are resumable (`hf` resume + the persistent volume), so a crashed pod does not
  re-pay the 250 GB.
