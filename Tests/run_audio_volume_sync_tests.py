# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parent.parent
text=(root/'RightDisplay/Services/AudioOutputStore.swift').read_text()
methods=text[text.index('    var virtualOutput:'):text.index('    func setMuted(')]
src='''import Foundation
import CoreAudio
struct AudioOutputSnapshot { var id:String;var deviceID:AudioDeviceID;var systemVolumeWritable:Bool;var volume:Double }
var writes:[(UInt32,Float32)]=[]
func AudioObjectSetPropertyData(_ device:AudioObjectID,_ address:UnsafePointer<AudioObjectPropertyAddress>,_ q:UInt32,_ qualifier:UnsafeRawPointer?,_ size:UInt32,_ value:UnsafeRawPointer)->OSStatus {
 writes.append((device,value.load(as:Float32.self)));return noErr
}
@MainActor final class Store {
 var outputs:[AudioOutputSnapshot]=[];var fresh:[AudioOutputSnapshot]=[];var refreshes=0
 func refresh() { refreshes+=1;outputs=fresh;for (id,v) in writes {for i in outputs.indices where outputs[i].deviceID==id {outputs[i].volume=Double(v)}} }
 func writableVolumeElements(_ device:AudioDeviceID)->[AudioObjectPropertyElement] {[0]}
'''+methods+'''}
@main struct Test {
 @MainActor static func main(){var n=0;func check(_ value:Bool){n+=1;precondition(value)}
 let store=Store();let virtual="RightDisplay.VirtualVolume"
 store.fresh=[.init(id:virtual,deviceID:90,systemVolumeWritable:true,volume:0.5),.init(id:"physical",deviceID:52,systemVolumeWritable:true,volume:0.8)]
 store.refresh();check(store.virtualOutput?.volume==0.5)
 store.setVirtualVolume(0.25);check(writes.count==1&&writes[0].0==90);check(store.virtualOutput?.volume==0.25);check(store.refreshes>=3)
 store.fresh=[.init(id:virtual,deviceID:90,systemVolumeWritable:true,volume:0.5),.init(id:virtual,deviceID:91,systemVolumeWritable:true,volume:0.5)]
 store.setVirtualVolume(0.75);check(writes.count==1&&store.virtualOutput==nil)
 store.fresh=[];store.setVirtualVolume(0.75);check(writes.count==1)
 store.fresh=[.init(id:virtual,deviceID:94,systemVolumeWritable:true,volume:0.5)]
 store.setVirtualVolume(Double.nan);check(writes.count==1)
 store.setVirtualVolume(0.6);check(writes.last?.0==94&&abs((store.virtualOutput?.volume ?? 0)-0.6)<0.00001)
 print("Production virtual volume binding: \\(n) assertions PASS; real functions, fake fresh UID/write/readback; no hardware")
 }
}
'''
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build15-volume-tests-',dir='/private/tmp'));file=out/'tests.swift';file.write_text(src)
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(out/'ModuleCache'),str(file),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
