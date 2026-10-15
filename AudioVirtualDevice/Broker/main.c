// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
// Control plane only: no audio devices, no PCM processing, no realtime thread.
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <sys/mman.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include "../Transport/PCMTransport.h"
// Accept only the two Apple audio hosts observed across supported macOS layouts.
// euid classifies the role; this requirement authenticates producer messages.
static const char* producerRequirement = "anchor apple and (identifier \"com.apple.audio.coreaudiod\" or identifier \"com.apple.audio.Core-Audio-Driver-Service.helper\")";
static xpc_connection_t producer,consumer;
static RDTransport* mapping;
static uint64_t serial;
static dispatch_queue_t queue;
static void invalidate(void){
 ++serial;if(mapping){atomic_store(&mapping->active,0);atomic_store(&mapping->consumer,0);munmap(mapping,rdMappingBytes());mapping=NULL;}
 if(consumer){xpc_release(consumer);consumer=NULL;}
 if(producer){xpc_object_t m=xpc_dictionary_create(NULL,NULL,0);xpc_dictionary_set_string(m,"op","detach");xpc_connection_send_message(producer,m);xpc_release(m);}
}
static void reply(xpc_connection_t peer,xpc_object_t request,const char* error){xpc_object_t r=xpc_dictionary_create_reply(request);if(r){if(error)xpc_dictionary_set_string(r,"error",error);xpc_connection_send_message(peer,r);xpc_release(r);}}
static void message(xpc_connection_t peer,xpc_object_t m){
 if(xpc_get_type(m)!=XPC_TYPE_DICTIONARY)return;const char* op=xpc_dictionary_get_string(m,"op");if(!op)return;
 if(!strcmp(op,"producer")){
  // Per-message XPC code requirements validate audit identity, avoiding PID reuse.
  if(producer&&producer!=peer){reply(peer,m,"PRODUCER_ALREADY_REGISTERED");return;}
  if(!producer){producer=peer;xpc_retain(peer);}reply(peer,m,NULL);return;
 }
 if(!strcmp(op,"detach")){if(peer==consumer)invalidate();reply(peer,m,NULL);return;}
 // Read-only connection health: no mapping, stream or device state changes.
 if(!strcmp(op,"status")){xpc_object_t r=xpc_dictionary_create_reply(m);if(r){xpc_dictionary_set_bool(r,"producer_registered",producer!=NULL);xpc_connection_send_message(peer,r);xpc_release(r);}return;}
 if(strcmp(op,"attach")){reply(peer,m,"UNKNOWN_REQUEST");return;}
 if(!producer||consumer){reply(peer,m,producer?"TRANSPORT_BUSY":"PRODUCER_UNAVAILABLE");return;}
 xpc_object_t memory=xpc_dictionary_get_value(m,"memory");uint64_t session=xpc_dictionary_get_uint64(m,"session");
 if(!memory||xpc_get_type(memory)!=XPC_TYPE_SHMEM){reply(peer,m,"INVALID_MEMORY");return;}
 void* region=NULL;size_t n=xpc_shmem_map(memory,&region);
 if(n!=rdMappingBytes()||!rdValid(region,session)){if(n)munmap(region,n);reply(peer,m,"INVALID_CONTRACT");return;}
 if(atomic_load(&((RDTransport*)region)->active)||atomic_load(&((RDTransport*)region)->producer)||atomic_load(&((RDTransport*)region)->write)||atomic_load(&((RDTransport*)region)->read)){munmap(region,n);reply(peer,m,"NONEMPTY_SESSION");return;}
 mapping=region;consumer=peer;xpc_retain(peer);const uint64_t token=++serial;
 xpc_object_t forward=xpc_dictionary_create(NULL,NULL,0);xpc_dictionary_set_string(forward,"op","attach");xpc_dictionary_set_uint64(forward,"session",session);xpc_dictionary_set_value(forward,"memory",memory);
 xpc_retain(m);xpc_retain(peer);
 xpc_connection_send_message_with_reply(producer,forward,queue,^(xpc_object_t response){
  if(serial!=token){reply(peer,m,"STALE_SESSION");}
  else if(xpc_get_type(response)!=XPC_TYPE_DICTIONARY||!xpc_dictionary_get_bool(response,"ready")){invalidate();reply(peer,m,"PRODUCER_ATTACH_FAILED");}
  else {reply(peer,m,NULL);}
  xpc_release(m);xpc_release(peer);
 });xpc_release(forward);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),queue,^{if(serial==token&&mapping&&!atomic_load(&mapping->active))invalidate();});
}
int main(void){
 queue=dispatch_queue_create("RightDisplay.Transport.Control",DISPATCH_QUEUE_SERIAL);
 xpc_connection_t listener=xpc_connection_create_mach_service(RD_SERVICE,queue,XPC_CONNECTION_MACH_SERVICE_LISTENER);
 xpc_connection_set_event_handler(listener,^(xpc_object_t event){
  if(xpc_get_type(event)!=XPC_TYPE_CONNECTION)return;xpc_connection_t peer=(xpc_connection_t)event;
  // Root audio service can only register; the current console user may consume.
  int isProducer;
  // Producer classification by euid alone is insufficient: authenticate its Apple host.
  if(xpc_connection_get_euid(peer)==0||xpc_connection_get_euid(peer)==202)isProducer=1;else isProducer=0;
  // Build41 intentionally does not authenticate the consumer's cryptographic identity.
  // Other console-user processes may attempt to consume; protocol/ownership guards remain.
  if(isProducer&&xpc_connection_set_peer_code_signing_requirement(peer,producerRequirement)){xpc_connection_cancel(peer);return;}
  if(!isProducer){uid_t consoleUID=0;CFStringRef name=SCDynamicStoreCopyConsoleUser(NULL,&consoleUID,NULL);if(name)CFRelease(name);if(!consoleUID||xpc_connection_get_euid(peer)!=consoleUID){xpc_connection_cancel(peer);return;}}
  xpc_connection_set_target_queue(peer,queue);
  xpc_connection_set_event_handler(peer,^(xpc_object_t m){
   if(xpc_get_type(m)==XPC_TYPE_ERROR){if(peer==consumer)invalidate();if(peer==producer){invalidate();xpc_release(producer);producer=NULL;}return;}
   if(xpc_get_type(m)!=XPC_TYPE_DICTIONARY)return;
   const char* op=xpc_dictionary_get_string(m,"op");if(!op)return;
   if((isProducer&&strcmp(op,"producer"))||(!isProducer&&!strcmp(op,"producer"))){reply(peer,m,"ROLE_DENIED");return;}
   message(peer,m);
  });xpc_connection_resume(peer);
 });xpc_connection_resume(listener);dispatch_main();
}
