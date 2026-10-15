// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#pragma once
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc11-extensions"
#include "../../AudioVirtualDevice/Transport/PCMTransport.h"
#pragma clang diagnostic pop
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <sys/mman.h>
#include <mach/mach_time.h>
#include "transport_context.hpp"
namespace bridge {
class TransportClient {
 struct Mapping {RDTransport* data=nullptr;~Mapping(){if(data)munmap(data,rdMappingBytes());}};
 std::shared_ptr<Mapping> lifetime;
 xpc_connection_t connection=nullptr; dispatch_queue_t queue=nullptr;
public:
 TransportContextTrace trace;
 RDTransport* memory=nullptr;uint64_t producer=0,session=0,leaseTicks=0;
 TransportClient(){
  arc4random_buf(&session,sizeof(session));if(!session)session=1;
  mach_timebase_info_data_t tb{};mach_timebase_info(&tb);leaseTicks=uint64_t(3e9*double(tb.denom)/tb.numer);
  lifetime=std::make_shared<Mapping>();
  void* region=mmap(nullptr,rdMappingBytes(),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANON,-1,0);if(region==MAP_FAILED)throw std::runtime_error("TRANSPORT_MAP_FAILED");memory=static_cast<RDTransport*>(region);lifetime->data=memory;rdInit(memory,session,48000);atomic_store(&memory->lease,mach_absolute_time()+leaseTicks);
  queue=dispatch_queue_create("RightDisplay.Transport.Consumer",DISPATCH_QUEUE_SERIAL);
  connection=xpc_connection_create_mach_service(RD_SERVICE,queue,XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
  if(xpc_connection_set_peer_code_signing_requirement(connection,RD_BROKER_REQUIREMENT)){close();throw std::runtime_error("TRANSPORT_PEER_REQUIREMENT_FAILED");}
  // Handler owns no C++ pointer: memory lives until connection-barrier + queue drain.
  auto owner=lifetime;RDTransport* mapped=memory;
  xpc_connection_set_event_handler(connection,^(xpc_object_t event){(void)owner;if(xpc_get_type(event)==XPC_TYPE_ERROR){atomic_store(&mapped->active,0);atomic_store(&mapped->failure,3);}});xpc_connection_resume(connection);
  xpc_object_t request=xpc_dictionary_create(nullptr,nullptr,0),shared=xpc_shmem_create(memory,rdMappingBytes());
  if(!shared){xpc_release(request);close();throw std::runtime_error("TRANSPORT_SHMEM_FAILED");}
  xpc_dictionary_set_string(request,"op","attach");xpc_dictionary_set_uint64(request,"session",session);xpc_dictionary_set_value(request,"memory",shared);xpc_release(shared);
  dispatch_semaphore_t done=dispatch_semaphore_create(0);
  struct Result {bool ok=false;std::string error="CONNECTION_FAILED";};auto result=std::make_shared<Result>();dispatch_retain(done);
  xpc_connection_send_message_with_reply(connection,request,queue,^(xpc_object_t reply){if(xpc_get_type(reply)==XPC_TYPE_DICTIONARY){const char* error=xpc_dictionary_get_string(reply,"error");result->ok=!error;result->error=error?error:"CONTRACT_UNCONFIRMED";}dispatch_semaphore_signal(done);dispatch_release(done);});xpc_release(request);
  bool completed=dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0;
  // Blocks capture semaphore/result; drain before releasing local ownership.
  if(!completed||!result->ok||!rdValid(memory,session)||!atomic_load(&memory->active)){close();dispatch_release(done);throw std::runtime_error(completed ? "TRANSPORT_"+result->error : "TRANSPORT_HANDSHAKE_TIMEOUT");}
  dispatch_release(done);producer=atomic_load(&memory->producer);if(!producer){close();throw std::runtime_error("TRANSPORT_GENERATION_INVALID");}
  trace.oldContext=TransportContextSnapshot::read(memory,mach_absolute_time());
 }
 ~TransportClient(){close();}
 void close()noexcept{
  if(memory){atomic_store(&memory->consumer,0);atomic_store(&memory->active,0);}
  if(connection){xpc_connection_cancel(connection);dispatch_sync(queue,^{});xpc_release(connection);connection=nullptr;}
  if(queue){dispatch_release(queue);queue=nullptr;}
  memory=nullptr;lifetime.reset();
 }
 void renew()noexcept{if(memory)atomic_store(&memory->lease,mach_absolute_time()+leaseTicks);}
 bool valid(uint32_t caller=1)noexcept{return trace.validate(memory,session,producer,mach_absolute_time(),caller);}
};
}
