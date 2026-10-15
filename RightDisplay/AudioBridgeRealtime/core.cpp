// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#include "core.hpp"
#include <bit>
#include <numbers>
namespace bridge {
const char* failureName(Failure f)noexcept {switch(f){case Failure::None:return "NONE";case Failure::Stopped:return "STOPPED";case Failure::TargetUnavailable:return "TARGET_UNAVAILABLE";case Failure::ContextChanged:return "CONTEXT_CHANGED";case Failure::FormatChanged:return "FORMAT_CHANGED";case Failure::InvalidBuffer:return "INVALID_BUFFER";case Failure::Underrun:return "UNDERRUN";case Failure::Overrun:return "OVERRUN";case Failure::Nonfinite:return "NONFINITE_PCM";case Failure::CallbackStalled:return "HAL_CALLBACK_STALLED";case Failure::DeviceStopped:return "DEVICE_STOPPED";case Failure::HALFailure:return "HAL_FAILURE";}return "UNKNOWN";}
Engine::Engine(std::vector<Frame> f,size_t cap,size_t t,size_t block,float volume,double rate,uint64_t epoch,bool fixtureInput):ring(cap),callbackEpoch(epoch),fixture(std::move(f)),target(t),maxBlock(block),sampleRate(rate),fixtureDriven(fixtureInput),gain(volume),requestedGain(std::bit_cast<uint32_t>(volume)){gate.epoch.store(epoch);if((fixtureDriven&&fixture.empty())||!std::isfinite(rate)||rate<44100||rate>192000||!epoch||!block||block>cap||t<block||t>cap-block)throw std::invalid_argument("fixture/target/capacity invalid");for(auto x:fixture)if(!std::isfinite(x.l)||!std::isfinite(x.r)||std::abs(x.l)>1||std::abs(x.r)>1)throw std::invalid_argument("fixture must be finite normalized PCM");}
void Engine::recordFill()noexcept {auto n=uint64_t(ring.fill());auto low=telemetry.minFill.load(std::memory_order_relaxed),high=telemetry.maxFill.load(std::memory_order_relaxed);if(n<low)telemetry.minFill.store(n,std::memory_order_relaxed);if(n>high)telemetry.maxFill.store(n,std::memory_order_relaxed);}
void Engine::prime(uint64_t host)noexcept {if(!fixtureDriven)return;for(size_t i=0;i<target;++i){if(!ring.push({fixture[cursor],host})){gate.invalidate(Failure::Overrun);break;}cursor=(cursor+1)%fixture.size();}recordFill();}
void Engine::commandGain(float v){if(!std::isfinite(v)||v<0||v>1)throw std::invalid_argument("gain must be finite 0..1");requestedGain.store(std::bit_cast<uint32_t>(v),std::memory_order_release);}
bool Engine::render(Frame* out,size_t n,uint64_t epoch,uint64_t host)noexcept {
 telemetry.callbacks.fetch_add(1,std::memory_order_relaxed);
 if(!out||n>maxBlock){gate.invalidate(Failure::InvalidBuffer);return false;}
 std::memset(out,0,n*sizeof(Frame));
 if(!gate.accepts(epoch)){telemetry.staleCallbacks.fetch_add(1,std::memory_order_relaxed);return false;}
 if(ring.fill()<n){ring.underrun.fetch_add(1,std::memory_order_relaxed);gate.invalidate(Failure::Underrun);return false;}
 gain.set(requestedMute.load(std::memory_order_acquire) ? 0 : std::bit_cast<float>(requestedGain.load(std::memory_order_acquire)),uint32_t(std::round(sampleRate*.01)));
 recordFill();
 for(size_t i=0;i<n;++i){TaggedFrame f{};if(!ring.pop(f)){gate.invalidate(Failure::Underrun);std::memset(out,0,n*sizeof(Frame));return false;}out[i]=gain.process(f.pcm);if(f.publishedHost&&host>=f.publishedHost){auto ticks=host-f.publishedHost;telemetry.residenceTicks.fetch_add(ticks,std::memory_order_relaxed);telemetry.residenceFrames.fetch_add(1,std::memory_order_relaxed);auto maximum=telemetry.maxResidenceTicks.load(std::memory_order_relaxed);if(ticks>maximum)telemetry.maxResidenceTicks.store(ticks,std::memory_order_relaxed);}}
 recordFill();
 // Phase 0A producer is clocked by this same consumer: no claim of dual-clock stability.
 if(fixtureDriven)for(size_t i=0;i<n;++i){if(!ring.push({fixture[cursor],host})){gate.invalidate(Failure::Overrun);std::memset(out,0,n*sizeof(Frame));return false;}cursor=(cursor+1)%fixture.size();}
 if(!gate.accepts(epoch)){std::memset(out,0,n*sizeof(Frame));return false;}
 telemetry.frames.fetch_add(n,std::memory_order_relaxed);recordFill();return true;
}
bool Engine::publishPCM(const Frame* frames,size_t count,uint64_t host,double sourceRate)noexcept {
 if(sourceRate!=sampleRate){gate.invalidate(Failure::FormatChanged);return false;}
 if(fixtureDriven||!frames||count>ring.capacity()||!gate.accepts(callbackEpoch))return false;
 for(size_t i=0;i<count;++i){if(!std::isfinite(frames[i].l)||!std::isfinite(frames[i].r)||std::abs(frames[i].l)>1||std::abs(frames[i].r)>1){gate.invalidate(Failure::Nonfinite);return false;}if(!ring.push({frames[i],host})){gate.invalidate(Failure::Overrun);return false;}}
 return true;
}
std::vector<Frame> fixture(const std::string& name,double seconds,double rate){if(!std::isfinite(seconds)||seconds<=0||seconds>30||!std::isfinite(rate)||rate<44100||rate>192000)throw std::invalid_argument("fixture duration");size_t n=size_t(seconds*rate);std::vector<Frame> f(n);const double pi=std::numbers::pi;for(size_t i=0;i<n;++i){double t=double(i)/rate;float s=0;if(name=="sine"||name=="low"||name=="near"||name=="full"||name=="phase"){double a=name=="low"?1e-6:name=="near"?0.999:name=="full"?1:0.1;s=float(a*std::sin(2*pi*1000*t));f[i]={s,name=="phase"?-s:s};}else if(name=="impulse"){f[i]={i==0?0.5F:0,i==0?0.25F:0};}else if(name=="channels"){f[i]={float(0.1*std::sin(2*pi*440*t)),float(0.1*std::sin(2*pi*880*t))};}else if(name=="sweep"){double k=std::log(20000.0/20)/seconds;float v=float(0.1*std::sin(2*pi*20*(std::exp(k*t)-1)/k));f[i]={v,v};}else if(name!="silence")throw std::invalid_argument("unknown fixture");}return f;}
Latency latency(size_t fill,size_t block,double rate){if(!std::isfinite(rate)||rate<=0)throw std::invalid_argument("rate");return {double(fill)*1000/rate,double(block)*1000/rate};}
}
