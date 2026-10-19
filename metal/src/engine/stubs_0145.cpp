// metal/src/engine/stubs_0145.cpp - the kernel-library entry points the 0.1.45 sources added and Metal does not implement yet.
// Same job and shape as stubs.cpp (each stops the engine with its name, metal/src/engine/missing.cpp). Written from the linker's
// undefined-symbol report because tools/gen_stubs.py reads an older clang AST dump format than macOS 27's clang prints.
// A symbol that gets a Metal implementation is deleted from here. fused_gr_persist_init / fused_gr_read_persist / f16_range_read /
// gemm_f16_range_read are opt-in features of the HIP and Turing builds: off on Metal, so they answer "nothing to do" instead of stopping the engine.

#include "cortex/kernels/bf16_bits.hpp"
#include "cortex/kernels/bf16_gemv.hpp"
#include "cortex/kernels/cvec.hpp"
#include "cortex/kernels/dequant_bf16.hpp"
#include "cortex/kernels/dequant_s2.hpp"
#include "cortex/kernels/elementwise.hpp"
#include "cortex/kernels/f16_bits.hpp"
#include "cortex/kernels/fused_gdn.hpp"
#include "cortex/kernels/fused_gr.hpp"
#include "cortex/kernels/gdn.hpp"
#include "cortex/kernels/gfx_arch.hpp"
#include "cortex/kernels/gr.hpp"
#include "cortex/kernels/iq_kernels.hpp"
#include "cortex/kernels/kv_q4.hpp"
#include "cortex/kernels/kv_q8.hpp"
#include "cortex/kernels/kv_stream.hpp"
#include "cortex/kernels/mrope.hpp"
#include "cortex/kernels/native_flash_attn.hpp"
#include "cortex/kernels/native_gdn.hpp"
#include "cortex/kernels/native_gdn_preprocess.hpp"
#include "cortex/kernels/native_gr_norm.hpp"
#include "cortex/kernels/native_gr_postops.hpp"
#include "cortex/kernels/native_mmvq.hpp"
#include "cortex/kernels/native_moe.hpp"
#include "cortex/kernels/native_ple_postops.hpp"
#include "cortex/kernels/native_qsa.hpp"
#include "cortex/kernels/native_qsa_indexer.hpp"
#include "cortex/kernels/native_qsa_score.hpp"
#include "cortex/kernels/native_rope.hpp"
#include "cortex/kernels/native_router.hpp"
#include "cortex/kernels/ngram.hpp"
#include "cortex/kernels/pdl.hpp"
#include "cortex/kernels/ple.hpp"
#include "cortex/kernels/qsa.hpp"
#include "cortex/kernels/qsa_decode_attn.hpp"
#include "cortex/kernels/qsa_prompt_attn.hpp"
#include "cortex/kernels/qsa_select.hpp"
#include "cortex/kernels/quantize_act.hpp"
#include "cortex/kernels/rope.hpp"
#include "cortex/kernels/rope_scaling.hpp"
#include "cortex/kernels/route_prior.hpp"
#include "cortex/kernels/router_top10.hpp"
#include "cortex/kernels/s2_expert_grouped.hpp"
#include "cortex/kernels/s2_gemv.hpp"
#include "cortex/kernels/s2_gemv_q8.hpp"
#include "cortex/kernels/s_gemv.hpp"
#include "cortex/kernels/sampler.hpp"
#include "cortex/kernels/shared_expert.hpp"
#include "cortex/kernels/verify_kernels.hpp"
#include "cortex/kernels/cpu/expert.hpp"
#include "cortex/kernels/cpu/expert_layout.hpp"
#include "cortex/kernels/cpu/iq_avx1.hpp"
#include "cortex/kernels/cpu/iq_avx2.hpp"
#include "cortex/kernels/cpu/iq_avx512.hpp"
#include "cortex/kernels/cpu/kq_avx1.hpp"
#include "cortex/kernels/cpu/kq_avx2.hpp"
#include "cortex/kernels/cpu/native_expert.hpp"
#include "cortex/kernels/cpu/pool.hpp"
#include "cortex/prefill/gemm.hpp"
#include "cortex/prefill/kernels.hpp"
#include "cortex/prefill/moe_fused.hpp"
#include "cortex/prefill/moe_fused_iq.hpp"
#include "cortex/prefill/moe_mmq.hpp"
#include "cortex/prefill/prefill.hpp"
#include "cortex/prefill/share_rules.hpp"
#include "cortex/prefill/xmx_moe.hpp"
#include "cortex/core/arch_defaults.hpp"
#include "cortex/core/batch_rows.hpp"
#include "cortex/core/conversation_buffer.hpp"
#include "cortex/core/conversation_cache.hpp"
#include "cortex/core/conversation_file.hpp"
#include "cortex/core/conversation_memory.hpp"
#include "cortex/core/conversation_snapshot.hpp"
#include "cortex/core/coupled_draft.hpp"
#include "cortex/core/device.hpp"
#include "cortex/core/dma_batch.hpp"
#include "cortex/core/emulate.hpp"
#include "cortex/core/exchange_storage.hpp"
#include "cortex/core/expert_cache.hpp"
#include "cortex/core/expert_source.hpp"
#include "cortex/core/foresight_swap.hpp"
#include "cortex/core/graph.hpp"
#include "cortex/core/hit_hook.hpp"
#include "cortex/core/layer.hpp"
#include "cortex/core/layout.hpp"
#include "cortex/core/logit_bias.hpp"
#include "cortex/core/mtp.hpp"
#include "cortex/core/native_dense.hpp"
#include "cortex/core/native_head.hpp"
#include "cortex/core/on_device.hpp"
#include "cortex/core/peer_experts.hpp"
#include "cortex/core/pinned.hpp"
#include "cortex/core/pinned_ring.hpp"
#include "cortex/core/progress.hpp"
#include "cortex/core/remote_expert_opt.hpp"
#include "cortex/core/remote_experts.hpp"
#include "cortex/core/session.hpp"
#include "cortex/core/session_save_reclaim.hpp"
#include "cortex/core/spec_prob.hpp"
#include "cortex/core/verify.hpp"
#include "cortex/core/vmm.hpp"
#include "cortex/core/weights.hpp"
#include "cortex/platform/aux_cpus.hpp"
#include "cortex/platform/direct_file.hpp"
#include "cortex/platform/host_limits.hpp"
#include "cortex/platform/memory.hpp"
#include "cortex/ngram/ple_reader.hpp"
#include "cortex/spec/controller.hpp"
#include "cortex/spec/draft_policy.hpp"
#include "cortex/spec/draft_source.hpp"
#include "cortex/spec/suffix_drafter.hpp"
#include <type_traits>

