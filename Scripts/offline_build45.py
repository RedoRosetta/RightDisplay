#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# Licensed under RNSL 1.0.
from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[1];out=r/'Build/build45-tests';out.mkdir(parents=True,exist_ok=True);src=r/'RightDisplay/AudioBridgeRealtime'
flags=['-std=c++20','-fblocks','-Wall','-Wextra','-Werror','-pthread','-O2'];libs=['-framework','CoreAudio','-framework','CoreFoundation']
for name,test,objects in [('plan','SessionBufferPlanTests.cpp',[]),('concurrency','AdaptiveBufferConcurrencyTests.cpp',[]),('format','AdaptiveFormatGuardTests.cpp',[src/'core.cpp',src/'hal.cpp',src/'route.cpp']),('playback','AdaptivePlaybackHALTests.cpp',[src/'core.cpp',src/'hal.cpp',src/'route.cpp']),('dsp','VirtualAudioRouteTests.cpp',[])]:
 exe=out/name
 for cmd in [['clang++',*flags,str(r/'Tests'/test),*map(str,objects),*libs,'-o',str(exe)],[str(exe)]]:
  p=subprocess.run(cmd,capture_output=True,text=True);(out/(name+('-compile' if cmd[0]=='clang++' else '')+'.log')).write_text(p.stdout+p.stderr)
  if p.returncode:raise SystemExit(p.stdout+p.stderr)
 print(name+' PASS',flush=True)
