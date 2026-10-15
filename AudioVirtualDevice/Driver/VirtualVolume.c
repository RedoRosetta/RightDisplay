// Output-only AudioServerPlugIn. All PCM transport is in Producer.h;
// no physical HAL client API, input stream, recording or input IO operation.
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreAudio/AudioHardware.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>
#include "Producer.h"
enum {Plugin=1,Device=2,Stream=3,Volume=4,Mute=5};
static AudioServerPlugInHostRef host;
static _Atomic(UInt32) refs=1,running=0;
static double ticksPerFrame;
static _Atomic(uint64_t) origin;
static AudioServerPlugInDriverInterface table;
static AudioServerPlugInDriverInterface* tablePointer=&table;
static AudioServerPlugInDriverRef driver=&tablePointer;
static AudioStreamBasicDescription format(void){return (AudioStreamBasicDescription){48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};}
static HRESULT query(void* d,REFIID id,LPVOID* out){(void)d;if(!out)return E_POINTER;CFUUIDRef u=CFUUIDCreateFromUUIDBytes(NULL,id);Boolean ok=CFEqual(u,IUnknownUUID)||CFEqual(u,kAudioServerPlugInDriverInterfaceUUID);CFRelease(u);*out=ok?driver:NULL;if(ok)atomic_fetch_add(&refs,1);return ok?S_OK:E_NOINTERFACE;}
static ULONG addref(void* d){(void)d;return atomic_fetch_add(&refs,1)+1;}
static ULONG release(void* d){(void)d;UInt32 r=atomic_load(&refs);if(r>1)return atomic_fetch_sub(&refs,1)-1;return 1;}
static OSStatus initialize(AudioServerPlugInDriverRef d,AudioServerPlugInHostRef h){(void)d;host=h;mach_timebase_info_data_t tb;mach_timebase_info(&tb);ticksPerFrame=1e9*(double)tb.denom/tb.numer/48000;rdProducerInitialize();return noErr;}
static OSStatus create(AudioServerPlugInDriverRef d,CFDictionaryRef desc,const AudioServerPlugInClientInfo* c,AudioObjectID* o){(void)d;(void)desc;(void)c;(void)o;return kAudioHardwareUnsupportedOperationError;}
static OSStatus destroy(AudioServerPlugInDriverRef d,AudioObjectID o){(void)d;(void)o;return kAudioHardwareUnsupportedOperationError;}
static OSStatus client(AudioServerPlugInDriverRef d,AudioObjectID o,const AudioServerPlugInClientInfo* c){(void)d;(void)c;return o==Device?noErr:kAudioHardwareBadObjectError;}
static OSStatus configuration(AudioServerPlugInDriverRef d,AudioObjectID o,UInt64 a,void* i){(void)d;(void)o;(void)a;(void)i;return kAudioHardwareUnsupportedOperationError;}
static int validObject(AudioObjectID o){return o>=Plugin&&o<=Mute;}
static UInt32 propertySize(AudioObjectID o,const AudioObjectPropertyAddress* a){
 if(!a||!validObject(o))return UINT32_MAX;UInt32 s=a->mSelector;
 switch(s){
 case kAudioObjectPropertyBaseClass:case kAudioObjectPropertyClass:case kAudioObjectPropertyOwner:return 4;
 case kAudioObjectPropertyName:case kAudioObjectPropertyManufacturer:return sizeof(CFStringRef);
 case kAudioObjectPropertyOwnedObjects:return o==Plugin?4:o==Device?(a->mScope==kAudioObjectPropertyScopeInput?0:12):0;
 }
 if(o==Plugin){switch(s){case kAudioPlugInPropertyBundleID:return sizeof(CFStringRef);case kAudioPlugInPropertyDeviceList:return 4;case kAudioPlugInPropertyTranslateUIDToDevice:return 4;case kAudioPlugInPropertyResourceBundle:return sizeof(CFStringRef);case kAudioPlugInPropertyBoxList:return 0;}return UINT32_MAX;}
 if(o==Device){switch(s){
 case kAudioDevicePropertyDeviceUID:case kAudioDevicePropertyModelUID:return sizeof(CFStringRef);
 case kAudioDevicePropertyTransportType:case kAudioDevicePropertyDeviceIsAlive:case kAudioDevicePropertyDeviceIsRunning:case kAudioDevicePropertyDeviceIsRunningSomewhere:case kAudioDevicePropertyDeviceCanBeDefaultDevice:case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:case kAudioDevicePropertyLatency:case kAudioDevicePropertySafetyOffset:case kAudioDevicePropertyZeroTimeStampPeriod:case kAudioDevicePropertyClockDomain:case kAudioDevicePropertyBufferFrameSize:case kAudioDevicePropertyUsesVariableBufferFrameSizes:case kAudioDevicePropertyIsHidden:return 4;
 case kAudioDevicePropertyStreams:return a->mScope==kAudioObjectPropertyScopeInput?0:4;
 case kAudioObjectPropertyControlList:return a->mScope==kAudioObjectPropertyScopeInput?0:8;
 case kAudioDevicePropertyNominalSampleRate:return 8;
 case kAudioDevicePropertyAvailableNominalSampleRates:case kAudioDevicePropertyBufferFrameSizeRange:return sizeof(AudioValueRange);
 case kAudioDevicePropertyPreferredChannelsForStereo:return a->mScope==kAudioObjectPropertyScopeInput?0:8;
 case kAudioDevicePropertyStreamConfiguration:return a->mScope==kAudioObjectPropertyScopeInput?offsetof(AudioBufferList,mBuffers):sizeof(AudioBufferList);
 }return UINT32_MAX;}
 if(o==Stream){switch(s){case kAudioStreamPropertyIsActive:case kAudioStreamPropertyDirection:case kAudioStreamPropertyTerminalType:case kAudioStreamPropertyStartingChannel:case kAudioStreamPropertyLatency:return 4;case kAudioStreamPropertyVirtualFormat:case kAudioStreamPropertyPhysicalFormat:return sizeof(AudioStreamBasicDescription);case kAudioStreamPropertyAvailableVirtualFormats:case kAudioStreamPropertyAvailablePhysicalFormats:return sizeof(AudioStreamRangedDescription);}return UINT32_MAX;}
 switch(s){case kAudioControlPropertyScope:case kAudioControlPropertyElement:return 4;case kAudioLevelControlPropertyScalarValue:case kAudioLevelControlPropertyDecibelValue:case kAudioLevelControlPropertyConvertScalarToDecibels:case kAudioLevelControlPropertyConvertDecibelsToScalar:return o==Volume?4:UINT32_MAX;case kAudioLevelControlPropertyDecibelRange:return o==Volume?sizeof(AudioValueRange):UINT32_MAX;case kAudioBooleanControlPropertyValue:return o==Mute?4:UINT32_MAX;}return UINT32_MAX;
}
static Boolean has(AudioServerPlugInDriverRef d,AudioObjectID o,pid_t p,const AudioObjectPropertyAddress* a){(void)d;(void)p;return propertySize(o,a)!=UINT32_MAX;}
static OSStatus settable(AudioServerPlugInDriverRef d,AudioObjectID o,pid_t p,const AudioObjectPropertyAddress* a,Boolean* out){(void)d;(void)p;if(!out||propertySize(o,a)==UINT32_MAX)return kAudioHardwareUnknownPropertyError;*out=(o==Volume&&(a->mSelector==kAudioLevelControlPropertyScalarValue||a->mSelector==kAudioLevelControlPropertyDecibelValue))||(o==Mute&&a->mSelector==kAudioBooleanControlPropertyValue);return noErr;}
static OSStatus size(AudioServerPlugInDriverRef d,AudioObjectID o,pid_t p,const AudioObjectPropertyAddress* a,UInt32 q,const void* v,UInt32* n){(void)d;(void)p;(void)q;(void)v;if(!n)return kAudioHardwareIllegalOperationError;*n=propertySize(o,a);return *n==UINT32_MAX?kAudioHardwareUnknownPropertyError:noErr;}
static OSStatus data(AudioServerPlugInDriverRef d,AudioObjectID o,pid_t p,const AudioObjectPropertyAddress* a,UInt32 q,const void* qualifier,UInt32 capacity,UInt32* n,void* out){
 (void)d;(void)p;UInt32 need=propertySize(o,a);if(need==UINT32_MAX)return kAudioHardwareUnknownPropertyError;if(!n||capacity<need||(!out&&need))return kAudioHardwareBadPropertySizeError;*n=need;if(!need)return noErr;
 UInt32 s=a->mSelector;UInt32 v=0;CFStringRef text=NULL;
 switch(s){
 case kAudioObjectPropertyBaseClass:v=o==Plugin?kAudioObjectClassID:o==Device?kAudioObjectClassID:o==Stream?kAudioObjectClassID:o==Volume?kAudioLevelControlClassID:kAudioBooleanControlClassID;break;
 case kAudioObjectPropertyClass:v=o==Plugin?kAudioPlugInClassID:o==Device?kAudioDeviceClassID:o==Stream?kAudioStreamClassID:o==Volume?kAudioVolumeControlClassID:kAudioMuteControlClassID;break;
 case kAudioObjectPropertyOwner:v=o==Plugin?kAudioObjectSystemObject:o==Device?Plugin:Device;break;
 case kAudioObjectPropertyName:text=CFSTR("RightDisplay Virtual Volume");break;
 case kAudioObjectPropertyManufacturer:text=CFSTR("RightDisplay");break;
 case kAudioPlugInPropertyBundleID:text=CFSTR("com.rightdisplay.audio.VirtualVolume");break;
 case kAudioPlugInPropertyResourceBundle:text=CFSTR("");break;
 case kAudioDevicePropertyDeviceUID:text=CFSTR("RightDisplay.VirtualVolume");break;
 case kAudioDevicePropertyModelUID:text=CFSTR("RightDisplay.VirtualVolume.Model.Build21");break;
 case kAudioObjectPropertyOwnedObjects:if(o==Plugin){v=Device;break;}else{UInt32 ids[]={Stream,Volume,Mute};memcpy(out,ids,need);return noErr;}
 case kAudioPlugInPropertyDeviceList:v=Device;break;
 case kAudioPlugInPropertyTranslateUIDToDevice:if(q==sizeof(CFStringRef)&&qualifier&&CFEqual(*(CFStringRef*)qualifier,CFSTR("RightDisplay.VirtualVolume")))v=Device;break;
 case kAudioDevicePropertyStreams:v=Stream;break;
 case kAudioObjectPropertyControlList:{UInt32 ids[]={Volume,Mute};memcpy(out,ids,need);return noErr;}
 case kAudioDevicePropertyTransportType:v=kAudioDeviceTransportTypeVirtual;break;
 case kAudioDevicePropertyDeviceIsAlive:case kAudioDevicePropertyDeviceCanBeDefaultDevice:case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:v=a->mScope==kAudioObjectPropertyScopeInput?0:1;break;
 case kAudioDevicePropertyDeviceIsRunning:case kAudioDevicePropertyDeviceIsRunningSomewhere:v=atomic_load(&running)>0;break;
 case kAudioDevicePropertyZeroTimeStampPeriod:v=512;break;
 case kAudioDevicePropertyBufferFrameSize:v=512;break;
 case kAudioDevicePropertyNominalSampleRate:*(Float64*)out=48000;return noErr;
 case kAudioDevicePropertyAvailableNominalSampleRates:*(AudioValueRange*)out=(AudioValueRange){48000,48000};return noErr;
 case kAudioDevicePropertyBufferFrameSizeRange:*(AudioValueRange*)out=(AudioValueRange){32,RD_MAX_BLOCK};return noErr;
 case kAudioDevicePropertyPreferredChannelsForStereo:((UInt32*)out)[0]=1;((UInt32*)out)[1]=2;return noErr;
 case kAudioDevicePropertyStreamConfiguration:{AudioBufferList* list=out;list->mNumberBuffers=a->mScope==kAudioObjectPropertyScopeInput?0:1;if(list->mNumberBuffers)list->mBuffers[0]=(AudioBuffer){2,0,NULL};return noErr;}
 case kAudioStreamPropertyIsActive:v=1;break;
 case kAudioStreamPropertyTerminalType:v=kAudioStreamTerminalTypeSpeaker;break;
 case kAudioStreamPropertyStartingChannel:v=1;break;
 case kAudioStreamPropertyVirtualFormat:case kAudioStreamPropertyPhysicalFormat:*(AudioStreamBasicDescription*)out=format();return noErr;
 case kAudioStreamPropertyAvailableVirtualFormats:case kAudioStreamPropertyAvailablePhysicalFormats:*(AudioStreamRangedDescription*)out=(AudioStreamRangedDescription){format(),{48000,48000}};return noErr;
 case kAudioControlPropertyScope:v=kAudioObjectPropertyScopeOutput;break;
 case kAudioControlPropertyElement:v=kAudioObjectPropertyElementMain;break;
 case kAudioLevelControlPropertyScalarValue:{uint32_t b=atomic_load(&rdVolume);memcpy(out,&b,4);return noErr;}
 case kAudioLevelControlPropertyDecibelValue:{float gain;uint32_t b=atomic_load(&rdVolume);memcpy(&gain,&b,4);*(Float32*)out=gain>0?20*log10f(gain):-96;return noErr;}
 case kAudioLevelControlPropertyDecibelRange:*(AudioValueRange*)out=(AudioValueRange){-96,0};return noErr;
 case kAudioLevelControlPropertyConvertScalarToDecibels:{float f=*(Float32*)out;*(Float32*)out=f>0?20*log10f(f):-96;return noErr;}
 case kAudioLevelControlPropertyConvertDecibelsToScalar:*(Float32*)out=powf(10,*(Float32*)out/20);return noErr;
 case kAudioBooleanControlPropertyValue:v=atomic_load(&rdMute);break;
 default:break;
 }
 if(text){CFRetain(text);*(CFStringRef*)out=text;}else *(UInt32*)out=v;return noErr;
}
static OSStatus set(AudioServerPlugInDriverRef d,AudioObjectID o,pid_t p,const AudioObjectPropertyAddress* a,UInt32 q,const void* qualifier,UInt32 n,const void* value){
 (void)q;(void)qualifier;Boolean writable=false;if(settable(d,o,p,a,&writable)||!writable)return kAudioHardwareUnsupportedOperationError;if(n!=4||!value)return kAudioHardwareBadPropertySizeError;
 if(o==Volume){float f=*(const Float32*)value;if(!isfinite(f))return kAudioHardwareIllegalOperationError;if(a->mSelector==kAudioLevelControlPropertyDecibelValue)f=f<=-96?0:powf(10,f/20);if(f<0||f>1)return kAudioHardwareIllegalOperationError;rdSetVolume(f);AudioObjectPropertyAddress changes[]={{kAudioLevelControlPropertyScalarValue,kAudioObjectPropertyScopeGlobal,0},{kAudioLevelControlPropertyDecibelValue,kAudioObjectPropertyScopeGlobal,0}};host->PropertiesChanged(host,o,2,changes);}
 else{rdSetMute(*(const UInt32*)value!=0);host->PropertiesChanged(host,o,1,a);}return noErr;
}
static OSStatus start(AudioServerPlugInDriverRef d,AudioObjectID o,UInt32 c){(void)d;(void)c;if(o!=Device)return kAudioHardwareBadObjectError;if(atomic_fetch_add(&running,1)==0){atomic_store(&origin,mach_absolute_time());rdSetStreaming(1);}return noErr;}
static OSStatus stop(AudioServerPlugInDriverRef d,AudioObjectID o,UInt32 c){(void)d;(void)c;if(o!=Device)return kAudioHardwareBadObjectError;UInt32 count=atomic_load(&running);while(count&&!atomic_compare_exchange_weak(&running,&count,count-1)){}if(count==1)rdSetStreaming(0);return noErr;}
static OSStatus stamp(AudioServerPlugInDriverRef d,AudioObjectID o,UInt32 c,Float64* sample,UInt64* time,UInt64* seed){(void)d;(void)c;if(o!=Device||!sample||!time||!seed)return kAudioHardwareBadObjectError;uint64_t base=atomic_load(&origin),now=mach_absolute_time();uint64_t periods=(uint64_t)((now>=base?now-base:0)/(ticksPerFrame*512));*sample=(double)periods*512;*time=base+(uint64_t)(periods*512*ticksPerFrame);*seed=base?base:1;return noErr;}
static OSStatus will(AudioServerPlugInDriverRef d,AudioObjectID o,UInt32 c,UInt32 op,Boolean* yes,Boolean* place){(void)d;(void)c;if(o!=Device)return kAudioHardwareBadObjectError;if(yes)*yes=op==kAudioServerPlugInIOOperationWriteMix;if(place)*place=true;return noErr;}
static OSStatus begin(AudioServerPlugInDriverRef d,AudioObjectID o,UInt32 c,UInt32 op,UInt32 n,const AudioServerPlugInIOCycleInfo* info){(void)d;(void)c;(void)op;(void)n;(void)info;return o==Device?noErr:kAudioHardwareBadObjectError;}
static OSStatus io(AudioServerPlugInDriverRef d,AudioObjectID o,AudioObjectID stream,UInt32 c,UInt32 op,UInt32 n,const AudioServerPlugInIOCycleInfo* info,void* main,void* secondary){(void)d;(void)c;(void)info;(void)secondary;if(o!=Device||stream!=Stream)return kAudioHardwareBadObjectError;if(op!=kAudioServerPlugInIOOperationWriteMix)return kAudioHardwareUnsupportedOperationError;if(n>RD_MAX_BLOCK||!main)return kAudioHardwareBadPropertySizeError;rdWrite(main,n);return noErr;}
static AudioServerPlugInDriverInterface table={NULL,query,addref,release,initialize,create,destroy,client,client,configuration,configuration,has,settable,size,data,set,start,stop,stamp,will,begin,io,begin};
void* NullAudio_Create(CFAllocatorRef allocator,CFUUIDRef type){(void)allocator;return CFEqual(type,kAudioServerPlugInTypeUUID)?driver:NULL;}
