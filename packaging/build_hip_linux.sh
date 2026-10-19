#!/bin/bash
# Linux AMD (HIP) engine package: cortex + the CPU picture reader (cortex-vision) + the GPU picture reader (cortex-vision-hip),
# the ROCm libraries both load, and the rocBLAS / hipBLASLt kernel data for the listed archs, packaged as an engine component.
# Run on a Linux box that has ROCm (TheRock Python wheels are enough); the tester packages were built in an Ubuntu 22.04 chroot
# (glibc 2.35) so they run on every distribution since.  All settings are environment variables:
#
#   VARIANT=rx9070     rx9070 (gfx1200 gfx1201) | rx7900 (gfx1100 gfx1101 gfx1102) | halo (gfx1151) | igpu (gfx1103 gfx1150) | a name + ARCHS=
#   ARCHS="gfx1200;gfx1201"          the code objects (default: the variant's)
#   SRC=<this checkout>              the Cortex source (default: the checkout this script is in)
#   LLAMA=<llama.cpp checkout>       at the pinned commit (setup.py LLAMA_CPP_COMMIT); mtmd and ggml come from it
#   HP=<ROCm devel root>  CORE=<ROCm core root>  LIBW=<ROCm libraries root>   (TheRock: _rocm_sdk_devel, _rocm_sdk_core, _rocm_sdk_libraries_*)
#   OUT=<work folder>  PKGVER=0.1.45.3  COMMIT=<source commit for the build id>  JOBS=16
#   VISION_ONLY=1                    build only the two readers (no engine, no package)
#   NO_PACKAGE=1                     stop after the stage folder
#   VISION_HIP_DEFS="-DGGML_CUDA_FA=OFF"   extra cmake definitions for the GPU reader only
#
# Both readers get RUNPATH $ORIGIN (tools/vision/CMakeLists.txt), and every bundled library is patched to $ORIGIN, so the
# component folder runs from anywhere with nothing from the environment (packaging/binary_deps.py checks it).
set -u
V=${VARIANT:?VARIANT=rx9070|rx7900|halo|igpu|<name> with ARCHS=}
SRC=${SRC:-$(cd "$(dirname "$0")/.." && pwd)}
LLAMA=${LLAMA:?LLAMA=<llama.cpp checkout at the pinned commit>}
HP=${HP:?HP=<ROCm devel root>}
CORE=${CORE:-$HP}
LIBW=${LIBW:-$HP}
OUT=${OUT:-$PWD/work-$V}
PKGVER=${PKGVER:-0.1.45.3}
COMMIT=${COMMIT:-unknown}
JOBS=${JOBS:-16}
case "$V" in
  rx9070) ARCHS=${ARCHS:-gfx1200;gfx1201} ;;
  rx7900) ARCHS=${ARCHS:-gfx1100;gfx1101;gfx1102} ;;
  halo)   ARCHS=${ARCHS:-gfx1151} ;;
  igpu)   ARCHS=${ARCHS:-gfx1103;gfx1150} ;;
  *)      ARCHS=${ARCHS:?ARCHS=gfx...} ;;
