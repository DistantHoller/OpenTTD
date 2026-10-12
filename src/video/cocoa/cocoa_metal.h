/* Metal presentation backend, added 2026-10-12. SPDX-License-Identifier: GPL-2.0-only */
#ifndef VIDEO_COCOA_METAL_H
#define VIDEO_COCOA_METAL_H
#include "cocoa_v.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

/** Presents the existing 32-bit renderer through Metal, preserving sprite semantics. */
class VideoDriver_CocoaMetal : public VideoDriver_Cocoa {
	id<MTLDevice> device = nil;
	id<MTLCommandQueue> queue = nil;
	id<MTLRenderPipelineState> pipeline = nil;
	id<MTLTexture> texture = nil;
	id<MTLTexture> offscreen = nil;
	id<MTLCommandBuffer> pending = nil;
	CAMetalLayer *metal_layer = nil;
	std::vector<Colour> pixels;
	std::string driver_info;
	int width = 0, height = 0;
	Palette palette{};
	std::string capture_path;
	uint capture_frame = 120, frame_count = 0;
	bool showcase = false, showcase_attempted = false;
	bool world_gallery = false;
	bool city_gallery = false;
	bool hidden_capture = false;
	bool quit_check = false, resize_check = false;
	uint layout_failures = 0;
	std::chrono::steady_clock::time_point capture_start{};

public:
	VideoDriver_CocoaMetal() : VideoDriver_Cocoa(true, false) {}
	std::optional<std::string_view> Start(const StringList &param) override;
	void Stop() override;
	std::string_view GetName() const override { return "cocoa-metal"; }
	std::string_view GetInfoString() const override { return this->driver_info; }
	void AllocateBackingStore(bool force = false) override;
	void ToggleVsync(bool vsync) override;

protected:
	void Paint() override;
	void CheckPaletteAnim() override;
	void *GetVideoPointer() override { return this->pixels.data(); }
	NSView *AllocateDrawView() override;
	bool WantsVisibleWindow() const override { return !this->hidden_capture; }
};

class FVideoDriver_CocoaMetal : public DriverFactoryBase {
public:
	FVideoDriver_CocoaMetal() : DriverFactoryBase(Driver::Type::Video, 10, "cocoa-metal", "Cocoa Metal Video Driver") {}
	std::unique_ptr<Driver> CreateInstance() const override { return std::make_unique<VideoDriver_CocoaMetal>(); }
protected:
	bool UsesHardwareAcceleration() const override { return true; }
};
#endif
