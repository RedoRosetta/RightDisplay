# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parent.parent
source=(root/'RightDisplay/Services/VirtualVolumeController.swift').read_text()
indicator=source[source.index('    var forwardingEnabled:'):source.index('    var busy:')]
out=Path(tempfile.mkdtemp(prefix='RightDisplay-AutoRouteTests-',dir='/private/tmp'))
src="""import Foundation
struct Indicator { var isSystemRoute=true;var model=VirtualVolumeStateModel(uid:"target");var lastFailure:String?
"""+indicator+"""}
@main struct Test {
 static func main(){var n=0;func check(_ ok:Bool){n+=1;precondition(ok,"Assertion \(n)")}
 var p=VirtualAudioAutoStartPolicy(manuallyDisabled:false)
 check(!p.shouldStart(virtualSelected:false,eligible:true))
 check(!p.shouldStart(virtualSelected:true,eligible:false))
 check(p.shouldStart(virtualSelected:true,eligible:true))
 for _ in 0..<20 {check(!p.shouldStart(virtualSelected:true,eligible:true))}
 check(!p.shouldStart(virtualSelected:false,eligible:true));check(p.shouldStart(virtualSelected:true,eligible:true))
 p.userStopped();p.targetSelected();check(!p.shouldStart(virtualSelected:true,eligible:true))
 check(!p.shouldStart(virtualSelected:false,eligible:true));check(!p.shouldStart(virtualSelected:true,eligible:true))
 p.userStarted();check(!p.manuallyDisabled);check(!p.shouldStart(virtualSelected:true,eligible:true))
 p.targetSelected();check(p.shouldStart(virtualSelected:true,eligible:true))
 var restored=VirtualAudioAutoStartPolicy(manuallyDisabled:true);check(!restored.shouldStart(virtualSelected:true,eligible:true))
 var indicator=Indicator();check(!indicator.forwardingEnabled)
 let d=AudioBridgeDevice(uid:"target",deviceID:1,name:"target",transport:0,rate:48000,channels:2,buffer:512,maxBlock:512,latency:nil,safety:nil,eligibility:"USABLE_DIRECT_PATH",physicalBits:24,physicalFloat:false,streamLatency:nil)
 indicator.model.reconcile([d],generation:indicator.model.generation);let token=indicator.model.requestStart()!;check(!indicator.forwardingEnabled)
 indicator.model.started(generation:token,error:nil)
 check(indicator.model.hasSession && indicator.model.starting);check(indicator.forwardingEnabled)
 indicator.lastFailure="failure";check(!indicator.forwardingEnabled)
 indicator.lastFailure=nil;indicator.isSystemRoute=false;check(!indicator.forwardingEnabled)
 indicator.isSystemRoute=true;_ = indicator.model.requestStop();check(!indicator.forwardingEnabled)
 print("Production automatic-route policy and pre-signal indicator: \(n) assertions PASS; no playback")
 }
}
"""
f=out/'tests.swift';f.write_text(src)
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(out/'ModuleCache'),str(root/'RightDisplay/Models/VirtualVolumeState.swift'),str(f),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
