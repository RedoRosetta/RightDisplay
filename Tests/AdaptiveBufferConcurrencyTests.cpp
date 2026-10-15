// Copyright © 2026 RedoRosetta
// First-party portions licensed under RNSL 1.0; see LICENSE_SCOPE.md.
#include "../RightDisplay/AudioBridgeRealtime/buffer_plan.hpp"
#include "../RightDisplay/AudioBridgeRealtime/route_buffer.hpp"
#include <thread>
#include <iostream>
int main(){using namespace bridge;auto p=BufferPlan::make({48000,2,32,8,192,192,true,false},{48000,2,32,8,256,256,true,false});RouteBuffer ring(p.target,48000,48000,p.capacity);std::atomic<bool> done{false};std::atomic<unsigned> errors{0};
 std::thread producer([&]{Frame frames[128]{};for(unsigned i=0;i<3000;){if(ring.fill()<8192){if(!ring.push(frames,128))errors++;++i;}else std::this_thread::yield();}done=true;});Frame out[256];
 while(!done||ring.fill()>4608){if(ring.fill()>=4608){if(!ring.render(out,256))errors++;}else std::this_thread::yield();}
 producer.join();if(errors||ring.overruns||ring.underruns)return 1;std::cout<<"Adaptive SPSC concurrency PASS; fixed capacity="<<p.capacity<<" observedPeak="<<ring.peak.load()<<"\n";
}
