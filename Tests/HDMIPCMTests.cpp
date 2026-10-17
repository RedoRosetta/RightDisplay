// Copyright © 2026 RedoRosetta
// Licensed under RNSL 1.0; see LICENSE_SCOPE.md.
#include "../RightDisplay/AudioBridgeRealtime/hal.hpp"
#include <iostream>
#include <array>
using namespace bridge;
static unsigned assertions=0;
void check(bool ok){++assertions;if(!ok)throw std::runtime_error("PCM assertion "+std::to_string(assertions));}
uint32_t word(const unsigned char* p,unsigned n,bool big){uint32_t v=0;for(unsigned i=0;i<n;++i)v|=uint32_t(p[i])<<(8*(big?n-1-i:i));return v;}
int main(){try{
 for(unsigned channels:{2U,8U})for(auto [bits,bytes]:{std::pair{16U,2U},{24U,3U},{24U,4U},{32U,4U}})for(bool planar:{false,true})for(bool big:{false,true})for(bool high:{false,true}){
  if(high&&bits==bytes*8)continue;
  auto flags=UInt32(kAudioFormatFlagIsSignedInteger|(bits==bytes*8?kAudioFormatFlagIsPacked:0)|(planar?kAudioFormatFlagIsNonInterleaved:0)|(big?kAudioFormatFlagIsBigEndian:0)|(high?kAudioFormatFlagIsAlignedHigh:0));
  unsigned stride=bytes*(planar?1:channels);AudioStreamBasicDescription f{48000,kAudioFormatLinearPCM,flags,stride,1,stride,channels,bits,0};
  unsigned left=channels==8?6:0,right=channels==8?2:1;auto p=PCMOutput::make(f,left,right);check(bool(p));check(clientFormatAllowed(f));check(physicalFormatAllowed(f));
  struct Buffers{UInt32 count;AudioBuffer buffers[8];} list{};list.count=planar?channels:1;
  std::array<std::array<unsigned char,256>,8> data;for(auto& a:data)a.fill(0xcc);
  for(unsigned i=0;i<list.count;++i)list.buffers[i]={planar?1U:channels,stride*3,data[i].data()};auto* out=reinterpret_cast<AudioBufferList*>(&list);
  Frame input[]={{1,-1},{2,-2},{0,0}};check(p->write(input,3,out));check(!p->write(input,0,nullptr));check(!p->write(nullptr,3,out));
  for(unsigned frame=0;frame<3;++frame)for(unsigned ch=0;ch<channels;++ch){auto* ptr=data[planar?ch:0].data()+frame*stride+(planar?0:ch*bytes);auto got=word(ptr,bytes,big);uint32_t expected=0;
   if(frame<2&&ch==left)expected=uint32_t((uint64_t(1)<<(bits-1))-1);
   if(frame<2&&ch==right)expected=uint32_t(-(int64_t(1)<<(bits-1)));
   if(high)expected<<=bytes*8-bits;else if(bytes<4)expected&=uint32_t((uint64_t(1)<<(bytes*8))-1);
   check(got==expected);
  }
  check(data[0][stride*3]==0xcc);--list.buffers[0].mDataByteSize;check(!p->write(input,3,out));++list.buffers[0].mDataByteSize;
  list.buffers[0].mData=nullptr;check(!p->write(input,3,out));
  Device d;d.uid="synthetic-HDMI";d.alive=1;d.rate=48000;d.channels=channels;d.buffer=d.maxBlock=512;d.transport=kAudioDeviceTransportTypeHDMI;d.stereoMap=true;d.left=left;d.right=right;Stream stream;stream.client=stream.physical=f;d.streams.push_back(stream);d.buffers=planar?std::vector<uint32_t>(channels,1):std::vector<uint32_t>{channels};check(eligibility(d)=="USABLE_DIRECT_PATH");d.stereoMap=false;check(eligibility(d)=="CHANNEL_LAYOUT_UNAVAILABLE");
 }
 for(bool planar:{false,true})for(bool big:{false,true}){
  AudioStreamBasicDescription f{48000,kAudioFormatLinearPCM,UInt32(kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked|(planar?kAudioFormatFlagIsNonInterleaved:0)|(big?kAudioFormatFlagIsBigEndian:0)),planar?4U:8U,1,planar?4U:8U,2,32,0};auto p=PCMOutput::make(f);check(bool(p));unsigned char data[4];p->sample(data,.5F);check(word(data,4,big)==std::bit_cast<uint32_t>(.5F));p->sample(data,0);check(word(data,4,big)==0);p->sample(data,std::numeric_limits<float>::quiet_NaN());check(word(data,4,big)==0);
  f.mBytesPerPacket++;check(!PCMOutput::make(f));f.mBytesPerPacket--;f.mChannelsPerFrame=0;check(!PCMOutput::make(f));f.mChannelsPerFrame=2;f.mBitsPerChannel=64;check(!PCMOutput::make(f));
 }
 std::cout<<"HDMI PCM: "<<assertions<<" assertions PASS; no hardware IO\n";
 }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
