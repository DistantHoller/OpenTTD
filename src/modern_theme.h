/* Modern macOS presentation, added 2026-10-12. SPDX-License-Identifier: GPL-2.0-only */
#ifndef MODERN_THEME_H
#define MODERN_THEME_H

#include "gfx_type.h"

bool ModernInterfaceEnabled();
void ModernFillRect(const Rect &r, Colour colour);
void ModernRoundedRect(const Rect &r, Colour colour, int radius);
void ModernDrawFrame(const Rect &r, bool lowered, bool darkened, bool border_only);
void ModernDrawWelcome(const Rect &r);
bool ModernDrawIcon(SpriteID sprite, const Rect &r, Alignment align);

namespace ModernColours {
inline constexpr Colour Paper{244, 241, 233};
inline constexpr Colour Surface{253, 251, 246};
inline constexpr Colour Border{205, 205, 190};
inline constexpr Colour Selected{205, 223, 205};
inline constexpr Colour Inset{231, 230, 220};
inline constexpr Colour Forest{39, 65, 53};
}

#endif
