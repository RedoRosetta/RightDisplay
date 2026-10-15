#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Inspect actual PyInstaller TOCs and payload; no helper execution or discovery."""
from pathlib import Path
import sys,json,ast,hashlib,importlib.metadata as md,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
 out=Path(sys.argv[1]).resolve();payload=out/'dist/RightDisplayAppleTVHelper';work=out/'work/RightDisplayAppleTVHelper';site=Path(md.distribution('pyatv').locate_file('')).resolve()
 records={};owners={}
 for dist in md.distributions():
  name=dist.metadata['Name'];records[name]={'dist':dist,'paths':[]}
  for f in dist.files or []:owners[str(Path(dist.locate_file(f)).resolve())]=name
 collected=[]
 def walk(x):
  if isinstance(x,(tuple,list)):
   if len(x)>=3 and isinstance(x[0],str) and isinstance(x[1],str) and Path(x[1]).is_file():collected.append((x[0],str(Path(x[1]).resolve()),str(x[2])))
   for y in x:walk(y)
 for toc in ['COLLECT-00.toc','PYZ-00.toc','PKG-00.toc']:
  p=work/toc
  if p.exists():walk(ast.literal_eval(p.read_text()))
 for dest,source,kind in collected:
  name=owners.get(source)
  if name:records[name]['paths'].append({'destination':dest,'source':str(Path(source).relative_to(site)) if Path(source).is_relative_to(site) else Path(source).name,'kind':kind})
 # Verify zeroconf remains outside the compressed module archive.
 from PyInstaller.archive.readers import ZlibArchiveReader
 pyz=ZlibArchiveReader(str(work/'PYZ-00.pyz'));assert not any(n=='zeroconf' or n.startswith('zeroconf.') for n in pyz.toc),'zeroconf found in PYZ'
 zdir=payload/'_internal/zeroconf';assert zdir.is_dir() and not list(zdir.rglob('*.so'))
 installed=site/'zeroconf';srcfiles=list(zdir.rglob('*.py'));assert srcfiles
 for p in srcfiles:assert p.read_bytes()==(installed/p.relative_to(zdir)).read_bytes(),p.name
 # Replaceable package test in an isolated COPY, using this freshly built environment.
 replacement=out/'replacement-test';replacement.mkdir();shutil.copytree(zdir,replacement/'zeroconf')
 init=replacement/'zeroconf/__init__.py';init.write_text(init.read_text()+'\nRNSL_REPLACEMENT_PROBE = "modified-compatible-source-loaded"\n')
 code='import sys; sys.path.insert(0,sys.argv[1]); import zeroconf; assert zeroconf.RNSL_REPLACEMENT_PROBE == "modified-compatible-source-loaded"; assert zeroconf.__file__.startswith(sys.argv[1]); print("replacement import PASS; no discovery called")'
 p=subprocess.run([sys.executable,'-I','-c',code,str(replacement)],capture_output=True,text=True);assert p.returncode==0,p.stderr
 (out/'replacement-test.log').write_text(p.stdout+p.stderr)
 # Preserve all supplied legal materials; actual runtime components are a subset, listed separately.
 shutil.copytree(ROOT/'third_party',payload/'Legal/third_party')
 original=ROOT/'release-assets/Right-Display-0.1-Beta-compliance'
 shutil.copytree(original/'SOURCES',payload/'Legal/CorrespondingSources')
 shutil.copytree(original/'LICENSES',payload/'Legal/LegacyLicenseMaterials')
 components=[];selected=[]
 inventory=json.loads((ROOT/'Dependencies/wheel-inventory.json').read_text())
 for name,rec in sorted(records.items()):
  if not rec['paths']:continue
  dist=rec['dist'];ver=dist.version;inv=next((x for x in inventory if x['name'].lower().replace('_','-')==name.lower().replace('_','-') and x['version']==ver),{})
  expr=dist.metadata.get('License-Expression');props=[{'name':'rightdisplay:evidence','value':'matched collected TOC source files to installed distribution RECORD'},{'name':'rightdisplay:license-review','value':'not-final; see THIRD_PARTY_LICENSES.md'}]
  comp={'type':'library','bom-ref':'pkg:pypi/'+name.lower().replace('_','-')+'@'+ver,'name':name,'version':ver,'purl':'pkg:pypi/'+name.lower().replace('_','-')+'@'+ver,'properties':props}
  if expr:comp['licenses']=[{'expression':expr}]
  components.append(comp);selected.append({'name':name,'version':ver,'collected_files':sorted({x['source'] for x in rec['paths']}),'license_materials':inv.get('materials',[]),'license_expression':expr,'status':'actual collection observed; licensing review separate'})
 components.append({'type':'platform','bom-ref':'cpython-3.12.14','name':'CPython','version':'3.12.14','properties':[{'name':'rightdisplay:evidence','value':'build interpreter verified and libpython collected; bundled native subcomponents require separate inventory'}]})
 sbom={'bomFormat':'CycloneDX','specVersion':'1.5','version':1,'metadata':{'component':{'type':'application','name':'RightDisplayAppleTVHelper','version':'candidate-from-Build44-source'},'properties':[{'name':'rightdisplay:scope','value':'actual newly rebuilt helper only; not old RC, not final app'},{'name':'rightdisplay:completeness','value':'Python distributions from TOCs; native embedded and nested component review incomplete'}]},'components':components}
 pub=ROOT/'compliance';pub.mkdir(exist_ok=True)
 (pub/'helper-sbom.cdx.json').write_text(json.dumps(sbom,indent=2));(pub/'helper-collected-distributions.json').write_text(json.dumps(selected,indent=2))
 manifest=[]
 for p in sorted(payload.rglob('*')):
  if p.is_file() and not p.is_symlink():manifest.append({'path':str(p.relative_to(payload)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
 (out/'payload-files.json').write_text(json.dumps(manifest,indent=2))
 (out/'audit-summary.json').write_text(json.dumps({'zeroconf_outside_PYZ':True,'zeroconf_no_extensions':True,'zeroconf_py_files':len(srcfiles),'zeroconf_matches_fresh_install':True,'replacement_import':True,'distributions_observed':len(selected),'payload_files':len(manifest),'hardware_tests':False},indent=2))
 print(json.dumps({'python_distributions_observed':len(selected),'zeroconf_source_files':len(srcfiles),'replacement_import':'PASS'}))
if __name__=='__main__':main()
