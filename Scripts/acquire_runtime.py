#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Acquire the exact public CPython runtime; never searches author caches."""
from pathlib import Path
import argparse,subprocess,hashlib,tarfile,posixpath,tempfile,shutil
URL='https://github.com/astral-sh/python-build-standalone/releases/download/20260825/cpython-3.12.14%2B20260825-aarch64-apple-darwin-install_only_stripped.tar.gz'
SHA256='8b0f1fa71eab7ca644e482c631807a1116fa848491051cd1c8d9429491de63a6'
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',required=True);ap.add_argument('--archive',help='explicit predownloaded archive; same digest required');a=ap.parse_args();out=Path(a.output).resolve()
 if out.exists():raise SystemExit('Refusing to overwrite an existing runtime')
 out.parent.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='runtime-acquire-',dir=out.parent) as tmp:
  tmp=Path(tmp);archive=Path(a.archive) if a.archive else tmp/'runtime.tar.gz'
  if not a.archive:subprocess.run(['curl','--fail','--location','--silent','--show-error','--connect-timeout','15','--max-time','90',URL,'-o',str(archive)],check=True)
  if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA256:raise SystemExit('Runtime archive digest mismatch')
  with tarfile.open(archive) as t:
   for m in t.getmembers():
    if m.name.startswith('/') or '..' in Path(m.name).parts or not (m.name=='python' or m.name.startswith('python/')):raise SystemExit('Unsafe archive path')
    if m.issym() or m.islnk():
     target=posixpath.normpath(posixpath.join(posixpath.dirname(m.name),m.linkname)) if m.issym() else posixpath.normpath(m.linkname)
     if m.linkname.startswith('/') or not target.startswith('python/'):raise SystemExit('Unsafe archive link')
   t.extractall(tmp)
  shutil.move(str(tmp/'python'),out)
 p=subprocess.run([str(out/'bin/python3.12'),'-I','-c','import sys,platform; assert sys.version_info[:3]==(3,12,14); assert platform.machine()=="arm64"; print("Official CPython3.12.14 arm64 input verified")'],capture_output=True,text=True,check=True);print(p.stdout.strip())
if __name__=='__main__':main()
