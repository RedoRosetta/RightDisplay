// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#include "../AudioVirtualDevice/Transport/PCMTransport.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
#include <pthread.h>
static unsigned checks;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"transport failure %u\n",checks);exit(1);}}while(0)
static void ready(RDTransport* t,uint64_t s,uint64_t p){rdInit(t,s,48000);atomic_store(&t->producer,p);atomic_store(&t->active,1);atomic_store(&t->lease,UINT64_MAX);}
int main(void){RDTransport* t=mmap(NULL,sizeof(*t),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANON,-1,0);CHECK(t!=MAP_FAILED);RDFrame f[8192],out[8192];for(unsigned i=0;i<8192;i++)f[i]=(RDFrame){(float)i,-(float)i};
 ready(t,10,20);CHECK(rdValid(t,10));CHECK(!rdValid(t,11));CHECK(!rdPush(t,19,f,32,1));CHECK(rdPop(t,19,out,32)==0);CHECK(rdPush(t,20,f,8192,1));CHECK(rdPop(t,20,out,8192)==8192);for(unsigned i=0;i<8192;i++)CHECK(out[i].l==f[i].l&&out[i].r==f[i].r);
 for(int wrap=0;wrap<12;wrap++){CHECK(rdPush(t,20,f,8192,1));CHECK(rdPop(t,20,out,8192)==8192);CHECK(out[8191].l==8191);}
 CHECK(rdPop(t,20,out,32)==0);for(int i=0;i<4;i++)CHECK(rdPush(t,20,f,8192,1));CHECK(!rdPush(t,20,f,1,1));CHECK(atomic_load(&t->failure)==1&&atomic_load(&t->overruns)==1);CHECK(rdPop(t,20,out,32)==0);
 ready(t,11,21);CHECK(!rdPush(t,20,f,1,1));CHECK(!rdValid(t,10));atomic_store(&t->consumer,0);CHECK(!rdPush(t,21,f,1,1));ready(t,12,22);t->rate=96000;CHECK(!rdValid(t,12));t->rate=48000;t->channels=1;CHECK(!rdValid(t,12));
 ready(t,13,23);atomic_store(&t->active,0);CHECK(!rdPush(t,23,f,1,1));ready(t,14,24);atomic_store(&t->lease,1);CHECK(!rdPush(t,24,f,1,2));ready(t,15,25);f[0].l=NAN;CHECK(!rdPush(t,25,f,1,1));CHECK(atomic_load(&t->failure)==2);
 // Actual separate address spaces, not just a fake in-process ring.
 ready(t,16,26);pid_t child=fork();CHECK(child>=0);if(child==0){RDFrame pcm[128];for(unsigned b=0;b<1000;b++){for(unsigned j=0;j<128;j++)pcm[j]=(RDFrame){(float)(b*128+j),-(float)(b*128+j)};while(atomic_load(&t->write)-atomic_load(&t->read)>RD_CAPACITY-128)usleep(100);if(!rdPush(t,26,pcm,128,1))_exit(2);} _exit(0);}
 unsigned frames=0;while(frames<128000){unsigned n=rdPop(t,26,out,8192);for(unsigned j=0;j<n;j++){CHECK(out[j].l==(float)(frames+j)&&out[j].r==-(float)(frames+j));}frames+=n;if(!n)usleep(100);}int status;waitpid(child,&status,0);CHECK(WIFEXITED(status)&&WEXITSTATUS(status)==0);atomic_store(&t->active,0);CHECK(!rdPush(t,26,f,1,1));CHECK(munmap(t,sizeof(*t))==0);printf("Cross-process PCM transport: %u assertions PASS\n",checks);return 0;}
