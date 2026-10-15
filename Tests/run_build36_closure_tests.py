# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Actual transport validation + first-failure snapshot; UI integration contracts."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parent.parent
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build36-tests-',dir='/private/tmp'))
for mode,flags in [('opt',['-O2']),('asan-ubsan',['-O1','-fsanitize=address,undefined']),('tsan',['-O1','-fsanitize=thread'])]:
 exe=out/mode
 subprocess.run(['clang++','-std=c++20','-Wall','-Wextra','-Werror']+flags+[str(root/'Tests/TransportContextTraceTests.cpp'),'-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
s=(root/'RightDisplay/Views/VirtualVolumeView.swift').read_text()
assert '悬停查看原因' not in s and 'hover for details' not in s
assert s.index('if controller.model.unexpectedStop')<s.index('if controller.forwardingEnabled { return')
assert 'controller.model.unexpectedStop ? Color.yellow' in s
assert 'if let error = controller.lastFailure' in s[s.index('private var audioDetails:'):]
assert 'if let error = controller.lastFailure' not in s[:s.index('private var audioDetails:')]
g=(root/'RightDisplay/Views/SettingsSupportViews.swift').read_text()
assert '.scaleEffect' not in g[g.index('struct GlassCard<'):g.index('struct AdaptiveGlassCard:')]
print('Build 36 transport/UI/hover contracts PASS; evidence='+str(out))