#include <type_traits>

namespace cortex::metal_engine { void missing(const char* name); }

namespace cortex::kernels { void copy_rows_from_mapped_after(unsigned int const* p0, unsigned int p1, float* p2, float const* p3, long long p4, long long p5, int const* p6, int const* p7, void* p8) { cortex::metal_engine::missing("cortex::kernels::copy_rows_from_mapped_after"); } }
namespace cortex::kernels::cpu { void iq256_gu_rows_exact_one(int p0, unsigned char const* p1, unsigned long p2, unsigned long p3, int p4, void const* p5, float* p6, int p7, int p8) { cortex::metal_engine::missing("cortex::kernels::cpu::iq256_gu_rows_exact_one"); } }
namespace cortex::kernels { void fused_gr_persist_init() {  } }
namespace cortex::kernels { bool fused_gr_read_persist(cortex::kernels::FusedGrArgs const* p0, int p1, void* p2) {  return false; } }
namespace cortex::kernels { void gdn_step_norm_groups(cortex::kernels::GdnGroups const& p0, float const* p1, int p2, float const* p3, float const* p4, float const* p5, float const* p6, float p7, float* p8, int p9, int p10, bool p11, void* p12) { cortex::metal_engine::missing("cortex::kernels::gdn_step_norm_groups"); } }
namespace cortex::kernels { void handoff_publish(float* p0, float const* p1, long long p2, float const* p3, long long p4, float const* p5, long long p6, unsigned int* p7, unsigned int* p8, void* p9, unsigned int const* p10) { cortex::metal_engine::missing("cortex::kernels::handoff_publish"); } }
namespace cortex::kernels { void hc_q8_to_bf16(void const* p0, float const* p1, unsigned short* p2, long long p3, void* p4) { cortex::metal_engine::missing("cortex::kernels::hc_q8_to_bf16"); } }
namespace cortex::kernels { void native_quantize_q8_1_il(float const* p0, void* p1, void* p2, int p3, int p4, void* p5) { cortex::metal_engine::missing("cortex::kernels::native_quantize_q8_1_il"); } }
namespace cortex::kernels { void qsa_block_scores_rows(cortex::kernels::QsaScoreRows const& p0, float const* p1, int const* p2, long long p3, long long p4, cortex::kernels::QsaShapes const& p5, float* p6, void* p7) { cortex::metal_engine::missing("cortex::kernels::qsa_block_scores_rows"); } }
namespace cortex::kernels { void qsa_decode_attn_batch_rows(float const* p0, cortex::kernels::QsaAttnPoolsRows const& p1, int const* p2, int const* p3, long long p4, cortex::kernels::QsaShapes const& p5, float* p6, float* p7, long long p8, void* p9) { cortex::metal_engine::missing("cortex::kernels::qsa_decode_attn_batch_rows"); } }
namespace cortex::kernels { bool qsa_decode_attn_split(float const* p0, cortex::kernels::QsaAttnPools const& p1, int const* p2, int const* p3, long long p4, cortex::kernels::QsaShapes const& p5, float* p6, unsigned long long p7, float* p8, long long p9, void* p10) { cortex::metal_engine::missing("cortex::kernels::qsa_decode_attn_split"); return {}; } }
namespace cortex::kernels { void res_patch(int* p0, int const* p1, int p2, void* p3) { cortex::metal_engine::missing("cortex::kernels::res_patch"); } }
namespace cortex::kernels { void wait_copy_i32_from_mapped(unsigned int const* p0, unsigned int p1, int* p2, int const* p3, long long p4, void* p5) { cortex::metal_engine::missing("cortex::kernels::wait_copy_i32_from_mapped"); } }
namespace cortex::kernels { void wait_flag_ge_stamped(unsigned int const* p0, unsigned int p1, unsigned long long* p2, unsigned long long* p3, void* p4) { cortex::metal_engine::missing("cortex::kernels::wait_flag_ge_stamped"); } }
namespace cortex::kernels { void wait_handoff(unsigned int const* p0, unsigned int p1, unsigned int* p2, unsigned long long p3, void* p4) { cortex::metal_engine::missing("cortex::kernels::wait_handoff"); } }
namespace cortex::prefill { bool f16_range_read(float& p0, unsigned long long& p1, bool p2) {  return false; } }
namespace cortex::prefill { bool gemm_f16_range_read(float* p0, unsigned long long* p1, bool p2) {  return false; } }
namespace cortex::prefill { void gr_norm(float const* p0, float const* p1, float p2, float* p3, unsigned short* p4, long long p5, void* p6, unsigned short* p7, bool p8) { cortex::metal_engine::missing("cortex::prefill::gr_norm"); } }
namespace cortex::prefill { void gr_norm_rs(float const* p0, float const* p1, float p2, float* p3, unsigned short* p4, long long p5, void* p6, unsigned short* p7, long long p8, bool p9) { cortex::metal_engine::missing("cortex::prefill::gr_norm_rs"); } }
namespace cortex::prefill { void gr_write_cvec_norm_rs(float* p0, float const* p1, float const* p2, long long p3, float const* p4, float const* p5, int const* p6, int p7, float const* p8, float p9, float* p10, unsigned short* p11, long long p12, void* p13, unsigned short* p14, long long p15, bool p16) { cortex::metal_engine::missing("cortex::prefill::gr_write_cvec_norm_rs"); } }
namespace cortex::prefill { void gr_write_norm_rs(float* p0, float const* p1, float const* p2, long long p3, float const* p4, float p5, float* p6, unsigned short* p7, long long p8, void* p9, unsigned short* p10, long long p11, bool p12) { cortex::metal_engine::missing("cortex::prefill::gr_write_norm_rs"); } }
// pf_wmma (CORTEX_PF_WMMA=1, Volta prompt experts) is CUDA only; the prefill code of 148/149 references it, so the Metal link needs the entry point. Off on Metal: "not launched".
namespace cortex::kernels { bool gemm_iq_f16_grouped(int p0, void const* p1, unsigned long p2, int p3, int p4, void const* p5, int p6, int const* p7, int p8, int p9, float* p10, int p11, void* p12) { return false; } }
// CORTEX_Q8_SM60 (Pascal GP100, opt-in): a no-op on Metal; NativeHead::load()/unload() call these for a Q8_0 head, so they must exist and answer "nothing packed".
namespace cortex::kernels { bool native_q8_0_sm60_pack(void const* p0, int p1, int p2, char const* p3) { return false; } }
namespace cortex::kernels { void native_q8_0_sm60_release(void const* p0) { } }
// only reached with pf_wmma (off on Metal)
namespace cortex::prefill { void swiglu_split_f16(float const* p0, unsigned short* p1, long long p2, int p3, bool p4, void* p5) { } }
