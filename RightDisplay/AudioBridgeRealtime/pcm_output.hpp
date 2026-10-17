// Copyright © 2026 RedoRosetta
// Licensed under RNSL 1.0; see LICENSE_SCOPE.md.
#pragma once
#include "core.hpp"
#include <CoreAudio/CoreAudio.h>
#include <optional>
#include <algorithm>
#include <bit>
namespace bridge {
// Immutable session-local encoder. HAL owns its current device format; this
// adapter never changes device or global Audio MIDI properties.
struct PCMOutput {
 uint32_t channels{},bits{},bytes{},stride{},left{},right{};
 bool planar{},floating{},bigEndian{},high{};
 static std::optional<PCMOutput> make(const AudioStreamBasicDescription& a,uint32_t l=0,uint32_t r=1) noexcept {
  PCMOutput p;p.channels=a.mChannelsPerFrame;p.bits=a.mBitsPerChannel;
  p.planar=a.mFormatFlags&kAudioFormatFlagIsNonInterleaved;
  p.floating=a.mFormatFlags&kAudioFormatFlagIsFloat;
  p.bigEndian=a.mFormatFlags&kAudioFormatFlagIsBigEndian;
  p.high=a.mFormatFlags&kAudioFormatFlagIsAlignedHigh;p.left=l;p.right=r;
  constexpr UInt32 allowed=kAudioFormatFlagIsFloat|kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked|kAudioFormatFlagIsAlignedHigh|kAudioFormatFlagIsNonInterleaved|kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsNonMixable;
  if(a.mFormatID!=kAudioFormatLinearPCM||!std::isfinite(a.mSampleRate)||a.mSampleRate<8000||a.mSampleRate>192000||!p.channels||p.channels>64||l>=p.channels||r>=p.channels||l==r||a.mFramesPerPacket!=1||a.mBytesPerPacket!=a.mBytesPerFrame||(a.mFormatFlags&~allowed))return {};
  const auto divisor=p.planar?1U:p.channels;
  if(!a.mBytesPerFrame||a.mBytesPerFrame%divisor)return {};
  p.bytes=a.mBytesPerFrame/divisor;p.stride=a.mBytesPerFrame;
  if(p.floating){if(p.bits!=32||p.bytes!=4||p.high||(a.mFormatFlags&kAudioFormatFlagIsSignedInteger))return {};}
  else if(!(a.mFormatFlags&kAudioFormatFlagIsSignedInteger)||!((p.bits==16&&p.bytes==2)||(p.bits==24&&(p.bytes==3||p.bytes==4))||(p.bits==32&&p.bytes==4)))return {};
  const bool packed=a.mFormatFlags&kAudioFormatFlagIsPacked;
  if(p.bits==p.bytes*8){if(!packed||p.high)return {};}
  else if(packed)return {};
  return p;
 }
 void sample(unsigned char* out,float value)const noexcept {
  // Non-finite source data is silent; integer limits are saturated before cast.
  double v=std::isfinite(value)?std::clamp(double(value),-1.,1.):0.;uint32_t word;
  if(floating){float f=float(v);word=std::bit_cast<uint32_t>(f);}
  else {const int64_t scale=int64_t(1)<<(bits-1);int64_t n=std::clamp(int64_t(v*double(scale)),-scale,scale-1);word=uint32_t(n);if(high)word<<=(bytes*8-bits);}
  for(uint32_t i=0;i<bytes;++i)out[i]=static_cast<unsigned char>(word>>(8*(bigEndian?bytes-1-i:i)));
 }
 size_t frames(const AudioBufferList* out,size_t maximum)const noexcept {
  if(!stride||!out||out->mNumberBuffers!=(planar?channels:1U))return 0;
  size_t n=0;for(uint32_t i=0;i<out->mNumberBuffers;++i){auto& b=out->mBuffers[i];
   if(!b.mData||b.mNumberChannels!=(planar?1U:channels)||b.mDataByteSize%stride)return 0;
   auto count=b.mDataByteSize/stride;if(!count||count>maximum||(i&&count!=n))return 0;n=count;
  }return n;
 }
 bool write(const Frame* input,size_t n,AudioBufferList* out)const noexcept {
  if(!input||!n||frames(out,n)!=n)return false;
  // All other channels, including padding, stay silent. Gain is already applied
  // exactly once by Playback, preserving mute, unity and existing gain ramps.
  for(uint32_t i=0;i<out->mNumberBuffers;++i)std::memset(out->mBuffers[i].mData,0,out->mBuffers[i].mDataByteSize);
  for(size_t i=0;i<n;++i){
   auto* l=static_cast<unsigned char*>(out->mBuffers[planar?left:0].mData)+i*stride+(planar?0:left*bytes);
   auto* r=static_cast<unsigned char*>(out->mBuffers[planar?right:0].mData)+i*stride+(planar?0:right*bytes);
   sample(l,input[i].l);sample(r,input[i].r);
  }return true;
 }
};
}
