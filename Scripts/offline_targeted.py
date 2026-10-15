# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[1];w=r/'Tests';out=r/'Build/offline-tests';out.mkdir(parents=True,exist_ok=True)
def run(cmd,name):
 p=subprocess.run(cmd,capture_output=True,text=True);(out/(name+'.log')).write_text(p.stdout+p.stderr);print(name,'PASS' if p.returncode==0 else 'FAIL',flush=True)
 if p.returncode:print(p.stdout+p.stderr);raise SystemExit(1)
flags=['-std=c++20','-fblocks','-Wall','-Wextra','-Werror','-fno-fast-math','-pthread','-O2'];lib=['-framework','CoreAudio','-framework','CoreFoundation']
src=r/'RightDisplay/AudioBridgeRealtime'
for name in ['core','hal','route']:run(['clang++',*flags,'-c',str(src/(name+'.cpp')),'-o',str(out/(name+'.o'))],name+'-compile')
objects=[str(out/(name+'.o')) for name in ['core','hal','route']]
swift=['xcrun','swiftc','-swift-version','5','-module-cache-path',str(out/'SwiftCache'),'-import-objc-header',str(src/'AudioBridgeC.h')]
common=[str(r/p) for p in ['RightDisplay/Models/VirtualVolumeState.swift','RightDisplay/Services/AudioDeviceProvider.swift','RightDisplay/Services/AudioBridgeEngine.swift']]
for name,test in [('diagnostic',w/'DiagnosticCaptureTests.swift'),('heartbeat',r/'Tests/AudioBridgeHeartbeatTests.swift'),('controller',r/'Tests/VirtualVolumeControllerTests.swift')]:
 files=common+[str(test)]
 if name!='diagnostic':files.insert(-1,str(r/'RightDisplay/Services/VirtualVolumeController.swift'))
 # Use test copies with no-op evidence sinks to avoid polluting user's real evidence file.
 if name!='diagnostic':
  text=test.read_text().replace('AudioBridgeEngine(backend:HeartbeatBackend())','AudioBridgeEngine(backend:HeartbeatBackend(), evidence:{ _ in })').replace('AudioBridgeEngine(backend:backend)','AudioBridgeEngine(backend:backend, evidence:{ _ in })');copy=out/test.name;copy.write_text(text);files[-1]=str(copy)
 exe=out/name;run([*swift,*files,*objects,'-lc++',*lib,'-o',str(exe)],name+'-compile');run([str(exe)],name)
for name,files in [('physical-context',[src/'core.cpp',src/'hal.cpp',src/'route.cpp',r/'Tests/VirtualAudioFakeHALTests.cpp']),('transport-context',[r/'Tests/TransportContextTraceTests.cpp'])]:
 exe=out/name;run(['clang++',*flags,*map(str,files),*lib,'-o',str(exe)],name+'-compile');run([str(exe)],name)
