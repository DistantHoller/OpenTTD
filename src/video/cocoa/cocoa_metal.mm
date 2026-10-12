/* Metal presentation backend, added 2026-10-12. SPDX-License-Identifier: GPL-2.0-only */
#include "../../stdafx.h"
#include "../../os/macosx/macos_objective_c.h"
#include "cocoa_metal.h"
#include "cocoa_wnd.h"
#include "../../blitter/factory.hpp"
#include "../../gfx_func.h"
#include "../../error_func.h"
#include "../../core/geometry_func.hpp"
#include "../../framerate_type.h"
#include "../../openttd.h"
#include "../../screenshot.h"
#include "../../modern_soundscape.h"
#include "../../modern_showcase.h"
#include "../../modern_sprite_loader.h"
#include "../../progress.h"
#include "../../window_func.h"
#include "../../window_gui.h"
#include "../../widgets/toolbar_widget.h"
#include "../../widgets/misc_widget.h"
#include <fstream>
#ifdef WITH_PNG
#include <png.h>
#endif
#include "../../safeguards.h"

/** Input remains in the parent Cocoa view; the Metal view only presents pixels. */
@interface OTTD_MetalView : NSView
@end
@implementation OTTD_MetalView
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)isOpaque { return YES; }
- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];
	self.layer.contentsScale = _allow_hidpi_window ? self.window.backingScaleFactor : 1.0;
}
@end

static FVideoDriver_CocoaMetal iFVideoDriver_CocoaMetal;

std::optional<std::string_view> VideoDriver_CocoaMetal::Start(const StringList &param)
{
	if (auto capture = GetDriverParam(param, "capture"); capture.has_value()) this->capture_path = *capture;
	this->capture_frame = std::max(1, GetDriverParamInt(param, "capture_frame", 120));
	this->showcase = GetDriverParamBool(param, "showcase");
	this->world_gallery = GetDriverParamBool(param, "world_gallery");
	this->city_gallery = GetDriverParamBool(param, "city_gallery");
	this->hidden_capture = !this->capture_path.empty() && GetDriverParamBool(param, "hidden_capture");
	this->quit_check = !this->capture_path.empty() && GetDriverParamBool(param, "quit_check");
	this->resize_check = !this->capture_path.empty() && GetDriverParamBool(param, "resize_check");
	this->device = MTLCreateSystemDefaultDevice();
	if (this->device == nil) return "No Metal device available";
	this->queue = [this->device newCommandQueue];
	if (this->queue == nil) { this->Stop(); return "Cannot create Metal command queue"; }

	/* Nearest sampling preserves exact sprite pixels and crisp GUI text. */
	NSString *source = @"#include <metal_stdlib>\n"
		"using namespace metal;\n"
		"struct V { float4 position [[position]]; float2 uv; };\n"
		"vertex V present_vertices(uint i [[vertex_id]]) {\n"
		" float2 p[3] = {float2(-1,1),float2(-1,-3),float2(3,1)};\n"
		" V v; v.position=float4(p[i],0,1); v.uv=float2((p[i].x+1)*0.5,(1-p[i].y)*0.5); return v; }\n"
		"fragment float4 present_fragment(V v [[stage_in]], texture2d<float> tex [[texture(0)]]) {\n"
		" constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::nearest);\n"
		" return float4(tex.sample(s,v.uv).rgb,1); }\n";
	NSError *error = nil;
	id<MTLLibrary> library = [this->device newLibraryWithSource:source options:nil error:&error];
	if (library == nil) {
		Debug(Facility::Driver, Severity::Critical, "Metal shader: {}", [error.localizedDescription UTF8String]);
		this->Stop(); return "Cannot compile Metal presentation shaders";
	}
	MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
	id<MTLFunction> vertex = [library newFunctionWithName:@"present_vertices"];
	id<MTLFunction> fragment = [library newFunctionWithName:@"present_fragment"];
	desc.vertexFunction = vertex;
	desc.fragmentFunction = fragment;
	desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
	this->pipeline = [this->device newRenderPipelineStateWithDescriptor:desc error:&error];
	[vertex release]; [fragment release]; [desc release]; [library release];
	if (this->pipeline == nil) {
		Debug(Facility::Driver, Severity::Critical, "Metal pipeline: {}", [error.localizedDescription UTF8String]);
		this->Stop(); return "Cannot create Metal render pipeline";
	}

	auto err = this->Initialize();
	if (err) { this->Stop(); return err; }
	if (BlitterFactory::GetCurrentBlitter()->GetScreenDepth() != 32) {
		this->Stop(); return "Metal requires a 32bpp blitter";
	}
	this->driver_info = "cocoa-metal (" + std::string([[this->device name] UTF8String]) + ")";
	bool fullscreen = _fullscreen && !this->hidden_capture;
	if (!this->MakeWindow(_cur_resolution.width, _cur_resolution.height)) {
		this->Stop(); return "Cannot create Metal window";
	}
	this->ToggleVsync(_video_vsync);
	this->AllocateBackingStore(true);
	if (fullscreen) this->ToggleFullscreen(fullscreen);
	this->UpdateVideoModes();
	/* Cocoa and CAMetalLayer work stay on the main thread in this initial backend. */
	this->is_game_threaded = false;
	return std::nullopt;
}

