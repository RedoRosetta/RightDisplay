#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Exercise the production status policy without display writes or a GUI."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
out=Path(tempfile.mkdtemp(prefix='RightDisplay-StatusTests-',dir='/private/tmp'))
source='''import Foundation
var count=0
func check(_ actual:DisplayStatusIndicator,_ expected:DisplayStatusIndicator){count+=1;precondition(actual==expected,"status assertion \\(count)")}
for raw:UInt32 in [0,1] {check(.pixelEncoding(raw:raw,known:true),.green)}
for raw:UInt32 in [2,3] {check(.pixelEncoding(raw:raw,known:true),.yellow)}
check(.pixelEncoding(raw:nil,known:true),.gray)
check(.pixelEncoding(raw:99,known:true),.gray)
check(.pixelEncoding(raw:0,known:false),.gray)
check(.hdr(systemManaged:true,supported:true,enabled:nil,known:true),.green)
check(.hdr(systemManaged:true,supported:true,enabled:nil,known:false),.gray)
check(.hdr(systemManaged:false,supported:true,enabled:true,known:true),.green)
check(.hdr(systemManaged:false,supported:true,enabled:false,known:true),.gray)
check(.hdr(systemManaged:false,supported:false,enabled:nil,known:true),.gray)
check(.vrr(enabled:true,known:true),.green)
check(.vrr(enabled:false,known:true),.gray)
check(.vrr(enabled:true,known:false),.gray)
print("Production display status: \\(count) assertions PASS")
'''
(out/'main.swift').write_text(source)
subprocess.run(['xcrun','swiftc','-module-cache-path',str(out/'cache'),str(root/'RightDisplay/Models/LinkPixelEncoding.swift'),str(out/'main.swift'),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
quick=(root/'RightDisplay/Views/QuickPanelView.swift').read_text();overview=(root/'RightDisplay/Views/SettingsView.swift').read_text()
for prop in ['pixelFormatIndicator','hdrIndicator']:
 assert prop in quick and prop in overview
assert 'value: display.pixelFormatSignal.text' in quick
assert 'status: display.vrrIndicator' in quick
print('Shared Quick Panel / Overview status and value integration guards PASS')
