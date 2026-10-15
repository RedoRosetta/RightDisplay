// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#include "hal.hpp"
#include "playback.hpp"
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <bit>
#include <iostream>
#include <cstdlib>
#include <algorithm>
#include <thread>
#include <chrono>
#include <csignal>
#include <poll.h>
#include <unistd.h>
#include <fcntl.h>
#include <array>
namespace bridge {
namespace {
AudioObjectPropertyAddress address(AudioObjectPropertySelector s,AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal){return {s,scope,kAudioObjectPropertyElementMain};}
template<class T> bool get(AudioObjectID id,AudioObjectPropertySelector s,T& value,AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal){auto a=address(s,scope);UInt32 bytes=sizeof(T);return AudioObjectGetPropertyData(id,&a,0,nullptr,&bytes,&value)==noErr&&bytes==sizeof(T);}
template<class T> std::vector<T> array(AudioObjectID id,AudioObjectPropertySelector s,AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal){auto a=address(s,scope);UInt32 bytes=0;if(AudioObjectGetPropertyDataSize(id,&a,0,nullptr,&bytes)!=noErr||bytes>1048576||bytes%sizeof(T))throw std::runtime_error("property array unavailable");std::vector<T> result(bytes/sizeof(T));UInt32 got=bytes;if(bytes&&AudioObjectGetPropertyData(id,&a,0,nullptr,&got,result.data())!=noErr)throw std::runtime_error("property array changed");if(got>bytes||got%sizeof(T))throw std::runtime_error("property array size invalid");result.resize(got/sizeof(T));return result;}
std::string stringValue(AudioObjectID id,AudioObjectPropertySelector s){CFStringRef value=nullptr;if(!get(id,s,value)||!value)return {};char text[4096];bool ok=CFStringGetCString(value,text,sizeof(text),kCFStringEncodingUTF8);CFRelease(value);return ok?text:"";}
std::optional<uint32_t> optional(AudioObjectID id,AudioObjectPropertySelector s,AudioObjectPropertyScope scope){uint32_t v=0;return get(id,s,v,scope)?std::optional<uint32_t>(v):std::nullopt;}
Device inspect(AudioDeviceID id){Device d;d.id=id;d.uid=stringValue(id,kAudioDevicePropertyDeviceUID);d.name=stringValue(id,kAudioObjectPropertyName);get(id,kAudioDevicePropertyTransportType,d.transport);get(id,kAudioDevicePropertyNominalSampleRate,d.rate);get(id,kAudioDevicePropertyDeviceIsAlive,d.alive);get(id,kAudioDevicePropertyDeviceIsRunningSomewhere,d.running);get(id,kAudioDevicePropertyBufferFrameSize,d.buffer);d.maxBlock=d.buffer;uint32_t largest=0;if(get(id,kAudioDevicePropertyUsesVariableBufferFrameSizes,largest)&&largest)d.maxBlock=largest;
 d.latency=optional(id,kAudioDevicePropertyLatency,kAudioObjectPropertyScopeOutput);d.safety=optional(id,kAudioDevicePropertySafetyOffset,kAudioObjectPropertyScopeOutput);
 UInt32 stereo[2]{};auto stereoAddress=address(kAudioDevicePropertyPreferredChannelsForStereo,kAudioObjectPropertyScopeOutput);UInt32 count=sizeof(stereo);d.stereoMap=AudioObjectGetPropertyData(id,&stereoAddress,0,nullptr,&count,stereo)==noErr&&count==sizeof(stereo)&&stereo[0]==1&&stereo[1]==2;
 auto a=address(kAudioDevicePropertyStreamConfiguration,kAudioObjectPropertyScopeOutput);UInt32 bytes=0;if(AudioObjectGetPropertyDataSize(id,&a,0,nullptr,&bytes)==noErr&&bytes>=offsetof(AudioBufferList,mBuffers)&&bytes<=65536){std::vector<unsigned char> storage(bytes);UInt32 got=bytes;if(AudioObjectGetPropertyData(id,&a,0,nullptr,&got,storage.data())==noErr){auto* list=reinterpret_cast<AudioBufferList*>(storage.data());if(got>=offsetof(AudioBufferList,mBuffers)&&got<=bytes&&list->mNumberBuffers<=(got-offsetof(AudioBufferList,mBuffers))/sizeof(AudioBuffer)){for(UInt32 i=0;i<list->mNumberBuffers;++i){d.buffers.push_back(list->mBuffers[i].mNumberChannels);d.channels+=list->mBuffers[i].mNumberChannels;}}}}
 for(auto s:array<AudioStreamID>(id,kAudioDevicePropertyStreams,kAudioObjectPropertyScopeOutput)){uint32_t active=1;if(!get(s,kAudioStreamPropertyIsActive,active))throw std::runtime_error("stream activity unavailable");if(!active)continue;Stream st;st.id=s;get(s,kAudioStreamPropertyVirtualFormat,st.client);get(s,kAudioStreamPropertyPhysicalFormat,st.physical);st.latency=optional(s,kAudioStreamPropertyLatency,kAudioObjectPropertyScopeGlobal);d.streams.push_back(st);}return d;}
void zero(AudioBufferList* out)noexcept{if(!out)return;for(UInt32 i=0;i<out->mNumberBuffers;++i)if(out->mBuffers[i].mData)std::memset(out->mBuffers[i].mData,0,out->mBuffers[i].mDataByteSize);}
struct Context {Playback engine;const AudioDeviceID id;std::vector<Frame> scratch;bool planar;uint64_t deadlineHost=0;std::atomic<uint64_t> changeTime{0},observationSequence{0},validatedSequence{0},validationSilencedCallbacks{0};std::atomic<uint32_t> changeSelector{0};Context(const Device& d,const std::string& f,float gain,size_t target,size_t cap,uint64_t epoch):engine(f,d.rate,gain,epoch),id(d.id),scratch(d.maxBlock),planar((d.streams[0].client.mFormatFlags&kAudioFormatFlagIsNonInterleaved)!=0){(void)cap;(void)target;}};
// Stable callback endpoint: removed-device callbacks may arrive late. The
// endpoint remains allocated, but can no longer reach a retired Context.
struct CallbackAnchor {
 std::atomic<Context*> context{nullptr};std::atomic<uint32_t> readers{0};
};
struct CallbackAccess {
 CallbackAnchor& anchor;Context* context;
 explicit CallbackAccess(void* user)noexcept:anchor(*static_cast<CallbackAnchor*>(user)){
  anchor.readers.fetch_add(1);context=anchor.context.load();
 }
 ~CallbackAccess(){anchor.readers.fetch_sub(1);}
};
// Control queue owns this bounded process-lifetime quarantine. Never reuse an
// endpoint which CoreAudio may still call. Exhaustion retains restart-required.
std::array<CallbackAnchor*,32> retiredAnchors{};size_t retiredAnchorCount=0;
OSStatus callback(AudioDeviceID id,const AudioTimeStamp*,const AudioBufferList*,const AudioTimeStamp*,AudioBufferList* out,const AudioTimeStamp* stamp,void* user)noexcept{zero(out);CallbackAccess access(user);if(!access.context)return noErr;auto& c=*access.context;if(c.deadlineHost&&mach_absolute_time()>=c.deadlineHost){c.engine.gate.invalidate(Failure::Stopped);return noErr;}if(id!=c.id||!c.engine.gate.accepts(c.engine.epoch)){c.engine.telemetry.staleCallbacks.fetch_add(1,std::memory_order_relaxed);return noErr;}if(!out||out->mNumberBuffers!=(c.planar?2U:1U)){c.engine.gate.invalidate(Failure::InvalidBuffer);return noErr;}const auto observation=c.observationSequence.load(std::memory_order_acquire);if(observation!=c.validatedSequence.load(std::memory_order_acquire)){c.validationSilencedCallbacks.fetch_add(1,std::memory_order_relaxed);return noErr;}size_t frames=0;for(UInt32 i=0;i<out->mNumberBuffers;++i){const auto& b=out->mBuffers[i];size_t stride=c.planar?sizeof(float):sizeof(Frame);size_t n=b.mDataByteSize/stride;if(!b.mData||b.mNumberChannels!=(c.planar?1U:2U)||b.mDataByteSize%stride||!n||n>c.scratch.size()||(i&&n!=frames)){c.engine.gate.invalidate(Failure::InvalidBuffer);return noErr;}frames=n;}
 uint64_t host=mach_absolute_time();if(stamp&&(stamp->mFlags&kAudioTimeStampHostTimeValid)){c.engine.telemetry.hostTime.store(stamp->mHostTime,std::memory_order_relaxed);if(stamp->mFlags&kAudioTimeStampSampleTimeValid){c.engine.telemetry.sampleBits.store(std::bit_cast<uint64_t>(stamp->mSampleTime),std::memory_order_relaxed);c.engine.telemetry.sampleTimeCount.fetch_add(1,std::memory_order_relaxed);}c.engine.telemetry.timestampCount.fetch_add(1,std::memory_order_relaxed);}
 if(!c.engine.render(c.scratch.data(),frames,c.engine.epoch,host))return noErr;
 if(c.planar){auto* l=static_cast<float*>(out->mBuffers[0].mData);auto* r=static_cast<float*>(out->mBuffers[1].mData);for(size_t i=0;i<frames;++i){l[i]=c.scratch[i].l;r[i]=c.scratch[i].r;}}else std::memcpy(out->mBuffers[0].mData,c.scratch.data(),frames*sizeof(Frame));
 if(!c.engine.gate.accepts(c.engine.epoch)||observation!=c.observationSequence.load(std::memory_order_acquire))zero(out);return noErr;}
OSStatus changed(AudioObjectID,UInt32 n,const AudioObjectPropertyAddress* addresses,void* user)noexcept{
 CallbackAccess access(user);if(!access.context)return noErr;auto& c=*access.context;if(n){c.changeSelector.store(addresses[0].mSelector);c.changeTime.store(mach_absolute_time());c.observationSequence.fetch_add(1,std::memory_order_release);}return noErr;
}
// Notifications dirty observation, never manufacture a route generation. Output
// stays silent while fresh validation is pending, including an event during IO.
bool sameFormat(const AudioStreamBasicDescription& a,const AudioStreamBasicDescription& b)noexcept{
 return a.mSampleRate==b.mSampleRate&&a.mFormatID==b.mFormatID&&a.mFormatFlags==b.mFormatFlags&&a.mBytesPerPacket==b.mBytesPerPacket&&a.mFramesPerPacket==b.mFramesPerPacket&&a.mBytesPerFrame==b.mBytesPerFrame&&a.mChannelsPerFrame==b.mChannelsPerFrame&&a.mBitsPerChannel==b.mBitsPerChannel;
}
bool sameImpl(const Device& a,const Device& b){if(a.id!=b.id||a.uid!=b.uid||a.transport!=b.transport||a.rate!=b.rate||a.buffer!=b.buffer||a.maxBlock!=b.maxBlock||a.stereoMap!=b.stereoMap||a.buffers!=b.buffers||a.streams.size()!=b.streams.size())return false;for(size_t i=0;i<a.streams.size();++i){const auto& x=a.streams[i];const auto& y=b.streams[i];if(x.id!=y.id||!sameFormat(x.client,y.client)||!sameFormat(x.physical,y.physical))return false;}return true;}

}
bool supportedRate(double r)noexcept{return r==44100||r==48000||r==88200||r==96000||r==176400||r==192000;}
bool physicalTransport(uint32_t t)noexcept {switch(t){case kAudioDeviceTransportTypeBuiltIn:case kAudioDeviceTransportTypePCI:case kAudioDeviceTransportTypeUSB:case kAudioDeviceTransportTypeFireWire:case kAudioDeviceTransportTypeBluetooth:case kAudioDeviceTransportTypeBluetoothLE:case kAudioDeviceTransportTypeHDMI:case kAudioDeviceTransportTypeDisplayPort:case kAudioDeviceTransportTypeThunderbolt:return true;default:return false;}}
bool clientFormatAllowed(const AudioStreamBasicDescription& a)noexcept {bool planar=(a.mFormatFlags&kAudioFormatFlagIsNonInterleaved)!=0;return a.mFormatID==kAudioFormatLinearPCM&&supportedRate(a.mSampleRate)&&a.mChannelsPerFrame==2&&a.mBitsPerChannel==32&&a.mFramesPerPacket==1&&a.mBytesPerFrame==(planar?4U:8U)&&a.mBytesPerPacket==a.mBytesPerFrame&&!(a.mFormatFlags&~UInt32(kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked|kAudioFormatFlagIsNonInterleaved))&&(a.mFormatFlags&kAudioFormatFlagIsFloat)&&(a.mFormatFlags&kAudioFormatFlagIsPacked)&&!(a.mFormatFlags&(kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsAlignedHigh|kAudioFormatFlagIsNonMixable));}
bool physicalFormatAllowed(const AudioStreamBasicDescription& a)noexcept {
 bool planar=(a.mFormatFlags&kAudioFormatFlagIsNonInterleaved)!=0;
 unsigned channels=planar?1:2;unsigned bits=a.mBitsPerChannel;unsigned bytes=a.mBytesPerFrame/channels;
 bool fp=(a.mFormatFlags&kAudioFormatFlagIsFloat)!=0;
 return a.mFormatID==kAudioFormatLinearPCM&&supportedRate(a.mSampleRate)&&a.mChannelsPerFrame==2&&a.mFramesPerPacket==1
 &&(bits==16||bits==24||bits==32)&&a.mBytesPerFrame%channels==0&&a.mBytesPerPacket==a.mBytesPerFrame
 &&(bytes==2||bytes==3||bytes==4)&&bits<=bytes*8&&!(a.mFormatFlags&kAudioFormatFlagIsBigEndian)
 &&(fp ? bits==32&&bytes==4 : bool(a.mFormatFlags&kAudioFormatFlagIsSignedInteger))
 &&!(a.mFormatFlags&~UInt32(kAudioFormatFlagIsFloat|kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked|kAudioFormatFlagIsAlignedHigh|kAudioFormatFlagIsNonInterleaved|kAudioFormatFlagIsNonMixable))
 &&(!fp||!(a.mFormatFlags&(kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsAlignedHigh)))
 &&((bits==bytes*8&&bool(a.mFormatFlags&kAudioFormatFlagIsPacked))||(bits==24&&bytes==4&&!fp&&!(a.mFormatFlags&kAudioFormatFlagIsPacked)));
}
bool layoutAllowed(const std::vector<uint32_t>& v,bool planar)noexcept{return planar?v.size()==2&&v[0]==1&&v[1]==1:v.size()==1&&v[0]==2;}

std::string eligibility(const Device& d){if(d.uid.empty()||!d.alive)return "TARGET_UNAVAILABLE";if(!supportedRate(d.rate))return "UNSUPPORTED_RATE";if(!physicalTransport(d.transport))return "UNSUPPORTED_TRANSPORT";if(d.channels!=2||!d.stereoMap||d.streams.size()!=1)return "UNSUPPORTED_STEREO_LAYOUT";if(d.streams[0].client.mSampleRate!=d.rate||d.streams[0].physical.mSampleRate!=d.rate||!clientFormatAllowed(d.streams[0].client)||!physicalFormatAllowed(d.streams[0].physical))return "UNSUPPORTED_PCM_FORMAT";if(!layoutAllowed(d.buffers,(d.streams[0].client.mFormatFlags&kAudioFormatFlagIsNonInterleaved)!=0))return "UNSUPPORTED_BUFFER_LAYOUT";if(!d.buffer||d.maxBlock<d.buffer||d.maxBlock>65536)return "UNSUPPORTED_BUFFER_SIZE";return "USABLE_DIRECT_PATH";}
std::vector<Device> devices(){std::vector<Device> result;for(auto id:array<AudioDeviceID>(kAudioObjectSystemObject,kAudioHardwarePropertyDevices)){try{auto d=inspect(id);if(d.channels)result.push_back(std::move(d));}catch(const std::exception& e){std::cerr<<"device "<<id<<" inspection failed: "<<e.what()<<'\n';}}return result;}
bool contextMatches(const Device& a,const Device& b){return sameImpl(a,b);}
Device resolveFrom(const std::vector<Device>& all,const std::string& uid){if(uid.empty())throw std::runtime_error("explicit UID required");std::optional<Device> found;for(auto d:all)if(d.uid==uid){if(found)throw std::runtime_error("AMBIGUOUS_UID");found=std::move(d);}if(!found)throw std::runtime_error("TARGET_UNAVAILABLE");return *found;}
void validationTrace(const char* event,uint64_t notification=0,uint64_t observation=0,uint32_t selector=0){
#ifndef NDEBUG
 static const bool enabled=[] {auto p=std::getenv("RIGHTDISPLAY_PERF_TRACE");return p&&std::strcmp(p,"1")==0;}();
 if(enabled)std::cerr<<event<<" machTicks="<<mach_absolute_time()<<" notificationMach="<<notification<<" observationGeneration="<<observation<<" selector="<<selector<<'\n';
#else
 (void)event;(void)notification;(void)observation;(void)selector;
#endif
}
Device resolve(const std::string& uid){validationTrace("AUDIO_UID_RESOLVE");return resolveFrom(devices(),uid);}

}

