// src/core/nv_defaults.cpp - see include/cortex/core/nv_defaults.hpp.
#include "cortex/core/nv_defaults.hpp"

#include "cortex/core/emulate.hpp"

#include <cstdio>
#include <cstdlib>

namespace cortex::core {

namespace {
bool off(const char* name) {
    const char* v = std::getenv(name);
    return v != nullptr && v[0] == '0';
}
}  // namespace

std::vector<std::pair<std::string, std::string>> nv_default_env(int major, int minor) {
    std::vector<std::pair<std::string, std::string>> t;
    const int mj = cortex::cc_major_of(major), mn = cortex::cc_minor_of(minor);
    if (mj == 8 && mn == 6) {
        if (off("CORTEX_SM86_PERF")) return t;
        t = {
            // 148-nv, RTX 3060 + RTX A4000 (IQ3_XXS, default flags, 8 pairs): the stack +9.6% / +14.6% (8/8 each), identity gate IDENTICAL.
            // Each is in because removing it from the full stack cost speed on a card (drop-one, 4 rounds) and saved none on the other.
            {"CORTEX_ADAPT_NOWAIT", "1"},        // A4000 -6.3 points when removed (with ADAPT_LAG), 3060 -0.8
            {"CORTEX_ADAPT_LAG", "2"},
            {"CORTEX_CPU_IQ_ALL_EXACT1", "1"},   // A4000 -3.3, 3060 -0.6
            {"CORTEX_SIDE_MIXER", "2"},          // A4000 -1.2, 3060 -2.3
            {"CORTEX_ATTN_DAILY", "1"},          // -1.2, -1.3
            {"CORTEX_GR_UP75", "1"},             // -0.9, -1.8
            {"CORTEX_GU_SWIGLU", "1"},           // -0.8, -1.4
            {"CORTEX_QSA_ROWS", "1"},            // -0.5, -1.2
            {"CORTEX_B6_MMVQ_ROWS", "1"},        // A4000 0, 3060 -1.7
        };
    } else if (mj == 6 && mn == 0) {
        if (off("CORTEX_SM60_PERF")) return t;
        t = {
            // 148-nv, Tesla P100 (IQ3_XXS, default flags, 8 pairs): the stack +17.8% (8/8), identity gate IDENTICAL.
            {"CORTEX_ADAPT_NOWAIT", "1"},        // -10 points when removed (with ADAPT_LAG)
            {"CORTEX_ADAPT_LAG", "2"},
            {"CORTEX_SIDE_MIXER", "2"},          // -1.8
            {"CORTEX_FUSE_WAIT", "2"},           // -1.6
            {"CORTEX_B6_MMVQ_ROWS", "1"},        // -1.3
            {"CORTEX_FUSE_DECODE", "1"},         // -1.3
            {"CORTEX_GR_UP75", "1"},             // -1.2
        };
    }
    return t;
}

std::vector<std::string> apply_nv_defaults(int major, int minor) {
    std::vector<std::string> set;
    for (const auto& kv : nv_default_env(major, minor)) {
        if (std::getenv(kv.first.c_str()) != nullptr) continue;   // the user's setting wins, whatever it is
#if defined(_WIN32)
        _putenv_s(kv.first.c_str(), kv.second.c_str());
#else
        setenv(kv.first.c_str(), kv.second.c_str(), 0);
#endif
        set.push_back(kv.first);
    }
    if (!set.empty()) {
        const bool sm86 = cortex::cc_major_of(major) == 8;
        std::fprintf(stderr, "cortex: %s: %zu exact speed switches on by default (%s=0 turns them off; a switch you set is kept): ",
                     sm86 ? "sm_86 (Ampere)" : "sm_60 (Pascal)", set.size(), sm86 ? "CORTEX_SM86_PERF" : "CORTEX_SM60_PERF");
        for (size_t i = 0; i < set.size(); ++i) std::fprintf(stderr, "%s%s", i ? " " : "", set[i].c_str() + 7);
        std::fprintf(stderr, "\n");
    }
    return set;
}

}  // namespace cortex::core
