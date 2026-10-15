// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#pragma once
#include "route_buffer.hpp"
#include "buffer_plan.hpp"
#include "transport_client.hpp"
#include <bit>
namespace bridge {
// TEST_AUDIO_PRODUCER and SYSTEM_AUDIO_PRODUCER both supply stereo Float32
// to this renderer. Exactly one Gain and one physical output callback.
class Playback {
 std::vector<Frame> fixturePCM;size_t cursor=0;
 std::unique_ptr<TransportClient> transport;
 const BufferPlan plan;RouteBuffer src;
 std::atomic<uint64_t> observedTransportPeak{0},streamResets{0};std::array<RDFrame,RD_MAX_BLOCK> incoming{};
 Gain gain{0};double rate;uint64_t streamEpoch=0;bool quiet=true;
 std::array<Frame,RD_MAX_BLOCK> normalized{};
public:
 Gate gate;Telemetry telemetry;const uint64_t epoch;
 std::atomic<uint32_t> requestedGain,requestedMute{0};
 const bool system;
 static BufferPlan fixturePlan(double outputRate){if(!std::isfinite(outputRate)||outputRate!=std::floor(outputRate)||outputRate<1||outputRate>192000)throw std::invalid_argument("UNSUPPORTED_SESSION_BUFFER_SPEC");return BufferPlan::make({48000,2,32,8,512,8192,true,false},{uint32_t(outputRate),2,32,8,512,8192,true,false});}
 Playback(const std::string& producer,double outputRate,float volume,uint64_t token):Playback(producer,outputRate,volume,token,fixturePlan(outputRate)){}
 Playback(const std::string& producer,double outputRate,float volume,uint64_t token,BufferPlan sessionPlan):fixturePCM(producer=="system"?std::vector<Frame>{}:fixture(producer,2,outputRate)),plan(sessionPlan),src(plan.target,plan.source.rate,outputRate,plan.capacity),rate(outputRate),epoch(token),requestedGain(std::bit_cast<uint32_t>(volume)),system(producer=="system"){
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
   auto currentEpoch=atomic_load(&t->streamEpoch);if(currentEpoch!=streamEpoch){src.reset();streamEpoch=currentEpoch;streamResets.fetch_add(1,std::memory_order_relaxed);}quiet=false;
   uint32_t bytes=atomic_load(&t->volumeBits);memcpy(&volume,&bytes,4);muted=atomic_load(&t->mute)!=0;
   auto write=atomic_load(&t->write),read=atomic_load(&t->read);
   if(write>=read&&write-read<=RD_CAPACITY)observedTransportPeak.store(std::max<uint64_t>(observedTransportPeak.load(std::memory_order_relaxed),write-read),std::memory_order_relaxed);
   auto fill=src.fill();if(fill>plan.readWindow){gate.invalidate(Failure::Overrun);return false;}
   size_t budget=plan.readWindow-fill;
   // Fixed at prepare time. At most two existing protocol21 pop calls for all
   // supported rates/max callbacks; no allocation or reconfiguration in IO.
   while(budget){
    uint32_t chunk=uint32_t(std::min<size_t>(RD_MAX_BLOCK,budget));
    uint32_t received=rdPop(t,transport->producer,incoming.data(),chunk);
    static_assert(sizeof(RDFrame)==sizeof(Frame));
    for(uint32_t i=0;i<received;i++)normalized[i]={incoming[i].l,incoming[i].r};
    if(received&&!src.push(normalized.data(),received)){gate.invalidate(Failure::Overrun);return false;}
    budget-=received;if(received<chunk)break;
   }
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
 const BufferPlan& bufferPlan()const noexcept{return plan;}
 uint64_t localPeak()const noexcept{return src.peak.load();}
 std::string bufferDetails()const{
  uint64_t available=0;if(transport&&transport->memory){auto w=atomic_load(&transport->memory->write),r=atomic_load(&transport->memory->read);if(w>=r&&w-r<=RD_CAPACITY)available=w-r;}
  std::ostringstream o;o<<"sourceSpecOrigin="<<(system?"HAL_READBACK_PROTOCOL21":"SYNTHETIC_FIXTURE")<<" sourceRate="<<plan.source.rate<<" sourceChannels="<<plan.source.channels<<" sourceBits="<<plan.source.bits<<" sourceBytesPerFrame="<<plan.source.bytesPerFrame<<" sourceIOFrames="<<plan.source.ioFrames<<" sourceMaxCallback="<<plan.source.maxCallbackFrames<<" producerReserve="<<plan.producerReserve<<" sourceIOMS="<<1000.0*plan.source.ioFrames/plan.source.rate<<" outputRate="<<plan.output.rate<<" outputChannels="<<plan.output.channels<<" outputBits="<<plan.output.bits<<" outputBytesPerPlaneFrame="<<plan.output.bytesPerFrame<<" outputIOFrames="<<plan.output.ioFrames<<" outputMaxCallback="<<plan.output.maxCallbackFrames<<" outputIOMS="<<1000.0*plan.output.ioFrames/plan.output.rate<<" localCapacity="<<plan.capacity<<" localCapacityMS="<<1000.0*plan.capacity/plan.source.rate<<" targetFill="<<plan.target<<" targetMS="<<1000.0*plan.target/plan.source.rate<<" readWindow="<<plan.readWindow<<" localPeak="<<src.peak.load()<<" transportCapacity="<<RD_CAPACITY<<" transportCapacityMS="<<1000.0*RD_CAPACITY/48000<<" observedTransportFill="<<available<<" observedTransportFree="<<RD_CAPACITY-available<<" observedTransportPeak="<<std::max<uint64_t>(available,observedTransportPeak.load())<<" producerOverrunRequest=UNAVAILABLE_PROTOCOL21 localOverflowFill="<<src.overflowFill.load()<<" localOverflowRequest="<<src.overflowRequest.load()<<" localOverflowFree="<<src.overflowFree.load()<<" localUnderflowAvailable="<<src.underflowAvailable.load()<<" localUnderflowRequest="<<src.underflowRequest.load()<<" streamResets="<<streamResets.load()<<" buildReason=FRESH_VERIFIED_HAL_SESSION actualEndToEndLatency=UNMEASURED";return o.str();
 }
 double ringMS()const noexcept{return system?1000.0*plan.target/plan.source.rate:0;}
};
}
