#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Run production warning presentation/update with invisible view doubles."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parent.parent
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build30-tests-',dir='/private/tmp'))
s=(root/'RightDisplay/Views/SettingsSupportViews.swift').read_text()
b=(root/'RightDisplay/Services/DisplayBrightnessStore.swift').read_text()
model=b[b.index('struct BrightnessDragProtection {'):b.index('@MainActor')]
policy=s[s.index('enum BrightnessWarningPresentation {'):s.index('struct BrightnessWarningAnchor:')]
update=s[s.index('    func updateNSView(_ view: Marker',s.index('struct BrightnessWarningAnchor:')):s.index('    static func dismantleNSView',s.index('struct BrightnessWarningAnchor:'))]
src='''import Foundation
'''+model+policy+'''
struct Marker {}
final class Coordinator {
 var sequence:UInt64;var visible=false;var shows=0
 init(sequence:UInt64){self.sequence=sequence}
 func hide(){visible=false}
 func show(below:Marker){visible=true;shows+=1}
}
struct Context {let coordinator:Coordinator}
struct Harness {var brightness:Double;var sequence:UInt64;var source:String?;let controlID="advanced-brightness"
'''+update+'''}
@main struct Tests {
 static func main(){
 var n=0;func check(_ v:Bool){n+=1;precondition(v)}
 check(BrightnessWarningPresentation.duration==2)
 for v in [Double(0),0.1,0.2,Double(Float(0.2))] {check(!BrightnessWarningPresentation.shouldHide(brightness:v))}
 for v in [Double(0.201),0.5,1,.nan,.infinity] {check(BrightnessWarningPresentation.shouldHide(brightness:v))}
 let c=Coordinator(sequence:0);let context=Context(coordinator:c)
 var h=Harness(brightness:0.2,sequence:1,source:"advanced-brightness")
 h.updateNSView(Marker(),context:context);check(c.visible && c.shows==1)
 h.brightness=1;h.updateNSView(Marker(),context:context);check(!c.visible)
 h.brightness=0.1;h.updateNSView(Marker(),context:context);check(!c.visible && c.shows==1)
 h.sequence=2;h.source="quick-brightness";h.updateNSView(Marker(),context:context);check(c.shows==1)
 h.sequence=3;h.source="advanced-brightness";h.updateNSView(Marker(),context:context);check(c.visible && c.shows==2)
 h.brightness=Double(Float(0.2));h.updateNSView(Marker(),context:context);check(c.visible)
 print("Build 30 brightness presentation: \\(n) assertions PASS; real policy/update, no hardware write or visible window")
 }
}
'''
f=out/'tests.swift';f.write_text(src)
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(out/'ModuleCache'),str(f),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
