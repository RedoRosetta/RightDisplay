#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# Licensed under RNSL 1.0; see LICENSE_SCOPE.md.
"""Build a content-pinned Ad-hoc distribution. Never installs or starts audio."""
from pathlib import Path
import argparse,subprocess,json,re,shutil,os,plistlib
ROOT=Path(__file__).resolve().parents[1]
def run(args,log=None):
 p=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True)
 if log:log.write_text(p.stdout+p.stderr)
 if p.returncode:raise RuntimeError(p.stdout[-2000:]+p.stderr[-3000:])
 return p.stdout+p.stderr
def cdhash(path):
 text=run(['codesign','-dvvv',path]);m=re.search(r'^CDHash=([a-f0-9]{40})$',text,re.M)
 if not m:raise RuntimeError('missing CDHash '+str(path))
 return m[1]
def sign(path,identifier=None,runtime=True):
 args=['codesign','--force','--sign','-']
 if runtime:args+=['--options','runtime']
 if identifier:args+=['--identifier',identifier]
 run(args+[path]);run(['codesign','--verify','--deep','--strict',path])
def requirement(identifier,pin):return 'identifier "'+identifier+'" and cdhash H"'+pin+'"'
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--inherit-outer-sandbox',action='store_true');a=ap.parse_args()
 out=ROOT/'Build/Adhoc';out.mkdir(parents=True,exist_ok=True)
 if (out/'pins.json').exists():raise RuntimeError('Preserve completed build; use a fresh checkout for a new release.')
 payload=out/'payload';driver=payload/'Library/Audio/Plug-Ins/HAL/RightDisplayVirtualVolume.driver';broker=payload/'Library/PrivilegedHelperTools/com.rightdisplay.audio.Transport'
 broker.parent.mkdir(parents=True,exist_ok=True);(driver/'Contents/MacOS').mkdir(parents=True,exist_ok=True);(driver/'Contents/Resources').mkdir()
 # Acyclic binding: Broker -> Driver -> App, all with exactly one native architecture.
 run(['xcrun','clang','-arch','arm64','-std=c11','-fblocks','-O2','-Wall','-Wextra','-Werror',ROOT/'AudioVirtualDevice/Broker/main.c','-framework','CoreFoundation','-framework','SystemConfiguration','-o',broker]);sign(broker,'com.rightdisplay.audio.Transport');bp=cdhash(broker)
 run(['xcrun','clang','-arch','arm64','-std=c11','-fblocks','-O2','-Wall','-Wextra','-Werror','-DRD_ADHOC_BROKER_CDHASH='+bp,'-bundle',ROOT/'AudioVirtualDevice/Driver/VirtualVolume.c','-framework','CoreAudio','-framework','CoreFoundation','-o',driver/'Contents/MacOS/VirtualVolume'])
 shutil.copy2(ROOT/'AudioVirtualDevice/Driver/Info.plist',driver/'Contents/Info.plist');shutil.copy2(ROOT/'AudioVirtualDevice/Driver/APPLE-LICENSE.txt',driver/'Contents/Resources/APPLE-LICENSE.txt');sign(driver,'com.rightdisplay.audio.VirtualVolume');dp=cdhash(driver)
 pins={'broker':bp,'driver':dp,'profile':'ad-hoc exact release content; not publisher authentication','component':21,'protocol':21}
 (out/'pins.json').write_text(json.dumps(pins,indent=2)+'\n')
 br=requirement('com.rightdisplay.audio.Transport',bp);dr=requirement('com.rightdisplay.audio.VirtualVolume',dp)
 for target,req in [(broker,br),(driver,dr)]:run(['codesign','--verify','--strict','-R','='+req,target])
 daemon=payload/'Library/LaunchDaemons';daemon.mkdir(parents=True);shutil.copy2(ROOT/'AudioVirtualDevice/Broker/com.rightdisplay.audio.Transport.plist',daemon/'com.rightdisplay.audio.Transport.plist')
 packages=ROOT/'Build/VirtualAudio/VirtualAudioPackages';packages.mkdir(parents=True,exist_ok=True)
 check=out/'CheckRemoval';run(['xcrun','clang','-arch','arm64','-O2','-Wall','-Wextra','-Werror',ROOT/'AudioVirtualDevice/Packaging/CheckRemoval.c','-framework','CoreAudio','-framework','CoreFoundation','-o',check]);sign(check)
 # Retain existing official-team upgrade compatibility OR this exact release. No arbitrary Ad-hoc code.
 for folder,script in [('install','preinstall'),('uninstall','postinstall')]:
  dest=out/(folder+'-scripts');dest.mkdir();text=(ROOT/'AudioVirtualDevice/Packaging'/folder/script).read_text()
  olddr='anchor apple generic and identifier "com.rightdisplay.audio.VirtualVolume" and certificate leaf[subject.OU] = "45F25M3DS7"'
  oldbr='anchor apple generic and identifier "com.rightdisplay.audio.Transport" and certificate leaf[subject.OU] = "45F25M3DS7"'
  assert olddr in text and oldbr in text
  text=text.replace(olddr,'('+olddr+') or ('+dr+')').replace(oldbr,'('+oldbr+') or ('+br+')')
  (dest/script).write_text(text);(dest/script).chmod(0o755);shutil.copy2(check,dest/'CheckRemoval')
 run(['pkgbuild','--analyze','--root',payload,out/'components.plist']);run(['plutil','-replace','0.BundleIsRelocatable','-bool','NO',out/'components.plist'])
 run(['pkgbuild','--root',payload,'--ownership','recommended','--component-plist',out/'components.plist','--identifier','com.rightdisplay.audio.VirtualVolume.install','--version','21','--scripts',out/'install-scripts','--install-location','/',packages/'InstallVirtualAudio.pkg'])
 run(['pkgbuild','--nopayload','--identifier','com.rightdisplay.audio.VirtualVolume.uninstall','--version','21','--scripts',out/'uninstall-scripts',packages/'UninstallVirtualAudio.pkg'])
 helper=ROOT/'Build/HelperExternalZeroconf/dist/RightDisplayAppleTVHelper'
 # Sign every actual Mach-O leaf, then the helper executable. No private team entitlement.
 for p in helper.rglob('*'):
  if p.is_file() and not p.is_symlink() and p.read_bytes()[:4] in [bytes.fromhex(x) for x in ['cffaedfe','cefaedfe','cafebabe','bebafeca']]:sign(p,runtime=False)
 sign(helper/'RightDisplayAppleTVHelper',runtime=False)
 run(['python3',ROOT/'Scripts/preflight.py'],out/'preflight.log')
 defs='$(inherited) RD_SIGNING_TEAM=\\\"45F25M3DS7\\\" RD_ADHOC_BROKER_CDHASH='+bp+' RD_ADHOC_DRIVER_CDHASH='+dp
 args=['xcodebuild','-project',ROOT/'RightDisplay.xcodeproj','-scheme','RightDisplay','-configuration','Release','-destination','platform=macOS,arch=arm64','-derivedDataPath',out/'DerivedData','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','DEVELOPMENT_TEAM=','GCC_PREPROCESSOR_DEFINITIONS='+defs,'DEPLOYMENT_POSTPROCESSING=YES','DEPLOYMENT_LOCATION=NO','STRIP_INSTALLED_PRODUCT=YES','STRIP_STYLE=debugging']
 if a.inherit_outer_sandbox:args+=['OTHER_SWIFT_FLAGS=-disable-sandbox']
 run(args+['build'],out/'xcodebuild.log')
 app=out/'DerivedData/Build/Products/Release/Right Display.app';pl=plistlib.loads((app/'Contents/Info.plist').read_bytes());assert (pl['CFBundleShortVersionString'],pl['CFBundleVersion'])==('1.0','45')
 legal=app/'Contents/Resources/Legal';legal.mkdir(exist_ok=True)
 for name in ['LICENSE','LICENSE_SCOPE.md','NOTICE.md','THIRD_PARTY_LICENSES.md','BRAND_ASSETS.md']:shutil.copy2(ROOT/name,legal/name)
 sign(app,'com.rightdisplay.gui');run(['codesign','--verify','--deep','--strict',app])
 (out/'result.json').write_text(json.dumps({'version':'1.0','build':45,'signing':'ad-hoc','notarized':False,'pins':pins,'app':str(app.relative_to(ROOT)),'installed':False,'hardware_testing':'not performed on repackaged artifact'},indent=2)+'\n')
 print('Ad-hoc build complete; run verify_adhoc.py before distribution.',flush=True)
if __name__=='__main__':main()
