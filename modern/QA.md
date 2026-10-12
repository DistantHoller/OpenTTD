# Local development verification — 2026-10-12

Build: Apple Silicon, macOS 14 deployment target, current validated upstream `daa6e1ca1c357eb9e6ae3d69af134205e1be8517`, local ad-hoc signature. Actual runtime tested on Apple M4; older macOS and Intel hardware remain untested.

- 101 CTest checks passed, including the upstream regression suites and three mixer checks for voice capacity, clipping order, and channel reuse.
- Sprite manifest validation passed: 636 nonempty RGBA exports, dimensions divisible by four, correct ID coverage, valid anchors, and twenty-two vehicle/station paint masks.
- Deep/strict bundle signature verification passed. Runtime dependencies resolve to bundled libraries or system frameworks; no Homebrew library path is required.
- Metal shader compilation and rendering succeeded at 2560×1600. GPU readback had zero RGB pixel mismatches. Centers of all thirty toolbar controls mapped to their expected command widgets.
- Fresh offline railway fixture: two stations, track, depot, express locomotive, three coaches, two orders, train started, station arrival observed, save succeeded.
- Reloaded that save with the Cocoa 48 kHz audio driver: train ID 8, two orders retained, moving at speed 148, positive displayed operating profit 41. Later captures also showed continued motion and positive profit.
- World-art gallery: both station axes and all four default station tile styles constructed, all eighteen non-flat slopes matched the expected engine slopes, fixture saved successfully. Rendered at 2560×1600 with zero GPU/framebuffer pixel mismatches and zero native view-layout failures. Flat terrain was checked in the same scene.
- The playable railway save reloads with the new grass, soil, crops, rails and station art. Original PNG families contain all grass densities/crop stages/slopes, including steep slopes. Native loaded-sprite counts confirm the overrides are used.
- City fixture: 31 enabled parent house types placed, all fifteen nonempty road patterns match engine state, bus depot/stops/orders constructed. Passenger vehicle ID 5 visited station 2 and travelled to world position 793,973 at speed 180; the fixture saved successfully. Native geometry, GPU pixel comparison and toolbar hit targets passed. The city fixture temporarily enables completed house placement and restores the game setting.
- Final city reload: train and bus retain two orders each; bus visits the second stop (station 3) and continues at speed 174, position 529,1113. Train displayed profit is 242. GPU readback has zero pixel mismatches, resize has zero layout failures, all toolbar hits match, Quit confirmation is visible and its Yes action exits. The checks run in `hidden_capture` at 2560×1600 without opening a demo window.

## Bugs found and corrected

1. The Metal vertex entry point initially used `quad`, a reserved Metal type name. Renamed both shader entries to explicit presentation names and verified runtime compilation.
2. Direct fixture construction bypassed the usual command wrapper's signal-buffer cleanup. Flush after every checked fixture command; the same railway then ran and saved without the assertion in `signal.cpp`.
3. The sprite override compared the engine's extension-free filename with a name ending in `.grf`. Match the normalized names of the pinned base/extra files and verify actual loads in render reports.
4. Installed Homebrew libraries targeted newer macOS releases. Build pinned dependencies for macOS 14 and bundle them; pass their locations to BundleUtilities after removal of build rpaths.
5. The Metal child view used the input wrapper's desktop frame instead of its local bounds, shifting the rendered game away from click targets. Use local bounds for the child and framebuffer sizing. Native regression resized 900×600 then 1280×800: zero view-layout failures, Quit button visible and correctly hit-tested, and its confirmation action exited successfully.
6. A rejected development command sometimes has no error string; the fixture logger now handles `INVALID_STRING_ID` instead of passing it into the language decoder. The bus fixture selects a currently buildable passenger engine, uses road-compatible stop flags, and explicitly connects its depot to the street grid.
7. Captures could stall in idle or hidden scenes. Opt-in capture forces frame presentation, and `hidden_capture` uses a private render target with native window geometry while leaving the window unshown. Ordinary rendering still uses CAMetalLayer and dirty-frame presentation.

## Practical limits

The graphics refresh is a playable development edition. The full bespoke temperate world and construction/fleet workflow redesigns remain unfinished. Industries, water, rock outcrops, bridges, complex tracks, depots, ancillary building animations and most vehicles still use OpenGFX2 High Def. Town buildings/courtyards, paved/rural roads and lamps, grass/soil/rough ground, fields, straight rails, stations, trees and the express train/carriages have original replacements. Further material/lighting and multi-tile-building polish is still needed. Metal currently presents the CPU-rendered framebuffer; it does not add dynamic world lighting.

Computer-use access to OpenTTD was not approved. Render checks use the app's own opt-in GPU export and game-command fixture. Toolbar geometry was checked, but comprehensive mouse/keyboard, resize/fullscreen, accessibility, dense-map performance, NewGRF, multiplayer, and old-save testing remain to be done. The sound driver started successfully; listening quality still requires human audition.

The bundle is locally signed, not Developer ID signed or notarized. No public release has been made.
