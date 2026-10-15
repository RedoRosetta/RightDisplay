// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#pragma once
#include <atomic>
#include <cstdint>
#include <memory>
#include <vector>
#include <string>
#include <cmath>
#include <cstring>
#include <stdexcept>
namespace bridge {
struct Frame { float l{},r{}; };
static_assert(sizeof(Frame)==8);
static_assert(std::atomic<uint64_t>::is_always_lock_free);
static_assert(std::atomic<uint32_t>::is_always_lock_free);
struct TaggedFrame { Frame pcm; uint64_t publishedHost{}; };
class Ring {
 std::unique_ptr<TaggedFrame[]> data_; size_t capacity_;
 alignas(64) std::atomic<uint64_t> write_{0};
 alignas(64) std::atomic<uint64_t> read_{0};
public:
 std::atomic<uint64_t> underrun{0},overrun{0};
 explicit Ring(size_t n): data_(n ? new TaggedFrame[n] : nullptr),capacity_(n) { if(n<2 || (n&(n-1)))throw std::invalid_argument("capacity must be power of two"); }
 size_t capacity()const noexcept{return capacity_;}
 size_t fill()const noexcept { auto r=read_.load(std::memory_order_acquire);auto w=write_.load(std::memory_order_acquire);return w>=r&&w-r<=capacity_ ? size_t(w-r):capacity_; }
 bool push(const TaggedFrame& f)noexcept {auto w=write_.load(std::memory_order_relaxed);auto r=read_.load(std::memory_order_acquire);if(w-r>=capacity_){overrun.fetch_add(1,std::memory_order_relaxed);return false;}data_[w&(capacity_-1)]=f;write_.store(w+1,std::memory_order_release);return true;}
 bool pop(TaggedFrame& f)noexcept {auto r=read_.load(std::memory_order_relaxed);auto w=write_.load(std::memory_order_acquire);if(w==r){underrun.fetch_add(1,std::memory_order_relaxed);return false;}f=data_[r&(capacity_-1)];read_.store(r+1,std::memory_order_release);return true;}
};
enum class Failure:uint32_t {None,Stopped,TargetUnavailable,ContextChanged,FormatChanged,InvalidBuffer,Underrun,Overrun,Nonfinite,CallbackStalled,DeviceStopped,HALFailure};
const char* failureName(Failure)noexcept;
struct Gate {
 std::atomic<uint64_t> epoch{1};std::atomic<uint32_t> failure{0};
 void invalidate(Failure f)noexcept {uint32_t none=0;failure.compare_exchange_strong(none,uint32_t(f),std::memory_order_relaxed);epoch.fetch_add(1,std::memory_order_release);}
 bool accepts(uint64_t e)const noexcept{return epoch.load(std::memory_order_acquire)==e&&failure.load(std::memory_order_acquire)==uint32_t(Failure::None);}
};
class Gain {
 float value_,start_,target_;uint32_t progressed_=0,total_=0;
public:
 explicit Gain(float value=1):value_(value),start_(value),target_(value){if(!std::isfinite(value)||value<0||value>1)throw std::invalid_argument("gain must be 0..1");}
 void set(float target,uint32_t frames=480)noexcept {if(!std::isfinite(target)||target<0||target>1)return;if(target==target_)return;start_=value_;target_=target;progressed_=0;total_=frames;if(frames==0)value_=target_;}
 Frame process(Frame f)noexcept {if(progressed_<total_){++progressed_;value_=progressed_==total_ ? target_ : start_+(target_-start_)*(float(progressed_)/float(total_));}if(value_==1)return f;if(value_==0)return {};return {f.l*value_,f.r*value_};}
 float current()const noexcept{return value_;}
};
struct Telemetry {std::atomic<uint64_t> callbacks{0},frames{0},minFill{UINT64_MAX},maxFill{0},residenceTicks{0},residenceFrames{0},maxResidenceTicks{0},hostTime{0},sampleBits{0},timestampCount{0},sampleTimeCount{0},staleCallbacks{0};};
struct Engine {
 Ring ring; Gate gate;Telemetry telemetry;const uint64_t callbackEpoch;const std::vector<Frame> fixture;size_t cursor=0;const size_t target,maxBlock;const double sampleRate;const bool fixtureDriven;
 Gain gain;std::atomic<uint32_t> requestedGain;std::atomic<uint32_t> requestedMute{0};
 Engine(std::vector<Frame>,size_t capacity=4096,size_t target=512,size_t maxBlock=256,float volume=1,double rate=48000,uint64_t epoch=1,bool fixtureInput=true);
 void prime(uint64_t host)noexcept;
 bool render(Frame* out,size_t frames,uint64_t epoch,uint64_t host)noexcept;
 void commandGain(float);
 void commandMute(bool muted)noexcept{requestedMute.store(muted?1:0,std::memory_order_release);}
 void recordFill()noexcept;
 // Future single-producer PCM input: rate must match sampleRate; no implicit SRC.
 bool publishPCM(const Frame* frames,size_t count,uint64_t host,double sourceRate=48000)noexcept;
};
std::vector<Frame> fixture(const std::string&,double seconds=2,double rate=48000);
struct Latency {double ringMs,bufferMs;};
Latency latency(size_t fill,size_t block,double rate);
}
