# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Hardware-free tests of production chart hover gating and interruption publication."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parent.parent
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build37-tests-',dir='/private/tmp'))
s=(root/'RightDisplay/Views/ColorProfilesView.swift').read_text()
geometry=s[s.index('struct ICCChartCoordinates {'):s.index('struct ICCXYPlot:')]
drawings=s[s.index('struct ICCXYDrawing:'):]
fixture=r'''
import Foundation
import CoreGraphics
import SwiftUI
import Combine
'''+geometry+drawings+r'''
final class NoticeSource: ObservableObject { @Published var model=VirtualVolumeStateModel(uid:"A") }
@main struct Tests {
 static func main() {
 var assertions=0
 func check(_ v:Bool,_ why:String) { assertions += 1; precondition(v,why) }
 var gate=ICCChartHoverGate()
 check(gate.update(CGPoint(x:0,y:0),now:0),"entry")
 for i in 1...1000 { check(!gate.update(CGPoint(x:0,y:0),now:Double(i)),"same coordinate is silent") }
 var publications=0
 for i in 1...1000 { if gate.update(CGPoint(x:i,y:i),now:Double(i)/1000) { publications += 1 } }
 check(publications <= 30 && publications >= 25,"bounded moving readout")
 check(gate.update(nil,now:1.0001),"exit bypasses throttle")
 check(gate.location == nil,"exit removes tooltip")
 check(!gate.update(nil,now:1.0002),"duplicate exit silent")
 check(gate.update(CGPoint(x:4,y:5),now:1.0003),"reentry immediate")
 let size=CGSize(width:330,height:330)
 let a=ICCXYDrawing(size:size,profile:nil,white:nil,reference:nil,english:false)
 check(a == ICCXYDrawing(size:size,profile:nil,white:nil,reference:nil,english:false),"same drawing input skips body")
 check(a != ICCXYDrawing(size:CGSize(width:331,height:330),profile:nil,white:nil,reference:nil,english:false),"resize updates drawing")
 check(a != ICCXYDrawing(size:size,profile:nil,white:nil,reference:nil,english:true),"language updates drawing")
 let c=ICCCalibrationDrawing(size:size,curves:[[0,0.5,1]],english:false)
 check(c == ICCCalibrationDrawing(size:size,curves:[[0,0.5,1]],english:false),"same curve input skips body")
 check(c != ICCCalibrationDrawing(size:size,curves:[[0,0.4,1]],english:false),"changed curve redraws")
 let source=NoticeSource(); var notices=0
 let subscription=source.$model.map(\.unexpectedStop).removeDuplicates().filter { $0 }.sink { _ in notices += 1 }
 let d=AudioBridgeDevice(uid:"A",deviceID:10,name:"Test",transport:0,rate:48000,channels:2,buffer:512,maxBlock:512,latency:nil,safety:nil,eligibility:"USABLE_DIRECT_PATH",physicalBits:24,physicalFloat:false,streamLatency:nil)
 func telemetry(_ failure:String)->AudioBridgeTelemetry { .init(epoch:1,callbacks:1,frames:512,fill:512,minFill:0,maxFill:512,capacity:4096,targetFill:512,underrun:0,overrun:0,ringMS:0,bufferMS:0,residenceMS:nil,failure:failure) }
 func run() { source.model.reconcile([d],generation:source.model.generation); let t=source.model.requestStart()!;source.model.started(generation:t,error:nil);source.model.observed(telemetry("NONE"),generation:t) }
 run();check(notices == 0,"running has no notice")
 source.model.observed(telemetry("CONTEXT_CHANGED"),generation:source.model.generation)
 check(notices == 1,"abnormal stop notifies once")
 for _ in 0..<10 { source.model.reconcile([d],generation:source.model.generation) }
 check(notices == 1,"reconciliation does not repeat notice")
 run();check(notices == 1,"recovery does not notify")
 source.model.observed(telemetry("UNDERRUN"),generation:source.model.generation)
 check(notices == 2,"next interruption notifies")
 let stop=source.model.requestStop();source.model.stopped(generation:stop,clean:true)
 check(notices == 2,"manual stop has no notice")
 _ = subscription
 print("Build 37 chart/notice publication: \(assertions) assertions PASS; moving hover publications=\(publications)/1000 events")
 }
}
'''
path=out/'Fixture.swift';path.write_text(fixture)
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(out/'cache'),str(root/'RightDisplay/Models/ICCProfile.swift'),str(root/'RightDisplay/Models/VirtualVolumeState.swift'),str(path),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
a=(root/'RightDisplay/AppDelegate.swift').read_text()
assert 'virtualVolume.$model.map(\\.unexpectedStop).removeDuplicates()' in a
notice=a[a.index('private struct AudioInterruptionNotice:'):a.index('@MainActor\nfinal class AdvancedWindowController:')]
assert 'controller.startRoute()' in notice and '.disabled(!recoveryAvailable)' in notice
assert 'controller.stop(' not in notice and 'startTest(' not in notice
assert 'panel.delegate = self' in a and 'panel === audioInterruptionPanel' in a
print('App-level explicit recovery wiring PASS; evidence='+str(out))
