// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#include "../AudioVirtualDevice/Driver/VirtualVolume.c"
#include <stdio.h>
#include <assert.h>
static unsigned checks;
#define CHECK(x) do{checks++;assert(x);}while(0)
static OSStatus notification(AudioServerPlugInHostRef h,AudioObjectID o,UInt32 n,const AudioObjectPropertyAddress* a){(void)h;(void)o;(void)n;(void)a;return noErr;}
int main(void){AudioServerPlugInHostInterface fake={0};fake.PropertiesChanged=notification;host=&fake;float unity=1;uint32_t bits;memcpy(&bits,&unity,4);atomic_store(&rdVolume,bits);
 AudioObjectPropertyAddress a={kAudioDevicePropertyStreams,kAudioObjectPropertyScopeInput,0};UInt32 n=999;CHECK(size(driver,Device,0,&a,0,NULL,&n)==0&&n==0);a.mScope=kAudioObjectPropertyScopeOutput;CHECK(size(driver,Device,0,&a,0,NULL,&n)==0&&n==4);UInt32 s=0;CHECK(data(driver,Device,0,&a,0,NULL,4,&n,&s)==0&&s==Stream);
 a.mSelector=kAudioObjectPropertyOwnedObjects;UInt32 ids[3];CHECK(data(driver,Device,0,&a,0,NULL,sizeof(ids),&n,ids)==0&&ids[0]==Stream&&ids[1]==Volume&&ids[2]==Mute);
 Boolean yes=true,place=false;CHECK(will(driver,Device,0,kAudioServerPlugInIOOperationReadInput,&yes,&place)==0&&!yes);CHECK(will(driver,Device,0,kAudioServerPlugInIOOperationWriteMix,&yes,&place)==0&&yes&&place);
 RDTransport* t=calloc(1,sizeof(*t));rdInit(t,99,48000);atomic_store(&t->producer,17);atomic_store(&t->lease,UINT64_MAX);atomic_store(&t->active,1);atomic_store(&rdCurrent,t);RDFrame pcm[16];for(unsigned i=0;i<16;i++)pcm[i]=(RDFrame){.5F,-.25F};CHECK(io(driver,Device,Stream,0,kAudioServerPlugInIOOperationWriteMix,16,NULL,pcm,NULL)==0);CHECK(atomic_load(&t->write)==16);CHECK(t->frames[0].l==.5F&&t->frames[0].r==-.25F);
 a=(AudioObjectPropertyAddress){kAudioLevelControlPropertyScalarValue,kAudioObjectPropertyScopeGlobal,0};float half=.5F;CHECK(set(driver,Volume,0,&a,0,NULL,4,&half)==0);CHECK(atomic_load(&t->volumeBits)==atomic_load(&rdVolume));CHECK(io(driver,Device,Stream,0,kAudioServerPlugInIOOperationWriteMix,16,NULL,pcm,NULL)==0);CHECK(t->frames[16].l==.5F); // plugin MUST NOT apply gain
 a.mSelector=kAudioBooleanControlPropertyValue;UInt32 mute=1;CHECK(set(driver,Mute,0,&a,0,NULL,4,&mute)==0&&atomic_load(&t->mute)==1);CHECK(io(driver,Device,Stream,0,kAudioServerPlugInIOOperationWriteMix,16,NULL,pcm,NULL)==0&&t->frames[32].l==.5F);
 CHECK(io(driver,Device,Stream,0,kAudioServerPlugInIOOperationReadInput,16,NULL,pcm,NULL)!=0);CHECK(io(driver,Device,Stream,0,kAudioServerPlugInIOOperationWriteMix,RD_MAX_BLOCK+1,NULL,pcm,NULL)!=0);
 atomic_store(&rdCurrent,NULL);free(t);CHECK(io(driver,Device,Stream,0,kAudioServerPlugInIOOperationWriteMix,16,NULL,pcm,NULL)==0);printf("Output-only production driver: %u assertions PASS; no HAL, no registration\n",checks);}