void VideoDriver_CocoaMetal::Stop()
{
	[this->pending waitUntilCompleted];
	[this->pending release]; this->pending = nil;
	VideoDriver_Cocoa::Stop();
	[this->texture release]; this->texture = nil;
	[this->offscreen release]; this->offscreen = nil;
	[this->pipeline release]; this->pipeline = nil;
	[this->queue release]; this->queue = nil;
	[this->device release]; this->device = nil;
	/* The view owned the layer; no retained pointer survives window destruction. */
	this->metal_layer = nil;
	this->pixels.clear();
}

NSView *VideoDriver_CocoaMetal::AllocateDrawView()
{
	/* A child's frame is in its parent's coordinates. The wrapper's frame
	 * still contains the window's screen origin until it becomes contentView. */
	OTTD_MetalView *view = [[OTTD_MetalView alloc] initWithFrame:[this->cocoaview bounds]];
	this->metal_layer = [CAMetalLayer layer];
	this->metal_layer.device = this->device;
	this->metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	this->metal_layer.framebufferOnly = this->capture_path.empty();
	this->metal_layer.opaque = YES;
	this->metal_layer.maximumDrawableCount = 2;
	view.layer = this->metal_layer;
	view.wantsLayer = YES;
	return view;
}

void VideoDriver_CocoaMetal::ToggleVsync(bool vsync)
{
	this->metal_layer.displaySyncEnabled = vsync;
}

void VideoDriver_CocoaMetal::AllocateBackingStore(bool force)
{
	if (this->setup || this->metal_layer == nil) return;
	NSRect frame = [this->cocoaview getRealRect:[this->cocoaview bounds]];
	int w = std::max(1, static_cast<int>(frame.size.width));
	int h = std::max(1, static_cast<int>(frame.size.height));
	if (!force && w == this->width && h == this->height) return;
	[this->pending waitUntilCompleted];
	[this->pending release]; this->pending = nil;
	this->width = w; this->height = h;
	this->pixels.assign(static_cast<size_t>(w) * h, Colour{0, 0, 0});
	[this->texture release];
	MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
	desc.storageMode = MTLStorageModeShared;
	desc.usage = MTLTextureUsageShaderRead;
	this->texture = [this->device newTextureWithDescriptor:desc];
	if (this->texture == nil) FatalError("Cannot allocate Metal frame texture");
	[this->offscreen release]; this->offscreen = nil;
	if (this->hidden_capture) {
		desc.storageMode = MTLStorageModePrivate;
		desc.usage = MTLTextureUsageRenderTarget;
		this->offscreen = [this->device newTextureWithDescriptor:desc];
		if (this->offscreen == nil) FatalError("Cannot allocate Metal capture target");
	}
	this->metal_layer.contentsScale = [this->cocoaview getContentsScale];
	this->metal_layer.drawableSize = CGSizeMake(w, h);
	_screen.width = w; _screen.height = h; _screen.pitch = w;
	_screen.dst_ptr = this->pixels.data();
	this->MakeDirty(0, 0, w, h);
	this->GameSizeChanged();
}

