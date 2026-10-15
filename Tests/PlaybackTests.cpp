// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#include "../RightDisplay/AudioBridgeRealtime/playback.hpp"
#include <iostream>
#include <cassert>
#include <cstdlib>
static std::atomic<size_t> allocations{0};
void* operator new(size_t n){allocations++;if(auto p=std::malloc(n))return p;throw std::bad_alloc();}
void operator delete(void* p)noexcept{std::free(p);}
void* operator new[](size_t n){return ::operator new(n);}
void operator delete[](void* p)noexcept{std::free(p);}
int main(){using namespace bridge;size_t checks=0;auto check=[&](bool v){checks++;assert(v);};
 for(double rate:{44100.,48000.,88200.,96000.,176400.,192000.}){
  auto expected=fixture("channels",2,rate);Playback p("channels",rate,1,7);Frame out[1];uint32_t ramp=uint32_t(std::round(rate*.010));auto count=allocations.load();
  for(size_t i=0;i<ramp+64;i++){check(p.render(out,1,7,0));if(i>=ramp){check(out[0].l==expected[i].l&&out[0].r==expected[i].r);}else{check(std::abs(out[0].l-expected[i].l*float(i+1)/float(ramp))<1e-7);}}
  check(allocations==count);p.commandMute(true);for(unsigned i=0;i<ramp;i++)check(p.render(out,1,7,0));check(out[0].l==0&&out[0].r==0);check(allocations==count);
  p.stop();check(!p.render(out,1,7,0)&&out[0].l==0&&out[0].r==0);check(!p.render(out,1,8,0));
 }
 std::cout<<"Unified production playback: "<<checks<<" assertions PASS; six rates, exact unity after 10 ms ramp, mute, stale epoch, zero callback allocations\n";
}
