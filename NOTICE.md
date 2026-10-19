# NOTICE

## What this repository is

**Cortex** is a rebrand and extension of [Strata](https://github.com/Niko1221/Strata) by Niko1221 and
contributors (MIT License), maintained by TheMindExpansionNetwork. The upstream project targets the
Qwen3.8-Flash-Next model family. Cortex's mission is the same trick applied to a newer frontier model:
**DeepSeek-V4.1-Flash-1017** on as little hardware as possible.

## Attribution & license chain

- Strata engine, desktop app, CLI and docs: Copyright (c) 2026 Niko1221 and the Strata contributors, MIT.
  The original MIT `LICENSE` file is preserved unchanged in this repository.
- llama.cpp / ggml parts: MIT, see `third_party/`.
- Strata's paper: `docs/paper/Strata-Paper.pdf` — upstream work, kept for reference.
- Community benchmark data under `bench/results/` is preserved verbatim from upstream (provenance;
  names, paths and metadata still say "Strata" by design).
- DeepSeek-V4.1-Flash-1017 model weights: DeepSeek-AI, MIT. The Unsloth Dynamic GGUF quantizations carry
  their own licensing terms from Unsloth. Model files are not distributed in this repository.
- The wordmark, logo and any Cortex branding created by TheMindExpansionNetwork are ours.

## What Cortex changed (vs upstream Strata)

1. **Brand rename** across user-facing strings, CLI (`strata` → `cortex`), config folder
   (`.strata` → `.cortex`), Python packages (`strata_cli` → `cortex_cli`, `strata_control` →
   `cortex_control`), C++ namespaces/paths (`include/strata` → `include/cortex`), brand SVGs and docs.
   Upstream translations of README/docs were removed; the English docs are rewritten for Cortex's focus.
2. **Model focus**: integration docs, quant matrix, 2×A100 GPU test plan, power analysis, and a launch
   script for DeepSeek-V4.1-Flash-1017 (see `docs/` and `scripts/`).
3. Engine support for the new architecture is **not** in this commit — it is the Phase P1–P3 work
   described in [docs/ROADMAP.md](docs/ROADMAP.md).

## What still points upstream (on purpose)

- The signed **engine update feed** (`https://github.com/Niko1221/Strata/releases/latest/download/strata-feed.json`)
  and the installer download URLs still resolve to upstream releases. Until Cortex publishes its own
  signed builds (Phase P5), this keeps the stack fully functional for the Qwen family today. The feed is
  signed upstream; Cortex does not modify engine binaries.
- Upstream repository links in docs/issue templates/credits are left intact — they point to the project
  this fork came from and to live upstream docs (CONTRIBUTING, TROUBLESHOOTING, benchmarks).
- Donation links (`buymeacoffee.com/strataengine`) belong to upstream and are preserved out of fairness.

## Trademark note

"Cortex" is the project name chosen by TheMindExpansionNetwork for this fork. Any use must respect the
MIT license terms of the upstream project. Name conflicts, if any, will be resolved by renaming this
repository — the code carries no other claim.
