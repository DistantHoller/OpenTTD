#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_root"
python_runtime="${PYTHON_RUNTIME:-python3}"
"$python_runtime" modern/tools/fetch_dependencies.py
cmake -S modern/vendor/sources/libpng-1.6.58 -B build/libpng -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_INSTALL_PREFIX="$project_root/build/deps" \
  -DPNG_SHARED=ON -DPNG_STATIC=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_FRAMEWORK=OFF
cmake --build build/libpng -j "${BUILD_JOBS:-8}"
cmake --install build/libpng
(
  cd modern/vendor/sources/lzo-2.10
  CFLAGS='-O2 -mmacosx-version-min=14.0' LDFLAGS='-mmacosx-version-min=14.0' \
    ./configure --prefix="$project_root/build/deps" --enable-shared --disable-static
  /usr/bin/make -j "${BUILD_JOBS:-8}" MAKE=/usr/bin/make
  /usr/bin/make install MAKE=/usr/bin/make
)
