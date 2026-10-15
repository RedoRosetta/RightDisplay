#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Build the complete helper in a fresh venv using explicit, hash-locked inputs."""
from pathlib import Path
import argparse,os,subprocess,sys,json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--python',required=True);ap.add_argument('--wheels',required=True);a=ap.parse_args()
 py=Path(a.python).resolve();wheels=Path(a.wheels).resolve();out=ROOT/'Build/HelperExternalZeroconf'
 if out.exists():raise SystemExit('Output already exists. Select a fresh checkout; preserve failed evidence before removing generated output.')
 out.mkdir(parents=True);env=os.environ.copy()
 for k in ['PYTHONPATH','PYTHONHOME','VIRTUAL_ENV','PIP_INDEX_URL','PIP_EXTRA_INDEX_URL','PIP_FIND_LINKS','PIP_CONFIG_FILE']:env.pop(k,None)
 env.update(PIP_CONFIG_FILE=os.devnull,PIP_NO_INDEX='1',PIP_DISABLE_PIP_VERSION_CHECK='1',PYTHONNOUSERSITE='1',PYTHONDONTWRITEBYTECODE='1',PIP_CACHE_DIR=str(out/'pip-cache'),PYINSTALLER_CONFIG_DIR=str(out/'pyinstaller-config'))
 # No host caches or old venvs; every child output is logged locally.
 def run(cmd,label,extra=None):
  with (out/(label+'.log')).open('w') as f:p=subprocess.run([str(x) for x in cmd],env={**env,**(extra or {})},cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
  print(label,'PASS' if p.returncode==0 else 'FAIL',flush=True)
  if p.returncode:raise SystemExit((out/(label+'.log')).read_text()[-5000:])
 version=subprocess.check_output([str(py),'-I','-c','import sys,platform; print(platform.machine(),sys.version_info[:3])'],text=True).strip()
 if version!="arm64 (3, 12, 14)":raise SystemExit('Requires explicit CPython 3.12.14 arm64: '+version)
 inv=json.loads((ROOT/'Dependencies/wheel-inventory.json').read_text())
 for x in inv:
  p=wheels/x['wheel']
  if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=x['sha256']:raise SystemExit('Missing/corrupt pinned wheel: '+x['wheel'])
 run([py,'-I','-m','venv',out/'venv'],'venv');vp=out/'venv/bin/python'
 run([vp,'-I','-m','pip','install','--no-cache-dir','--require-hashes','--only-binary=:all:','--find-links',wheels,'-r',ROOT/'Dependencies/helper-requirements.lock'],'dependencies')
 # Build dependencies are separately pinned, not fetched by pip build isolation.
 builder=[]
 for x in inv:
  if x['name'].lower() in ['poetry-core','cython']:builder.append(f"{x['name']}=={x['version']} --hash=sha256:{x['sha256']}")
 bp=out/'builder.lock';bp.write_text('\n'.join(builder)+'\n')
 run([vp,'-I','-m','pip','install','--no-cache-dir','--require-hashes','--only-binary=:all:','--find-links',wheels,'-r',bp],'build-dependencies')
 src=ROOT/'release-assets/Right-Display-0.1-Beta-compliance/SOURCES/zeroconf-0.150.0.tar.gz'
 if hashlib.sha256(src.read_bytes()).hexdigest()!='a5fe7feab1de6ef5e541e0a3d07e534fd91629b813fc27281593584100f63164':raise SystemExit('zeroconf source mismatch')
 run([vp,'-I','-m','pip','install','--no-cache-dir','--no-build-isolation','--no-deps','--force-reinstall',src],'pure-zeroconf',{'SKIP_CYTHON':'1'})
 run([vp,'-I','-m','pip','uninstall','--yes','Cython','poetry-core'],'remove-build-only-tools')
 for test in ['test_audio_session.py','test_native_discovery.py']:
  run([vp,'-I','-m','unittest','discover','-s',ROOT/'Helpers/HomePodAudioHelper','-p',test],test)
 run([vp,'-I','-m','PyInstaller','--noconfirm','--clean','--distpath',out/'dist','--workpath',out/'work',ROOT/'Helpers/HomePodAudioHelper/RightDisplayAppleTVHelper.spec'],'pyinstaller')
 run([vp,'-I',ROOT/'Scripts/audit_helper.py',out],'payload-audit')
 print('Helper built and audited; no network discovery/pairing/playback or application launch performed.',flush=True)
if __name__=='__main__':main()
