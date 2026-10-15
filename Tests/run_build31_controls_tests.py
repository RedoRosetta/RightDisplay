#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Measure the actual shared slider control offscreen; no playback or writes."""
from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parent.parent
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build31-control-',dir='/private/tmp'))
s=(root/'RightDisplay/Views/SettingsSupportViews.swift').read_text()
control=s[s.index('struct VolumeLevelControl:'):s.index('// Scope scrollbar')]
control=control.replace('.accessibilityLabel(accessibilityLabel)', '.accessibilityLabel(accessibilityLabel).onGeometryChange(for:CGRect.self){$0.frame(in:.named("control"))} action:{measurements["slider"]=$0}')
control=control.replace('.frame(width:38,alignment:.trailing)', '.frame(width:38,alignment:.trailing).onGeometryChange(for:CGRect.self){$0.frame(in:.named("control"))} action:{measurements["percent"]=$0}')
src='''import AppKit
import SwiftUI
var measurements:[String:CGRect]=[:]
'''+control+'''
@main struct Tests {
 @MainActor static func main(){
 _ = NSApplication.shared
 var n=0;func check(_ value:Bool){n+=1;precondition(value)}
 for percent in [0,20,100] {
 measurements=[:]
 let host=NSHostingView(rootView:VolumeLevelControl(value:.constant(Double(percent)/100),percent:percent,accessibilityLabel:"level").coordinateSpace(name:"control"))
 let window=NSWindow(contentRect:NSRect(x:0,y:0,width:326,height:32),styleMask:[.borderless],backing:.buffered,defer:false)
 window.isReleasedWhenClosed=false;window.contentView=host
 host.frame=NSRect(x:0,y:0,width:326,height:32);host.layoutSubtreeIfNeeded()
 RunLoop.main.run(until:Date().addingTimeInterval(0.1))
 check(measurements["slider"] != nil && measurements["percent"] != nil)
 let slider=measurements["slider"]!,label=measurements["percent"]!
 check(abs(label.minX-slider.maxX-10)<0.01)
 check(abs(label.maxX-326)<0.01)
 check(abs(slider.width-278)<0.01)
 check(!window.isVisible);window.close()
 }
 print("Build 31 controls: \\(n) assertions PASS; actual shared control at 0/20/100%, 10 pt gap and stable trailing edge; no writes")
 }
}
'''
f=out/'tests.swift';f.write_text(src)
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(out/'ModuleCache'),str(f),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
