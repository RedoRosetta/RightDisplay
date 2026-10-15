#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parent.parent
out=Path(tempfile.mkdtemp(prefix='RightDisplay-Build13-ResourceTests-',dir='/private/tmp'))
source=(root/'RightDisplay/Services/DisplayOutputController.swift').read_text()
model=source[source.index('struct CGSTimingDescription {'):source.index('final class DisplayTimingController')]
store=(root/'RightDisplay/Services/DisplayStore.swift').read_text()
index=next(l.strip() for l in store.splitlines() if 'let recordsByModeID = Dictionary' in l)
lookup=next(l.strip() for l in store.splitlines() if 'let matches = (recordsByModeID[' in l)
program=r'''
import Foundation
struct ModeRefreshRange { let minimum: Double?;let maximum: Double?;let source: String }
final class CGDisplayMode {
 static var reads=0
 let key:Int32,w:Int,h:Int,pw:Int,ph:Int,rate:Double
 init(_ id:Int32,_ width:Int=3840,_ refresh:Double=120){key=id;w=width;h=2160;pw=width;ph=2160;rate=refresh}
 var ioDisplayModeID:Int32 {Self.reads+=1;return key}
 var width:Int {w};var height:Int {h};var pixelWidth:Int {pw};var pixelHeight:Int {ph};var refreshRate:Double {rate}
}
'''+model+r'''
func old(_ records:[CGSTimingDescription],_ modes:[CGDisplayMode])->[[UInt32]] { modes.map { mode in records.filter {$0.matches(mode)}.map(\.index) } }
func indexed(_ records:[CGSTimingDescription],_ modes:[CGDisplayMode])->[[UInt32]] {
 INDEX
 return modes.map { mode in LOOKUP;return matches.map(\.index) }
}
func record(_ i:UInt32,_ id:Int32,_ width:Int=3840,_ rate:Double=120,_ vrr:Bool?=false)->CGSTimingDescription {
 .init(index:i,ioModeID:id,width:width,height:2160,pixelWidth:width,pixelHeight:2160,refreshRate:rate,ioFlags:3,vrr:vrr,range:.init(minimum:nil,maximum:nil,source:"fixture"))
}
let records=(0..<1000).map { record(UInt32($0),Int32($0)) }
let modes=(0..<1000).map { CGDisplayMode(Int32($0)) }
CGDisplayMode.reads=0;let before=old(records,modes);let beforeReads=CGDisplayMode.reads
CGDisplayMode.reads=0;let after=indexed(records,modes);let afterReads=CGDisplayMode.reads
precondition(before==after && beforeReads==1_000_000 && afterReads==2000)
let special=[record(1,4,3840,120),record(2,4,3840,119.88),record(3,4,1920,120),record(4,4,3840,120,true)]
let choices=[CGDisplayMode(4),CGDisplayMode(4,3840,119.88),CGDisplayMode(4,1920,120),CGDisplayMode(99)]
precondition(old(special,choices)==indexed(special,choices))
precondition(indexed(special,choices)==[[1,4],[2],[3],[]]) // retain ambiguous matches, never choose first
print("Resource matching: PASS; original production predicate; identical results; mode-ID getter calls \(beforeReads) -> \(afterReads) (500x fewer, synthetic enumeration)")
'''
program=program.replace('INDEX',index).replace('LOOKUP',lookup).replace('\\\\.','\\.')
(out/'main.swift').write_text(program)
subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'ModuleCache'),str(out/'main.swift'),'-o',str(out/'test')],check=True)
subprocess.run([str(out/'test')],check=True)
print('Evidence='+str(out))
