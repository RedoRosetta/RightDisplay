// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <stdio.h>
static int readProperty(AudioObjectID id,AudioObjectPropertySelector s,void* value,UInt32 size){AudioObjectPropertyAddress a={s,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};UInt32 got=size;return AudioObjectGetPropertyData(id,&a,0,NULL,&got,value)==noErr&&got==size;}
int main(void){AudioDeviceID current=0,system=0;if(!readProperty(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,&current,sizeof(current))||!readProperty(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultSystemOutputDevice,&system,sizeof(system)))return 2;
 AudioObjectPropertyAddress a={kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};UInt32 bytes=0;if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,NULL,&bytes)!=noErr||bytes>65536||bytes%sizeof(AudioDeviceID))return 2;AudioDeviceID *ids=calloc(1,bytes?bytes:1);if(!ids)return 2;if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,NULL,&bytes,ids)!=noErr){free(ids);return 2;}int result=0;
 for(unsigned i=0;i<bytes/sizeof(AudioDeviceID);++i){CFStringRef uid=NULL;if(!readProperty(ids[i],kAudioDevicePropertyDeviceUID,&uid,sizeof(uid))||!uid){result=2;break;}int same=CFStringCompare(uid,CFSTR("RightDisplay.VirtualVolume"),0)==kCFCompareEqualTo;CFRelease(uid);if(same){UInt32 running=0;if(ids[i]==current||ids[i]==system){result=3;break;}if(!readProperty(ids[i],kAudioDevicePropertyDeviceIsRunningSomewhere,&running,sizeof(running))||running){result=3;break;}}}free(ids);if(result)fputs("RightDisplay virtual device is in use or its state is unknown. Select another output and stop all clients before removal.\n",stderr);return result;
}
