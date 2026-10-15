// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#pragma once
#include "core.hpp"
#include <algorithm>
#include <array>
#include <numbers>
namespace bridge {
// SPSC, preallocated polyphase windowed-sinc interpolation. A bounded +/-1000 ppm
// correction follows occupancy around an explicit input/output rate ratio.
// This version supports equal-rate, upsampling and filtered downsampling; never changes HAL formats.
class RouteBuffer {
 static constexpr size_t capacity=32768, taps=32, phases=1024;
 std::unique_ptr<Frame[]> data{new Frame[capacity]};
 std::unique_ptr<uint64_t[]> nonzeroPrefix{new uint64_t[capacity]};uint64_t nonzeroTotal=0;
 std::array<std::array<double,taps>,phases+1> coefficients{};
 alignas(64) std::atomic<uint64_t> written{0},read{0};
 double fraction=0,ratio=1; const double nominalRatio; bool primed=false;
public:
 const size_t target;
 std::atomic<uint64_t> underruns{0},overruns{0};
 explicit RouteBuffer(size_t desired=4096,double inputRate=48000,double outputRate=48000):nominalRatio(inputRate/outputRate),target(desired) {
  if(!std::isfinite(nominalRatio)||nominalRatio<.25||nominalRatio>48000.0/44100.0)throw std::invalid_argument("unsupported route rate ratio");
  ratio=nominalRatio;
  if(desired<64||desired>8192)throw std::invalid_argument("route prefill");
  for(size_t phase=0;phase<=phases;++phase){double sum=0;for(size_t j=0;j<taps;++j){double x=double(j)-15-double(phase)/phases;
   double cutoff=std::min(1.0,1.0/(nominalRatio*1.001));
   double sinc=std::abs(x)<1e-12 ? cutoff : std::sin(std::numbers::pi*x*cutoff)/(std::numbers::pi*x);
   double window=std::abs(x)>=16 ? 0 : .5+.5*std::cos(std::numbers::pi*x/16);
   coefficients[phase][j]=sinc*window;sum+=sinc*window;
  }for(auto& v:coefficients[phase])v/=sum;}
 }
 size_t fill()const noexcept {auto r=read.load(std::memory_order_acquire),w=written.load(std::memory_order_acquire);return w>=r&&w-r<=capacity ? size_t(w-r):capacity;}
 bool push(const Frame* input,size_t count)noexcept {auto w=written.load(std::memory_order_relaxed),r=read.load(std::memory_order_acquire);if(count>8192||count>capacity-(w-r)){overruns.fetch_add(1);return false;}
  for(size_t i=0;i<count;++i){if(!std::isfinite(input[i].l)||!std::isfinite(input[i].r))return false;nonzeroPrefix[(w+i)&(capacity-1)]=nonzeroTotal;nonzeroTotal+=(input[i].l!=0||input[i].r!=0);data[(w+i)&(capacity-1)]=input[i];}written.store(w+count,std::memory_order_release);return true;
 }
 bool render(Frame* out,size_t count)noexcept {
  std::fill_n(out,count,Frame{});if(count>8192)return false;
  auto r=read.load(std::memory_order_relaxed),w=written.load(std::memory_order_acquire);
  if(!primed){if(w-r<target+taps+size_t(std::ceil(count*nominalRatio)))return true;primed=true;}
  double demand=nominalRatio*(1+std::clamp((double(w-r)-double(target+taps)-count*nominalRatio)*0.00000005,-.001,.001));
  ratio += (demand-ratio)*.02;
  if(w-r<count*nominalRatio*1.001+taps+1){underruns.fetch_add(1);return false;}
  for(size_t i=0;i<count;++i){double phase=fraction*phases;size_t p=size_t(phase);double mix=phase-double(p);double l=0,rr=0;
   auto last=data[(r+taps-1)&(capacity-1)];bool silent=nonzeroPrefix[r&(capacity-1)]==nonzeroPrefix[(r+taps-1)&(capacity-1)]&&last.l==0&&last.r==0;
   if(!silent)for(size_t j=0;j<taps;++j){auto f=data[(r+j)&(capacity-1)];double c=coefficients[p][j]*(1-mix)+coefficients[p+1][j]*mix;l+=f.l*c;rr+=f.r*c;}
   out[i]={float(l),float(rr)};fraction+=ratio;auto advance=uint64_t(fraction);fraction-=double(advance);r+=advance;
  }read.store(r,std::memory_order_release);return true;
 }
 void reset()noexcept {read.store(written.load(std::memory_order_acquire),std::memory_order_release);fraction=0;ratio=nominalRatio;primed=false;}
 double correctionRatio()const noexcept{return ratio;} // consumer only
};
}
