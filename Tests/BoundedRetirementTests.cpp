// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#include "../RightDisplay/AudioBridgeRealtime/AudioBridgeC.h"
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <map>
#include <vector>
#include <cstring>
#include <stdexcept>
#include <iostream>
#include <algorithm>
#include <thread>
#include <chrono>
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <sys/mman.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc11-extensions"
#include "../AudioVirtualDevice/Transport/PCMTransport.h"
#pragma clang diagnostic pop
namespace {
bool present=true,duplicate=false,failDestroy=false,compatible=true,physicalGone=false;double rate=48000;uint64_t ticks=1;unsigned starts=0,stops=0,destroys=0;unsigned count=0;
struct Callback{AudioDeviceIOProc fn;void* user;};std::map<unsigned,Callback> callbacks,retired;
struct Listener{unsigned id;AudioObjectPropertyAddress address;AudioObjectPropertyListenerProc fn;void* user;};std::vector<Listener> listeners;
template<class T> std::vector<unsigned char> bytes(T x){std::vector<unsigned char> b(sizeof(x));std::memcpy(b.data(),&x,sizeof(x));return b;}
AudioStreamBasicDescription format(unsigned id){return {id==90?48000:rate,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};}
std::vector<unsigned char> value(unsigned id,AudioObjectPropertySelector s){switch(s){
case kAudioHardwarePropertyDevices:{std::vector<unsigned> ids;if(!physicalGone)ids.push_back(20);if(present)ids.push_back(10);if(duplicate)ids.push_back(11);std::vector<unsigned char>b(ids.size()*4);std::memcpy(b.data(),ids.data(),b.size());return b;}
case kAudioHardwarePropertyDefaultOutputDevice:case kAudioHardwarePropertyDefaultSystemOutputDevice:return bytes(UInt32(20));
case kAudioDevicePropertyDeviceUID:{CFStringRef str=id==10||id==11?CFSTR("RightDisplay.VirtualVolume"):CFSTR("synthetic-physical-output");CFRetain(str);return bytes(str);}
case kAudioDevicePropertyModelUID:{CFStringRef str=compatible?CFSTR("RightDisplay.VirtualVolume.Model.Build21"):CFSTR("obsolete-protocol");CFRetain(str);return bytes(str);}
case kAudioObjectPropertyName:{CFStringRef str=CFSTR("Synthetic device");CFRetain(str);return bytes(str);}
case kAudioDevicePropertyTransportType:return bytes(UInt32(id==10||id==11?kAudioDeviceTransportTypeVirtual:kAudioDeviceTransportTypeHDMI));
case kAudioDevicePropertyNominalSampleRate:return bytes(id==10||id==11?48000.:rate);
case kAudioDevicePropertyDeviceIsAlive:case kAudioDevicePropertyDeviceIsRunningSomewhere:return bytes(UInt32(1));
case kAudioDevicePropertyBufferFrameSize:return bytes(UInt32(512));
case kAudioDevicePropertyLatency:case kAudioDevicePropertySafetyOffset:return bytes(UInt32(0));
case kAudioDevicePropertyStreams:return bytes(UInt32(id==10||id==11?90:91));
case kAudioStreamPropertyIsActive:return bytes(UInt32(1));
case kAudioStreamPropertyVirtualFormat:case kAudioStreamPropertyPhysicalFormat:return bytes(format(id));
case kAudioDevicePropertyPreferredChannelsForStereo:{UInt32 vals[2]={1,2};std::vector<unsigned char>b(sizeof(vals));std::memcpy(b.data(),vals,sizeof(vals));return b;}
case kAudioDevicePropertyStreamConfiguration:{AudioBufferList a{};a.mNumberBuffers=1;a.mBuffers[0].mNumberChannels=2;return bytes(a);}
default:return {};
}}
void check(bool v){++count;if(!v)throw std::runtime_error("virtual facade assertion "+std::to_string(count));}
std::string take(char* p){check(p!=nullptr);std::string s=p;ABFreeString(p);return s;}
void capture();
void render(bool silent=false,bool stale=false){float pcm[1024];std::fill_n(pcm,1024,1);AudioBufferList in{},out{};out.mNumberBuffers=1;out.mBuffers[0]={2,sizeof(pcm),pcm};AudioTimeStamp stamp{};auto cb=(stale?retired:callbacks).at(20);check(cb.fn(20,&stamp,&in,&stamp,&out,&stamp,cb.user)==noErr);if(silent)check(std::all_of(pcm,pcm+1024,[](float v){return v==0;}));else check(std::all_of(pcm,pcm+1024,[](float v){return v>=0&&v<=.5F;}));}
}
extern "C" uint64_t mach_absolute_time(){return ticks;}
extern "C" Boolean AudioObjectHasProperty(AudioObjectID,const AudioObjectPropertyAddress* a){return a->mSelector!=kAudioDevicePropertyUsesVariableBufferFrameSizes;}
extern "C" OSStatus AudioObjectGetPropertyDataSize(AudioObjectID id,const AudioObjectPropertyAddress* a,UInt32,const void*,UInt32* n){*n=UInt32(value(id,a->mSelector).size());return noErr;}
extern "C" OSStatus AudioObjectGetPropertyData(AudioObjectID id,const AudioObjectPropertyAddress* a,UInt32,const void*,UInt32* n,void* out){if(physicalGone&&(id==20||id==91))return kAudioHardwareBadObjectError;auto v=value(id,a->mSelector);if(v.empty()||*n<v.size())return kAudioHardwareBadObjectError;*n=UInt32(v.size());std::memcpy(out,v.data(),v.size());return noErr;}
extern "C" OSStatus AudioObjectAddPropertyListener(AudioObjectID id,const AudioObjectPropertyAddress* a,AudioObjectPropertyListenerProc fn,void* user){listeners.push_back({id,*a,fn,user});return noErr;}
extern "C" OSStatus AudioObjectRemovePropertyListener(AudioObjectID id,const AudioObjectPropertyAddress* a,AudioObjectPropertyListenerProc fn,void* user){std::erase_if(listeners,[&](auto& l){return l.id==id&&l.address.mSelector==a->mSelector&&l.fn==fn&&l.user==user;});return noErr;}
extern "C" OSStatus AudioDeviceCreateIOProcID(AudioObjectID id,AudioDeviceIOProc fn,void* user,AudioDeviceIOProcID* out){callbacks[id]={fn,user};*out=fn;return noErr;}
extern "C" OSStatus AudioDeviceStart(AudioObjectID,AudioDeviceIOProcID){++starts;return noErr;}
extern "C" OSStatus AudioDeviceStop(AudioObjectID,AudioDeviceIOProcID){++stops;return physicalGone?OSStatus(kAudioHardwareBadObjectError):OSStatus(noErr);}
extern "C" OSStatus AudioDeviceDestroyIOProcID(AudioObjectID id,AudioDeviceIOProcID){++destroys;if(failDestroy||physicalGone){retired[id]=callbacks.at(id);return kAudioHardwareBadObjectError;}callbacks.erase(id);return noErr;}
// Fake control plane only; actual anonymous XPC shared-memory boxing/mapping.
static RDTransport* sharedPCM=nullptr;
extern "C" xpc_connection_t xpc_connection_create_mach_service(const char*,dispatch_queue_t q,uint64_t){return xpc_connection_create(nullptr,q);}
extern "C" int xpc_connection_set_peer_code_signing_requirement(xpc_connection_t,const char*){return 0;}
extern "C" void xpc_connection_send_message_with_reply(xpc_connection_t,xpc_object_t m,dispatch_queue_t q,xpc_handler_t reply){
 if(sharedPCM){munmap(sharedPCM,sizeof(*sharedPCM));sharedPCM=nullptr;}
 void* memory=nullptr;auto n=xpc_shmem_map(xpc_dictionary_get_value(m,"memory"),&memory);check(n==rdMappingBytes());sharedPCM=static_cast<RDTransport*>(memory);atomic_store(&sharedPCM->producer,123);atomic_store(&sharedPCM->streaming,1);atomic_store(&sharedPCM->streamEpoch,1);atomic_store(&sharedPCM->active,1);
 dispatch_async(q,^{auto response=xpc_dictionary_create(nullptr,nullptr,0);reply(response);xpc_release(response);});
}
namespace {void capture(){RDFrame pcm[512];for(auto& f:pcm)f={.5F,.5F};check(rdPush(sharedPCM,123,pcm,512,ticks));}}
int main(){try{
 char* error=nullptr;check(take(RVCopyStatusJSON()).find("\"loaded\":true")!=std::string::npos);
 // System route resolves only the explicit physical UID; exactly one output IOProc.
 auto s=ABStartTest("synthetic-physical-output","system",1,0,&error);if(!s)std::cerr<<"start error: "<<(error?error:"none")<<"\n";check(s&&starts==1&&callbacks.size()==1&&callbacks.count(20)==1&&callbacks.count(10)==0);
 for(int i=0;i<10;++i)capture();for(int i=0;i<12;++i){render();capture();}check(take(ABPollJSON(s)).find("\"failure\":\"NONE\"")!=std::string::npos);
 float zeroGain=0;uint32_t bits;memcpy(&bits,&zeroGain,4);atomic_store(&sharedPCM->volumeBits,bits);render();capture();render(true);capture();
 rate=96000;check(take(ABPollJSON(s)).find("FORMAT_CHANGED")!=std::string::npos);render(true);check(ABStop(s)==0&&callbacks.empty()&&listeners.empty());
 rate=48000;s=ABStartTest("synthetic-physical-output","system",1,0,&error);check(s!=nullptr);atomic_store(&sharedPCM->active,0);render(true);check(ABStop(s)==0);
 for(double r:{44100.,48000.,88200.,96000.,176400.,192000.}){rate=r;s=ABStartTest("synthetic-physical-output","system",1,0,&error);check(s!=nullptr);for(int i=0;i<10;i++)capture();double credit=0;for(int i=0;i<80;i++){render();credit+=512*48000/r;while(credit>=512){capture();credit-=512;}}check(take(ABPollJSON(s)).find("\"failure\":\"NONE\"")!=std::string::npos);check(ABStop(s)==0);}
 rate=48000;s=ABStartTest("synthetic-physical-output","system",1,0,&error);check(s);for(auto l:listeners)if(l.address.mSelector==kAudioHardwarePropertyDevices)l.fn(l.id,1,&l.address,l.user);render(true);check(ABStop(s)==0);
 s=ABStartTest("synthetic-physical-output","system",1,0,&error);check(s);atomic_store(&sharedPCM->producer,124);render(true);check(ABStop(s)==0);
 check(!ABStartTest("missing-physical-UID","system",1,0,&error));check(take(error).find("TARGET_UNAVAILABLE")!=std::string::npos);

 // Device withdrawal must retire the endpoint, release ownership, then allow a
 // fresh same-UID session. Deliberately deliver stale IO and listener afterward.
 s=ABStartTest("synthetic-physical-output","system",1,0,&error);check(s);
 auto lateListener=listeners.front();physicalGone=true;
 check(take(ABPollJSON(s)).find("TARGET_UNAVAILABLE")!=std::string::npos);
 check(ABStop(s)==0);render(true,true);
 check(lateListener.fn(lateListener.id,1,&lateListener.address,lateListener.user)==noErr);
 physicalGone=false;s=ABStartTest("synthetic-physical-output","system",1,0,&error);check(s);
 for(int i=0;i<10;++i)capture();render();render(true,true);
 check(take(ABPollJSON(s)).find("\"failure\":\"NONE\"")!=std::string::npos);check(ABStop(s)==0);
 // Quarantine has one endpoint from the first removal above; permit 31
 // more, then fail closed on capacity exhaustion, never reuse a stale endpoint.
 for(int i=0;i<32;++i){
  s=ABStartTest("synthetic-physical-output","system",1,0,&error);check(s);
  physicalGone=true;check(take(ABPollJSON(s)).find("TARGET_UNAVAILABLE")!=std::string::npos);
  check((ABStop(s)==0)==(i<31));render(true,true);physicalGone=false;
 }
 check(!ABStartTest("synthetic-physical-output","system",1,0,&error));check(take(error).find("RESTART_REQUIRED")!=std::string::npos);
 if(sharedPCM)munmap(sharedPCM,sizeof(*sharedPCM));std::cout<<"Direct-output fake HAL: "<<count<<" assertions PASS; real anonymous memory, no hardware IO\n";
 }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
