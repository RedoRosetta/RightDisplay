// Copyright © 2026 RedoRosetta
// First-party portions licensed under RNSL 1.0; see LICENSE_SCOPE.md.
#include "../RightDisplay/AudioBridgeRealtime/buffer_plan.hpp"
#include "../RightDisplay/AudioBridgeRealtime/route_buffer.hpp"
#include <iostream>
#include <limits>
#include <functional>
#include <chrono>
int main(){using namespace bridge;unsigned n=0;auto check=[&](bool x){++n;if(!x)throw std::runtime_error("plan assertion "+std::to_string(n));};auto rejects=[&](auto fn){try{fn();return false;}catch(const std::invalid_argument&){return true;}};
 SessionAudioSpec source{48000,2,32,8,192,192,true,false};
 for(uint32_t rate:{44100,48000,88200,96000,176400,192000})for(uint32_t block:{32,128,192,256,512,1024,4096,8192})for(uint32_t producer:{32,192,512,8192}){
  auto in=source;in.ioFrames=producer;in.maxCallbackFrames=producer;auto p=BufferPlan::make(in,{rate,2,32,8,block,block,true,false});check(p.target==4096);check(p.capacity>=p.readWindow+p.producerReserve);check(p.capacity<=32768&&(p.capacity&(p.capacity-1))==0);check(p.readWindow>=p.target+33+p.sourceDemand);RouteBuffer ring(p.target,48000,rate,p.capacity);check(ring.allocatedFrames()==p.capacity);
 }
 auto out=SessionAudioSpec{48000,2,32,8,512,512,true,false};
 for(auto field:{0,1,2,3,4,5,6,7,8}){auto in=source;switch(field){case 0:in.rate=0;break;case 1:in.channels=6;break;case 2:in.bits=16;break;case 3:in.floating=false;break;case 4:in.bytesPerFrame=16;break;case 5:in.ioFrames=0;break;case 6:in.maxCallbackFrames=UINT32_MAX;break;case 7:in.rate=96000;break;case 8:in.planar=true;break;}check(rejects([&]{BufferPlan::make(in,out);}));}
 for(uint32_t channels:{0,1,6,8}){auto spec=out;spec.channels=channels;check(rejects([&]{BufferPlan::make(source,spec);}));}
 for(uint32_t bits:{8,16,24,64}){auto spec=out;spec.bits=bits;check(rejects([&]{BufferPlan::make(source,spec);}));}
 auto planar=out;planar.planar=true;planar.bytesPerFrame=4;check(BufferPlan::make(source,planar).capacity==16384);planar.bytesPerFrame=8;check(rejects([&]{BufferPlan::make(source,planar);}));
 check(rejects([]{BufferPlan::mul(UINT64_MAX,2);}));check(rejects([]{BufferPlan::add(UINT64_MAX,1);}));check(rejects([]{BufferPlan::ceilDiv(1,0);}));check(BufferPlan::ceilDiv(UINT64_MAX,UINT64_MAX)==1);
 for(size_t cap:std::array<size_t,6>{0,1,127,1000,65536,SIZE_MAX})check(rejects([&]{RouteBuffer ring(4096,48000,48000,cap);}));
 // Existing clock correction and nominal target remain unchanged. Synthetic
 // ten-minute streams on either side of a 100ppm clock mismatch; not real time.
 Frame zeros[8192]{},pcm[512];
 for(double ppm:{-100.,0.,100.}){auto p=BufferPlan::make(source,out);RouteBuffer ring(p.target,48000,48000,p.capacity);check(ring.push(zeros,4608));double credit=0;
  for(unsigned i=0;i<56250;i++){credit+=512*(1+ppm/1e6);auto count=size_t(credit);credit-=count;check(ring.push(zeros,count));check(ring.render(pcm,512));check(ring.fill()<p.capacity);}
  check(ring.underruns==0&&ring.overruns==0);check(ring.peak.load()<p.capacity);
 }
 auto p=BufferPlan::make(source,out);RouteBuffer full(p.target,48000,48000,p.capacity);check(full.push(zeros,8192));check(full.push(zeros,8192));check(!full.push(zeros,1));check(full.overflowFill==16384&&full.overflowFree==0&&full.overflowRequest==1);
 RouteBuffer empty(p.target,48000,48000,p.capacity);check(empty.push(zeros,6144));for(unsigned i=0;i<11;i++)check(empty.render(pcm,512));check(!empty.render(pcm,512));check(empty.underflowAvailable<empty.underflowRequest);
 auto capacity=empty.allocatedFrames();empty.reset();check(empty.allocatedFrames()==capacity);check(empty.render(pcm,512));
 std::cout<<"Session buffer plans: "<<n<<" assertions PASS; rates/periods, rejected multichannel/unsupported PCM, safe arithmetic, fixed capacity, synthetic clocks, exact local fault counters\n";
}
