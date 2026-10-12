/* Audio regression checks, added 2026-10-12. SPDX-License-Identifier: GPL-2.0-only */
#include "../stdafx.h"
#include "../3rdparty/catch2/catch.hpp"
#include "../mixer.h"
#include "../safeguards.h"

static void ResetMixer()
{
	MxInitialize(48000);
	SetEffectVolume(127);
	MxCloseAllChannels();
	std::array<int16_t, 2> output{};
	MxMixSamples(output.data(), 1);
}

static MixerChannel *PlayConstant(int16_t value, size_t frames = 1024)
{
	auto samples = std::make_shared<std::vector<std::byte>>((frames + 1) * sizeof(int16_t));
	for (size_t i = 0; i < frames; ++i) std::copy_n(reinterpret_cast<const std::byte *>(&value), sizeof(value), samples->data() + i * sizeof(value));
	auto *channel = MxAllocateChannel();
	if (channel == nullptr) return nullptr;
	MxSetChannelRawSrc(channel, samples, 48000, true);
	MxSetChannelVolume(channel, 16384, 0);
	MxActivateChannel(channel);
	return channel;
}

TEST_CASE("Mixer preserves all 32 simultaneous effects")
{
	ResetMixer();
	for (int i = 0; i < 32; ++i) REQUIRE(PlayConstant(1000) != nullptr);
	CHECK(MxAllocateChannel() == nullptr);
	std::array<int16_t, 2> output{};
	MxMixSamples(output.data(), 1);
	CHECK(output[0] >= 3900);
	CHECK(output[0] <= 4100);
	CHECK(output[1] == 0);
	ResetMixer();
}

TEST_CASE("Mixer clips after summing opposing loud effects")
{
	ResetMixer();
	for (int i = 0; i < 10; ++i) REQUIRE(PlayConstant(30000) != nullptr);
	for (int i = 0; i < 10; ++i) REQUIRE(PlayConstant(-30000) != nullptr);
	std::array<int16_t, 600> output{};
	MxMixSamples(output.data(), 300); // Cross the fixed scratch-block boundary.
	/* Signed integer quantisation can leave one LSB per opposing pair. */
	CHECK(std::all_of(output.begin(), output.end(), [](int16_t value) { return std::abs(int(value)) <= 10; }));
	ResetMixer();
}

TEST_CASE("Mixer stops exhausted samples and can reuse every channel")
{
	ResetMixer();
	for (int i = 0; i < 32; ++i) REQUIRE(PlayConstant(30000, 1) != nullptr);
	std::array<int16_t, 600> output{};
	MxMixSamples(output.data(), 300);
	CHECK(output[0] == 32767);
	CHECK(std::all_of(output.begin() + 2, output.end(), [](int16_t value) { return value == 0; }));
	for (int i = 0; i < 32; ++i) REQUIRE(PlayConstant(1000) != nullptr);
	ResetMixer();
}
