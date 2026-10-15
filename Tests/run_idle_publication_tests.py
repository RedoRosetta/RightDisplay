# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Real presentation equality and refresh methods; synthetic reads, no hardware/UI."""
from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parent.parent
out=Path(tempfile.mkdtemp(prefix='RightDisplay-IdlePublicationTests-',dir='/private/tmp'))
def section(text,start,end):return text[text.index(start):text.index(end,text.index(start))]
model=(root/'RightDisplay/Models/DisplaySnapshot.swift').read_text()
controller=(root/'RightDisplay/Services/DisplayOutputController.swift').read_text()
source='import Foundation\nimport CoreGraphics\nenum OutputPreference:Hashable {case automatic,rgbFullRange,yCbCr}\n'
source+=section(model,'enum Verification:','enum AutoCorrectionStage:')
source+=section(controller,'struct DisplayLinkDescription:','enum LinkControlIntent:')
source+=section(model,'struct DisplaySnapshot:','    /// Built-in HDR-capable')+'}\n'
source+=r'''
var count=0
func check(_ value:Bool){count+=1;precondition(value,"display publication \(count)")}
func mode(rate:Double=119.88, output:Int=3840, low:Double?=48)->DisplayModeOption {
 .init(id:5,width:1920,height:1080,pixelWidth:3840,pixelHeight:2160,outputWidth:output,outputHeight:2160,refreshRate:rate,isHiDPI:true,vrrState:true,ioFlags:3,mode:nil,displayID:7,hardwareKey:"A",cgsIndex:11,refreshRange:.init(minimum:low,maximum:120,source:"fixture"))
}
func snapshot(_ mode:DisplayModeOption,name:String="A",source:String="system",range:UInt32=1)->DisplaySnapshot {
 let signal=SignalValue(text:"fixture",verification:.slsReported,source:source)
 return .init(id:7,hardwareKey:"A",name:name,systemName:"A",isBuiltin:false,isMain:true,reportedDiagonalInches:42,correctedDiagonalInches:nil,resolution:"3840x2160",logicalResolution:"1920x1080",renderResolution:"3840x2160",refreshRate:signal,pixelEncoding:signal,colorGamut:signal,bitDepth:signal,hdr:signal,vrr:signal,dsc:signal,dscEnabled:nil,dscSupported:true,activeOutputPreference:.rgbFullRange,activeRawPixelEncoding:0,activeBitDepth:12,supportedBitDepths:[8,10,12],linkCapabilities:[],hdrEnabled:true,hdrSupported:true,vrrEnabled:true,vrrSupported:true,vrrStateKnown:true,modes:[mode],currentModeID:mode.id,currentModeKey:mode.selectionKey,currentConnectionIdentity:.init(pixelEncoding:0,depth:12,range:range,eotf:2))
}
let base=snapshot(mode())
check(base.hasSamePresentation(as:snapshot(mode())))
check(mode()==mode(output:4096)) // timing identity intentionally ignores UI inference
check(!base.hasSamePresentation(as:snapshot(mode(output:4096))))
check(mode()==mode(low:40))
check(!base.hasSamePresentation(as:snapshot(mode(low:40))))
check(!base.hasSamePresentation(as:snapshot(mode(low:nil))))
check(!base.hasSamePresentation(as:snapshot(mode(rate:119.89))))
check(!base.hasSamePresentation(as:snapshot(mode(),name:"alias changed")))
check(!base.hasSamePresentation(as:snapshot(mode(),source:"unavailable")))
check(!base.hasSamePresentation(as:snapshot(mode(),range:0)))
print("Production display presentation equality: \(count) assertions PASS; full raw identity, range, output inference and evidence changes still publish")
'''
(out/'main.swift').write_text(source)
subprocess.run(['xcrun','swiftc','-module-cache-path',str(out/'cache'),str(root/'RightDisplay/Models/LinkPixelEncoding.swift'),str(out/'main.swift'),'-o',str(out/'display')],check=True)
subprocess.run([str(out/'display')],check=True)
audio=(root/'RightDisplay/Services/AudioOutputStore.swift').read_text()
brightness=(root/'RightDisplay/Services/DisplayBrightnessStore.swift').read_text()
refresh=section(audio,'    func refresh() {','    deinit {')
br_refresh=section(brightness,'    func refresh() {','    func editingChanged(')
source='''import Foundation
import CoreAudio
struct SignalValue: Equatable {enum Verification {case unavailable};let text:String;let verification:Verification}
enum AppLocalization {static let isEnglish=false;static func string(_ s:String)->String{s}}
'''+section(audio,'struct AudioOutputSnapshot:','@MainActor')+'''
var defaultID:UInt32=51;var defaultKnown=true
func AudioObjectGetPropertyData(_ id:AudioObjectID,_ a:UnsafePointer<AudioObjectPropertyAddress>,_ q:UInt32,_ b:UnsafeRawPointer?,_ size:UnsafeMutablePointer<UInt32>,_ data:UnsafeMutableRawPointer)->OSStatus {
 data.assumingMemoryBound(to:UInt32.self).pointee=defaultID;return defaultKnown ? noErr : -1
}
final class AudioStore {
 var publishes=0;var listeners=0
 var current=AudioOutputSnapshot.unavailable {didSet{publishes+=1}}
 var outputs:[AudioOutputSnapshot]=[] {didSet{publishes+=1}}
 var fixtures:[AudioOutputSnapshot]=[]
 func allOutputDeviceIDs()->[UInt32]{fixtures.map(\\.deviceID)}
 func snapshot(for id:UInt32,defaultDeviceID:UInt32)->AudioOutputSnapshot{fixtures.first{$0.deviceID==id}!}
 func synchronizeLevelListeners(){listeners+=1}
'''+refresh+'''
}
final class BrightnessStore {
 var publishes=0
 var value:Double=0.5 {didSet{publishes+=1}}
 var isAvailable=false {didSet{publishes+=1}}
 var statusText="系统未提供亮度控制" {didSet{publishes+=1}}
 var activeDisplayID:UInt32=7
 var getBrightness:((UInt32,UnsafeMutablePointer<Float>)->Int32)?
'''+br_refresh+'''
}
func output(_ volume:Double=0.5,_ rate:Double=48000,_ uid:String="physical")->AudioOutputSnapshot {
 .init(id:uid,deviceID:51,name:"same-name",transport:"HDMI",channels:2,sampleRate:rate,format:"PCM",dolby:.init(text:"unknown",verification:.unavailable),systemVolumeWritable:true,volume:volume,isMuted:false,isDefault:true)
}
var assertions=0;func check(_ ok:Bool){assertions+=1;precondition(ok,"idle read assertion \\(assertions)")}
let a=AudioStore();a.fixtures=[output()];a.refresh();check(a.publishes==2)
for _ in 0..<60{a.refresh()};check(a.publishes==2 && a.listeners==61)
a.fixtures=[output(0.7)];a.refresh();check(a.current.volume==0.7 && a.publishes==4)
a.fixtures=[output(0.7,96000)];a.refresh();check(a.current.sampleRate==96000 && a.publishes==6)
a.fixtures=[output(0.7,96000,"replacement")];a.refresh();check(a.current.id=="replacement" && a.publishes==8)
defaultKnown=false;a.refresh();check(a.current==.unavailable && a.outputs.isEmpty && a.publishes==10)
for _ in 0..<60{a.refresh()};check(a.publishes==10)
let b=BrightnessStore();b.getBrightness={_,p in p.pointee=0.75;return 0};b.refresh();check(b.value==0.75 && b.isAvailable)
let first=b.publishes;for _ in 0..<60{b.refresh()};check(b.publishes==first)
b.getBrightness={_,p in p.pointee=0.25;return 0};b.refresh();check(b.value==0.25 && b.publishes==first+1)
b.getBrightness={_,p in p.pointee=Float.nan;return 0};b.refresh();check(!b.isAvailable)
let failed=b.publishes;for _ in 0..<60{b.refresh()};check(b.publishes==failed)
b.getBrightness=nil;b.refresh();let missing=b.publishes;for _ in 0..<60{b.refresh()};check(b.publishes==missing)
print("Production idle read publication: \\(assertions) assertions PASS; unchanged polling silent, volume/rate/UID/brightness/unavailable changes preserved")
'''
source=source.replace('a.current==.unavailable','a.current == .unavailable')
(out/'audio-brightness.swift').write_text(source)
subprocess.run(['xcrun','swiftc','-module-cache-path',str(out/'cache'),str(out/'audio-brightness.swift'),'-o',str(out/'audio-brightness')],check=True)
subprocess.run([str(out/'audio-brightness')],check=True)
print('Evidence='+str(out))
