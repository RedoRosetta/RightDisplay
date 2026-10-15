# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Production dwell and startup policy tests; no app launch or audio playback."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parent.parent
source=(root/'RightDisplay/Views/ColorProfilesView.swift').read_text()
inspection=source[source.index('final class ICCChartInspection:'):source.index('private struct ICCInspectionInteraction:')]
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build40-tests-',dir='/private/tmp'))
fixture=r'''import Foundation
import CoreGraphics
import Combine
import AppKit
'''+inspection+r'''
@main struct Tests {
 static func main() {
 var count=0
 func check(_ ok:Bool) { count += 1; precondition(ok,"Assertion \(count)") }
 let chart=ICCChartInspection();var publications=0
 let subscription=chart.$location.dropFirst().sink { _ in publications += 1 }
 for i in 0..<1000 { chart.moved(CGPoint(x:i,y:i)) }
 check(publications == 0);check(chart.location == nil)
 RunLoop.main.run(until:Date().addingTimeInterval(0.2));check(chart.location == nil)
 RunLoop.main.run(until:Date().addingTimeInterval(0.2));check(chart.location == CGPoint(x:999,y:999));check(publications == 1)
 for _ in 0..<1000 { chart.moved(CGPoint(x:999,y:999)) };check(publications == 1)
 chart.moved(CGPoint(x:20,y:20));check(chart.location == nil);chart.cancel()
 RunLoop.main.run(until:Date().addingTimeInterval(0.4));check(chart.location == nil)
 chart.clicked(CGPoint(x:10,y:12));check(chart.location == CGPoint(x:10,y:12))
 chart.moved(CGPoint(x:30,y:30));chart.clicked(CGPoint(x:40,y:40))
 RunLoop.main.run(until:Date().addingTimeInterval(0.4));check(chart.location == CGPoint(x:40,y:40));chart.cancel();check(chart.location == nil)
 _ = subscription
 check(VirtualAudioAutoStartPolicy.virtualSelected(systemDefault:false,controlUID:"RightDisplay.VirtualVolume"))
 check(VirtualAudioAutoStartPolicy.virtualSelected(systemDefault:true,controlUID:nil))
 check(!VirtualAudioAutoStartPolicy.virtualSelected(systemDefault:false,controlUID:nil))
 check(!VirtualAudioAutoStartPolicy.virtualSelected(systemDefault:false,controlUID:"physical"))
 var policy=VirtualAudioAutoStartPolicy(manuallyDisabled:false)
 let selected=VirtualAudioAutoStartPolicy.virtualSelected(systemDefault:false,controlUID:"RightDisplay.VirtualVolume")
 for _ in 0..<20 { check(!policy.shouldStart(virtualSelected:selected,eligible:false)) }
 check(policy.shouldStart(virtualSelected:selected,eligible:true));check(!policy.shouldStart(virtualSelected:selected,eligible:true))
 policy.userStopped();policy.targetSelected();check(!policy.shouldStart(virtualSelected:selected,eligible:true))
 let versions=RightDisplayReleaseHistory.notes.map(\.version)
 check(versions == ["0.4 Beta","0.3 Beta","0.2 Beta","0.1 Beta"])
 for name in ["play.circle","person.crop.circle.badge.checkmark","paintbrush.pointed","hifispeaker.2"] { check(NSImage(systemSymbolName:name,accessibilityDescription:nil) != nil) }
 check(NSFont(name:"AvenirNext-MediumItalic",size:23) != nil)
 print("Build 40 production dwell / automatic selection / release notes: \(count) assertions PASS; no hardware actions")
 }
}
'''
f=out/'Tests.swift';f.write_text(fixture)
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(out/'cache'),str(root/'RightDisplay/Models/VirtualVolumeState.swift'),str(root/'RightDisplay/Models/ReleaseNotes.swift'),str(f),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
