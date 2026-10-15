#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Execute production layout and feedback policy with silent sound doubles."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parent.parent
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build28-tests-',dir='/private/tmp'))
support=(root/'RightDisplay/Views/SettingsSupportViews.swift').read_text()
geometry=support[support.index('enum AdvancedPageGeometry {'):support.index('enum BrightnessWarningPresentation')]
view=(root/'RightDisplay/Views/VirtualVolumeView.swift').read_text()
feedback=view[view.index('    private func playVolumeFeedback('):view.index('    private var virtualAudioHeading:')].replace('private func','func')
src='''import AppKit
struct Output { var id:String;var volume:Double?;var isMuted:Bool? }
final class Controller { var forwardingEnabled=false }
final class Audio { var virtualOutput:Output?;var refreshes=0;func refresh(){refreshes+=1} }
final class NSSound {
 struct Name { init(_ value:String){} }
 static var shared=NSSound();static var plays:[String]=[];static var stops=0
 var playbackDeviceIdentifier:String?
 convenience init?(named:Name){self.init()}
 func copy()->Any { NSSound() }
 func play(){Self.plays.append(playbackDeviceIdentifier ?? "DEFAULT")}
 func stop(){Self.stops+=1}
}
struct Harness {
 let controller=Controller();let systemAudio=Audio();var feedbackSound:NSSound?
'''+feedback.replace('func playVolumeFeedback','mutating func playVolumeFeedback')+'''}
'''+geometry+'''
@main struct Tests {
 static func main(){
 var n=0;func check(_ value:Bool){n+=1;precondition(value)}
 for icon in ["rectangle.3.group","slider.horizontal.3","waveform.path","checkmark.shield"] {
 check(NSImage(systemSymbolName:icon,accessibilityDescription:nil) != nil)
 }
 for width in stride(from:CGFloat(0),through:1400,by:50) {
 let content=AdvancedPageGeometry.contentWidth(viewport:width)
 check(content>=0 && content<=width && content==max(0,AdvancedPageGeometry.documentWidth(viewport:width)-48))
 }
 check(AdvancedPageGeometry.contentWidth(viewport:1400)-AdvancedPageGeometry.contentWidth(viewport:1050)==350)
 var h=Harness();h.systemAudio.virtualOutput=Output(id:"VIRTUAL-UID",volume:0.5,isMuted:false)
 h.playVolumeFeedback(false);check(NSSound.plays.isEmpty && h.systemAudio.refreshes==0)
 h.controller.forwardingEnabled=true;h.playVolumeFeedback(true);check(NSSound.plays.isEmpty)
 h.playVolumeFeedback(false);check(NSSound.plays==["VIRTUAL-UID"])
 check(NSSound.shared.playbackDeviceIdentifier==nil)
 h.playVolumeFeedback(false);check(NSSound.stops==1 && NSSound.plays.count==2)
 for output in [nil,Output(id:"VIRTUAL-UID",volume:0,isMuted:false),Output(id:"VIRTUAL-UID",volume:0.5,isMuted:true)] as [Output?] {
 h.systemAudio.virtualOutput=output;h.playVolumeFeedback(false);check(NSSound.plays.count==2)
 }
 print("Build 28 UI: \\(n) assertions PASS; production geometry, installed symbols, silent feedback policy; no playback")
 }
}
'''
f=out/'tests.swift';f.write_text(src)
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(out/'ModuleCache'),str(f),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