void VideoDriver_CocoaMetal::CheckPaletteAnim()
{
	if (!CopyPalette(this->palette)) return;
	Blitter *blitter = BlitterFactory::GetCurrentBlitter();
	if (blitter->UsePaletteAnimation() == Blitter::PaletteAnimation::Blitter) blitter->PaletteAnimate(this->palette);
}

void VideoDriver_CocoaMetal::Paint()
{
	/* Opt-in native-layout regression: framebuffer checks alone cannot detect
	 * a correctly rendered image placed outside its input wrapper. */
	if (this->resize_check && (this->frame_count == 30 || this->frame_count == 60)) {
		this->ChangeResolution(this->frame_count == 30 ? 900 : 1280, this->frame_count == 30 ? 600 : 800);
	}
	if (this->quit_check && this->frame_count + 2 == this->capture_frame) HandleExitGameRequest();
	if (!this->capture_path.empty() && this->cocoaview != nil &&
			!NSEqualRects(this->cocoaview.subviews.firstObject.frame, this->cocoaview.bounds)) ++this->layout_failures;
	ModernUpdateSoundscape();
	if (this->showcase && !this->showcase_attempted && _game_mode == GameMode::Normal && _switch_mode == SwitchMode::None && !HasModalProgress()) {
		this->showcase_attempted = true;
		ModernBuildShowcase(this->world_gallery,this->city_gallery);
	}
	PerformanceMeasurer framerate(PerformanceElement::Video);
	/* A capture's frame count must advance even in a completely still scene.
	 * Normal play continues to present only when the framebuffer is dirty. */
	if (!this->capture_path.empty()) this->MakeDirty(0,0,this->width,this->height);
	if (this->texture == nil || IsEmptyRect(this->dirty_rect) || (!this->hidden_capture && [this->window isMiniaturized])) return;
	@autoreleasepool {
		/* Never overwrite a texture that the GPU is still sampling. */
		[this->pending waitUntilCompleted];
		[this->pending release]; this->pending = nil;
		id<CAMetalDrawable> drawable = this->hidden_capture ? nil : [this->metal_layer nextDrawable];
		if (!this->hidden_capture && drawable == nil) return;
		id<MTLTexture> target = this->hidden_capture ? this->offscreen : drawable.texture;
		[this->texture replaceRegion:MTLRegionMake2D(0, 0, this->width, this->height) mipmapLevel:0 withBytes:this->pixels.data() bytesPerRow:this->width * sizeof(Colour)];
		MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
		pass.colorAttachments[0].texture = target;
		pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
		pass.colorAttachments[0].storeAction = MTLStoreActionStore;
		id<MTLCommandBuffer> command = [this->queue commandBuffer];
		id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
		[encoder setRenderPipelineState:this->pipeline];
		[encoder setFragmentTexture:this->texture atIndex:0];
		[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
		[encoder endEncoding];
		id<MTLBuffer> readback = nil;
		bool ready = !HasModalProgress() && (!this->showcase || this->showcase_attempted);
		if (ready && this->frame_count == 0) this->capture_start = std::chrono::steady_clock::now();
		bool capture = !this->capture_path.empty() && ready && ++this->frame_count == this->capture_frame;
		NSUInteger readback_pitch = Align(this->width * sizeof(Colour), 256);
		if (capture) {
			readback = [this->device newBufferWithLength:readback_pitch * this->height options:MTLResourceStorageModeShared];
			id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
			[blit copyFromTexture:target sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(this->width, this->height, 1) toBuffer:readback destinationOffset:0 destinationBytesPerRow:readback_pitch destinationBytesPerImage:readback_pitch * this->height];
			[blit endEncoding];
		}
		if (drawable != nil) [command presentDrawable:drawable];
		this->pending = [command retain];
		[command commit];
		this->dirty_rect = {};
		if (capture) {
			[command waitUntilCompleted];
			size_t mismatches = 0;
			for (int y = 0; y < this->height; ++y) {
				const auto *row = reinterpret_cast<const Colour *>(static_cast<const uint8_t *>([readback contents]) + y * readback_pitch);
				for (int x = 0; x < this->width; ++x) {
					const auto &expected = this->pixels[y * this->width + x];
					if (row[x].r != expected.r || row[x].g != expected.g || row[x].b != expected.b) ++mismatches;
				}
			}
			std::ofstream report(this->capture_path + ".metal-check.txt");
			report << "hidden_capture=" << this->hidden_capture << "\n";
			NSView *draw_view = this->cocoaview.subviews.firstObject;
			bool fills_content = NSEqualRects(draw_view.frame, this->cocoaview.bounds);
			report << "draw_view_fills_content=" << fills_content << "\nlayout_failures=" << this->layout_failures << "\n";
			if (this->quit_check) {
				bool visible = false, hit = false;
				if (Window *query = FindWindowById(WindowClass::ConfirmPopupQuery, 0); query != nullptr) {
					const auto *yes = query->GetWidget<NWidgetCore>(WID_Q_YES);
					visible = query->left + yes->pos_x >= 0 && query->top + yes->pos_y >= 0 &&
						query->left + yes->pos_x + int(yes->current_x) <= _screen.width && query->top + yes->pos_y + int(yes->current_y) <= _screen.height;
					hit = GetWidgetFromPos(query, yes->pos_x + yes->current_x / 2, yes->pos_y + yes->current_y / 2) == WID_Q_YES;
				}
				report << "quit_button_visible=" << visible << "\nquit_button_hit=" << hit << "\n";
			}
			report << "device=" << this->driver_info << "\nsize=" << this->width << "x" << this->height << "\npixel_mismatches=" << mismatches << "\ngpu_status=" << int(command.status) << "\n";
			double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - this->capture_start).count();
			report << "rendered_frames=" << this->frame_count << "\nelapsed_seconds=" << seconds << "\nrendered_fps=" << this->frame_count / std::max(seconds, 0.001) << "\n";
			report << "native_sprites_loaded=" << ModernLoadedSpriteCount() << "\nnative_vehicle_sprites_loaded=" << ModernLoadedSpriteCount(true) << "\n";
			if (const Window *toolbar = FindWindowById(WindowClass::MainToolbar, 0); toolbar != nullptr) {
				uint failures = 0;
				for (WidgetID id = WID_TN_PAUSE; id < WID_TN_SWITCH_BAR; ++id) {
					const auto *widget = toolbar->GetWidget<NWidgetCore>(id);
					if (widget->current_x == 0 || GetWidgetFromPos(toolbar, widget->pos_x + widget->current_x / 2, widget->pos_y + widget->current_y / 2) != id) ++failures;
				}
				report << "toolbar_hit_failures=" << failures << "\n";
			}
#ifdef WITH_PNG
			png_image image{};
			image.version = PNG_IMAGE_VERSION;
			image.width = this->width; image.height = this->height;
			image.format = PNG_FORMAT_BGRA;
			bool written = png_image_write_to_file(&image, (this->capture_path + ".png").c_str(), 0, [readback contents], readback_pitch, nullptr);
			report << "png_written=" << written << "\n";
			png_image_free(&image);
#endif
			[readback release];
			if (this->showcase) ModernSaveShowcaseReport(this->capture_path);
			if (_game_mode == GameMode::Normal) ModernInspectScene(this->capture_path);
		}
		if (!this->capture_path.empty() && this->frame_count > this->capture_frame + 5) {
			if (this->quit_check) {
				if (Window *query = FindWindowById(WindowClass::ConfirmPopupQuery, 0); query != nullptr) {
					const auto *yes = query->GetWidget<NWidgetCore>(WID_Q_YES);
					query->OnClick({yes->pos_x + int(yes->current_x / 2), yes->pos_y + int(yes->current_y / 2)}, WID_Q_YES, 1);
				}
				std::ofstream(this->capture_path + ".quit-check.txt") << "quit_action_exits=" << _exit_game << "\n";
			}
			_exit_game = true;
		}
	}
}
