/* Modern macOS presentation, added 2026-10-12. SPDX-License-Identifier: GPL-2.0-only */
#include "stdafx.h"
#include "modern_theme.h"
#include "gfx_func.h"
#include "fileio_func.h"
#include "blitter/factory.hpp"
#include "zoom_func.h"
#include "table/sprites.h"
#ifdef WITH_PNG
#include <png.h>
#endif
#include "safeguards.h"

bool ModernInterfaceEnabled()
{
#ifdef MODERN_EDITION
	return BlitterFactory::GetCurrentBlitter() != nullptr && BlitterFactory::GetCurrentBlitter()->GetScreenDepth() == 32;
#else
	return false;
#endif
}

/** Fill using RGB without leaving stale palette-animation indices behind. */
void ModernFillRect(const Rect &r, Colour colour)
{
	const DrawPixelInfo *dpi = _cur_dpi;
	if (!ModernInterfaceEnabled() || dpi->zoom != ZoomLevel::Min) return;
	int left = std::max(r.left, dpi->left);
	int top = std::max(r.top, dpi->top);
	int right = std::min(r.right, dpi->left + dpi->width - 1);
	int bottom = std::min(r.bottom, dpi->top + dpi->height - 1);
	if (left > right || top > bottom) return;

	/* DrawRect clears animation metadata for both 32bpp-anim and 40bpp-anim. */
	GfxFillRect(left, top, right, bottom, PixelColour{0});
	Blitter *blitter = BlitterFactory::GetCurrentBlitter();
	for (int y = top; y <= bottom; ++y) {
		auto *row = static_cast<Colour *>(blitter->MoveTo(dpi->dst_ptr, left - dpi->left, y - dpi->top));
		std::fill_n(row, right - left + 1, colour);
	}
}

void ModernRoundedRect(const Rect &r, Colour colour, int radius)
{
	if (r.Width() <= 0 || r.Height() <= 0) return;
	radius = std::min({radius, r.Width() / 2, r.Height() / 2});
	ModernFillRect({r.left, r.top + radius, r.right, r.bottom - radius}, colour);
	for (int y = 0; y < radius; ++y) {
		const double dy = radius - y - 0.5;
		const int inset = static_cast<int>(std::ceil(radius - std::sqrt(radius * radius - dy * dy)));
		ModernFillRect({r.left + inset, r.top + y, r.right - inset, r.top + y}, colour);
		ModernFillRect({r.left + inset, r.bottom - y, r.right - inset, r.bottom - y}, colour);
	}
}

void ModernDrawFrame(const Rect &r, bool lowered, bool darkened, bool border_only)
{
	int border = std::max(1, ScaleGUITrad(1));
	ModernFillRect({r.left, r.top, r.right, r.top + border - 1}, ModernColours::Border);
	ModernFillRect({r.left, r.bottom - border + 1, r.right, r.bottom}, ModernColours::Border);
	ModernFillRect({r.left, r.top, r.left + border - 1, r.bottom}, ModernColours::Border);
	ModernFillRect({r.right - border + 1, r.top, r.right, r.bottom}, ModernColours::Border);
	if (!border_only) ModernFillRect(r.Shrink(border), darkened ? ModernColours::Inset : lowered ? ModernColours::Selected : ModernColours::Paper);
}

