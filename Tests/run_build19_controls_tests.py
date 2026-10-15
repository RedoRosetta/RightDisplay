#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Exercise actual production reducers, profile-independent size and fresh output selection."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parent.parent
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build19-controls-',dir='/private/tmp'))
brightness=(root/'RightDisplay/Services/DisplayBrightnessStore.swift').read_text()
model=brightness[brightness.index('struct BrightnessDragProtection {'):brightness.index('@MainActor')]
snapshot=(root/'RightDisplay/Models/DisplaySnapshot.swift').read_text()
size=snapshot[snapshot.index('    var sizeText: String {'):snapshot.index('    var hasIdentityCorrection:')]
app=(root/'RightDisplay/AppDelegate.swift').read_text()
layout=app[app.index('    private struct Glyph:',app.index('private struct LaunchStrokeText:')):app.index('    let reduceMotion: Bool',app.index('private struct LaunchStrokeText:'))]
support=(root/'RightDisplay/Views/SettingsSupportViews.swift').read_text()
parsed=support[support.index('    private var parsedSize:Double?'):support.index('    @Environment',support.index('    private var parsedSize:Double?'))].replace('private ', '')
audio=(root/'RightDisplay/Services/AudioOutputStore.swift').read_text()
method=audio[audio.index('    func useVirtualSystemOutput()'):audio.index('    private func snapshot(')]
src='''import Foundation
import AppKit
import SwiftUI
import CoreText
import CoreAudio
'''+model+'''struct Sizes { var correctedDiagonalInches:Double?;var reportedDiagonalInches:Double?
'''+size+'''}
struct SizeInput { var size:String
'''+parsed+'''}
struct GlyphLayout {
'''+layout+'''
 static func validate()->Int {
   let dimensions = intrinsicSize
   let period = layout.glyphs.last!.path
   precondition(period.boundingRect.maxX < dimensions.width && period.boundingRect.maxY < dimensions.height)
   precondition(layout.glyphs.allSatisfy{dimensions.width >= $0.path.boundingRect.maxX && dimensions.height >= $0.path.boundingRect.maxY})
   let w=Int(dimensions.width*4),h=Int(dimensions.height*4)
   let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0)!
   c.scaleBy(x:4,y:4);c.setFillColor(gray:1,alpha:1);c.addPath(period.cgPath);c.fillPath()
   let bytes=c.data!.assumingMemoryBound(to:UInt8.self)
   precondition((0..<w*h).contains{bytes[$0]>0},"Final punctuation has no visible pixels")
   return 3
 }
}
struct Output { var deviceID:AudioDeviceID;var systemVolumeWritable:Bool;var isDefault:Bool }
var requests:[AudioDeviceID]=[];var requestSucceeds=true
func AudioObjectSetPropertyData(_ id:AudioObjectID,_ a:UnsafePointer<AudioObjectPropertyAddress>,_ n:UInt32,_ q:UnsafeRawPointer?,_ size:UInt32,_ data:UnsafeRawPointer)->OSStatus {
 requests.append(data.load(as:AudioDeviceID.self));return requestSucceeds ? noErr : -1
}
@MainActor final class FakeAudio {
 var virtualKeyboardFailure:String?;var virtualOutput:Output?;var reads:[Output?]=[]
 func refresh(){virtualOutput = reads.removeFirst()}
'''+method+'''}
@main struct Tests {
 @MainActor static func main() {
 var n=0;func check(_ b:Bool){n+=1;precondition(b)}
 var drag=BrightnessDragProtection();drag.begin(current:1)
 var value=drag.apply(0,current:1);check(value==0.2 && drag.shouldWarn)
 for _ in 0..<50 {value=drag.apply(0,current:value);check(value==0 && !drag.shouldWarn)}
 drag.end();drag.begin(current:value);value=drag.apply(0,current:value);check(value==0)
 check(drag.apply(0.9,current:value)==0.9)
 check(drag.apply(0.1,current:0.9)==0.2 && drag.shouldWarn)
 check(drag.apply(0.1,current:0.2)==0.1 && !drag.shouldWarn)
 drag.reset();drag.begin(current:0.8);check(drag.apply(0.1,current:0.8)==0.2)
 drag.end();drag.reset();drag.begin(current:0.2);check(drag.apply(0,current:0.2)==0.2)
 check(drag.apply(.nan,current:0.2)==0.2 && !drag.shouldWarn)
 check(drag.apply(0,current:0.2)==0)
 drag.reset();drag.begin(current:0.1);check(drag.apply(0,current:0.1)==0)
 check(Sizes(correctedDiagonalInches:42,reportedDiagonalInches:55).sizeText=="42 英寸")
 check(Sizes(correctedDiagonalInches:nil,reportedDiagonalInches:55).sizeText=="55 英寸")
 check(Sizes(correctedDiagonalInches:nil,reportedDiagonalInches:nil).sizeText=="尺寸未知")
 for bad in ["nan","inf","-2","0","abc"] { check(SizeInput(size:bad).parsedSize==nil) }
 check(SizeInput(size:"42,5").parsedSize==42.5)
 n+=GlyphLayout.validate()
 let a=FakeAudio();let ready=Output(deviceID:90,systemVolumeWritable:true,isDefault:false)
 a.reads=[ready,Output(deviceID:90,systemVolumeWritable:true,isDefault:true)];a.useVirtualSystemOutput();check(a.virtualKeyboardFailure==nil && requests==[90])
 a.reads=[ready,ready];a.useVirtualSystemOutput();check(a.virtualKeyboardFailure != nil)
 a.reads=[ready,Output(deviceID:91,systemVolumeWritable:true,isDefault:true)];a.useVirtualSystemOutput();check(a.virtualKeyboardFailure != nil)
 let count=requests.count;a.reads=[nil];a.useVirtualSystemOutput();check(requests.count==count)
 requestSucceeds=false;a.reads=[ready,Output(deviceID:90,systemVolumeWritable:true,isDefault:true)];a.useVirtualSystemOutput();check(a.virtualKeyboardFailure != nil)
 print("Build 19 controls: \\(n) assertions PASS; production gesture/size/glyph geometry/fresh output selection; no hardware writes")
 }
}
'''
f=out/'tests.swift';f.write_text(src)
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(out/'ModuleCache'),str(f),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
