# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Exercise production level-listener lifecycle/readback without hardware calls."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parent.parent
source=(root/'RightDisplay/Services/AudioOutputStore.swift').read_text()
snapshot=source[source.index('struct AudioOutputSnapshot:'):source.index('@MainActor')]
fields=source[source.index('    private struct PropertyListener'):source.index('    private let defaults')].replace('private ', '')
methods=source[source.index('    private func installTopologyListeners'):source.index('    var selectedAudioDevice:')].replace('private ', '')
src='''import Foundation
import CoreAudio
import Combine
struct AppLocalization { static let isEnglish=false;static func string(_ s:String)->String{s} }
struct SignalValue: Equatable { enum Verification {case unavailable};var text:String;var verification:Verification }
'''+snapshot+'''
struct Registration { var device:AudioObjectID;var address:AudioObjectPropertyAddress;var block:AudioObjectPropertyListenerBlock }
var registrations:[Registration]=[];var additions=0;var removals=0
func AudioObjectHasProperty(_ device:AudioObjectID,_ a:UnsafePointer<AudioObjectPropertyAddress>)->Bool {
    a.pointee.mElement == 0 && [kAudioDevicePropertyVolumeScalar,kAudioDevicePropertyMute].contains(a.pointee.mSelector)
}
func AudioObjectAddPropertyListenerBlock(_ device:AudioObjectID,_ a:UnsafePointer<AudioObjectPropertyAddress>,_ queue:DispatchQueue?,_ block:@escaping AudioObjectPropertyListenerBlock)->OSStatus {
    registrations.append(.init(device:device,address:a.pointee,block:block));additions+=1;return noErr
}
func AudioObjectRemovePropertyListenerBlock(_ device:AudioObjectID,_ a:UnsafePointer<AudioObjectPropertyAddress>,_ queue:DispatchQueue?,_ block:@escaping AudioObjectPropertyListenerBlock)->OSStatus {
    registrations.removeAll{$0.device==device && $0.address.mSelector==a.pointee.mSelector && $0.address.mElement==a.pointee.mElement};removals+=1;return noErr
}
@MainActor final class Store {
'''+fields+'''
    var publishes=0;var refreshes=0;var reads=0
    var current=AudioOutputSnapshot.unavailable {didSet{publishes+=1}}
    var outputs:[AudioOutputSnapshot]=[] {didSet{publishes+=1}}
    var uids:[UInt32:String]=[:];var levels:[UInt32:Float32]=[:];var mutes:[UInt32:Bool]=[:]
    func refresh(){refreshes+=1}
    func stringProperty(_ device:AudioObjectID,selector:AudioObjectPropertySelector,scope:AudioObjectPropertyScope)->String?{uids[device]}
    func volumeScalar(_ device:AudioDeviceID)->Float32?{reads+=1;return levels[device]}
    func muteValue(_ device:AudioDeviceID)->Bool?{mutes[device]}
'''+methods+'''
}
func output(_ device:UInt32,_ uid:String,_ value:Double)->AudioOutputSnapshot {
 .init(id:uid,deviceID:device,name:uid,transport:"test",channels:2,sampleRate:48000,format:"PCM",dolby:.init(text:"test",verification:.unavailable),systemVolumeWritable:true,volume:value,isMuted:false,isDefault:device==51)
}
@main struct Test {
 @MainActor static func main() async {
  var n=0;func check(_ ok:Bool){n+=1;precondition(ok,"Assertion \(n)")}
  let s=Store();s.installTopologyListeners();check(s.topologyListeners.count==2)
  s.outputs=[output(51,"physical",0.8),output(90,"virtual",0.5)];s.current=s.outputs[0]
  s.uids=[51:"physical",90:"virtual"];s.levels=[51:0.8,90:0.5];s.mutes=[51:false,90:false]
  s.synchronizeLevelListeners();check(s.levelListeners.count==4)
  let count=additions;let generation=s.listenerGeneration
  for _ in 0..<10{s.synchronizeLevelListeners()};check(additions==count && s.listenerGeneration==generation)
  let listener=s.levelListeners.first{$0.device==90 && $0.address.mSelector==kAudioDevicePropertyVolumeScalar}!
  s.levels[90]=0.25;var address=listener.address
  for _ in 0..<20{withUnsafePointer(to:&address){listener.block(1,$0)}}
  try! await Task.sleep(for:.milliseconds(80))
  check(s.outputs[1].volume==0.25);check(s.current.volume==0.8);check(s.reads==1);check(s.refreshes==0)
  let publishes=s.publishes
  s.enqueueLevelRead(device:90,generation:generation);try! await Task.sleep(for:.milliseconds(40));check(s.publishes==publishes)
  s.mutes[90]=true;s.enqueueLevelRead(device:90,generation:generation);try! await Task.sleep(for:.milliseconds(40));check(s.outputs[1].isMuted==true)
  s.uids[90]="replacement";s.levels[90]=0.75;s.enqueueLevelRead(device:90,generation:generation)
  try! await Task.sleep(for:.milliseconds(40));check(s.outputs[1].volume==0.25)
  s.uids[90]="virtual";s.enqueueLevelRead(device:90,generation:generation)
  s.outputs=[s.outputs[0]];s.synchronizeLevelListeners()
  try! await Task.sleep(for:.milliseconds(40));check(!registrations.contains{$0.device==90});check(s.pendingLevelDevices.isEmpty)
  let reads=s.reads;s.enqueueLevelRead(device:90,generation:generation)
  try! await Task.sleep(for:.milliseconds(40));check(s.reads==reads && s.current.deviceID==51)
  s.outputs=[];s.current = .unavailable;s.synchronizeLevelListeners();check(s.levelListeners.isEmpty && s.observedDeviceIDs.isEmpty)
  check(registrations.count==2 && removals==6)
  for _ in 0..<20{s.enqueueTopologyRefresh()}
  try! await Task.sleep(for:.milliseconds(40));check(s.refreshes==1)
  print("Production audio level listener tests: \\(n) assertions PASS; coalescing, UID guard, disconnect, stale callbacks, no hardware writes")
 }
}
'''
out=Path(tempfile.mkdtemp(prefix='RightDisplay-LevelListenerTests-',dir='/private/tmp'));f=out/'tests.swift';f.write_text(src)
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(out/'ModuleCache'),str(f),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
