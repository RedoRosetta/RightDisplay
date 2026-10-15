// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#include "../RightDisplay/AudioBridgeRealtime/route_buffer.hpp"
#include <iostream>
#include <thread>
#include <cassert>
int main(){using namespace bridge;size_t assertions=0;auto check=[&](bool v){++assertions;if(!v)throw std::runtime_error("route assertion "+std::to_string(assertions));};
 RouteBuffer empty;Frame out[256];check(empty.render(out,256));for(auto f:out)check(f.l==0&&f.r==0);check(empty.underruns==0);
 Frame in[8192];for(auto& f:in)f={.25F,-.5F};RouteBuffer constant;check(constant.push(in,6144));for(int block=0;block<100;++block){check(constant.render(out,256));for(auto f:out){check(std::abs(f.l-.25F)<1e-6&&std::abs(f.r+.5F)<1e-6);}check(constant.push(in,256));}
 // Compare real interpolated PCM to analytic stereo sinusoids, including 20 kHz.
 for(double hz:{1000.,12000.,20000.}){RouteBuffer tone;uint64_t cursor=0;double position=15,maxError=0;
  auto feed=[&](size_t n){for(size_t j=0;j<n;++j){float v=float(.25*std::sin(2*std::numbers::pi*hz*double(cursor++)/48000));in[j]={v,-v};}check(tone.push(in,n));};
  feed(6144);for(int b=0;b<100;++b){check(tone.render(out,256));double ratio=tone.correctionRatio();for(auto f:out){double ideal=.25*std::sin(2*std::numbers::pi*hz*position/48000);maxError=std::max(maxError,std::abs(double(f.l)-ideal));check(std::abs(f.l+f.r)<1e-7);position+=ratio;}feed(256);}
  check(maxError<.005);std::cout<<"Analytic sine "<<hz<<" Hz: maximum normalized error="<<maxError<<"\n";
 }
 for(auto& f:in)f={.25F,-.5F};
 // 30 seconds each side of a 100 ppm independent producer clock. No device IO.
 for(double ppm:{-100.,0.,100.}){RouteBuffer ring;check(ring.push(in,4608));double credit=0;for(int b=0;b<5625;++b){credit+=256*(1+ppm/1e6);auto n=size_t(credit);credit-=n;check(ring.push(in,n));check(ring.render(out,256));for(auto f:out)check(std::isfinite(f.l)&&std::abs(f.l-.25F)<1e-6);check(ring.fill()<32768);check(ring.correctionRatio()>=.999&&ring.correctionRatio()<=1.001);}check(ring.underruns==0&&ring.overruns==0);}
 // Production resampler: 48 kHz to every supported higher-rate target.
 for(double targetRate:{44100.,88200.,96000.,176400.,192000.}){
  RouteBuffer converted(4096,48000,targetRate);uint64_t cursor=0;double position=15,credit=0,maxError=0;
  auto feed=[&](size_t n){for(size_t j=0;j<n;++j){float v=float(.25*std::sin(2*std::numbers::pi*1000*double(cursor++)/48000));in[j]={v,-v};}check(converted.push(in,n));};
  feed(4608);
  for(int b=0;b<1500;++b){check(converted.render(out,256));double ratio=converted.correctionRatio();
   for(auto f:out){double ideal=.25*std::sin(2*std::numbers::pi*1000*position/48000);maxError=std::max(maxError,std::abs(double(f.l)-ideal));position+=ratio;check(std::abs(f.l+f.r)<1e-7);}
   credit+=256*48000/targetRate;auto n=size_t(credit);credit-=n;feed(n);
  }
  check(maxError<.005&&converted.underruns==0&&converted.overruns==0);
  std::cout<<"48k -> "<<targetRate<<" Hz: peak analytic error="<<maxError<<"\n";
 }
 for(auto& f:in)f={.25F,-.5F};
 // Silence fast path must retain phase/clock behavior and clear old convolution
 // history at an explicit producer stream boundary.
 Frame zeros[8192]{};RouteBuffer silent;check(silent.push(zeros,6144));
 for(int b=0;b<100;b++){check(silent.render(out,256));for(auto f:out)check(f.l==0&&f.r==0);check(silent.push(zeros,256));}
 silent.reset();check(silent.render(out,256));check(silent.fill()==0);
 RouteBuffer starving;check(starving.push(in,6144));for(int i=0;i<23;++i)check(starving.render(out,256));check(!starving.render(out,256));check(starving.underruns==1);for(auto f:out)check(f.l==0&&f.r==0);
 RouteBuffer full;for(int i=0;i<4;++i)check(full.push(in,8192));check(!full.push(in,1));check(full.overruns==1);
 RouteBuffer malformed;in[0].l=NAN;check(!malformed.push(in,256));check(malformed.fill()==0);
 // Real concurrent SPSC, checks stereo ordering and finite interpolation under TSan.
 RouteBuffer concurrent;std::atomic<bool> done{false};std::thread producer([&]{Frame frames[256];for(auto& f:frames)f={.5F,-.5F};for(int i=0;i<1000;){if(concurrent.fill()<8192){assert(concurrent.push(frames,256));++i;}else std::this_thread::yield();}done.store(true,std::memory_order_release);});
 while(!done.load(std::memory_order_acquire)||concurrent.fill()>512){if(concurrent.fill()>=4608){check(concurrent.render(out,256));for(auto f:out)check(std::abs(f.l+f.r)<1e-6);}else if(done.load(std::memory_order_acquire))break;else std::this_thread::yield();}producer.join();
 std::cout<<"Virtual route DSP: "<<assertions<<" assertions PASS (synthetic dual-clock, no hardware)\n";
}