#include "AudioBridgeC.h"
#include <sstream>
#include <iomanip>
#include <cstdlib>
namespace bridge {
namespace {
std::atomic<uint64_t> nextEpoch{1};
// Prevent repeated starts after an uncertain native deregistration; retained context
// stays silent until process exit, rather than accumulating abandoned live callbacks.
bool teardownUncertain=false;
std::string quote(const std::string& value){std::ostringstream s;s<<'"';for(unsigned char c:value){if(c=='"'||c=='\\')s<<'\\'<<char(c);else if(c<32)s<<"\\u"<<std::hex<<std::setw(4)<<std::setfill('0')<<unsigned(c)<<std::dec;else s<<char(c);}s<<'"';return s.str();}
std::string optionalJSON(std::optional<uint32_t> v){return v?std::to_string(*v):"null";}
char* copied(const std::string& s){return strdup(s.c_str());}
std::string deviceJSON(const Device& d){std::ostringstream s;s<<"{\"uid\":"<<quote(d.uid)<<",\"deviceID\":"<<d.id<<",\"name\":"<<quote(d.name)<<",\"transport\":"<<d.transport<<",\"rate\":"<<d.rate<<",\"channels\":"<<d.channels<<",\"buffer\":"<<d.buffer<<",\"maxBlock\":"<<d.maxBlock<<",\"latency\":"<<optionalJSON(d.latency)<<",\"safety\":"<<optionalJSON(d.safety)<<",\"eligibility\":"<<quote(eligibility(d));if(!d.streams.empty()){auto& a=d.streams[0].physical;s<<",\"physicalBits\":"<<a.mBitsPerChannel<<",\"physicalFloat\":"<<((a.mFormatFlags&kAudioFormatFlagIsFloat)?"true":"false")<<",\"streamLatency\":"<<optionalJSON(d.streams[0].latency);}s<<"}";return s.str();}
}
}
struct ABSession {
 bridge::Device device;
 std::unique_ptr<bridge::Context> context;
 std::unique_ptr<bridge::CallbackAnchor> anchor=std::make_unique<bridge::CallbackAnchor>();
 AudioDeviceIOProcID proc=nullptr;
 std::vector<std::pair<AudioObjectID,AudioObjectPropertyAddress>> listeners;
 bool started=false;
 std::chrono::steady_clock::time_point progress=std::chrono::steady_clock::now();
 uint64_t lastCallbacks=0;
 std::string failureDetail;
 explicit ABSession(bridge::Device d,const std::string& f,float gain,int muted):device(std::move(d)){
   size_t target=std::max<size_t>(512,device.maxBlock),capacity=4096;
   while(capacity<target+device.maxBlock)capacity*=2;
   bridge::validationTrace("AUDIO_CONTEXT_BUILD");
   context=std::make_unique<bridge::Context>(device,f,muted?0:gain,target,capacity,bridge::nextEpoch.fetch_add(1));
   anchor->context.store(context.get());
   context->engine.commandGain(gain);context->engine.commandMute(muted!=0);
   listeners.reserve(8+2*device.streams.size());
 }
 bool removedDevice()const noexcept{
   try{
    auto ids=bridge::array<AudioDeviceID>(kAudioObjectSystemObject,kAudioHardwarePropertyDevices);
    if(std::find(ids.begin(),ids.end(),device.id)!=ids.end())return false;
    auto property=bridge::address(kAudioDevicePropertyDeviceUID);CFStringRef uid=nullptr;UInt32 bytes=sizeof(uid);
    auto status=AudioObjectGetPropertyData(device.id,&property,0,nullptr,&bytes,&uid);
    if(status==noErr&&uid)CFRelease(uid);
    return status==kAudioHardwareBadObjectError||status==kAudioHardwareBadDeviceError;
   }catch(...){return false;} // enumeration failure is never proof of removal
 }
 bool close()noexcept{
   bridge::validationTrace("AUDIO_ROUTE_STOP");
   auto& c=*context;
   // Seq_cst reader entry and pointer withdrawal order the last possible access.
   // Only this non-RT control path waits; late callbacks see null and stay silent.
   anchor->context.store(nullptr);
   auto deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(100);
   while(anchor->readers.load()&&std::chrono::steady_clock::now()<deadline)std::this_thread::sleep_for(std::chrono::milliseconds(1));
   bool drained=anchor->readers.load()==0;
   // If a callback has not returned, do not mutate or release its transport.
   if(!drained){bridge::teardownUncertain=true;context.release();anchor.release();return false;}
   bool removed=bridge::Failure(c.engine.gate.failure.load())==bridge::Failure::TargetUnavailable&&removedDevice();
   c.engine.stop();bool ok=true,missingError=false;
   auto accepted=[&](OSStatus status,bool mayBeRemoved){
    if(status==noErr)return true;
    if(removed&&mayBeRemoved&&(status==kAudioHardwareBadObjectError||status==kAudioHardwareBadDeviceError)){missingError=true;return true;}
    return false;
   };
   if(started&&!accepted(AudioDeviceStop(device.id,proc),true))ok=false;
   if(proc&&!accepted(AudioDeviceDestroyIOProcID(device.id,proc),true))ok=false;
   for(auto& x:listeners)if(!accepted(AudioObjectRemovePropertyListener(x.first,&x.second,bridge::changed,anchor.get()),x.first!=kAudioObjectSystemObject))ok=false;
   if(missingError&&(!removedDevice()||bridge::retiredAnchorCount==bridge::retiredAnchors.size()))ok=false;
   proc=nullptr;started=false;listeners.clear();
   if(!ok){bridge::teardownUncertain=true;context.release();anchor.release();}
   else if(missingError){
    bridge::retiredAnchors[bridge::retiredAnchorCount++]=anchor.release();
    bridge::validationTrace("AUDIO_CONTEXT_RETIRED_REMOVED_DEVICE");
    // Context destruction closes XPC and releases the old transport before start.
   }
   return ok;
 }
 std::string differences(const bridge::Device& d)const{
  std::string out;auto field=[&](bool changed,const char* name){if(changed){if(!out.empty())out+=",";out+=name;}};
  field(d.uid!=device.uid,"physicalTargetUID");field(d.id!=device.id,"AudioDeviceID");field(d.transport!=device.transport,"transportType");field(d.rate!=device.rate,"sampleRate");field(d.channels!=device.channels,"channels");field(d.buffer!=device.buffer,"bufferFrames");field(d.maxBlock!=device.maxBlock,"maxBlock");field(d.stereoMap!=device.stereoMap,"stereoMap");field(d.buffers!=device.buffers,"channelLayout");field(d.streams.size()!=device.streams.size(),"streamCount");
  for(size_t i=0;i<std::min(d.streams.size(),device.streams.size());i++){field(d.streams[i].id!=device.streams[i].id,"streamID");field(!bridge::sameFormat(d.streams[i].client,device.streams[i].client),"clientFormat");field(!bridge::sameFormat(d.streams[i].physical,device.streams[i].physical),"physicalFormat");}return out;
 }
 std::string identity(const bridge::Device& d)const{
   // UID stays private: explicit selected UID equality is recorded, not its value.
   std::ostringstream o;o<<"{selectedUID="<<(d.uid==device.uid)<<",deviceID="<<d.id<<",transport="<<d.transport<<",rate="<<d.rate<<",channels="<<d.channels<<",buffer="<<d.buffer<<",maxBlock="<<d.maxBlock<<",alive="<<d.alive<<",running="<<d.running<<",stereoMap="<<d.stereoMap<<",streams="<<d.streams.size();
   for(auto& st:d.streams){o<<",streamID="<<st.id;for(auto* f:{&st.client,&st.physical})o<<",format={rate="<<f->mSampleRate<<",id="<<f->mFormatID<<",flags="<<f->mFormatFlags<<",bytesPacket="<<f->mBytesPerPacket<<",framesPacket="<<f->mFramesPerPacket<<",bytesFrame="<<f->mBytesPerFrame<<",channels="<<f->mChannelsPerFrame<<",bits="<<f->mBitsPerChannel<<"}";}o<<",layout=";for(auto n:d.buffers)o<<n<<',';o<<"}";return o.str();
 }
 void physicalFailure(const bridge::Device* fresh,const char* reason){
   failureDetail="CHANGE_SOURCE=COREAUDIO_READBACK CALLER=ABSession.observe TIMESTAMP_MACH="+std::to_string(mach_absolute_time())+" NOTIFICATION_MACH="+std::to_string(context->changeTime.load())+" SELECTOR="+std::to_string(context->changeSelector.load())+" OBSERVATION_GENERATION="+std::to_string(context->observationSequence.load())+" EPOCH="+std::to_string(context->engine.epoch)+" OLD_CONTEXT="+identity(device)+" NEW_CONTEXT="+(fresh?identity(*fresh):"TARGET_UNRESOLVED")+" DIFF_FIELDS="+reason;
   if(!fresh&&removedDevice())failureDetail+=" TARGET_REMOVAL_CONFIRMED=1";
 }
 void observe(){
   auto& e=context->engine;e.observe();if(!e.gate.accepts(e.epoch)){failureDetail=e.contextFailureDetail()+" COREAUDIO_OBSERVATION={selector="+std::to_string(context->changeSelector.load())+",notificationMach="+std::to_string(context->changeTime.load())+",observedSequence="+std::to_string(context->observationSequence.load())+",validatedSequence="+std::to_string(context->validatedSequence.load())+",validationSilencedCallbacks="+std::to_string(context->validationSilencedCallbacks.load())+"}";return;}
   const auto observation=context->observationSequence.load(std::memory_order_acquire);
   try{auto fresh=bridge::resolve(device.uid);
    if(!fresh.alive){physicalFailure(&fresh,"alive");e.gate.invalidate(bridge::Failure::TargetUnavailable);return;}
    if(!bridge::contextMatches(device,fresh)){physicalFailure(&fresh,differences(fresh).c_str());e.gate.invalidate(bridge::Failure::FormatChanged);return;}
    if(!fresh.running){physicalFailure(&fresh,"running");e.gate.invalidate(bridge::Failure::DeviceStopped);return;}
    if(observation!=context->validatedSequence.load())bridge::validationTrace("AUDIO_CONTEXT_EQUIVALENT_NOTIFICATION",context->changeTime.load(),observation,context->changeSelector.load());
    context->validatedSequence.store(observation,std::memory_order_release);
   }catch(...){physicalFailure(nullptr,"selected_UID_resolution");e.gate.invalidate(bridge::Failure::TargetUnavailable);return;}
   auto callbacks=e.telemetry.callbacks.load();if(callbacks!=lastCallbacks){lastCallbacks=callbacks;progress=std::chrono::steady_clock::now();}
   if(std::chrono::steady_clock::now()-progress>std::chrono::seconds(2)){physicalFailure(nullptr,"callback_progress");e.gate.invalidate(bridge::Failure::CallbackStalled);}
 }

};
extern "C" char *ABCopyDevicesJSON(void){try{auto all=bridge::devices();std::string out="{\"devices\":[";bool first=true;for(auto& d:all){if(!bridge::physicalTransport(d.transport))continue;if(!first)out+=",";first=false;out+=bridge::deviceJSON(d);}return bridge::copied(out+"]}");}catch(const std::exception& e){return bridge::copied("{\"devices\":[],\"error\":"+bridge::quote(e.what())+"}");}}
extern "C" void ABFreeString(char* s){std::free(s);}
extern "C" ABSession *ABStartTest(const char* uid,const char* fixture,float gain,int muted,char** error){
 std::unique_ptr<ABSession> session;
 if(error)*error=nullptr;
 try{
  if(bridge::teardownUncertain)throw std::runtime_error("HAL_TEARDOWN_UNCONFIRMED_RESTART_REQUIRED");
  if(!uid||!fixture||!std::isfinite(gain)||gain<0||gain>1)throw std::runtime_error("INVALID_REQUEST");
  std::string f=fixture;if(f!="sine"&&f!="channels"&&f!="silence"&&f!="system")throw std::runtime_error("UNSUPPORTED_FIXTURE");
  auto d=bridge::resolve(uid);auto eligible=d.maxBlock>RD_MAX_BLOCK?std::string("UNSUPPORTED_BUFFER_SIZE"):bridge::eligibility(d);if(eligible!="USABLE_DIRECT_PATH")throw std::runtime_error(eligible);
  session=std::make_unique<ABSession>(d,f,gain,muted);auto& c=*session->context;
  auto add=[&](AudioObjectID id,AudioObjectPropertySelector selector,AudioObjectPropertyScope scope){auto a=bridge::address(selector,scope);if(selector==kAudioDevicePropertyUsesVariableBufferFrameSizes&&!AudioObjectHasProperty(id,&a))return;OSStatus result=AudioObjectAddPropertyListener(id,&a,bridge::changed,session->anchor.get());if(result!=noErr)throw std::runtime_error("LISTENER_FAILED "+std::to_string(result));session->listeners.emplace_back(id,a);};
  add(kAudioObjectSystemObject,kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal);
  for(auto selector:std::array<AudioObjectPropertySelector,4>{kAudioDevicePropertyDeviceIsAlive,kAudioDevicePropertyNominalSampleRate,kAudioDevicePropertyBufferFrameSize,kAudioDevicePropertyUsesVariableBufferFrameSizes})add(d.id,selector,kAudioObjectPropertyScopeGlobal);
  add(d.id,kAudioDevicePropertyStreams,kAudioObjectPropertyScopeOutput);
  for(auto& stream:d.streams){add(stream.id,kAudioStreamPropertyVirtualFormat,kAudioObjectPropertyScopeGlobal);add(stream.id,kAudioStreamPropertyPhysicalFormat,kAudioObjectPropertyScopeGlobal);}
  OSStatus create=AudioDeviceCreateIOProcID(d.id,bridge::callback,session->anchor.get(),&session->proc);if(create!=noErr)throw std::runtime_error("HAL_CREATE_FAILED "+std::to_string(create));
  if(!bridge::contextMatches(d,bridge::resolve(uid))||!c.engine.gate.accepts(c.engine.epoch))throw std::runtime_error("FORMAT_CHANGED");
  mach_timebase_info_data_t timebase{};mach_timebase_info(&timebase);
  if(f!="system")c.deadlineHost=mach_absolute_time()+uint64_t(30e9*double(timebase.denom)/double(timebase.numer));
  OSStatus start=AudioDeviceStart(d.id,session->proc);if(start!=noErr)throw std::runtime_error("HAL_START_FAILED "+std::to_string(start));
  session->started=true;bridge::validationTrace("AUDIO_ROUTE_START");return session.release();
 }catch(const std::exception& e){bool closed=!session||session->close();if(error)*error=bridge::copied(std::string(e.what())+(closed?"":"; HAL_TEARDOWN_UNCONFIRMED"));return nullptr;}
}
extern "C" char *ABPollJSON(ABSession* s){if(!s)return nullptr;try{s->observe();auto& e=s->context->engine;
 std::ostringstream o;o<<"{\"epoch\":"<<e.epoch<<",\"callbacks\":"<<e.telemetry.callbacks.load()<<",\"frames\":"<<e.telemetry.frames.load()<<",\"fill\":"<<e.fill()<<",\"minFill\":0,\"maxFill\":0,\"capacity\":32768,\"targetFill\":4096,\"underrun\":"<<e.underruns()<<",\"overrun\":"<<e.overruns()<<",\"ringMS\":"<<e.ringMS()<<",\"bufferMS\":"<<double(s->device.buffer)*1000/s->device.rate<<",\"residenceMS\":null,\"inputCallbacks\":"<<e.producerBlocks()<<",\"transportUnderrun\":"<<e.transportUnderruns()<<",\"transportOverrun\":"<<e.transportOverruns()<<",\"validationPending\":"<<(s->context->observationSequence.load()!=s->context->validatedSequence.load()?"true":"false")<<",\"validationSilencedCallbacks\":"<<s->context->validationSilencedCallbacks.load()<<",\"failureDetail\":"<<bridge::quote(s->failureDetail)<<",\"failure\":"<<bridge::quote(bridge::failureName(bridge::Failure(e.gate.failure.load())))<<"}";return bridge::copied(o.str());}catch(...){s->context->engine.gate.invalidate(bridge::Failure::HALFailure);return bridge::copied("{\"error\":\"HAL_POLL_FAILED\"}");}}
extern "C" void ABSetGain(ABSession* s,float gain,int muted){if(!s)return;try{s->context->engine.commandGain(gain);s->context->engine.commandMute(muted!=0);}catch(...){s->context->engine.gate.invalidate(bridge::Failure::HALFailure);}}
extern "C" int ABStop(ABSession* s){if(!s)return 0;bool ok=s->close();delete s;return ok?0:-1;}
