"""Cortex `cortex-flash` on Modal: DeepSeek-V4.1-Flash-1017 behind an OpenAI-compatible endpoint on 2× A100 80GB.

Owner-only (it spends GPU-hours); nothing here deploys on its own:

    pip install modal
    modal setup                                            # token + workspace, once
    modal secret create hf-token HF_TOKEN=hf_xxx           # the only credential this app needs
    modal deploy hosting/modal_app.py                      # serves the web endpoint at port 8080

GPU note: the request below is `modal.gpu.A100(count=2, size="80GB")` and MUST stay two GPUs. A single
A100-80GB cannot hold the model — the docs/CORTEX-DEEPSEEK.md resident math is ~139.8 GB of weights +
~0.93 GB mmproj + KV for UD-IQ1_M (~145 GB total), and ~128 GB even for UD-IQ1_S. Modal accepts a gpu count
per function, so the string form `gpu="A100-80GB:2"` is equivalent; keep the count.

Models live on the `cortex-models` volume (Modal volumes are elastic, so there is no fixed 500 GB to pick —
only stored files are billed; the ~250 GB download lands there and the Engram table is mmap-streamed from it,
which is exactly the NVMe-streaming mode the launch script defaults to).
"""

from pathlib import Path

import modal

app = modal.App("cortex-flash")

MODELS_VOLUME = modal.Volume.from_name("cortex-models", create_if_missing=True)

# The image: Modal builds hosting/Dockerfile.cortex itself (from_dockerfile; the build needs no GPU —
# nvcc compiles, nothing executes on a card). If the owner has pushed the same image to a registry,
# replace with:  image = modal.Image.from_registry("ghcr.io/themindexpansionnetwork/cortex:latest",
#                                                  add_python="3.11")
image = modal.Image.from_dockerfile(
    Path(__file__).parent / "Dockerfile.cortex",
    context_dir=Path(__file__).parent.parent,          # the repo root, so the Dockerfile can COPY scripts/
)


@app.function(
    image=image,
    gpu="A100-80GB:2",          # 2× required — see the docstring above
    volumes={"/models": MODELS_VOLUME},
    secrets=[modal.Secret.from_name("hf-token")],
    timeout=4 * 60 * 60,                                # the shard download alone is 25–45 min; keep headroom
    scaledown_window=15 * 60,
)
@modal.web_server(port=8080, startup_timeout=60 * 60)
def serve():
    """Start the launch script and hold the function open until llama-server answers on the port."""
    import socket
    import subprocess
    import time

    subprocess.Popen(
        ["bash", "/opt/cortex/scripts/deepseek-2xa100.sh", "--port", "8080", "--repo", "/models/dsv41"],
        cwd="/models",
        start_new_session=True,
    )
    for _ in range(60 * 60):
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=2):
                return                                   # llama-server is up; Modal keeps the process alive
        except OSError:
            time.sleep(1)
    raise RuntimeError("llama-server did not open port 8080 within an hour; check the Modal logs")
