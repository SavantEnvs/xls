#!/usr/bin/env bash
#
# mayhem/build.sh — builds the XLS IR-parser + DSLX-frontend slice (mayhem/CMakeLists.txt, no Bazel) three ways:
#   $B   sanitized + SanCov + DWARF-3 -> /mayhem/<fuzzer> and /mayhem/<fuzzer>-standalone
#   $BT  plain build (normal flags, no sanitizers) of the upstream gtest suites listed in mayhem/tests.txt and of the
#        known-answer probe, which mayhem/test.sh runs
# Third-party deps (abseil, protobuf, re2, boringssl, ...) come from /opt/toolchains/xlsdeps, built into the
# image by mayhem/install-deps.sh, so this script is air-gapped and re-runnable.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE STANDALONE_FUZZ_MAIN MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
# Build trees live outside the source tree (the gate scans mayhem/ for sanitizer-runtime strings).
B="${TMPDIR:-/tmp}/xls-mayhem-build" ; BT="${TMPDIR:-/tmp}/xls-mayhem-build-tests"
[ -d /opt/toolchains/xlsdeps/lib ] || { echo "missing /opt/toolchains/xlsdeps (mayhem/install-deps.sh)" >&2; exit 1; }

# CMake wipes its cache (and the -D FUZZ_MODE choice with it) when the compiler path changes between runs,
# so always reconfigure from a fresh cache; ninja still rebuilds only what changed.
rm -f "$B/CMakeCache.txt" "$BT/CMakeCache.txt"
mkdir -p "$B"

# 1) sanitized fuzz build: library + harnesses + -standalone reproducers. lsan_off.cc turns LeakSanitizer off
#    at build time and is linked into every fuzz and -standalone binary.
"$CXX" $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$B"/lsan_off.o
cmake -S mayhem -B "$B" -G Ninja -DCMAKE_BUILD_TYPE=Release -DFUZZ_MODE=ON \
  -DLSAN_OFF_OBJECT="$B/lsan_off.o" \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" \
  -DCMAKE_C_FLAGS_RELEASE="-O1" -DCMAKE_CXX_FLAGS_RELEASE="-O1"
cmake --build "$B" -j"$MAYHEM_JOBS"
for h in mayhem/harnesses/fuzz_*.cc; do
  n=$(basename "$h" .cc)
  cp -f "$B/bin/$n" "/mayhem/$n"
  cp -f "$B/bin/$n-standalone" "/mayhem/$n-standalone"
done

# 2) plain build (normal flags, no sanitizers) of the upstream gtest suites and the known-answer probe that test.sh runs.
#    DCHECKs stay enabled here too, as in upstream's default Bazel build.
cmake -S mayhem -B "$BT" -G Ninja -DCMAKE_BUILD_TYPE=Release -DFUZZ_MODE=OFF \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_C_FLAGS_RELEASE="-O1" -DCMAKE_CXX_FLAGS_RELEASE="-O1"
cmake --build "$BT" -j"$MAYHEM_JOBS" --target xls_kat xls_upstream_tests
cp -f "$BT/bin/xls_kat" /mayhem/xls_kat
mkdir -p /mayhem/xls_tests
while read -r t; do
  n=$(basename "$t" .cc)
  cp -f "$BT/bin/$n" "/mayhem/xls_tests/$n"
done < mayhem/tests.txt