/** A single consistent vector icon family; unrecognised content keeps its supplied art. */
bool ModernDrawIcon(SpriteID sprite, const Rect &r, Alignment align)
{
	if (!ModernInterfaceEnabled()) return false;
	int size = std::min({ScaleGUITrad(20), r.Width() - ScaleGUITrad(6), r.Height() - ScaleGUITrad(6)});
	if (size < 8) return false;
	int ox = r.left + (r.Width() - size) / 2;
	int oy = align.v == AlignmentV::Top ? r.top + ScaleGUITrad(4) : r.top + (r.Height() - size) / 2;
	double scale = size / 24.0;
	int stroke = std::max(1, int(std::round(scale * 1.7)));
	auto line = [&](double x1, double y1, double x2, double y2) {
		int steps = std::max(1, int(std::ceil(std::max(std::abs(x2 - x1), std::abs(y2 - y1)) * scale)));
		for (int i = 0; i <= steps; ++i) {
			int x = ox + int(std::round((x1 + (x2 - x1) * i / steps) * scale));
			int y = oy + int(std::round((y1 + (y2 - y1) * i / steps) * scale));
			ModernFillRect({x - stroke / 2, y - stroke / 2, x + (stroke - 1) / 2, y + (stroke - 1) / 2}, ModernColours::Forest);
		}
	};
	auto box = [&](double x1, double y1, double x2, double y2) { line(x1,y1,x2,y1); line(x2,y1,x2,y2); line(x2,y2,x1,y2); line(x1,y2,x1,y1); };
	auto circle = [&](double x, double y, double radius) {
		for (int i = 0; i < 24; ++i) {
			double a = i * 2 * M_PI / 24, b = (i + 1) * 2 * M_PI / 24;
			line(x + std::cos(a) * radius, y + std::sin(a) * radius, x + std::cos(b) * radius, y + std::sin(b) * radius);
		}
	};
	switch (sprite) {
		case SPR_IMG_PAUSE: box(7,4,9,20); box(15,4,17,20); break;
		case SPR_IMG_FASTFORWARD:
			line(3,5,11,12); line(11,12,3,19); line(3,19,3,5); line(13,5,21,12); line(21,12,13,19); line(13,19,13,5); break;
		case SPR_IMG_SETTINGS:
			circle(12,12,6); circle(12,12,2);
			for (int i=0;i<8;++i) { double a=i*M_PI/4; line(12+std::cos(a)*6,12+std::sin(a)*6,12+std::cos(a)*9,12+std::sin(a)*9); } break;
		case SPR_IMG_SAVE: case SPR_IMG_SAVE + 1:
			box(4,3,20,21); box(8,3,16,9); box(8,14,16,21); break;
		case SPR_IMG_SMALLMAP: case SPR_IMG_SHOW_COUNTOURS:
			line(3,6,9,3); line(9,3,15,6); line(15,6,21,3); line(21,3,21,18); line(21,18,15,21); line(15,21,9,18); line(9,18,3,21); line(3,21,3,6); line(9,3,9,18); line(15,6,15,21); break;
		case SPR_IMG_TOWN: case SPR_IMG_COMPANY_GENERAL:
			box(3,10,10,21); box(13,4,21,21); line(3,10,6,6); line(6,6,10,10); line(16,8,18,8); line(16,12,18,12); line(16,16,18,16); break;
		case SPR_IMG_SUBSIDIES: case SPR_IMG_COMPANY_LEAGUE:
			box(7,3,17,14); line(7,6,3,6); line(3,6,3,10); line(3,10,7,13); line(17,6,21,6); line(21,6,21,10); line(21,10,17,13); line(12,14,12,20); line(7,21,17,21); break;
		case SPR_IMG_COMPANY_LIST: case SPR_IMG_SHOW_VEHICLES:
			for(int y=5;y<=19;y+=7) { box(3,y-1,6,y+2); line(10,y,21,y); } break;
		case SPR_IMG_COMPANY_FINANCE:
			line(3,8,12,3); line(12,3,21,8); line(3,8,21,8); line(3,21,21,21); for(int x=6;x<=18;x+=6)line(x,11,x,18); break;
		case SPR_IMG_GRAPHS:
			line(3,3,3,21); line(3,21,21,21); line(6,17,11,11); line(11,11,15,14); line(15,14,21,5); break;
		case SPR_IMG_INDUSTRY:
			line(3,21,3,11); line(3,11,10,7); line(10,7,10,11); line(10,11,17,7); line(17,7,17,21); line(3,21,21,21); box(18,3,21,21); line(6,16,8,16); line(12,16,14,16); break;
		case SPR_IMG_TRAINLIST:
			box(6,3,18,18); box(8,6,16,11); circle(9,15,1); circle(15,15,1); line(8,18,5,22); line(16,18,19,22); break;
		case SPR_IMG_TRUCKLIST:
			box(2,5,14,16); line(14,9,19,9); line(19,9,22,13); line(22,13,22,17); line(14,17,22,17); circle(7,18,2); circle(18,18,2); break;
		case SPR_IMG_SHIPLIST: case SPR_IMG_BUILDWATER:
			line(3,14,21,14); line(21,14,17,20); line(17,20,7,20); line(7,20,3,14); box(8,8,16,14); line(12,3,12,8); line(2,23,22,23); break;
		case SPR_IMG_AIRPLANESLIST: case SPR_IMG_BUILDAIR:
			line(12,2,12,22); line(12,8,3,14); line(3,14,12,12); line(12,8,21,14); line(21,14,12,12); line(12,18,7,22); line(12,18,17,22); break;
		case SPR_IMG_BUILDRAIL: case SPR_IMG_BUILDTRAMS:
			line(7,2,4,22); line(17,2,20,22); for(int y=5;y<=21;y+=4)line(7-(y-2)*0.15,y,17+(y-2)*0.15,y); break;
		case SPR_IMG_BUILDROAD:
			line(7,2,3,22); line(17,2,21,22); for(int y=3;y<22;y+=6)line(12,y,12,y+2); break;
		case SPR_IMG_LANDSCAPING: case SPR_IMG_PLANTTREES:
			line(12,2,4,12); line(4,12,8,12); line(8,12,2,19); line(2,19,22,19); line(22,19,16,12); line(16,12,20,12); line(20,12,12,2); line(12,19,12,23); break;
		case SPR_IMG_ZOOMIN: case SPR_IMG_ZOOMOUT:
			circle(10,10,7); line(15,15,22,22); line(6,10,14,10); if(sprite==SPR_IMG_ZOOMIN)line(10,6,10,14); break;
		case SPR_IMG_MUSIC:
			line(9,5,9,18); line(9,5,20,3); line(20,3,20,16); circle(6,18,3); circle(17,16,3); break;
		case SPR_IMG_MESSAGES:
			box(3,4,21,18); line(7,18,7,22); line(7,22,12,18); line(7,9,17,9); line(7,13,15,13); break;
		case SPR_IMG_QUERY:
			circle(12,12,10); line(8,7,12,5); line(12,5,16,8); line(16,8,12,12); line(12,12,12,15); circle(12,19,0.6); break;
		case SPR_IMG_STORY_BOOK:
			box(3,4,21,20); line(12,4,12,20); line(6,8,9,8); line(15,8,18,8); break;
		case SPR_IMG_SWITCH_TOOLBAR:
			line(3,8,21,8); line(21,8,17,4); line(21,8,17,12); line(21,17,3,17); line(3,17,7,13); line(3,17,7,21); break;
		default: return false;
	}
	return true;
}

