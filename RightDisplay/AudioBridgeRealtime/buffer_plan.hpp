// Copyright © 2026 RedoRosetta
// First-party portions licensed under RNSL 1.0; see LICENSE_SCOPE.md.
#pragma once
#include <algorithm>
#include <cstdint>
#include <limits>
#include <stdexcept>
namespace bridge {
struct SessionAudioSpec {
 uint32_t rate=0,channels=0,bits=0,bytesPerFrame=0,ioFrames=0,maxCallbackFrames=0;
 bool floating=false,planar=false;
};
struct BufferPlan {
 SessionAudioSpec source,output;
 uint32_t capacity=0,target=4096,readWindow=0,sourceDemand=0,producerReserve=8192;
 static uint64_t add(uint64_t a,uint64_t b){if(b>UINT64_MAX-a)throw std::invalid_argument("BUFFER_ARITHMETIC_OVERFLOW");return a+b;}
 static uint64_t mul(uint64_t a,uint64_t b){if(a&&b>UINT64_MAX/a)throw std::invalid_argument("BUFFER_ARITHMETIC_OVERFLOW");return a*b;}
 static uint64_t ceilDiv(uint64_t a,uint64_t b){if(!b)throw std::invalid_argument("BUFFER_ZERO_DIVISOR");return a/b+(a%b!=0);}
 static bool rateSupported(uint32_t v){return v==44100||v==48000||v==88200||v==96000||v==176400||v==192000;}
 static BufferPlan make(SessionAudioSpec in,SessionAudioSpec out){
  auto valid=[](const SessionAudioSpec& s){return rateSupported(s.rate)&&s.channels==2&&s.bits==32&&s.floating&&s.bytesPerFrame==(s.planar?4U:8U)&&s.ioFrames&&s.maxCallbackFrames>=s.ioFrames&&s.maxCallbackFrames<=8192;};
  if(!valid(in)||!valid(out)||in.rate!=48000||in.planar)throw std::invalid_argument("UNSUPPORTED_SESSION_BUFFER_SPEC");
  BufferPlan p;p.source=in;p.output=out;p.producerReserve=in.maxCallbackFrames;
  // Existing drift correction is bounded to +1000 ppm; no new latency factor.
  auto demand=ceilDiv(mul(mul(out.maxCallbackFrames,in.rate),1001),mul(out.rate,1000));
  p.sourceDemand=uint32_t(demand);
  // Preserve the legacy 4096-frame target and 8192-frame normal read window.
  // Large output periods must still fit target + sinc history + one render.
  auto window=std::max<uint64_t>(8192,add(add(p.target,33),demand));
  // One negotiated producer callback is reserved as burst headroom.
  // The shared protocol21 ring remains unchanged and bounded to 8192 per push.
  // Align required frames to producer I/O, then to a power of two.
  auto required=mul(ceilDiv(add(window,p.producerReserve),in.ioFrames),in.ioFrames);
  uint64_t cap=1;while(cap<required&&cap<32768)cap*=2;
  if(required>32768||cap<required||cap>32768)throw std::invalid_argument("SESSION_BUFFER_CAPACITY_LIMIT");
  p.capacity=uint32_t(cap);p.readWindow=uint32_t(window);return p;
 }
};
}
