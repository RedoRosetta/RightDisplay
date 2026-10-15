// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#include <iostream>
#include <memory>
#include <stdexcept>
#include "../RightDisplay/AudioBridgeRealtime/transport_context.hpp"
int main(){int n=0;auto check=[&](bool v){++n;if(!v)throw std::runtime_error("transport trace assertion "+std::to_string(n));};
 auto t=std::make_unique<RDTransport>();rdInit(t.get(),42,48000);atomic_store(&t->producer,7);atomic_store(&t->active,1);atomic_store(&t->lease,1000);
 bridge::TransportContextTrace trace;trace.oldContext=bridge::TransportContextSnapshot::read(t.get(),100);
 for(int i=0;i<100;i++)check(trace.validate(t.get(),42,7,200,2));
 check(trace.publication.load()==0);atomic_store(&t->producer,8);check(!trace.validate(t.get(),42,7,201,2));
 check(trace.detail().find("DIFF_FIELDS=producer,")!=std::string::npos);check(trace.detail().find("TIMESTAMP_MACH=201")!=std::string::npos);
 atomic_store(&t->consumer,0);check(!trace.validate(t.get(),42,7,202,1));check(trace.detail().find("TIMESTAMP_MACH=201")!=std::string::npos);
 auto s=bridge::TransportContextSnapshot::read(t.get(),2001);check((s.differences(42,7)&(128|256|1024))==(128|256|1024));
 rdInit(t.get(),42,48000);atomic_store(&t->active,1);atomic_store(&t->producer,7);atomic_store(&t->lease,1000);
 atomic_store(&t->failure,1);atomic_store(&t->overruns,1);s=bridge::TransportContextSnapshot::read(t.get(),200);
 check(s.overruns==1&&s.failure==1&&s.differences(42,7)==512);check(s.describe().find("transportOverrun=1")!=std::string::npos);
 for(unsigned bit=0;bit<11;bit++){
  rdInit(t.get(),42,48000);atomic_store(&t->active,1);atomic_store(&t->producer,7);atomic_store(&t->lease,1000);
  bridge::TransportContextTrace fault;fault.oldContext=bridge::TransportContextSnapshot::read(t.get(),100);
  switch(bit){case 0:t->magic=0;break;case 1:t->version=0;break;case 2:t->capacity=0;break;case 3:t->rate=96000;break;case 4:t->channels=1;break;case 5:t->session=43;break;case 6:atomic_store(&t->active,0);break;case 7:atomic_store(&t->producer,8);break;case 8:atomic_store(&t->consumer,43);break;case 9:atomic_store(&t->failure,3);break;case 10:atomic_store(&t->lease,1);break;}
  check(!fault.validate(t.get(),42,7,200,2));check(fault.diff==(1U<<bit));check(fault.publication.load()==2);
 }
 std::cout<<"Transport trace: "<<n<<" assertions PASS; no HAL/XPC/real audio\n";
}
