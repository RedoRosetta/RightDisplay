# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[1];w=r/'Tests';src=r/'RightDisplay/AudioBridgeRealtime';out=r/'Build/offline-tests';out.mkdir(parents=True,exist_ok=True);lib=['-framework','CoreAudio','-framework','CoreFoundation']
def run(cmd,n):
 p=subprocess.run(cmd,capture_output=True,text=True);(out/(n+'.log')).write_text(p.stdout+p.stderr);print(n,p.returncode,p.stdout[-300:],p.stderr[-1000:],flush=True)
 if p.returncode:raise SystemExit(1)
for n,test,include in [('recovery-fake-hal','RecoveryFakeHALTests.cpp',False),('in-flight-retirement','InFlightRetirementTests.cpp',True),('bounded-retirement','BoundedRetirementTests.cpp',False)]:
 files=[src/'core.cpp',src/'route.cpp']+([] if include else [src/'hal.cpp'])+[w/test]
 run(['clang++','-std=c++20','-fblocks','-Wall','-Wextra','-Werror','-pthread','-O2',*map(str,files),*lib,'-o',str(out/n)],n+'-compile');run([str(out/n)],n)
run(['xcrun','swiftc','-swift-version','5','-module-cache-path',str(out/'SwiftCache'),'-import-objc-header',str(src/'AudioBridgeC.h'),*map(str,[r/'RightDisplay/Models/VirtualVolumeState.swift',r/'RightDisplay/Services/AudioDeviceProvider.swift',r/'RightDisplay/Services/AudioBridgeEngine.swift',r/'RightDisplay/Services/VirtualVolumeController.swift',w/'RecoveryControllerTests.swift']),*map(str,[out/'core.o',out/'hal.o',out/'route.o']),'-lc++',*lib,'-o',str(out/'recovery-controller')],'recovery-controller-compile')
run([str(out/'recovery-controller')],'recovery-controller')
