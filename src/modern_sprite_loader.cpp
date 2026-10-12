/* Bespoke sprite bridge, added 2026-10-12. SPDX-License-Identifier: GPL-2.0-only */
#include "stdafx.h"
#include "modern_sprite_loader.h"
#include "fileio_func.h"
#include "debug.h"
#include "settings_type.h"
#include <fstream>
#ifdef WITH_PNG
#include <png.h>
#endif
#include "safeguards.h"

static std::set<SpriteID> _modern_loaded_sprites;

uint ModernLoadedSpriteCount(bool vehicles_only)
{
	if (!vehicles_only) return _modern_loaded_sprites.size();
	return std::count_if(_modern_loaded_sprites.begin(), _modern_loaded_sprites.end(), [](SpriteID id) {
		return (id >= 0xAAD && id <= 0xAB0) || (id >= 0xB7D && id <= 0xB84);
	});
}

bool ModernLoadSprite(SpriteID id, SpriteLoader::SpriteCollection &sprites, ZoomLevels &available)
{
#if defined(MODERN_EDITION) && defined(WITH_PNG)
	/* The bespoke family currently covers temperate art only. */
	if (_settings_game.game_creation.landscape != LandscapeType::Temperate) return false;
	struct Entry { int x, y; bool company; std::string filename; };
	static const auto entries = [] {
		std::map<SpriteID, Entry> result;
		std::ifstream input(FioFindFullPath(Subdirectory::Baseset, "modern-sprites/manifest.tsv"));
		SpriteID sprite;
		Entry entry;
		while (input >> sprite >> entry.x >> entry.y >> entry.company >> entry.filename) {
			if (entry.filename.find_first_of("/\\") != std::string::npos || std::abs(entry.x) > 4096 || std::abs(entry.y) > 4096) continue;
			result.emplace(sprite, entry);
		}
		return result;
	}();
	auto found = entries.find(id);
	if (found == entries.end()) return false;
	const auto &entry = found->second;
	auto path = FioFindFullPath(Subdirectory::Baseset, "modern-sprites/" + entry.filename);
	if (path.empty()) return false;
	png_image image{};
	image.version = PNG_IMAGE_VERSION;
	if (!png_image_begin_read_from_file(&image, path.c_str())) return false;
	image.format = PNG_FORMAT_RGBA;
	if (image.width == 0 || image.height == 0 || image.width > 1024 || image.height > 1024) { png_image_free(&image); return false; }
	std::vector<uint8_t> rgba(PNG_IMAGE_SIZE(image));
	if (!png_image_finish_read(&image, nullptr, rgba.data(), 0, nullptr)) { png_image_free(&image); return false; }
	auto &root = sprites.Root();
	root.width = image.width; root.height = image.height;
	root.x_offs = entry.x; root.y_offs = entry.y;
	root.colours = {SpriteComponent::RGB, SpriteComponent::Alpha, SpriteComponent::Palette};
	root.AllocateData(ZoomLevel::Min, image.width * image.height);
	for (size_t i = 0; i < rgba.size() / 4; ++i) {
		auto &pixel = root.data[i];
		pixel.r = rgba[i * 4]; pixel.g = rgba[i * 4 + 1]; pixel.b = rgba[i * 4 + 2]; pixel.a = rgba[i * 4 + 3];
		/* Saturated blue is the export material for company paint. Its lighting
		 * becomes brightness while the palette mask supplies the actual livery. */
		if (entry.company && pixel.a != 0 && pixel.b > 60 && pixel.b > pixel.r * 2 && pixel.b > pixel.g * 1.5) {
			uint8_t brightness = pixel.b;
			pixel.m = 198 + std::min(7, brightness / 32);
			pixel.r = pixel.g = pixel.b = brightness;
		}
	}
	png_image_free(&image);
	available = {ZoomLevel::Min};
	_modern_loaded_sprites.insert(id);
	Debug(Facility::Sprite, Severity::Debug1, "Modern sprite {}: {}", id, entry.filename);
	return true;
#else
	return false;
#endif
}
