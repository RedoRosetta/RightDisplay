// Copyright © 2026 RedoRosetta
// Licensed under RNSL 1.0.
// Anonymous XPC only: no Mach service, HAL, installation or device calls.
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
int main(int argc,const char **argv){
 if(argc!=3)return 64;
 dispatch_queue_t q=dispatch_queue_create("test.adhoc.peer",DISPATCH_QUEUE_SERIAL);
 dispatch_semaphore_t done=dispatch_semaphore_create(0);
 xpc_connection_t listener=xpc_connection_create(NULL,q);
 xpc_connection_set_event_handler(listener,^(xpc_object_t e){
  if(xpc_get_type(e)!=XPC_TYPE_CONNECTION)return;
  xpc_connection_t peer=(xpc_connection_t)e;
  xpc_connection_set_event_handler(peer,^(xpc_object_t m){
   if(xpc_get_type(m)==XPC_TYPE_DICTIONARY){xpc_object_t reply=xpc_dictionary_create_reply(m);if(reply){xpc_dictionary_set_bool(reply,"ok",1);xpc_connection_send_message(peer,reply);xpc_release(reply);}}
  });xpc_connection_resume(peer);
 });xpc_connection_resume(listener);
 xpc_endpoint_t endpoint=xpc_endpoint_create(listener);
 xpc_connection_t client=xpc_connection_create_from_endpoint(endpoint);xpc_release(endpoint);
 xpc_connection_set_target_queue(client,q);
 if(xpc_connection_set_peer_code_signing_requirement(client,argv[1]))return 65;
 xpc_connection_set_event_handler(client,^(xpc_object_t e){(void)e;});xpc_connection_resume(client);
 __block int success=0;
 xpc_object_t message=xpc_dictionary_create(NULL,NULL,0);
 xpc_connection_send_message_with_reply(client,message,q,^(xpc_object_t reply){success=xpc_get_type(reply)==XPC_TYPE_DICTIONARY&&xpc_dictionary_get_bool(reply,"ok");dispatch_semaphore_signal(done);});xpc_release(message);
 int timeout=dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));
 xpc_connection_cancel(client);xpc_connection_cancel(listener);
 if(timeout)return 66;
 int expected=atoi(argv[2]);printf("anonymous XPC authenticated=%d expected=%d\n",success,expected);
 return success==expected?0:1;
}
