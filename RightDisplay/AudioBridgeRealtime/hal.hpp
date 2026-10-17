// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#pragma once
#include "core.hpp"
#include "pcm_output.hpp"
#include <CoreAudio/CoreAudio.h>
#include <optional>
namespace bridge {
struct Stream {AudioStreamID id{};AudioStreamBasicDescription client{},physical{};std::optional<uint32_t> latency;std::vector<AudioStreamRangedDescription> available;};
struct Device {AudioDeviceID id{};std::string uid,name;double rate{};uint32_t channels{},buffer{},maxBlock{},alive{},running{};std::optional<uint32_t> latency,safety;std::vector<Stream> streams;std::vector<uint32_t> buffers;uint32_t transport{};bool stereoMap=false;uint32_t left=0,right=1;};
std::vector<Device> devices();
bool contextMatches(const Device&,const Device&);
Device resolveFrom(const std::vector<Device>&,const std::string&);
Device resolve(const std::string& uid);
void printDevice(const Device&);
bool clientFormatAllowed(const AudioStreamBasicDescription&)noexcept;
bool physicalFormatAllowed(const AudioStreamBasicDescription&)noexcept;
bool layoutAllowed(const std::vector<uint32_t>&,bool planar)noexcept;
std::string eligibility(const Device&);
bool supportedRate(double)noexcept;
bool physicalTransport(uint32_t)noexcept;
}
