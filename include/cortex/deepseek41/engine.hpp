// include/cortex/deepseek41/engine.hpp - the DeepSeek-V4.1-Flash (GGUF architecture `deepseek41`) engine path.
//
// The family switch in src/program/generate.cpp hands every `deepseek41` file to cortex::deepseek41::run(),
// the same pattern as src/qwen35 (include/cortex/qwen35/engine.hpp). The implementation is under construction:
// docs/ROADMAP.md phases P1-P3, ported from the vendored upstream reference (third_party/upstream-dsv41/,
// unslothai/llama.cpp branch dsv41-all). This header is the contract the port implements; the numbers below
// are read from the model card and the Unsloth GGUF header (2026-10-19) and must not drift from
// docs/CORTEX-DEEPSEEK.md.
#pragma once

#include <cstddef>
#include <cstdint>

namespace cortex::deepseek41 {

/// Architecture geometry of DeepSeek-V4.1-Flash-1017 (748B-A16B), from the model card + the Unsloth GGUF.
struct Geometry {
    static constexpr uint32_t kEncoderLayers = 20;   // causal encoder: runs on prefill only (8B active)
    static constexpr uint32_t kDecoderLayers = 20;   // decoder: autoregressive (16B active)
    static constexpr uint32_t kTotalLayers = kEncoderLayers + kDecoderLayers;
    static constexpr uint32_t kHiddenSize = 5120;
    static constexpr uint32_t kRoutedExperts = 384;  // per MoE layer (+1 shared expert)
    static constexpr uint32_t kActiveRoutedExperts = 6;
    static constexpr uint32_t kMaxContext = 1048576; // 1M tokens
    /// Global KV per token (compressed): ~890 B/token → 1M ctx ≈ 0.93 GB (docs/CORTEX-DEEPSEEK.md).
    static constexpr uint32_t kKvBytesPerToken = 890;
    /// Two-tier sparse attention: 128-token sliding window per layer; 4 layers (2, 8, 14, 20) compress their
    /// own KV; the indexer keeps the best 512 latents per query, pre-filtered from 2048 blocks × 8 candidates.
    static constexpr uint32_t kSwaWindow = 128;
    static constexpr uint32_t kKvCompressLayers[4] = {2, 8, 14, 20};
    static constexpr uint32_t kIndexerKeep = 512;
    static constexpr uint32_t kCandidateBlocks = 2048;
    static constexpr uint32_t kCandidateBlockSize = 8;
    /// Hyper-connections: 4 parallel residual copies, per-sublayer pre/post/combine coefficients,
    /// combine matrix doubly stochastic (20 Sinkhorn iterations) — the GGUF tensors `blk.N.hc_*`.
    static constexpr uint32_t kHyperConnectionCopies = 4;
    /// Engram conditional memory: 2 tables (layers 1 and 14 own one each), ~384M rows × 256 dims each,
    /// 2/3/4-gram hashed lookups, learned gate into the residual stream. Lives OUT of VRAM (P2).
    static constexpr uint32_t kEngramTables = 2;
    static constexpr uint32_t kEngramRowsPerTable = 384u * 1000u * 1000u; // ~384M rows
    static constexpr uint32_t kEngramDim = 256;
    /// DSpark: semi-autoregressive draft (dspark/*.gguf, ~8.5 GB BF16), confidence-scheduled verification.
    /// Reasoning effort: integer 1-100 (default 75), template kwarg `reasoning_effort`.
};

/// Where each weight class lives, per the Cortex memory hierarchy (P1-P3 targets this layout):
///   VRAM: attention, dense projections, routers, shared experts, output head, the KV cache, and the
///         hot-expert cache (the engine's adaptive expert pool, as for Qwen).
///   RAM:  the routed experts (pinned, computed in place on the CPU when not hot in VRAM).
///   SSD:  the Engram table (`per_layer_token_embd.weight` in the Engram shard) streamed a few rows per
///         token through the OS page cache — the same on-demand path as the Qwen n-gram table, via
///         include/cortex/ngram/ple_reader.hpp (P2 wires it for deepseek41's tensors and metadata).
struct MemoryPlan {
    /// Non-Engram resident weights per quant (GB), from the Unsloth quant table: IQ1_S 122.4, IQ1_M 139.8.
    /// Only IQ1_S and IQ1_M fit 2× A100 80GB (160 GB) with headroom for KV + the vision encoder + buffers.
    static constexpr double kResidentGbIQ1S = 122.4;
    static constexpr double kResidentGbIQ1M = 139.8;
    /// Engram table sizes per precision (GB): IQ4_NL / Q5_K / Q6_K / MXFP8.
    static constexpr double kEngramGbIq4Nl = 110.6;
    static constexpr double kEngramGbQ5K = 135.2;
    static constexpr double kEngramGbQ6K = 161.3;
    static constexpr double kEngramGbMxfp8 = 202.8;
};

/// The engine's entry point (the family switch calls this for a `deepseek41` file). Flags mirror the
/// engine's own surface (--native/--model, --max-context, --prefill, --serve, --mtp, --expert-vram,
/// --expert-slots, --pool-workers, --cpu-threads) plus the family's: --engram ram|ssd, --dspark PATH,
/// --reasoning-effort 1-100. Returns the process exit code.
///
/// Until the P1 port lands, `run` refuses with a clear, actionable message (exit code 2) instead of
/// mis-running the model: it reports the geometry, the memory plan for the file's quant and the pointer
/// to docs/PORTING-DSV41.md.
int run(int argc, char** argv);

}  // namespace cortex::deepseek41
