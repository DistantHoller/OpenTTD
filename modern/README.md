# OpenTTD Modern — macOS development edition

Direction: a detailed miniature temperate world, warm lighting, a clear contemporary interface, and a restrained transport soundscape. Preserve the fixed isometric camera and OpenTTD simulation.

Current validated engine base: OpenTTD commit `daa6e1ca1c357eb9e6ae3d69af134205e1be8517` (2026-10-12). The initial foundation used `e52a422015e8ed89413ff841ecf878afcf833d38`.

## Build

Requirements: full Xcode tools, CMake, Ninja, Python 3.12+, and a C compiler. The build script downloads and builds pinned libpng/LZO sources for macOS 14; no Homebrew runtime libraries are needed by the finished bundle. On the development Mac, pass the bundled Python runtime through `PYTHON_RUNTIME`.

Run `bash modern/tools/build_macos.sh`. The app is written to `build/modern/OpenTTD Modern.app`. It includes the engine, pinned base sets, their attribution/license files, and an independent profile under `~/Library/Application Support/OpenTTD Modern`.

The build uses an ad-hoc local signature unless `SIGNING_IDENTITY` is supplied. Public release requires a Developer ID signature and notarization. Engine and bundled libraries target macOS 14 on Apple Silicon; actual runtime QA is on the development M4, with testing on macOS 14 hardware still required.

To build upstream presentation, set `OPTION_MODERN_EDITION=OFF` in a separate build directory. All original game commands remain available.

## Implemented foundation

- Metal presentation of the existing 32-bit framebuffer, including CPU palette animation, Retina sizing, resize/fullscreen hooks, and vsync.
- Warm paper panels and forest-green captions with company-color strips.
- Consistent line icons, labeled game toolbar, and a two-column welcome screen.
- OpenGFX2 High Def 0.8.1 for complete base-set coverage (some HD variants remain upstream placeholders).
- Modern Temperate sound bank: seven original 48 kHz interface/construction replacements, with 66 attributed OpenSFX recordings retained.
- 32 concurrent effects and 32-bit accumulation before final output clipping.
- Camera-sensitive wind/water ambience and a restrained bed for moving visible trains, respecting sound toggles and pause.
- 145 original 3D sprite exports: an express locomotive in eight directions, passenger carriages in four symmetric directions, and nineteen tree variants with all seven growth/decay stages. Transparent space is trimmed while retaining exact ground anchors and company-paint masks.
- 292 additional world sprites: all nineteen slopes for bare land and three grass densities, rough ground variants, all nine crop stages on every slope, both straight rail orientations with opaque/overlay variants, and eighteen station platform/building/canopy components.
- Original brick station buildings, slate roofs, stone platforms, tactile platform edges, benches, lanterns, glazing, and company-color signs. Terrain materials use the engine's exact 2:1 projection and height units.
- 38 urban/rural road sprites: every flat connection pattern, the four supported incline orientations, stone curbs, lane markings and junction crossings. Two original street-lamp sprites.
- 100 town-building sprites plus 59 courtyard sprites, derived from the engine tables to cover 41 temperate house tiles including multi-tile parts. Homes, shops, offices, warehouses, churches, cinemas, parks, fountains, statues and stadiums include the original construction-stage coverage and height/footprint envelopes. Some ancillary animations still use upstream art.

The bespoke world assets currently apply to temperate maps using the pinned OpenGFX2 base/extra files. Other climates and separately supplied NewGRF art retain their source sprites.

The Metal backend currently presents CPU-rendered sprites. It is not yet a GPU sprite engine with dynamic world lighting. The welcome illustration is artwork, not a representation of completed gameplay graphics.

## Graphics and source attribution

