#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# Licensed under RNSL 1.0.
"""Targeted release checks; no audio, device enumeration, installation or App launch."""
from pathlib import Path
import subprocess,json,re,shutil,plistlib,tempfile
from build_adhoc import run,cdhash,requirement,ROOT

def main():
 out=ROOT/'Build/Adhoc';pins=json.loads((out/'pins.json').read_text());app=out/'DerivedData/Build/Products/Release/Right Display.app';res=app/'Contents/Resources';test=Path(tempfile.mkdtemp(prefix='verification-',dir=out))
 pl=plistlib.loads((app/'Contents/Info.plist').read_bytes());assert (pl['CFBundleShortVersionString'],pl['CFBundleVersion'])==('1.0','45')
 run(['codesign','--verify','--deep','--strict',app])
 text=run(['codesign','-dvvv',app]);assert 'Signature=adhoc' in text and 'runtime' in text and 'TeamIdentifier=not set' in text
 macho=app/'Contents/MacOS/Right Display'
 for pin in [pins['broker'],pins['driver']]:assert pin.encode() in macho.read_bytes(),'App did not embed required component hash'
 # Check the actual packages copied into the App, not only loose build intermediates.
 package=res/'VirtualAudioPackages/InstallVirtualAudio.pkg';unpacked=test/'installed-payload';run(['pkgutil','--expand-full',package,unpacked])
 driver=next(p for p in unpacked.rglob('RightDisplayVirtualVolume.driver') if p.is_dir());broker=next(p for p in unpacked.rglob('com.rightdisplay.audio.Transport') if p.is_file())
 assert cdhash(driver)==pins['driver'] and cdhash(broker)==pins['broker']
 assert pins['broker'].encode() in (driver/'Contents/MacOS/VirtualVolume').read_bytes()
 for path,ident,pin in [(driver,'com.rightdisplay.audio.VirtualVolume',pins['driver']),(broker,'com.rightdisplay.audio.Transport',pins['broker'])]:run(['codesign','--verify','--deep','--strict','-R','='+requirement(ident,pin),path])
 script=next(unpacked.rglob('preinstall')).read_text();assert pins['driver'] in script and pins['broker'] in script and 'anchor apple generic' in script
 # Validate the exact compiled C requirement getter used by Swift and XPC call sites.
 ctest=test/'requirements.c';ctest.write_text('#include "SigningIdentity.h"\n#include <stdio.h>\nint main(void){puts(RD_BROKER_REQUIREMENT);puts(RDDriverRequirement());return 0;}\n')
 cexe=test/'requirements';run(['xcrun','clang','-I',ROOT/'AudioVirtualDevice','-DRD_ADHOC_BROKER_CDHASH='+pins['broker'],'-DRD_ADHOC_DRIVER_CDHASH='+pins['driver'],ctest,'-o',cexe]);assert run([cexe]).splitlines()==[requirement('com.rightdisplay.audio.Transport',pins['broker']),requirement('com.rightdisplay.audio.VirtualVolume',pins['driver'])]
 # A same-name, same-path-class, validly Ad-hoc signed replacement must fail the exact release requirement.
 dummy=test/'dummy.c';dummy.write_text('int main(void){return 0;}\n');forged=test/'com.rightdisplay.audio.Transport';run(['xcrun','clang',dummy,'-o',forged]);run(['codesign','--force','--sign','-','--identifier','com.rightdisplay.audio.Transport',forged])
 bad=subprocess.run(['codesign','--verify','--strict','-R','='+requirement('com.rightdisplay.audio.Transport',pins['broker']),str(forged)],capture_output=True);assert bad.returncode!=0
 corrupt=test/'corrupt';shutil.copy2(broker,corrupt);b=bytearray(corrupt.read_bytes());b[4096]^=1;corrupt.write_bytes(b);bad=subprocess.run(['codesign','--verify','--strict',str(corrupt)],capture_output=True);assert bad.returncode!=0
 # Exercise the real XPC signing-requirement API with anonymous endpoints and audit identities.
 probe=test/'peer';run(['xcrun','clang','-arch','arm64','-fblocks','-Wall','-Wextra','-Werror',ROOT/'Tests/AdhocPeerRequirement.c','-o',probe]);run(['codesign','--force','--sign','-','--identifier','com.rightdisplay.test.peer',probe]);hp=cdhash(probe)
 for pin,expected in [(hp,'1'),('0'*40,'0')]:run([probe,requirement('com.rightdisplay.test.peer',pin),expected])
 # All actual nested Mach-O leaves must verify. No trusted Team is invented.
 count=0
 for p in app.rglob('*'):
  if p.is_file() and not p.is_symlink() and p.read_bytes()[:4] in [bytes.fromhex(x) for x in ['cffaedfe','cefaedfe','cafebabe','bebafeca']]:run(['codesign','--verify','--strict',p]);count+=1
 helper=res/'AppleTVAudioHelper/RightDisplayAppleTVHelper';policy='(version 1)(allow default)(deny network*)(deny file-write* (subpath "'+str(Path.home()/'Library')+'"))'
 run(['sandbox-exec','-p',policy,helper,'--help'],test/'helper-help.log')
 # Check exact module sources are still external and shipped source obligations remain present.
 assert len(list((helper.parent/'_internal/zeroconf').rglob('*.py')))==33
 assert not list((helper.parent/'_internal/zeroconf').rglob('*.so'))
 assert (helper.parent/'Legal/CorrespondingSources/zeroconf-0.150.0.tar.gz').is_file()
 broker_src=(ROOT/'AudioVirtualDevice/Broker/main.c').read_text();assert 'anchor apple and (identifier \"com.apple.audio.coreaudiod\"' in broker_src.replace('\\"','\"')
 result={'version':'1.0','build':45,'signature':'ad-hoc','notarized':False,'nested_macho_verified':count,'exact_content_requirements':True,'same_identifier_replacement_rejected':True,'tampered_binary_rejected':True,'anonymous_XPC_matching_peer_accepted':True,'anonymous_XPC_wrong_pin_rejected':True,'Apple_system_producer_requirement_unchanged':True,'packaged_helper_help_network_denied':True,'hardware_tests_performed':False,'installed_app_changed':False}
 (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result),flush=True)
if __name__=='__main__':main()
