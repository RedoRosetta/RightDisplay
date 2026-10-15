// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#pragma once
#include "route_buffer.hpp"
#include "transport_client.hpp"
#include <bit>
namespace bridge {
// TEST_AUDIO_PRODUCER and SYSTEM_AUDIO_PRODUCER both supply stereo Float32
// to this renderer. Exactly one Gain and one physical output callback.
class Playback {
 std::vector<Frame> fixturePCM;size_t cursor=0;
 std::unique_ptr<TransportClient> transport;
 RouteBuffer src;std::array<RDFrame,RD_MAX_BLOCK> incoming{};
 Gain gain{0};double rate;uint64_t streamEpoch=0;bool quiet=true;
 std::array<Frame,RD_MAX_BLOCK> normalized{};
public:
 Gate gate;Telemetry telemetry;const uint64_t epoch;
 std::atomic<uint32_t> requestedGain,requestedMute{0};
 const bool system;
 Playback(const std::string& producer,double outputRate,float volume,uint64_t token):fixturePCM(producer=="system"?std::vector<Frame>{}:fixture(producer,2,outputRate)),src(4096,48000,outputRate),rate(outputRate),epoch(token),requestedGain(std::bit_cast<uint32_t>(volume)),system(producer=="system"){
  gate.epoch.store(epoch);if(system)transport=std::make_unique<TransportClient>();
 }
 void stop()noexcept{gate.invalidate(Failure::Stopped);if(transport&&transport->memory){atomic_store(&transport->memory->consumer,0);atomic_store(&transport->memory->active,0);}}
 void observe()noexcept{if(transport){if(!transport->valid())gate.invalidate(Failure::ContextChanged);else transport->renew();}}
 bool render(Frame* out,size_t n,uint64_t token,uint64_t)noexcept{
  std::fill_n(out,n,Frame{});if(n>RD_MAX_BLOCK||!gate.accepts(token))return false;
  float volume=std::bit_cast<float>(requestedGain.load());bool muted=requestedMute.load()!=0;
  if(system){
   if(!transport->valid(2)){gate.invalidate(Failure::ContextChanged);return false;}
   auto* t=transport->memory;
   if(!atomic_load(&t->streaming)){if(!quiet){src.reset();quiet=true;}atomic_store(&t->read,atomic_load(&t->write));telemetry.callbacks.fetch_add(1);return true;}
   auto currentEpoch=atomic_load(&t->streamEpoch);if(currentEpoch!=streamEpoch){src.reset();streamEpoch=currentEpoch;}quiet=false;
   uint32_t bytes=atomic_load(&t->volumeBits);memcpy(&volume,&bytes,4);muted=atomic_load(&t->mute)!=0;
   uint32_t budget=uint32_t(std::min<size_t>(RD_MAX_BLOCK,8192-src.fill()));
   uint32_t received=rdPop(t,transport->producer,incoming.data(),budget);
   static_assert(sizeof(RDFrame)==sizeof(Frame));
   // Copy into a typed preallocated frame block, avoiding C/C++ aliasing UB.
   for(uint32_t i=0;i<received;i++)normalized[i]={incoming[i].l,incoming[i].r};
   if(received&&!src.push(normalized.data(),received)){gate.invalidate(Failure::Overrun);return false;}
   if(!src.render(out,n)){gate.invalidate(Failure::Underrun);return false;}
  }else{for(size_t i=0;i<n;i++){out[i]=fixturePCM[cursor];cursor=(cursor+1)%fixturePCM.size();}}
  if(!std::isfinite(volume)||volume<0||volume>1){gate.invalidate(Failure::Nonfinite);std::fill_n(out,n,Frame{});return false;}
  gain.set(muted?0:volume,uint32_t(std::round(rate*.010)));
  for(size_t i=0;i<n;i++){out[i]=gain.process(out[i]);if(!std::isfinite(out[i].l)||!std::isfinite(out[i].r)){gate.invalidate(Failure::Nonfinite);std::fill_n(out,n,Frame{});return false;}}
  if(!gate.accepts(token)){std::fill_n(out,n,Frame{});return false;}telemetry.callbacks.fetch_add(1);telemetry.frames.fetch_add(n);return true;
 }
 void commandGain(float v){if(!std::isfinite(v)||v<0||v>1)throw std::invalid_argument("gain");requestedGain.store(std::bit_cast<uint32_t>(v));}
 void commandMute(bool v)noexcept{requestedMute.store(v);}
 size_t fill()const noexcept{return src.fill();}
 uint64_t underruns()const noexcept{return src.underruns.load();}
 uint64_t overruns()const noexcept{return src.overruns.load();}
 std::string contextFailureDetail()const{return transport?transport->trace.detail():std::string{};}
 uint64_t transportUnderruns()const noexcept{return transport?atomic_load(&transport->memory->underruns):0;}
 uint64_t transportOverruns()const noexcept{return transport?atomic_load(&transport->memory->overruns):0;}
 uint64_t producerBlocks()const noexcept{return transport?atomic_load(&transport->memory->blocks):0;}
 double ringMS()const noexcept{return system?4096.0/48:0;}
};
}
