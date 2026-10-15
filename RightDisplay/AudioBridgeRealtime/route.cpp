// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#include "AudioBridgeC.h"
#include "hal.hpp"
#include <sstream>
#include <cstdlib>
namespace {
AudioObjectPropertyAddress addr(AudioObjectPropertySelector s){return {s,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};}
template<class T> bool get(AudioObjectID id,AudioObjectPropertySelector selector,T& value){auto a=addr(selector);UInt32 size=sizeof(value);return AudioObjectGetPropertyData(id,&a,0,nullptr,&size,&value)==noErr&&size==sizeof(value);}
}
// Small status read: no formats, buffer lists or full physical-device enumeration.
extern "C" char* RVCopyStatusJSON(){try{
 auto a=addr(kAudioHardwarePropertyDevices);UInt32 bytes=0;if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,nullptr,&bytes)!=noErr||bytes%sizeof(AudioDeviceID)||bytes>65536)throw std::runtime_error("LIST_UNAVAILABLE");
 std::vector<AudioDeviceID> ids(bytes/sizeof(AudioDeviceID));if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&bytes,ids.data())!=noErr)throw std::runtime_error("LIST_UNAVAILABLE");ids.resize(bytes/sizeof(AudioDeviceID));
 AudioDeviceID found=0;unsigned matches=0;for(auto id:ids){CFStringRef uid=nullptr;if(get(id,kAudioDevicePropertyDeviceUID,uid)&&uid){bool same=CFStringCompare(uid,CFSTR("RightDisplay.VirtualVolume"),0)==kCFCompareEqualTo;CFRelease(uid);if(same){found=id;++matches;}}}
 AudioDeviceID current=0,system=0;bool known=get(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,current)&&get(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultSystemOutputDevice,system);
 bool compatible=false;CFStringRef model=nullptr;if(found&&get(found,kAudioDevicePropertyModelUID,model)&&model){compatible=CFStringCompare(model,CFSTR("RightDisplay.VirtualVolume.Model.Build21"),0)==kCFCompareEqualTo;CFRelease(model);}
 bool alive=false;UInt32 aValue=0;if(found&&get(found,kAudioDevicePropertyDeviceIsAlive,aValue))alive=aValue!=0;double rate=0;if(found)get(found,kAudioDevicePropertyNominalSampleRate,rate);
 std::ostringstream o;o<<"{\"matches\":"<<matches<<",\"loaded\":"<<(matches==1&&alive&&compatible?"true":"false")<<",\"defaultKnown\":"<<(known?"true":"false")<<",\"isDefault\":"<<(matches==1&&(current==found||system==found)?"true":"false")<<",\"rate\":"<<rate<<"}";return strdup(o.str().c_str());
 }catch(...){return strdup("{\"matches\":0,\"loaded\":false,\"defaultKnown\":false,\"isDefault\":false,\"rate\":0}");}}
