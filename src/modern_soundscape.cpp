/* Temperate soundscape, added 2026-10-12. SPDX-License-Identifier: GPL-2.0-only */
#include "stdafx.h"
#include <atomic>
#include "modern_soundscape.h"
#include "openttd.h"
#include "window_func.h"
#include "window_gui.h"
#include "viewport_func.h"
#include "landscape.h"
#include "vehicle_base.h"
#include "settings_type.h"
#include "safeguards.h"

/* The audio callback never reads game objects or takes a game-thread lock. */
static std::atomic<float> _wind_target{0}, _water_target{0}, _train_target{0};

void ModernUpdateSoundscape()
{
#ifdef MODERN_EDITION
	float wind = 0, water = 0, train = 0;
	Window *window = GetMainWindow();
	if (_game_mode == GameMode::Normal && window != nullptr && window->viewport != nullptr && _pause_mode.None()) {
		const Viewport &vp = *window->viewport;
		if (_settings_client.sound.ambient) {
			uint trees = 0, waters = 0;
			for (int y = 1; y <= 3; ++y) for (int x = 1; x <= 3; ++x) {
				Point p = TranslateXYToTileCoord(vp, vp.left + vp.width * x / 4, vp.top + vp.height * y / 4);
				if (p.x < 0 || p.y < 0) continue;
				auto tile = TileVirtXYClampedToMap(p.x, p.y);
				trees += IsTileType(tile, TileType::Trees);
				waters += IsTileType(tile, TileType::Water);
			}
			wind = 0.15f + trees / 9.0f;
			water = waters / 9.0f;
		}
		if (_settings_client.sound.vehicle) {
			for (const Vehicle *v : Vehicle::Iterate()) {
				if (v->type != VehicleType::Train || v->cur_speed == 0 || !v->IsPrimaryVehicle()) continue;
				if (v->coord.right < vp.virtual_left || v->coord.left > vp.virtual_left + vp.virtual_width ||
					v->coord.bottom < vp.virtual_top || v->coord.top > vp.virtual_top + vp.virtual_height) continue;
				train += std::min(1.0f, v->cur_speed / 180.0f) * 0.3f;
				if (train >= 1.0f) break;
			}
		}
	}
	_wind_target.store(std::min(wind, 1.0f), std::memory_order_relaxed);
	_water_target.store(water, std::memory_order_relaxed);
	_train_target.store(std::min(train, 1.0f), std::memory_order_relaxed);
#endif
}

void ModernMixSoundscape(int32_t *buffer, uint frames, uint rate, float volume)
{
	static_assert(std::atomic<float>::is_always_lock_free);
	static uint32_t seed = 0x7f3a21c5;
	static double phase = 0;
	static float wind = 0, water = 0, train = 0, low_left = 0, low_right = 0, flow = 0;
	float tw = _wind_target.load(std::memory_order_relaxed);
	float ta = _water_target.load(std::memory_order_relaxed);
	float tt = _train_target.load(std::memory_order_relaxed);
	float smoothing = 1.0f - std::exp(-1.0f / (rate * 0.8f));
	float wind_filter = 1.0f - std::exp(-2.0f * M_PI * 180.0f / rate);
	float water_filter = 1.0f - std::exp(-2.0f * M_PI * 1400.0f / rate);
	auto noise = [&]() {
		seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
		return (seed / 2147483648.0f) - 1.0f;
	};
	for (uint i = 0; i < frames; ++i) {
		wind += (tw - wind) * smoothing;
		water += (ta - water) * smoothing;
		train += (tt - train) * smoothing;
		low_left += (noise() - low_left) * wind_filter;
		low_right += (noise() - low_right) * wind_filter;
		flow += (noise() - flow) * water_filter;
		phase += 1.0 / rate;
		if (phase >= 60.0) phase -= 60.0;
		float swell = 0.75f + 0.25f * std::sin(phase * 0.7);
		float bed = water * flow * 0.009f * swell;
		/* A restrained wheel/engine bed, with smoothing on camera and vehicle changes. */
		bed += train * (low_left * 0.028f + std::sin(phase * 2 * M_PI * 68) * 0.003f) * (0.8f + 0.2f * std::sin(phase * 2 * M_PI * 5.2));
		buffer[i * 2] += int((wind * low_left * 0.014f * swell + bed) * 32767 * volume);
		buffer[i * 2 + 1] += int((wind * low_right * 0.014f * swell + bed) * 32767 * volume);
	}
}