void ModernDrawWelcome(const Rect &r)
{
	ModernFillRect(r, ModernColours::Forest);
#ifdef WITH_PNG
	struct WelcomeImage {
		uint width = 0, height = 0;
		std::vector<Colour> pixels;
		WelcomeImage()
		{
			auto path = FioFindFullPath(Subdirectory::Baseset, "modern-welcome.png");
			if (path.empty()) return;
			png_image image{};
			image.version = PNG_IMAGE_VERSION;
			if (!png_image_begin_read_from_file(&image, path.c_str())) return;
			image.format = PNG_FORMAT_RGBA;
			if (image.width > 4096 || image.height > 4096) { png_image_free(&image); return; }
			std::vector<uint8_t> rgba(PNG_IMAGE_SIZE(image));
			if (png_image_finish_read(&image, nullptr, rgba.data(), 0, nullptr)) {
				width = image.width; height = image.height;
				pixels.reserve(width * height);
				for (size_t i = 0; i < rgba.size(); i += 4) pixels.emplace_back(rgba[i], rgba[i + 1], rgba[i + 2]);
			}
			png_image_free(&image);
		}
	};
	static const WelcomeImage image;
	if (image.pixels.empty() || !ModernInterfaceEnabled()) return;
	const DrawPixelInfo *dpi = _cur_dpi;
	if (dpi->zoom != ZoomLevel::Min) return;
	/* Aspect-fill, centred on the station and river rather than stretching the art. */
	double scale = std::max(double(r.Width()) / image.width, double(r.Height()) / image.height);
	double ox = (image.width - r.Width() / scale) / 2;
	double oy = (image.height - r.Height() / scale) * 0.65;
	Blitter *blitter = BlitterFactory::GetCurrentBlitter();
	for (int y = std::max(r.top, dpi->top); y <= std::min(r.bottom, dpi->top + dpi->height - 1); ++y) {
		int sy = std::clamp(int(oy + (y - r.top) / scale), 0, int(image.height) - 1);
		for (int x = std::max(r.left, dpi->left); x <= std::min(r.right, dpi->left + dpi->width - 1); ++x) {
			int sx = std::clamp(int(ox + (x - r.left) / scale), 0, int(image.width) - 1);
			*static_cast<Colour *>(blitter->MoveTo(dpi->dst_ptr, x - dpi->left, y - dpi->top)) = image.pixels[sy * image.width + sx];
		}
	}
#endif
}
