// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
// Hardware-free interposition: these public HAL symbols are defined by this test
// executable. Neither AudioDeviceStart nor any device property reaches CoreAudio.
#include "../RightDisplay/AudioBridgeRealtime/AudioBridgeC.h"
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <vector>
#include <string>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <algorithm>
namespace {
AudioDeviceIOProc callback=nullptr;void* user=nullptr;
uint32_t deviceID=10;double rate=48000;bool changedUID=false,present=true,running=false,badFormat=false,failDestroy=false;
int starts=0,stops=0,destroys=0;
struct Listener {AudioObjectID id;AudioObjectPropertyAddress address;AudioObjectPropertyListenerProc fn;void* context;};
std::vector<Listener> listeners;
AudioStreamBasicDescription format(){AudioStreamBasicDescription a{};a.mSampleRate=rate;a.mFormatID=badFormat?kAudioFormatAC3:kAudioFormatLinearPCM;a.mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked;a.mFramesPerPacket=1;a.mChannelsPerFrame=2;a.mBitsPerChannel=32;a.mBytesPerFrame=8;a.mBytesPerPacket=8;return a;}
std::vector<unsigned char> value(AudioObjectID id,AudioObjectPropertySelector selector){
 auto bytes=[](auto x){std::vector<unsigned char> b(sizeof(x));std::memcpy(b.data(),&x,sizeof(x));return b;};
 if(selector==kAudioHardwarePropertyDevices)return present?bytes(deviceID):std::vector<unsigned char>{};
 if(!present||(id!=deviceID&&id!=90))return {};
 switch(selector){
 case kAudioDevicePropertyDeviceUID:{CFStringRef v=changedUID?CFSTR("changed-uid"):CFSTR("uid-do-not-export-123456");CFRetain(v);return bytes(v);}
 case kAudioObjectPropertyName:{CFStringRef v=CFSTR("Synthetic HDMI");CFRetain(v);return bytes(v);}
 case kAudioDevicePropertyTransportType:return bytes(UInt32(kAudioDeviceTransportTypeHDMI));
 case kAudioDevicePropertyNominalSampleRate:return bytes(rate);
 case kAudioDevicePropertyDeviceIsAlive:return bytes(UInt32(1));
 case kAudioDevicePropertyDeviceIsRunningSomewhere:return bytes(UInt32(running));
 case kAudioDevicePropertyBufferFrameSize:return bytes(UInt32(512));
 case kAudioDevicePropertyLatency:case kAudioDevicePropertySafetyOffset:return bytes(UInt32(10));
 case kAudioDevicePropertyStreams:return bytes(UInt32(90));
 case kAudioStreamPropertyIsActive:return bytes(UInt32(1));
 case kAudioStreamPropertyVirtualFormat:case kAudioStreamPropertyPhysicalFormat:return bytes(format());
 case kAudioDevicePropertyPreferredChannelsForStereo:{UInt32 stereo[2]={1,2};std::vector<unsigned char> b(sizeof(stereo));std::memcpy(b.data(),stereo,sizeof(stereo));return b;}
 case kAudioDevicePropertyStreamConfiguration:{AudioBufferList list{};list.mNumberBuffers=1;list.mBuffers[0].mNumberChannels=2;return bytes(list);}
 default:return {};
 }
}
std::string take(char* c){if(!c)throw std::runtime_error("null JSON");std::string s=c;ABFreeString(c);return s;}
int assertions=0;
void check(bool x){++assertions;if(!x)throw std::runtime_error("assertion "+std::to_string(assertions));}
void render(bool silent=false){float samples[1024];std::fill_n(samples,1024,1);AudioBufferList output{};output.mNumberBuffers=1;output.mBuffers[0]={2,sizeof(samples),samples};AudioTimeStamp timestamp{};AudioBufferList input{};check(callback!=nullptr);check(callback(deviceID,&timestamp,&input,&timestamp,&output,&timestamp,user)==noErr);if(silent)check(std::all_of(samples,samples+1024,[](float v){return v==0;}));}
}
extern "C" Boolean AudioObjectHasProperty(AudioObjectID,const AudioObjectPropertyAddress* a){return a->mSelector!=kAudioDevicePropertyUsesVariableBufferFrameSizes;}
extern "C" OSStatus AudioObjectGetPropertyDataSize(AudioObjectID id,const AudioObjectPropertyAddress* a,UInt32,const void*,UInt32* size){auto v=value(id,a->mSelector);*size=UInt32(v.size());return noErr;}
extern "C" OSStatus AudioObjectGetPropertyData(AudioObjectID id,const AudioObjectPropertyAddress* a,UInt32,const void*,UInt32* size,void* out){auto v=value(id,a->mSelector);if(v.empty()||*size<v.size())return kAudioHardwareBadObjectError;*size=UInt32(v.size());std::memcpy(out,v.data(),v.size());return noErr;}
extern "C" OSStatus AudioObjectAddPropertyListener(AudioObjectID id,const AudioObjectPropertyAddress* a,AudioObjectPropertyListenerProc f,void* c){listeners.push_back({id,*a,f,c});return noErr;}
extern "C" OSStatus AudioObjectRemovePropertyListener(AudioObjectID id,const AudioObjectPropertyAddress* a,AudioObjectPropertyListenerProc f,void* c){std::erase_if(listeners,[&](auto& x){return x.id==id&&x.address.mSelector==a->mSelector&&x.fn==f&&x.context==c;});return noErr;}
extern "C" OSStatus AudioDeviceCreateIOProcID(AudioObjectID,AudioDeviceIOProc f,void* c,AudioDeviceIOProcID* out){callback=f;user=c;*out=f;return noErr;}
extern "C" OSStatus AudioDeviceStart(AudioObjectID,AudioDeviceIOProcID){++starts;running=true;return noErr;}
extern "C" OSStatus AudioDeviceStop(AudioObjectID,AudioDeviceIOProcID){++stops;running=false;return noErr;}
extern "C" OSStatus AudioDeviceDestroyIOProcID(AudioObjectID,AudioDeviceIOProcID){++destroys;if(failDestroy)return kAudioHardwareBadObjectError;callback=nullptr;user=nullptr;return noErr;}
int main(){try{
 check(take(ABCopyDevicesJSON()).find("Synthetic HDMI")!=std::string::npos);
 char* error=nullptr;
 auto absent=ABStartTest("missing","sine",.02F,0,&error);check(!absent&&take(error).find("TARGET_UNAVAILABLE")!=std::string::npos&&starts==0);
 for(double r:{44100.,48000.,88200.,96000.,176400.,192000.}){rate=r;auto s=ABStartTest("uid-do-not-export-123456","sine",.02F,0,&error);check(s&&error==nullptr);render();auto t=take(ABPollJSON(s));check(t.find("\"callbacks\":1")!=std::string::npos&&t.find("\"failure\":\"NONE\"")!=std::string::npos);ABSetGain(s,0,1);render();check(ABStop(s)==0&&listeners.empty());}
 // Equivalent notification: pending callback is silent; fresh equality resumes
 // the same session, never a new epoch or fallback.
 rate=48000;auto eq=ABStartTest("uid-do-not-export-123456","sine",.02F,0,&error);check(eq!=nullptr);render();
 auto before=take(ABPollJSON(eq));
 for(auto selector:std::vector<AudioObjectPropertySelector>{kAudioHardwarePropertyDevices,kAudioStreamPropertyVirtualFormat,kAudioStreamPropertyPhysicalFormat,kAudioDevicePropertyNominalSampleRate}){
  auto listener=std::find_if(listeners.begin(),listeners.end(),[&](auto& l){return l.address.mSelector==selector;});check(listener!=listeners.end());
  listener->fn(listener->id,1,&listener->address,listener->context);render(true);
  auto equivalent=take(ABPollJSON(eq));check(equivalent.find("\"failure\":\"NONE\"")!=std::string::npos);render();
 }
 check(ABStop(eq)==0&&listeners.empty());
 rate=32000;auto unsupported=ABStartTest("uid-do-not-export-123456","sine",.02F,0,&error);check(!unsupported&&take(error).find("UNSUPPORTED_RATE")!=std::string::npos);error=nullptr;
 rate=48000;auto s=ABStartTest("uid-do-not-export-123456","channels",.02F,0,&error);check(s!=nullptr);rate=96000;auto changedRate=take(ABPollJSON(s));check(changedRate.find("FORMAT_CHANGED")!=std::string::npos&&changedRate.find("DIFF_FIELDS=sampleRate,clientFormat,physicalFormat")!=std::string::npos);check(ABStop(s)==0);
 rate=48000;s=ABStartTest("uid-do-not-export-123456","silence",.02F,0,&error);check(s!=nullptr);present=false;check(take(ABPollJSON(s)).find("TARGET_UNAVAILABLE")!=std::string::npos);check(ABStop(s)==0);
 present=true;s=ABStartTest("uid-do-not-export-123456","sine",.02F,0,&error);check(s!=nullptr);deviceID=11;check(take(ABPollJSON(s)).find("FORMAT_CHANGED")!=std::string::npos);check(ABStop(s)==0);
 s=ABStartTest("uid-do-not-export-123456","sine",.02F,0,&error);check(s!=nullptr);changedUID=true;check(take(ABPollJSON(s)).find("TARGET_UNAVAILABLE")!=std::string::npos);render(true);check(ABStop(s)==0);changedUID=false;
 s=ABStartTest("uid-do-not-export-123456","sine",.02F,0,&error);check(s!=nullptr);badFormat=true;check(take(ABPollJSON(s)).find("FORMAT_CHANGED")!=std::string::npos);render(true);check(ABStop(s)==0);badFormat=false;
 check(starts==12&&stops==12&&destroys==12&&listeners.empty());
 s=ABStartTest("uid-do-not-export-123456","sine",.02F,0,&error);check(s!=nullptr);failDestroy=true;
 check(ABStop(s)!=0&&listeners.empty());render(true);
 auto blocked=ABStartTest("uid-do-not-export-123456","sine",.02F,0,&error);
 check(!blocked&&take(error).find("RESTART_REQUIRED")!=std::string::npos&&starts==13);
 std::cout<<"Fake HAL integration: "<<assertions<<" assertions PASS; no real CoreAudio start\n";return 0;
}catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<'\n';return 1;}}
