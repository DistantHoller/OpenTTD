#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_root"
python_runtime="${PYTHON_RUNTIME:-python3}"
mkdir -p build/art-tools build/swift-cache
"$python_runtime" modern/tools/extract_town_assets.py
swiftc -O -module-cache-path build/swift-cache modern/tools/render_sprites.swift -o build/art-tools/render_sprites
swiftc -O -module-cache-path build/swift-cache modern/tools/render_world.swift -o build/art-tools/render_world
build/art-tools/render_sprites modern/assets/sprites
build/art-tools/render_world modern/assets/sprites
"$python_runtime" modern/tools/assemble_manifest.py
"$python_runtime" modern/tools/validate_assets.py
