// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#ifndef RD_PCM_TRANSPORT_H
#define RD_PCM_TRANSPORT_H
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#define RD_CAPACITY 32768u
#define RD_MAX_BLOCK 8192u
#define RD_PROTOCOL 21u
#define RD_SERVICE "com.rightdisplay.audio.Transport"
#include "../SigningIdentity.h"
typedef struct {float l,r;} RDFrame;
// C ABI used by C driver and C++ bridge. macOS arm64 lock-free atomics only.
typedef struct {
 uint64_t magic,session; uint32_t version,capacity,rate,channels;
 _Alignas(64) _Atomic(uint64_t) write;
 _Alignas(64) _Atomic(uint64_t) read;
 _Alignas(64) _Atomic(uint64_t) producer;
 _Atomic(uint64_t) consumer;
 _Atomic(uint64_t) lease;
 _Atomic(uint64_t) blocks,underruns,overruns;
 _Atomic(uint32_t) active,failure,volumeBits,mute,streaming;
 _Atomic(uint64_t) streamEpoch;
 RDFrame frames[RD_CAPACITY];
} RDTransport;
static inline size_t rdMappingBytes(void){size_t page=(size_t)getpagesize();return (sizeof(RDTransport)+page-1)/page*page;}
#define RD_MAGIC UINT64_C(0x524450434d303231)
static inline void rdInit(RDTransport* t,uint64_t session,uint32_t rate){
 memset(t,0,sizeof(*t));t->magic=RD_MAGIC;t->session=session;t->version=RD_PROTOCOL;t->capacity=RD_CAPACITY;t->rate=rate;t->channels=2;
 atomic_init(&t->write,0);atomic_init(&t->read,0);atomic_init(&t->producer,0);atomic_init(&t->consumer,session);atomic_init(&t->lease,0);atomic_init(&t->blocks,0);atomic_init(&t->underruns,0);atomic_init(&t->overruns,0);atomic_init(&t->active,0);atomic_init(&t->failure,0);float unity=1;uint32_t bits;memcpy(&bits,&unity,4);atomic_init(&t->volumeBits,bits);atomic_init(&t->mute,0);atomic_init(&t->streaming,0);atomic_init(&t->streamEpoch,0);
}
static inline int rdValid(const RDTransport* t,uint64_t session){return t&&t->magic==RD_MAGIC&&t->version==RD_PROTOCOL&&t->capacity==RD_CAPACITY&&t->rate==48000&&t->channels==2&&t->session==session&&session!=0;}
// No retries, allocation, locks, syscall or gain in the producer. Overflow latches
// a safe terminal failure; consumer cannot silently skip/duplicate a sample.
static inline int rdPush(RDTransport* t,uint64_t generation,const RDFrame* f,uint32_t n,uint64_t now){
 if(!t||!f||!n||n>RD_MAX_BLOCK||!atomic_load_explicit(&t->active,memory_order_acquire)||atomic_load(&t->producer)!=generation||atomic_load(&t->consumer)!=t->session||now>atomic_load(&t->lease)||atomic_load(&t->failure))return 0;
 uint64_t w=atomic_load_explicit(&t->write,memory_order_relaxed),r=atomic_load_explicit(&t->read,memory_order_acquire);
 if(w<r||w-r>RD_CAPACITY||n>RD_CAPACITY-(w-r)){atomic_fetch_add(&t->overruns,1);atomic_store(&t->failure,1);return 0;}
 for(uint32_t i=0;i<n;i++){if(!isfinite(f[i].l)||!isfinite(f[i].r)){atomic_store(&t->failure,2);return 0;}t->frames[(w+i)&(RD_CAPACITY-1)]=f[i];}
 atomic_store_explicit(&t->write,w+n,memory_order_release);atomic_fetch_add(&t->blocks,1);return 1;
}
static inline uint32_t rdPop(RDTransport* t,uint64_t generation,RDFrame* f,uint32_t maximum){
 if(!t||!f||maximum>RD_MAX_BLOCK||!atomic_load(&t->active)||atomic_load(&t->producer)!=generation||atomic_load(&t->consumer)!=t->session||atomic_load(&t->failure))return 0;
 uint64_t r=atomic_load_explicit(&t->read,memory_order_relaxed),w=atomic_load_explicit(&t->write,memory_order_acquire);if(w<r||w-r>RD_CAPACITY)return 0;
 uint32_t n=(uint32_t)(w-r);if(n>maximum)n=maximum;for(uint32_t i=0;i<n;i++)f[i]=t->frames[(r+i)&(RD_CAPACITY-1)];atomic_store_explicit(&t->read,r+n,memory_order_release);return n;
}
#endif
