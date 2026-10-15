#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# Licensed under RNSL 1.0.
"""Create and verify a source-paired DMG from the checked local Ad-hoc build."""
from pathlib import Path
import subprocess,shutil,json,hashlib,plistlib
from build_adhoc import ROOT,run

def main():
 if run(['git','status','--porcelain']).strip():raise RuntimeError('Commit the exact reviewed source before packaging')
 commit=run(['git','rev-parse','HEAD']).strip();out=ROOT/'Build/Distribution';out.mkdir(parents=True,exist_ok=True);stage=out/'stage';stage.mkdir()
 app=ROOT/'Build/Adhoc/DerivedData/Build/Products/Release/Right Display.app'
 run(['codesign','--verify','--deep','--strict',app]);run(['ditto',app,stage/'Right Display.app']);(stage/'Applications').symlink_to('/Applications')
 sources=stage/'Sources';sources.mkdir();archive=sources/'RightDisplay-1.0-Build45-source.tar.gz'
 with archive.open('wb') as f:subprocess.run(['git','archive','--format=tar.gz','--prefix=RightDisplay-1.0-Build45/',commit],cwd=ROOT,stdout=f,check=True)
 (sources/'SOURCE_COMMIT.txt').write_text(commit+'\n')
 for name in ['LICENSE','LICENSE_SCOPE.md','NOTICE.md','THIRD_PARTY_LICENSES.md']:shutil.copy2(ROOT/name,stage/name)
 shutil.copy2(ROOT/'releases/1.0.0.md',stage/'READ_ME.md')
 dmg=out/'RightDisplay-1.0-Build45.dmg'
 run(['hdiutil','create','-volname','RightDisplay 1.0','-srcfolder',stage,'-format','UDZO','-ov',dmg],out/'hdiutil-create.log');run(['hdiutil','verify',dmg],out/'hdiutil-verify.log')
 mounted=plistlib.loads(subprocess.check_output(['hdiutil','attach','-readonly','-nobrowse','-plist',str(dmg)]));vol=next(Path(x['mount-point']) for x in mounted['system-entities'] if 'mount-point' in x)
 try:
  copied=vol/'Right Display.app';pl=plistlib.loads((copied/'Contents/Info.plist').read_bytes());assert (pl['CFBundleShortVersionString'],pl['CFBundleVersion'])==('1.0','45');run(['codesign','--verify','--deep','--strict',copied]);assert (vol/'Applications').is_symlink();assert (vol/'Sources/SOURCE_COMMIT.txt').read_text().strip()==commit
  # Compare every mounted app file to the already validated candidate without recomputing artifact digest.
  original={str(p.relative_to(app)):p for p in app.rglob('*') if p.is_file() and not p.is_symlink()};actual={str(p.relative_to(copied)):p for p in copied.rglob('*') if p.is_file() and not p.is_symlink()};assert original.keys()==actual.keys()
  for name,path in original.items():assert path.read_bytes()==actual[name].read_bytes(),name
 finally:run(['hdiutil','detach',vol])
 # Compute final DMG SHA-256 once, reuse for Release and remote digest comparison.
 digest=hashlib.file_digest(dmg.open('rb'),'sha256').hexdigest() if hasattr(hashlib,'file_digest') else hashlib.sha256(dmg.read_bytes()).hexdigest()
 result={'version':'1.0','build':45,'commit':commit,'dmg':dmg.name,'bytes':dmg.stat().st_size,'sha256':digest,'signature':'ad-hoc','notarized':False,'dmg_integrity':'PASS','mounted_app_signature':'PASS','mounted_app_byte_compare':'PASS','paired_source_archive':True}
 (out/'SHA256SUMS').write_text(digest+'  '+dmg.name+'\n');(out/'release-result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result),flush=True)
if __name__=='__main__':main()
