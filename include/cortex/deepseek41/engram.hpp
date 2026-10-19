// include/cortex/deepseek41/engram.hpp - the Engram conditional-memory plan for Phase P2.
//
// DeepSeek-V4.1-Flash's Engram is two hash tables (~384M rows × 256 dims each, layers 1 and 14), looked
// up by 2-, 3- and 4-gram hashes of the input and written into the residual stream through a learned gate.
// In the Unsloth GGUF layout the whole table is ONE tensor, `per_layer_token_embd.weight`, shipped as the
// final GGUF shard (verified from the shard 5 header, 2026-10-19). It is read a few rows per token —
// exactly the access pattern of Cortex's existing SSD n-gram reader for the Qwen families.
//
// P2 wires this to the proven machinery instead of inventing a new one:
//   - include/cortex/ngram/ple_reader.hpp  — the PLE n-gram reader (on-demand mmap rows, page-cache friendly)
//   - include/cortex/kernels/ngram.hpp     — the hash kernels
//   - include/cortex/kernels/ple.hpp       — the PLE post-ops (the gate into the residual stream)
// The upstream reference (third_party/upstream-dsv41/reference/deepseek41.cpp, search "engram") defines the
// GGUF metadata this must honour: LLM_KV_PLE_NGRAM_SIZE (max n-gram), LLM_KV_PLE_HEADS_PER_NGRAM,
// LLM_KV_EMBEDDING_LENGTH_PER_LAYER, LLM_KV_PLE_LAYER_MULTIPLIERS, LLM_KV_PLE_HEAD_OFFSETS,
// LLM_KV_PLE_HEAD_VOCAB_SIZES, LLM_KV_ENGRAM_PAD_TOKEN_ID, LLM_KV_ENGRAM_TOKEN_MAP. The reader validates
// them exactly like upstream: mult.size() == n_e*max_ngram, primes/offsets sized n_e*n_cols, and
// pad_id < token_map.size(), else "DeepSeek-V4.1 engram metadata is inconsistent".
//
// Swap-the-table (Unsloth's `engram/set_split.py` scheme): any table precision (IQ4_NL 110.6 / Q5_K 135.2 /
// Q6_K 161.3 / MXFP8 202.8 GB) can be stamped as the quant's table shard and dropped in place of the shipped
// one — `cortex --engram ssd` streams it from NVMe; `--engram ram` requires the host to have the table's
// size free (page-cache warm) for the fast path. Placement is decided at load time, never mid-run.
#pragma once

#include <cstdint>

namespace cortex::deepseek41 {

/// Engram placement decision (P2). Pure data; the engine's loader consults it.
enum class EngramPlacement {
    Ssd,  ///< mmap rows on demand from the NVMe table (default; needs no RAM beyond the page cache)
    Ram,  ///< host keeps the table resident (page-cache warm); requires >= table size of free RAM
};

/// The reader contract P2 implements. Inputs come from the GGUF metadata above; the tensor is the Engram
/// shard's `per_layer_token_embd.weight` (n_e * n_cols * rows * head_dim, quantised per the table format).
/// Row fetches are 2/3/4-gram hash buckets — the PLE reader already bounds memory traffic to a few rows
/// per token, which is what makes SSD streaming viable (the KV cache stays at ~890 B/token regardless).
struct EngramPlan {
    uint32_t max_ngram = 4;      // LLM_KV_PLE_NGRAM_SIZE (2-4 used)
    uint32_t heads_per_ngram = 0;// LLM_KV_PLE_HEADS_PER_NGRAM
    uint32_t head_dim = 0;       // LLM_KV_EMBEDDING_LENGTH_PER_LAYER
    EngramPlacement placement = EngramPlacement::Ssd;
};

}  // namespace cortex::deepseek41
