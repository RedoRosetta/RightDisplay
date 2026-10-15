#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Download exact public artifacts; no unpinned fallback or author cache."""
from pathlib import Path
import argparse,json,hashlib,urllib.request
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',default=str(ROOT/'Build/inputs/wheels'));a=ap.parse_args();out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
 for x in json.loads((ROOT/'Dependencies/wheel-inventory.json').read_text()):
  p=out/x['wheel']
  if p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==x['sha256']:continue
  if not x.get('url') or not x.get('upstream_hash_verified'):raise SystemExit('BLOCKED: public source/hash unverified for '+x['wheel'])
  with urllib.request.urlopen(x['url'],timeout=60) as f:data=f.read()
  if hashlib.sha256(data).hexdigest()!=x['sha256']:raise SystemExit('BLOCKED: download hash mismatch '+x['wheel'])
  p.write_bytes(data);print(p.name,flush=True)
if __name__=='__main__':main()
