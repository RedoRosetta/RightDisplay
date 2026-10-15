#ifndef RD_PRODUCER_H
#define RD_PRODUCER_H
#include "../Transport/PCMTransport.h"
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <sys/mman.h>
#include <mach/mach_time.h>
static _Atomic(RDTransport*) rdCurrent;
static _Atomic(uint32_t) rdReaders;
static _Atomic(uint32_t) rdVolume;
static _Atomic(uint32_t) rdMute;
static dispatch_queue_t rdQueue;
static xpc_connection_t rdConnection;
static uint64_t rdGeneration;
static uint32_t rdRetiring;
static _Atomic(uint32_t) rdStreaming;
static _Atomic(uint64_t) rdStreamEpoch;
static void rdRetire(RDTransport* old){
 if(!old)return;atomic_store(&old->active,0);
 // Only control queue reclaims memory. A seq_cst reader-entry fence precedes
 // pointer load; detach precedes reader check. No callback waits or frees.
 if(atomic_load(&rdReaders)){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_MSEC),rdQueue,^{rdRetire(old);});return;}
 munmap(old,rdMappingBytes());rdRetiring--;
}
static void rdDetach(void){RDTransport* old=atomic_exchange(&rdCurrent,NULL);if(old)rdRetiring++;rdRetire(old);}
static void rdConnect(void){
 rdConnection=xpc_connection_create_mach_service(RD_SERVICE,rdQueue,XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
 if(xpc_connection_set_peer_code_signing_requirement(rdConnection,RD_BROKER_REQUIREMENT)){xpc_release(rdConnection);rdConnection=NULL;return;}
 xpc_connection_set_event_handler(rdConnection,^(xpc_object_t m){
  if(xpc_get_type(m)==XPC_TYPE_ERROR){rdDetach();if(m==XPC_ERROR_CONNECTION_INTERRUPTED){xpc_object_t registration=xpc_dictionary_create(NULL,NULL,0);xpc_dictionary_set_string(registration,"op","producer");xpc_connection_send_message(rdConnection,registration);xpc_release(registration);}return;}
  if(xpc_get_type(m)!=XPC_TYPE_DICTIONARY)return;const char* op=xpc_dictionary_get_string(m,"op");if(!op)return;
  if(!strcmp(op,"detach")){rdDetach();return;}
  if(strcmp(op,"attach"))return;
  xpc_object_t reply=xpc_dictionary_create_reply(m);int ready=0;
  xpc_object_t memory=xpc_dictionary_get_value(m,"memory");uint64_t session=xpc_dictionary_get_uint64(m,"session");void* region=NULL;size_t n=0;
  if(memory&&xpc_get_type(memory)==XPC_TYPE_SHMEM)n=xpc_shmem_map(memory,&region);
  if(n==rdMappingBytes()&&rdValid(region,session)&&!atomic_load(&rdCurrent)&&!rdRetiring){
   RDTransport* t=region;rdGeneration++;if(!rdGeneration)rdGeneration++;
   atomic_store(&t->producer,rdGeneration);atomic_store(&t->streaming,atomic_load(&rdStreaming));atomic_store(&t->streamEpoch,atomic_load(&rdStreamEpoch));atomic_store(&t->volumeBits,atomic_load(&rdVolume));atomic_store(&t->mute,atomic_load(&rdMute));atomic_store(&t->active,1);atomic_store(&rdCurrent,t);ready=1;
  }else if(n)munmap(region,n);
  if(reply){xpc_dictionary_set_bool(reply,"ready",ready);xpc_connection_send_message(rdConnection,reply);xpc_release(reply);}
 });xpc_connection_resume(rdConnection);
 xpc_object_t m=xpc_dictionary_create(NULL,NULL,0);xpc_dictionary_set_string(m,"op","producer");xpc_connection_send_message(rdConnection,m);xpc_release(m);
}
static void rdProducerInitialize(void){
 float unity=1;uint32_t bits;memcpy(&bits,&unity,4);atomic_store(&rdVolume,bits);
 arc4random_buf(&rdGeneration,sizeof(rdGeneration));rdQueue=dispatch_queue_create("RightDisplay.Output.Transport",DISPATCH_QUEUE_SERIAL);dispatch_async(rdQueue,^{rdConnect();});
}
static void rdSetVolume(float value){uint32_t bits;memcpy(&bits,&value,4);atomic_store(&rdVolume,bits);atomic_fetch_add(&rdReaders,1);RDTransport* t=atomic_load(&rdCurrent);if(t)atomic_store(&t->volumeBits,bits);atomic_fetch_sub(&rdReaders,1);}
static void rdSetMute(uint32_t value){atomic_store(&rdMute,value);atomic_fetch_add(&rdReaders,1);RDTransport* t=atomic_load(&rdCurrent);if(t)atomic_store(&t->mute,value);atomic_fetch_sub(&rdReaders,1);}
static void rdSetStreaming(uint32_t value){
 atomic_store(&rdStreaming,value);if(value)atomic_fetch_add(&rdStreamEpoch,1);
 atomic_fetch_add(&rdReaders,1);RDTransport* t=atomic_load(&rdCurrent);if(t){atomic_store(&t->streamEpoch,atomic_load(&rdStreamEpoch));atomic_store(&t->streaming,value);}atomic_fetch_sub(&rdReaders,1);
}
static void rdWrite(const RDFrame* pcm,uint32_t frames){
 atomic_fetch_add(&rdReaders,1);RDTransport* t=atomic_load(&rdCurrent);
 if(t)rdPush(t,atomic_load(&t->producer),pcm,frames,mach_absolute_time());
 atomic_fetch_sub(&rdReaders,1);
}
#endif
