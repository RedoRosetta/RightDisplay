// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#pragma once
#include <atomic>
#include <sstream>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc11-extensions"
#include "../../AudioVirtualDevice/Transport/PCMTransport.h"
#pragma clang diagnostic pop
namespace bridge {
// First failing read is retained before teardown mutates the shared mapping.
// One winning writer; release/acquire publication. No allocation/logging in RT.
struct TransportContextSnapshot {
 uint64_t magic=0,session=0,producer=0,consumer=0,lease=0,now=0,blocks=0,underruns=0,overruns=0,writePosition=0,readPosition=0,streamEpoch=0;
 uint32_t version=0,capacity=0,rate=0,channels=0,active=0,failure=0,streaming=0;
 static TransportContextSnapshot read(const RDTransport* t,uint64_t now)noexcept {
  TransportContextSnapshot s;s.now=now;if(!t)return s;
  s.magic=t->magic;s.session=t->session;s.version=t->version;s.capacity=t->capacity;s.rate=t->rate;s.channels=t->channels;
  s.producer=atomic_load(&t->producer);s.consumer=atomic_load(&t->consumer);s.lease=atomic_load(&t->lease);s.active=atomic_load(&t->active);s.failure=atomic_load(&t->failure);
  s.writePosition=atomic_load(&t->write);s.readPosition=atomic_load(&t->read);s.streamEpoch=atomic_load(&t->streamEpoch);s.streaming=atomic_load(&t->streaming);s.blocks=atomic_load(&t->blocks);s.underruns=atomic_load(&t->underruns);s.overruns=atomic_load(&t->overruns);return s;
 }
 uint32_t differences(uint64_t expectedSession,uint64_t expectedProducer)const noexcept {
  return (magic!=RD_MAGIC?1U:0)|(version!=RD_PROTOCOL?2U:0)|(capacity!=RD_CAPACITY?4U:0)|(rate!=48000?8U:0)|(channels!=2?16U:0)|(session!=expectedSession||!expectedSession?32U:0)|(!active?64U:0)|(producer!=expectedProducer?128U:0)|(consumer!=expectedSession?256U:0)|(failure?512U:0)|(now>lease?1024U:0);
 }
 std::string describe()const {std::ostringstream o;o<<"{magic="<<magic<<",version="<<version<<",capacity="<<capacity<<",rate="<<rate<<",channels="<<channels<<",session="<<session<<",producer="<<producer<<",consumer="<<consumer<<",active="<<active<<",failure="<<failure<<",lease="<<lease<<",write="<<writePosition<<",read="<<readPosition<<",streaming="<<streaming<<",streamEpoch="<<streamEpoch<<",blocks="<<blocks<<",transportUnderrun="<<underruns<<",transportOverrun="<<overruns<<"}";return o.str();}
};
struct TransportContextTrace {
 std::atomic<uint32_t> publication{0};
 TransportContextSnapshot oldContext,newContext;uint32_t diff=0,source=0;
 bool validate(const RDTransport* t,uint64_t session,uint64_t producer,uint64_t now,uint32_t caller)noexcept {
  if(rdValid(t,session)&&atomic_load(&t->active)&&atomic_load(&t->producer)==producer&&atomic_load(&t->consumer)==session&&!atomic_load(&t->failure)&&now<=atomic_load(&t->lease))return true;
  auto s=TransportContextSnapshot::read(t,now);auto mask=s.differences(session,producer);if(!mask)return true;
  uint32_t empty=0;if(publication.compare_exchange_strong(empty,1)){newContext=s;diff=mask;source=caller;publication.store(2,std::memory_order_release);}return false;
 }
 // Control queue only; shared timestamp units are mach_absolute_time ticks.
 std::string detail()const {
  if(publication.load(std::memory_order_acquire)!=2)return {};
  const char* fields[]={"magic","version","capacity","rate","channels","session","active","producer","consumer","failure","lease"};
  std::ostringstream o;o<<"CHANGE_SOURCE=SHARED_TRANSPORT CALLER="<<(source==1?"Playback.observe":"Playback.render")<<" TIMESTAMP_MACH="<<newContext.now<<" OLD_CONTEXT="<<oldContext.describe()<<" NEW_CONTEXT="<<newContext.describe()<<" DIFF_FIELDS=";
  for(unsigned i=0;i<11;i++)if(diff&(1U<<i))o<<fields[i]<<',';return o.str();
 }
};
}
