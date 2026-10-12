#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_root"
python_runtime="${PYTHON_RUNTIME:-python3}"
"$python_runtime" modern/tools/fetch_assets.py
"$python_runtime" modern/tools/build_soundset.py
"$python_runtime" modern/tools/assemble_manifest.py
"$python_runtime" modern/tools/validate_assets.py
if [ ! -f build/deps/lib/libpng16.dylib ] || [ ! -f build/deps/lib/liblzo2.dylib ]; then
  bash modern/tools/build_dependencies.sh
fi
cmake -S . -B build/mac -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DPNG_PNG_INCLUDE_DIR="$project_root/build/deps/include" \
  -DPNG_LIBRARY_RELEASE="$project_root/build/deps/lib/libpng16.dylib" \
  -DLZO_INCLUDE_DIR="$project_root/build/deps/include" \
  -DLZO_LIBRARY="$project_root/build/deps/lib/liblzo2.dylib" \
  -DOPTION_MODERN_EDITION=ON \
  -DPERSONAL_DIR='Library/Application Support/OpenTTD Modern' \
  -DCMAKE_DISABLE_FIND_PACKAGE_Grfcodec=ON
cmake --build build/mac -j "${BUILD_JOBS:-8}"
app_path="$project_root/build/modern/OpenTTD Modern.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
"$python_runtime" modern/tools/write_plist.py "$app_path/Contents/Info.plist"
cmake --install build/mac --prefix "$app_path/Contents/Resources"
cp -R modern/assets/baseset/OpenGFX2_HighDef-* "$app_path/Contents/Resources/baseset/"
cp -R modern/assets/baseset/opensfx-1.0.3 "$app_path/Contents/Resources/baseset/"
cp -R modern/assets/baseset/modern-temperate "$app_path/Contents/Resources/baseset/"
cp modern/assets/art/welcome.png "$app_path/Contents/Resources/baseset/modern-welcome.png"
if [ -f modern/assets/sprites/manifest.tsv ]; then
  mkdir -p "$app_path/Contents/Resources/baseset/modern-sprites"
  cp modern/assets/sprites/*.png modern/assets/sprites/manifest.tsv "$app_path/Contents/Resources/baseset/modern-sprites/"
fi
cp modern/defaults.cfg "$app_path/Contents/Resources/modern-defaults.cfg"
cp modern/assets/art/app-icon.icns "$app_path/Contents/Resources/openttd.icns"
cp modern/README.md "$app_path/Contents/Resources/MODERN-README.md"
cp modern/QA.md "$app_path/Contents/Resources/MODERN-QA.md"
mkdir -p "$app_path/Contents/Resources/licenses"
cp modern/vendor/sources/libpng-1.6.58/LICENSE "$app_path/Contents/Resources/licenses/libpng.txt"
cp modern/vendor/sources/lzo-2.10/COPYING "$app_path/Contents/Resources/licenses/lzo.txt"
signing_identity="${SIGNING_IDENTITY:--}"
while IFS= read -r library; do codesign --force --sign "$signing_identity" "$library"; done < <(find "$app_path/Contents/Frameworks" -name '*.dylib' -type f)
codesign --force --sign "$signing_identity" "$app_path/Contents/MacOS/openttd"
codesign --force --sign "$signing_identity" "$app_path"
codesign --verify --deep --strict "$app_path"
printf '\nApp ready: %s\n' "$app_path"
