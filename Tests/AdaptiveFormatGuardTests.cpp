// Copyright © 2026 RedoRosetta
// First-party portions licensed under RNSL 1.0; see LICENSE_SCOPE.md.
#include "../RightDisplay/AudioBridgeRealtime/hal.hpp"
#include <iostream>
int main(){using namespace bridge;unsigned n=0;auto check=[&](bool x){++n;if(!x)throw std::runtime_error("format guard");};
 for(auto pair:{std::pair{16U,2U},std::pair{24U,3U},std::pair{24U,4U},std::pair{32U,4U}}){auto [bits,bytes]=pair;AudioStreamBasicDescription f{48000,kAudioFormatLinearPCM,UInt32(kAudioFormatFlagIsSignedInteger|(bits==bytes*8?kAudioFormatFlagIsPacked:0)),bytes*2,1,bytes*2,2,bits,0};check(physicalFormatAllowed(f));check(clientFormatAllowed(f));}
 AudioStreamBasicDescription f{48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};check(physicalFormatAllowed(f)&&clientFormatAllowed(f));f.mFormatFlags|=kAudioFormatFlagIsNonInterleaved;f.mBytesPerFrame=f.mBytesPerPacket=4;check(physicalFormatAllowed(f)&&clientFormatAllowed(f));check(layoutAllowed({1,1},true));check(!layoutAllowed({2},true));f.mChannelsPerFrame=6;check(physicalFormatAllowed(f)&&clientFormatAllowed(f));f.mChannelsPerFrame=2;f.mBitsPerChannel=64;f.mBytesPerFrame=f.mBytesPerPacket=8;check(!clientFormatAllowed(f));f.mFormatID=kAudioFormatAC3;check(!physicalFormatAllowed(f)&&!clientFormatAllowed(f));std::cout<<"PCM physical/client/layout guards: "<<n<<" assertions PASS; unsupported paths rejected\n";
}
