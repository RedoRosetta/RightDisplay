# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Compile the actual production broker admission block with offline XPC/user doubles."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
broker=(root/'AudioVirtualDevice/Broker/main.c').read_text()
admission=broker[broker.index('  int isProducer;'):broker.index('  xpc_connection_set_target_queue(peer,queue);')]
producer=broker[broker.index('static const char* producerRequirement'):broker.index('static xpc_connection_t producer,consumer;')]
assert 'com.rightdisplay.gui' not in admission and 'subject.OU' not in admission
fixture=r"""
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <cstring>
using uid_t=unsigned int;
struct Peer {uid_t uid;int signing;bool cancelled=false;int requirementCalls=0;const char* requirement=nullptr;};
using xpc_connection_t=Peer*;using CFStringRef=void*;
static uid_t console=501;
static uid_t xpc_connection_get_euid(Peer* p){return p->uid;}
static int xpc_connection_set_peer_code_signing_requirement(Peer*p,const char*r){p->requirementCalls++;p->requirement=r;return p->signing==9;}
static void xpc_connection_cancel(Peer*p){p->cancelled=true;}
static CFStringRef SCDynamicStoreCopyConsoleUser(void*,uid_t* u,void*){*u=console;return nullptr;}
static void CFRelease(CFStringRef){}
"""+producer+'\nstatic void admit(Peer* peer){\n'+admission+'\n}\n'+r"""
int main(){int n=0;auto check=[&](bool v){n++;assert(v);};
// Signing modes only label the fixtures. Consumer admission must not query any signature.
for(int signing:{1,2,3,4}){Peer p{501,signing};admit(&p);check(!p.cancelled);check(p.requirementCalls==0);}
Peer other{502,1};admit(&other);check(other.cancelled);check(other.requirementCalls==0);
console=0;Peer noConsole{501,1};admit(&noConsole);check(noConsole.cancelled);check(noConsole.requirementCalls==0);console=501;
for(uid_t uid:{0u,202u}){Peer p{uid,1};admit(&p);check(!p.cancelled);check(p.requirementCalls==1);check(p.requirement==producerRequirement);}
Peer setupFailure{0,9};admit(&setupFailure);check(setupFailure.cancelled);check(setupFailure.requirementCalls==1);
check(strstr(producerRequirement,"anchor apple")!=nullptr);check(strstr(producerRequirement,"com.apple.audio.coreaudiod")!=nullptr);
printf("Build41 production broker admission: %d assertions PASS; no live XPC/audio\n",n);}
"""
fixture=fixture.replace('#include <cstdint>','#include <cstdint>\n#include <initializer_list>')
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build41-IdentityPolicy-',dir='/private/tmp'));p=out/'tests.cpp';p.write_text(fixture)
subprocess.run(['xcrun','clang++','-std=c++20','-O2','-Wall','-Wextra','-Werror',str(p),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