- OpenTTD: https://github.com/OpenTTD/OpenTTD — GPLv2.
- OpenGFX2: https://github.com/OpenTTD/OpenGFX2 — GPLv2 or later; full credits in the bundled readme/license. Pinned archive SHA-256: `c1f5066e82b7754d29f7637457f5b77ac71f10198e3a38f7a75353ea62386e2d`.
- OpenSFX: https://github.com/OpenTTD/OpenSFX — recording licenses and individual attribution are preserved in each bank entry and the bundled readme/license. Pinned archive SHA-256: `e0a218b7dd9438e701503b0f84c25a97c1c11b7c2f025323fb19d6db16ef3759`.
- Welcome illustration: built-in ImageGen, 2026-10-12, saved as `modern/assets/art/welcome.png`. Prompt: a detailed miniature temperate transport world with a brick station, red/cream train, European town, river bridge, countryside and warm afternoon light; no text or UI.
- App icon: built-in ImageGen, 2026-10-12, `modern/assets/art/app-icon.png`. Prompt: cream/forest-green miniature passenger locomotive, curved rail, broadleaf tree and brick station on an ivory rounded tile, orthographic view, warm afternoon light, transparent surround, no text. The `.icns` uses native macOS downsampling of this source.
- Original sound replacement source: `modern/tools/build_soundset.py` — GPLv2.
- Original 3D model/lighting/export source: `modern/tools/render_sprites.swift` — GPLv2. Uses the Mac's offscreen 3D renderer as the initial asset pipeline. Compile with `swiftc -O -module-cache-path /tmp/openttd-swift-cache modern/tools/render_sprites.swift -o build/render_sprites`, then run `build/render_sprites modern/assets/sprites`. Validate with `python3 modern/tools/validate_assets.py`.
- Original terrain/crop/track/road materials and station/town model source: `modern/tools/render_world.swift` — GPLv2. Terrain is rasterized in exact engine coordinates; buildings use the same orthographic projection. `modern/tools/extract_town_assets.py` derives coverage from the current engine tables. Run `bash modern/tools/render_art.sh` to reproduce the families, combine their source manifests, and validate all 636 sprites. Generated PNGs are included so ordinary app builds do not require rerendering artwork.
- libpng 1.6.58 and LZO 2.10: pinned source URLs/checksums in `modern/tools/fetch_dependencies.py`; licenses bundled in `Contents/Resources/licenses`.

## Remaining release work

1. Complete water, cliffs/foundations, bridges, complex tracks, industries, depots and the remaining vehicle art, then finish lighting/material/animation polish across the integrated temperate families.
2. Finish construction, inspection, purchase, orders, and fleet workflow redesigns, including accessibility.
3. Benchmark dense maps and prototype GPU sprite drawing/effects using the proven Metal presentation.
4. Validate old saves, long simulations, NewGRF combinations, and multiplayer against the pinned upstream revision.
5. Sign/notarize, and test the portable bundle on the intended minimum macOS and reference Macs.
6. Extend finished art to arctic, tropical, and toyland climates.

## Render regression mode

The Metal driver accepts `capture=<absolute output stem>` and `capture_frame=<n>`. It exports its own rendered GPU frame to PNG, compares GPU output to the engine framebuffer, reports frame rate and toolbar hit targets, writes a `.metal-check.txt` report, and exits a few frames later. This is an opt-in development check, not a desktop screenshot. An example is `-v 'cocoa-metal:capture=/tmp/modern-welcome,capture_frame=120' -x`.

Add `hidden_capture` to keep the native window unshown and render the identical presentation shader into a private Metal texture. Capture mode presents every frame even in still scenes, so a requested frame count completes predictably. Its reported rate measures presentation throughput during capture, not a dense-map simulation benchmark. Normal play presents only dirty frames.

With capture enabled, `resize_check` exercises two native window sizes and records whether the drawing view fills the input wrapper. In a running game, `quit_check` opens the normal quit confirmation, verifies visibility and hit testing, then invokes its Yes action and records `.quit-check.txt`. These checks cover native view placement as well as framebuffer pixels.

The additional `showcase` parameter builds a railway fixture only in a fresh offline world with no transport vehicles. Use `modern/tools/make_test_heightmap.py` to create level test terrain, and launch with `-g build/qa/flat-heightmap.png -t 1990 -G 20261012 -v 'cocoa-metal:showcase,capture=/tmp/modern-scene,capture_frame=600'`. It produces a scene save and a report of construction, orders, movement and profit. This opt-in fixture supplies test construction funds; normal games use the unchanged simulation rules.

With `showcase,world_gallery`, the fixture also constructs both station axes with all four default tile styles and all nineteen terrain slopes. Use a separate test config with `[difficulty] number_towns=4, industry_density=0` and `[game_creation] custom_town_number=1` to leave space for the fixtures. The generated report checks actual engine slopes; the gallery is only for art QA.

With `showcase,city_gallery`, the fixture constructs every enabled temperate parent house type, every nonempty road-bit pattern, a street grid, a depot and two bus stops. It selects an available passenger engine from the live roster, starts a two-stop route, records movement/station visits, and saves. Use the same sparse test config on a fresh map at least 128×128. House-placement rules are temporarily enabled within the fixture and restored before ordinary play.