esac
ARCHLIST=${ARCHS//;/ }
DATAARCH=${ARCHS//;/,}
mkdir -p "$OUT"; S=$OUT/build.status
st() { echo "$* $(date +%T)" >> "$S"; }
: > "$S"
export HIP_PLATFORM=amd HIP_COMPILER=clang HIP_RUNTIME=rocclr ROCM_PATH=$HP HIP_PATH=$HP
HIPDEFS=(-DCMAKE_HIP_COMPILER=$HP/llvm/bin/clang++ -DCMAKE_HIP_COMPILER_ROCM_ROOT=$HP "-DCMAKE_PREFIX_PATH=$HP;$LIBW"
         "-DCMAKE_HIP_FLAGS=--rocm-path=$HP --rocm-device-lib-path=$HP/lib/llvm/amdgcn/bitcode")
st "start $V ($ARCHS) commit $COMMIT"
cd "$SRC" || exit 1
if [ -z "${VISION_ONLY:-}" ]; then
  cmake -G Ninja -S . -B "$OUT/b" -DCMAKE_BUILD_TYPE=Release -DCORTEX_ENABLE_HIP=ON -DCORTEX_ENABLE_CUDA=OFF -DCORTEX_BUILD_TESTS=OFF \
    -DCORTEX_PREFILL_MMQ=ON "-DCMAKE_HIP_ARCHITECTURES=$ARCHS" "${HIPDEFS[@]}" -DCORTEX_GGML_DIR="$LLAMA" -DCORTEX_PORTABLE=ON \
    "-DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath,'\$ORIGIN' -Wl,--enable-new-dtags" > "$OUT/cfg.log" 2>&1
  st "engine configured rc=$?"
  nice -n 10 cmake --build "$OUT/b" --target cortex -j "$JOBS" > "$OUT/build.log" 2>&1
  st "engine built rc=$?"
  [ -x "$OUT/b/cortex" ] || { st "ABORT no cortex"; exit 1; }
fi
# the CPU reader: portable (AVX2), the fallback that runs on any PC
cmake -G Ninja -S tools/vision -B "$OUT/bv" -DCMAKE_BUILD_TYPE=Release -DLLAMA_DIR="$LLAMA" -DCORTEX_VISION_CUDA=OFF \
  -DCORTEX_PORTABLE=ON > "$OUT/cfg-vision.log" 2>&1
nice -n 10 cmake --build "$OUT/bv" --target cortex-vision -j "$JOBS" > "$OUT/build-vision.log" 2>&1
st "cpu reader built rc=$?"
[ -x "$OUT/bv/bin/cortex-vision" ] || { st "ABORT no cortex-vision"; exit 1; }
# the GPU reader: ggml-hip for the same archs; the CPU kernels in it are portable too
cmake -G Ninja -S tools/vision -B "$OUT/bh" -DCMAKE_BUILD_TYPE=Release -DLLAMA_DIR="$LLAMA" -DCORTEX_VISION_HIP=ON \
  "-DCORTEX_VISION_HIP_ARCHS=$ARCHS" -DCORTEX_PORTABLE=ON "${HIPDEFS[@]}" ${VISION_HIP_DEFS:-} > "$OUT/cfg-vision-hip.log" 2>&1
st "gpu reader configured rc=$?"
nice -n 10 cmake --build "$OUT/bh" --target cortex-vision -j "$JOBS" > "$OUT/build-vision-hip.log" 2>&1
st "gpu reader built rc=$?"
[ -x "$OUT/bh/bin/cortex-vision-hip" ] || { st "ABORT no cortex-vision-hip"; tail -20 "$OUT/build-vision-hip.log" >> "$S"; exit 1; }
[ -n "${VISION_ONLY:-}" ] && { st "VISION-DONE"; exit 0; }
STAGE=$OUT/stage; rm -rf "$STAGE"; mkdir -p "$STAGE"
ARCHJSON=$(for a in $ARCHLIST; do printf '"%s", ' "$a"; done | sed 's/, $//')
cat > "$STAGE/BUILD.json" <<EOJ
{"version": "$PKGVER", "source": "f-amd-vision $COMMIT", "variant": "$V", "archs": [$ARCHJSON], "portable": true, "vision": "gpu", "vision_cpu": "cortex-vision", "vision_gpu": "cortex-vision-hip", "vision_archs": [$ARCHJSON]}
EOJ
# the libraries the engine and the GPU reader load (the CPU reader needs only the system's), collected from the build outputs
DATA=(--data "$LIBW/lib/rocblas/library=rocblas/library" --data "$LIBW/lib/hipblaslt/library=hipblaslt/library" --data-arch "$DATAARCH")
for b in "$OUT/b/cortex" "$OUT/bh/bin/cortex-vision-hip"; do
  python3 packaging/collect_libs.py --binary "$b" --search "$LIBW/lib" --search "$HP/lib" --search "$CORE/lib" --search "$CORE/lib/llvm/lib" \
    --also 'libamd_comgr.so*' --also 'libhiprtc*.so*' --out "$STAGE" \
    "${DATA[@]}" >> "$OUT/collect.log" 2>&1
  st "collected for $(basename "$b") rc=$?"
  DATA=()                                              # the kernel data once
done
cp "$OUT/b/cortex" "$OUT/bv/bin/cortex-vision" "$OUT/bh/bin/cortex-vision-hip" "$STAGE/"
for f in "$STAGE"/*.so "$STAGE"/*.so.*; do [ -f "$f" ] && [ ! -L "$f" ] && patchelf --set-rpath '$ORIGIN' "$f"; done
for f in "$STAGE/cortex" "$STAGE/cortex-vision" "$STAGE/cortex-vision-hip"; do
  st "RUNPATH $(basename "$f"): $(readelf -d "$f" | grep -E 'RPATH|RUNPATH' | cut -d'[' -f2 | tr -d ']' | paste -sd' ')"
done
[ -n "${NO_PACKAGE:-}" ] && { st "STAGE-DONE"; exit 0; }
rm -rf "$OUT/components"; mkdir -p "$OUT/components/engine"
ARCHARGS=""; for a in $ARCHLIST; do ARCHARGS="$ARCHARGS --arch $a"; done
python3 packaging/package_engine.py --src "$STAGE" --backend hip --version "$PKGVER" --out "$OUT/components/engine" $ARCHARGS \
  --variant "$V" --build-id "$COMMIT+rocm" --tree --notes "AMD $V build: engine, CPU picture reader, GPU picture reader" > "$OUT/package.log" 2>&1
st "packaged rc=$?"
cat "$OUT/package.log" >> "$S"
st "BUILD-DONE"
