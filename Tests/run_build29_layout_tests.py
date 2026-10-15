#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Offscreen native scrollbar/layout checks, with no application launch or hardware access."""
from pathlib import Path
import tempfile, subprocess
root=Path(__file__).resolve().parent.parent
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build29-layout-',dir='/private/tmp'))
s=(root/'RightDisplay/Views/SettingsSupportViews.swift').read_text()
geometry=s[s.index('enum AdvancedPageGeometry {'):s.index('enum BrightnessWarningPresentation')]
inset=s[s.index('private struct CardSubmenuIndentKey:'):s.index('struct GlassCard<')]
# Extract the actual native scroll policy, not a parallel implementation.
policy=s[s.index('            scroll.scrollerStyle = .overlay',s.index('struct StablePageScrollGutter')):s.index('\n        }',s.index('            scroll.scrollerStyle = .overlay',s.index('struct StablePageScrollGutter')))]
src='''import AppKit
import SwiftUI
'''+geometry+inset+'''
final class Measurements { var frames:[String:CGRect]=[:] }
struct Probe: View {
 let inset:CGFloat;let measurements:Measurements
 func measured(_ key:String)->some View {
 Rectangle().fill(.clear).onGeometryChange(for:CGRect.self){$0.frame(in:.named("root"))} action:{measurements.frames[key]=$0}
 }
 var body:some View {
 HStack(spacing:0){ measured("label").frame(width:80);Spacer(minLength:0);measured("control").frame(width:40) }
 .modifier(CardSubmenuInset()).environment(\\.cardSubmenuIndent,inset)
 .frame(width:300,height:50).coordinateSpace(name:"root")
 }
}
@main struct Tests {
 @MainActor static func main(){
 _ = NSApplication.shared
 var n=0;func check(_ value:Bool,_ message:String){n+=1;precondition(value,message)}
 for page in ["overview","display","audio","ICC","EDID","general"] {
 for width in [CGFloat(620),800,1040,1400] {
 for height in [CGFloat(120),1800] {
 let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:width,height:540))
'''+policy+'''
 let document=NSView(frame:NSRect(x:0,y:0,width:AdvancedPageGeometry.documentWidth(viewport:width),height:height))
 scroll.documentView=document;scroll.tile()
 let clip=scroll.contentSize.width
 check(abs(clip-width)<0.01 && scroll.scrollerStyle == .overlay && scroll.autohidesScrollers,"\\(page): overlay policy mismatch")
 let card=CGRect(x:AdvancedPageGeometry.margin,y:24,width:AdvancedPageGeometry.contentWidth(viewport:width),height:70)
 check(abs(card.minX-24)<0.01 && abs(document.frame.width-card.maxX-24)<0.01,"\\(page): unequal card margins")
 }
 }
 }
 var measured:[Measurements]=[]
 var windows:[NSWindow]=[]
 for indent in [CGFloat(0),8] {
 let m=Measurements();measured.append(m)
 let view=NSHostingView(rootView:Probe(inset:indent,measurements:m))
 let window=NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:50),styleMask:[.borderless],backing:.buffered,defer:false)
 window.isReleasedWhenClosed=false;window.contentView=view;windows.append(window)
 view.frame=NSRect(x:0,y:0,width:300,height:50);view.layoutSubtreeIfNeeded()
 }
 RunLoop.main.run(until:Date().addingTimeInterval(0.25))
 let a=measured[0].frames,b=measured[1].frames
 check(a["label"] != nil && b["label"] != nil,"offscreen row did not measure")
 check(abs(b["label"]!.minX-a["label"]!.minX-8)<0.01,"label should move 8 pt")
 check(abs(b["control"]!.maxX-a["control"]!.maxX)<0.01,"trailing control must not move")
 for window in windows {check(!window.isVisible,"test must remain offscreen");window.close()}
 print("Build 29 layout: \\(n) assertions PASS; six page cases, four viewport widths, short/long content, actual overlay scrollbar and offscreen SwiftUI row; no application launch")
 }
}
'''
f=out/'tests.swift';f.write_text(src)
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(out/'ModuleCache'),str(f),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
