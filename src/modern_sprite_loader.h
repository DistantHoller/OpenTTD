/* Bespoke sprite bridge, added 2026-10-12. SPDX-License-Identifier: GPL-2.0-only */
#ifndef MODERN_SPRITE_LOADER_H
#define MODERN_SPRITE_LOADER_H
#include "spriteloader/spriteloader.hpp"
bool ModernLoadSprite(SpriteID id, SpriteLoader::SpriteCollection &sprites, ZoomLevels &available);
uint ModernLoadedSpriteCount(bool vehicles_only = false);
#endif
