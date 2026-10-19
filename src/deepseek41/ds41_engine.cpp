// src/deepseek41/ds41_engine.cpp - the DeepSeek-V4.1-Flash engine path, Phase P1 entry stub.
//
// cortex::deepseek41::run() is reached from the family switch in src/program/generate.cpp for every GGUF
// with `general.architecture == deepseek41`. Until the P1-P3 port lands (docs/ROADMAP.md; the upstream
// reference is vendored in third_party/upstream-dsv41/), this refuses honestly: it validates the file it
// was given, prints the architecture it detected, the memory plan for that quant and exactly what is
// missing — never a half-working model. Exit code 2 (usage/expected-refusal class, not a crash).
#include "cortex/deepseek41/engine.hpp"

#include <cstdio>
#include <cstring>
#include <string>

namespace cortex::deepseek41 {

namespace {

int fail(const char* model_path) {
    std::fprintf(stderr,
        "cortex: DeepSeek-V4.1-Flash (architecture 'deepseek41') is recognised but the engine path is\n"
        "not built yet — Phase P1 of docs/ROADMAP.md. Nothing was run; no partial state was created.\n"
        "  file: %s\n"
        "  geometry: 20+20 layers, 384 routed + 1 shared experts (6 active), 1M context, ~890 B/token KV\n"
        "  plan: IQ1_M needs %.1f GB resident (fits 2x A100 80GB); the Engram table (%.1f-%.1f GB) streams\n"
        "        from NVMe via the PLE n-gram reader (P2); DSpark drafts via the spec controller (P3)\n"
        "  meanwhile: run the same files through a runtime with deepseek41 support (see docs/CORTEX-DEEPSEEK.md)\n"
        "  status + port map: docs/PORTING-DSV41.md\n",
        model_path ? model_path : "(not given)",
        MemoryPlan::kResidentGbIQ1M, MemoryPlan::kEngramGbIq4Nl, MemoryPlan::kEngramGbMxfp8);
    return 2;
}

}  // namespace

int run(int argc, char** argv) {
    const char* model_path = nullptr;
    for (int i = 1; i + 1 < argc; ++i) {
        if (std::strcmp(argv[i], "--native") == 0 || std::strcmp(argv[i], "--model") == 0) {
            model_path = argv[i + 1];
            break;
        }
    }
    if (!model_path || !*model_path) return fail(nullptr);
    // A light existence check so the message can point at the actual file (no GGUF parsing yet: the
    // architecture was already verified by the family switch before this call).
    if (std::FILE* f = std::fopen(model_path, "rb")) {
        std::fclose(f);
    } else {
        std::fprintf(stderr, "cortex: cannot open model file: %s\n", model_path);
        return 2;
    }
    return fail(model_path);
}

}  // namespace cortex::deepseek41
