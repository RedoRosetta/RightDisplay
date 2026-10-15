#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
from pathlib import Path
import tempfile,subprocess,os,shutil
root=Path(__file__).resolve().parent.parent
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build13-VirtualAudioTests-',dir='/private/tmp'))
src=root/'RightDisplay/AudioBridgeRealtime'
flags=['-std=c++20','-fblocks','-Wall','-Wextra','-Wpedantic','-Werror','-fno-fast-math','-pthread']
libs=['-framework','CoreAudio','-framework','CoreFoundation']
def run(args,log):
 with (out/log).open('w') as f:r=subprocess.run(args,cwd=root,stdout=f,stderr=subprocess.STDOUT)
 if r.returncode:print((out/log).read_text());raise SystemExit('FAIL '+log)
for suffix,opt in [('optimized',['-O2']),('asan-ubsan',['-O1','-g','-fsanitize=address,undefined']),('tsan',['-O1','-g','-fsanitize=thread'])]:
 for name,files in [('dsp',[root/'Tests/VirtualAudioRouteTests.cpp']),('playback',[src/'core.cpp',root/'Tests/PlaybackTests.cpp']),('fake-hal',[src/'core.cpp',src/'hal.cpp',src/'route.cpp',root/'Tests/VirtualAudioFakeHALTests.cpp'])]:
  exe=out/(name+'-'+suffix)
  run(['clang++']+flags+opt+[str(p) for p in files]+libs+['-o',str(exe)],name+'-'+suffix+'-build.log')
  run([str(exe)],name+'-'+suffix+'.log');print((out/(name+'-'+suffix+'.log')).read_text().strip())
for suffix,opt in [('optimized',['-O2']),('asan-ubsan',['-O1','-g','-fsanitize=address,undefined'])]:
 exe=out/('transport-'+suffix)
 run(['clang','-std=c11','-D_DARWIN_C_SOURCE','-Wall','-Wextra','-Werror']+opt+[str(root/'Tests/PCMTransportTests.c'),'-o',str(exe)],'transport-'+suffix+'-build.log')
 run([str(exe)],'transport-'+suffix+'.log');print((out/('transport-'+suffix+'.log')).read_text().strip())
exe=out/'driver-test'
run(['clang','-std=c11','-fblocks','-O1','-g','-fsanitize=address,undefined',str(root/'Tests/VirtualAudioDriverTests.c')]+libs+['-o',str(exe)],'driver-build.log')
run([str(exe)],'driver.log');print((out/'driver.log').read_text().strip())
# Exercise package scripts only inside a redirected temporary filesystem, with
# fake signature and usage probes. Never execute scripts against /Library.
fs=out/'filesystem';driver=fs/'Library/Audio/Plug-Ins/HAL/RightDisplayVirtualVolume.driver';driver.mkdir(parents=True)
(driver/'sentinel').write_text('driver');other=driver.parent/'Unrelated.driver';other.mkdir();(other/'sentinel').write_text('keep')
mock=out/'codesign';mock.write_text('#!/bin/sh\n[ "${MOCK_VALID:-1}" = 1 ]\n');mock.chmod(0o755)
scripts=out/'Scripts';scripts.mkdir();probe=scripts/'CheckRemoval';probe.write_text('#!/bin/sh\nexit "${MOCK_USAGE_RESULT:-0}"\n');probe.chmod(0o755)
for action,file in [('uninstall','postinstall'),('install','preinstall')]:
 text=(root/'AudioVirtualDevice/Packaging'/action/file).read_text().replace('/Library',str(fs/'Library')).replace('/usr/bin/codesign',str(mock))
 (scripts/file).write_text(text)
assertions=0
def script(name,env,success):
 global assertions
 result=subprocess.run(['/bin/sh',str(scripts/name)],env=dict(os.environ,**env),capture_output=True)
 assert (result.returncode==0)==success,(name,result.stdout,result.stderr);assertions+=1
script('postinstall',{'MOCK_VALID':'0'},False);assert driver.exists()
script('postinstall',{'MOCK_USAGE_RESULT':'3'},False);assert driver.exists()
script('postinstall',{'MOCK_USAGE_RESULT':'2'},False);assert driver.exists()
script('preinstall',{'MOCK_VALID':'0'},False);assert driver.exists()
script('preinstall',{'MOCK_USAGE_RESULT':'3'},False);assert driver.exists()
script('preinstall',{},True);assert (fs/'Library/Application Support/RightDisplay/AudioDriverRollback/RightDisplayVirtualVolume.driver/sentinel').read_text()=='driver'
script('postinstall',{},True);assert not driver.exists() and (other/'sentinel').read_text()=='keep'
script('postinstall',{},True)
driver.symlink_to(other,target_is_directory=True);script('postinstall',{},False);assert other.exists()
print(f'Package lifecycle: {assertions} cases PASS; redirected paths, fake signature/usage, no installation')
print('Evidence='+str(out))

# Production controller with fake authorization and backend. No NSApplication,
# window, monitoring timer, HAL start, or real permission request.
for name in ['core','hal','route']:
 run(['clang++']+flags+['-c',str(src/(name+'.cpp')),'-o',str(out/(name+'.o'))],name+'-object.log')
exe=out/'controller-test'
swift=['xcrun','swiftc','-swift-version','5','-module-cache-path',str(out/'ModuleCache'),'-import-objc-header',str(src/'AudioBridgeC.h')]
swift += [str(root/f) for f in ['RightDisplay/Models/VirtualVolumeState.swift','RightDisplay/Services/AudioDeviceProvider.swift','RightDisplay/Services/AudioBridgeEngine.swift','RightDisplay/Services/VirtualVolumeController.swift','Tests/VirtualVolumeControllerTests.swift']]
run(swift+[str(out/(n+'.o')) for n in ['core','hal','route']]+['-lc++']+libs+['-o',str(exe)],'controller-build.log')
run([str(exe)],'controller.log');print((out/'controller.log').read_text().strip())
exe=out/'heartbeat-test'
heartbeatSwift=swift[:-1]+[str(root/'Tests/AudioBridgeHeartbeatTests.swift')]
run(heartbeatSwift+[str(out/(n+'.o')) for n in ['core','hal','route']]+['-lc++']+libs+['-o',str(exe)],'heartbeat-build.log')
run([str(exe)],'heartbeat.log');print((out/'heartbeat.log').read_text().strip())
