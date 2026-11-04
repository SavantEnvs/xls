#!/usr/bin/env bash
# Builds XLS's third-party C++ deps (abseil, protobuf, boringssl, re2, googletest, cppitertools, or-tools graph headers) from pinned tarballs into
# /opt/toolchains/xlsdeps. Run once as root at image build time; build.sh then resolves them offline.
set -euo pipefail
PREFIX=/opt/toolchains/xlsdeps
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

fetch() { # name url sha256
  curl -fsSL --retry 5 -o "$1.tar.gz" "$2"
  echo "$3  $1.tar.gz" | sha256sum -c -
  mkdir "$1" && tar -xzf "$1.tar.gz" -C "$1" --strip-components=1
}

fetch absl https://github.com/abseil/abseil-cpp/releases/download/20260526.0/abseil-cpp-20260526.0.tar.gz \
  6e1aee535473414164bf83e4ebc40240dec71a4701f8a642d906e95bea1aea0c
fetch protobuf https://github.com/protocolbuffers/protobuf/releases/download/v33.5/protobuf-33.5.tar.gz \
  c6c7c27fadc19d40ab2eaa23ff35debfe01f6494a8345559b9bb285ce4144dd1
fetch re2 https://github.com/google/re2/releases/download/2025-11-05/re2-2025-11-05.tar.gz \
  87f6029d2f6de8aa023654240a03ada90e876ce9a4676e258dd01ea4c26ffd67
fetch googletest https://github.com/google/googletest/releases/download/v1.17.0/googletest-1.17.0.tar.gz \
  65fab701d9829d38cb77c14acdc431d2108bfdbf8979e40eb8ae567edf10b27c
fetch cppitertools https://github.com/ryanhaining/cppitertools/archive/refs/tags/v2.2.tar.gz \
  d4e796c9d8ec769fbd68df92943d238d0c43667307995ede058069e770827481

fetch ortools https://github.com/google/or-tools/archive/refs/tags/v9.15.tar.gz \
  6395a00a97ff30af878ee8d7fd5ad0ab1c7844f7219182c6d71acbee1b5f3026

fetch boringssl https://github.com/google/boringssl/archive/refs/tags/0.20251002.0.tar.gz \
  f96733fc3df03d4195db656d1b7b8c174c33f95d052f811f0ecc8f4e4e3db332

COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
        -DCMAKE_CXX_STANDARD=20 -DCMAKE_CXX_STANDARD_REQUIRED=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX")

# googletest/googlemock: only the upstream unit tests and abseil's status matchers (mayhem/test.sh) link them; the fuzz build does not.
cmake -S googletest -B googletest-b "${COMMON[@]}" -DBUILD_GMOCK=ON -DINSTALL_GTEST=ON
cmake --build googletest-b && cmake --install googletest-b

# ABSL_BUILD_TEST_HELPERS adds libabsl_status_matchers (absl_testing::IsOk etc.), which the upstream XLS tests use.
cmake -S absl -B absl-b "${COMMON[@]}" -DABSL_PROPAGATE_CXX_STD=ON -DABSL_BUILD_TESTING=OFF -DABSL_ENABLE_INSTALL=ON \
  -DABSL_BUILD_TEST_HELPERS=ON -DABSL_USE_EXTERNAL_GOOGLETEST=ON -DABSL_FIND_GOOGLETEST=ON
cmake --build absl-b && cmake --install absl-b

cmake -S protobuf -B protobuf-b "${COMMON[@]}" -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_ABSL_PROVIDER=package \
  -Dprotobuf_INSTALL=ON -Dprotobuf_BUILD_SHARED_LIBS=OFF
cmake --build protobuf-b && cmake --install protobuf-b

cmake -S boringssl -B boringssl-b "${COMMON[@]}" -DBUILD_TESTING=OFF -DGO_EXECUTABLE=
cmake --build boringssl-b && cmake --install boringssl-b

cmake -S re2 -B re2-b "${COMMON[@]}" -DRE2_BUILD_TESTING=OFF
cmake --build re2-b && cmake --install re2-b

mkdir -p "$PREFIX/include" && cp -r cppitertools/cppitertools "$PREFIX/include/"

# or-tools: only the header-only graph library (proc_elaboration.h) is needed.
mkdir -p "$PREFIX/include/ortools/base" "$PREFIX/include/ortools/graph"
cp ortools/ortools/base/*.h "$PREFIX/include/ortools/base/"
cp ortools/ortools/graph/*.h "$PREFIX/include/ortools/graph/"

# googleapis: module_signature.proto imports google/api/field_behavior.proto (pinned to the commit XLS uses).
mkdir -p "$PREFIX/include/google/api"
curl -fsSL --retry 5 -o "$PREFIX/include/google/api/field_behavior.proto" \
  https://raw.githubusercontent.com/googleapis/googleapis/fe8ba054a/google/api/field_behavior.proto
echo "6df6a3770a3d45d6ddd5d8f1789b0e893d2d1659ebcf8dd56326d514038d69cf  $PREFIX/include/google/api/field_behavior.proto" | sha256sum -c -
