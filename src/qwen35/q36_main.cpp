// src/qwen35/q36_main.cpp - cortex-q36: the Qwen3.6 engine path on its own (the same entry point `cortex` switches
// to for a qwen35moe model).
#include "cortex/qwen35/engine.hpp"

int main(int argc, char** argv) { return cortex::qwen35::run(argc, argv); }
