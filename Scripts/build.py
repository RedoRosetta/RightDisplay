#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Compile/assemble an unsigned candidate only, with explicit local inputs."""
from pathlib import Path
import argparse,subprocess,os,json,plistlib,hashlib,re
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--compile-only',action='store_true',required=True);ap.add_argument('--inherit-outer-sandbox',action='store_true',help='Swift macro processes retain the existing outer sandbox; avoid rejected nested sandbox');ap.add_argument('--component-team',default='45F25M3DS7');a=ap.parse_args();
 if not re.fullmatch(r'[A-Z0-9]{10}',a.component_team):raise SystemExit('invalid component team')
 out=ROOT/'Build/Product';out.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy();env['RD_COMPONENT_TEAM']=a.component_team;env['CLANG_MODULE_CACHE_PATH']=str(out/'ModuleCache');env['SWIFT_MODULECACHE_PATH']=str(out/'SwiftModuleCache')
 def run(cmd,name):
  with (out/(name+'.log')).open('w') as f:p=subprocess.run([str(x) for x in cmd],cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT)
  print(name,'PASS' if p.returncode==0 else 'FAIL',flush=True)
  if p.returncode:raise SystemExit((out/(name+'.log')).read_text()[-6000:])
 run(['python3',ROOT/'Scripts/preflight.py'],'preflight')
 # No keychain input or installation. Own-component authentication is unchanged.
 run(['/usr/bin/xcodebuild','-project',ROOT/'RightDisplay.xcodeproj','-scheme','RightDisplay','-configuration','Release','-destination','platform=macOS,arch=arm64','-derivedDataPath',out/'DerivedData','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','DEVELOPMENT_TEAM=', 'RD_COMPONENT_TEAM='+a.component_team,'DEPLOYMENT_POSTPROCESSING=YES','DEPLOYMENT_LOCATION=NO','STRIP_INSTALLED_PRODUCT=YES','STRIP_STYLE=debugging',*(['OTHER_SWIFT_FLAGS=-disable-sandbox'] if a.inherit_outer_sandbox else []),'build'],'xcodebuild')
 app=out/'DerivedData/Build/Products/Release/Right Display.app';pl=plistlib.loads((app/'Contents/Info.plist').read_bytes());assert pl['CFBundleVersion']=='46';assert pl['CFBundleShortVersionString']=='1.0.1'
 for name in ['AppleTVAudioHelper/RightDisplayAppleTVHelper','VirtualAudioPackages/InstallVirtualAudio.pkg','VirtualAudioPackages/UninstallVirtualAudio.pkg']:
  assert (app/'Contents/Resources'/name).is_file(),name
 result={'component_team':a.component_team,'status':'COMPILE_AND_ASSEMBLY_PASS','version':'1.0.1','build':'46','component':'21','protocol':'21','app':str(app.relative_to(ROOT)),'app_signing':'disabled; not an installable release claim','component_signing':'local ad-hoc compile artifacts; existing authentication is not satisfied','installed':False,'runtime':'UNVERIFIED','public_RC_correspondence':'different: RC uses Build41','release':'compile-only output; use the separately verified Ad-hoc distribution pipeline for a release'}
 (out/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
if __name__=='__main__':main()
