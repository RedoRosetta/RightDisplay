#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Offline only: quality, interposed fake HAL, Swift model/control, sanitizers."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parent.parent
out = Path(tempfile.mkdtemp(prefix='RightDisplay-Build12-AudioTests-',dir='/private/tmp'))
src = root/'RightDisplay/AudioBridgeRealtime'
flags = ['-std=c++20','-fblocks','-Wall','-Wextra','-Wpedantic','-Werror','-fno-fast-math','-pthread']
sources = [str(src/'core.cpp'),str(src/'hal.cpp'),str(src/'route.cpp')]
libs = ['-framework','CoreAudio','-framework','CoreFoundation']
def run(args, log):
    with (out/log).open('w') as stream:
        result = subprocess.run(args,cwd=root,stdout=stream,stderr=subprocess.STDOUT)
    if result.returncode:
        print((out/log).read_text());raise SystemExit(f'FAIL {log} / evidence={out}')
for suffix,opts in [('optimized',['-O2']),('asan-ubsan',['-O1','-g','-fno-omit-frame-pointer','-fsanitize=address,undefined']),('tsan',['-O1','-g','-fsanitize=thread'])]:
    for name,test in [('quality','AudioBridgeQualityTests.cpp'),('fake-hal','AudioBridgeFakeHALTests.cpp')]:
        executable=out/f'{name}-{suffix}'
        run(['clang++']+flags+opts+sources+[str(root/'Tests'/test)]+libs+['-o',str(executable)],f'{name}-{suffix}-build.log')
        run([str(executable)],f'{name}-{suffix}.log')
        print((out/f'{name}-{suffix}.log').read_text().splitlines()[-1])
for name in ['core','hal','route']:
    run(['clang++']+flags+['--analyze',str(src/f'{name}.cpp'),'-Xanalyzer','-analyzer-output=text'],f'{name}-analysis.log')
    if (out/f'{name}-analysis.log').stat().st_size:raise SystemExit(f'Static diagnostics: {out}')
    run(['clang++']+flags+['-c',str(src/f'{name}.cpp'),'-o',str(out/f'{name}.o')],f'{name}-object.log')
exporter=(root/'RightDisplay/Services/DiagnosticReportExporter.swift').read_text()
(out/'DisplayPrivacy.swift').write_text('import Foundation\n'+exporter[exporter.index('struct DiagnosticPrivacyRedactor'):exporter.index('struct DiagnosticEvent:')])
exe=out/'swift-integration'
swift=['xcrun','swiftc','-swift-version','5','-warnings-as-errors','-module-cache-path',str(out/'ModuleCache'),'-import-objc-header',str(src/'AudioBridgeC.h')]
swift += [str(root/f) for f in ['RightDisplay/Models/VirtualVolumeState.swift','RightDisplay/Services/AudioDeviceProvider.swift','RightDisplay/Services/AudioBridgeEngine.swift','Tests/VirtualVolumeIntegrationTests.swift']]
run(swift+[str(out/'DisplayPrivacy.swift'),str(out/'core.o'),str(out/'hal.o'),str(out/'route.o'),'-lc++']+libs+['-o',str(exe)],'swift-build.log')
run([str(exe)],'swift-integration.log')
print((out/'swift-integration.log').read_text().strip())
print('STATIC_ANALYSIS=PASS; WARNINGS_AS_ERRORS=PASS; no real HAL start; evidence='+str(out))
