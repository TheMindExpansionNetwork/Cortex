// include/cortex/deepseek41/dspark.hpp - the DSpark speculative-decoding plan for Phase P3.
//
// DSpark is DeepSeek-V4.1-Flash's semi-autoregressive drafter: it drafts tokens with confidence-scheduled
// verification — the main model checks a whole drafted block in one pass and keeps the accepted prefix,
// exactly the contract Cortex's spec controller already implements for the Qwen MTP path:
//   - include/cortex/spec/controller.hpp  — the verification/acceptance loop
//   - include/cortex/spec/draft_policy.hpp, draft_source.hpp — how drafts are produced and capped
//   - include/cortex/core/coupled_draft.hpp — the coupled draft machinery (the MTP integration point)
// The drafter ships as its own GGUF (`dspark/DeepSeek-V4.1-Flash-1017-BF16.gguf`, 8.5 GB; ~+14B drafter
// params on top of the main model's expert load — plan capacity for it). Upstream reference:
// third_party/upstream-dsv41/reference/dflash.cpp (`dflash` = the drafter's engine-side name).
//
// P3's exit criteria (docs/ROADMAP.md): >=1.6x decode speedup vs undrafted on the same hardware, with
// identical greedy outputs on the check set. When the drafter is absent the engine must run undrafted —
// DSpark is an accelerator, never a requirement.
#pragma once

#include <cstdint>

namespace cortex::deepseek41 {

/// DSpark drafter configuration (P3).
struct DSparkPlan {
    bool enabled = false;          ///< --dspark PATH turns this on
    const char* model_path = nullptr;  ///< the drafter GGUF
    uint32_t draft_tokens_per_round = 5;  ///< upstream: DSpark drafts 5 tokens per round (vLLM recipe)
    /// Confidence-scheduled verification: accept the drafted prefix up to the first token whose verifier
    /// confidence drops below schedule; the main model rewrites from there. The controller owns the loop;
    /// this plan only carries the schedule's shape (P3 tunes it on the A100 bring-up).
    double confidence_floor = 0.0;  ///< 0 = always verify the full block (conservative default)
};

}  // namespace cortex::deepseek41
