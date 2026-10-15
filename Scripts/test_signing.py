#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Compile-only own-component identity checks; no XPC, HAL, devices or private keys."""
from pathlib import Path
import subprocess,json
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'Build/signing-tests';out.mkdir(parents=True,exist_ok=True)
def run(args):return subprocess.run(list(map(str,args)),capture_output=True,text=True,check=True)
c=out/'identity.c';c.write_text('#include "SigningIdentity.h"\n#include <stdio.h>\nint main(void){puts(RDComponentSigningTeam());puts(RD_BROKER_REQUIREMENT);return 0;}\n')
dummy=out/'dummy.c';dummy.write_text('int main(void){return 0;}\n');forged=out/'forged'
run(['xcrun','clang',dummy,'-o',forged]);run(['/usr/bin/codesign','--force','--sign','-','--identifier','com.rightdisplay.audio.Transport',forged])
swift=out/'probe.swift';swift.write_text(r'''import Foundation
import Security
let expected=CommandLine.arguments[1]
let team=String(cString:RDComponentSigningTeam())
precondition(team==expected)
var req:SecRequirement?
let text="anchor apple generic and identifier \"com.rightdisplay.audio.Transport\" and certificate leaf[subject.OU] = \"\(team)\""
precondition(SecRequirementCreateWithString(text as CFString,[],&req)==errSecSuccess)
var code:SecStaticCode?
precondition(SecStaticCodeCreateWithPath(URL(fileURLWithPath:CommandLine.arguments[2]) as CFURL,[],&code)==errSecSuccess)
precondition(SecStaticCodeCheckValidity(code!,SecCSFlags(rawValue:kSecCSStrictValidate),req!) != errSecSuccess)
print(team+": ad-hoc/name-only forged broker rejected")
''')
rows=[]
for selected in [None,'ABCDE12345']:
 team=selected or '45F25M3DS7';macro=[] if selected is None else ['-DRD_SIGNING_TEAM="'+team+'"'];exe=out/('c-'+team)
 run(['xcrun','clang','-I',ROOT/'AudioVirtualDevice',*macro,c,'-o',exe]);actual=run([exe]).stdout.splitlines()
 expected='anchor apple generic and identifier "com.rightdisplay.audio.Transport" and certificate leaf[subject.OU] = "'+team+'"'
 assert actual==[team,expected],actual
 sx=out/('swift-'+team);run(['xcrun','swiftc','-module-cache-path',out/'cache','-import-objc-header',ROOT/'RightDisplay/AudioBridgeRealtime/AudioBridgeC.h',*sum((['-Xcc',x] for x in macro),[]),swift,'-o',sx]);print(run([sx,team,forged]).stdout.strip())
 rows.append({'team':team,'C_Swift_policy_consistent':True,'ad_hoc_forged_identity_rejected':True})
broker=(ROOT/'AudioVirtualDevice/Broker/main.c').read_text()
producer_line=next(line for line in broker.splitlines() if line.startswith('static const char* producerRequirement = '))
producer_text=json.loads(producer_line.split(' = ',1)[1].removesuffix(';'))
assert producer_text == 'anchor apple and (identifier "com.apple.audio.coreaudiod" or identifier "com.apple.audio.Core-Audio-Driver-Service.helper")'
p=subprocess.run(['python3',str(ROOT/'Scripts/build.py'),'--compile-only','--component-team','INVALID'],capture_output=True,text=True);assert p.returncode!=0
(out/'result.json').write_text(json.dumps({'profiles':rows,'system_producer_requirement_retained':True,'invalid_team_rejected':True,'HAL_or_XPC':'not invoked'},indent=2))
print('Signing policy PASS; default official and custom-team compile policies, forged identity rejected; no hardware')
