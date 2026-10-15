#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Structural full-payload checks; never declares runtime or release acceptance."""
from pathlib import Path
import subprocess,json,sys,os,re
ROOT=Path(__file__).resolve().parents[1]
def main():
 errors=[]
 team=os.environ.get('RD_COMPONENT_TEAM','45F25M3DS7')
 if not re.fullmatch(r'[A-Z0-9]{10}',team):errors.append('invalid component signing team')
 helper=ROOT/'Build/HelperExternalZeroconf/dist/RightDisplayAppleTVHelper'
 required=[helper/'RightDisplayAppleTVHelper',helper/'_internal/libpython3.12.dylib',helper/'_internal/zeroconf/__init__.py',helper/'Legal/third_party/CPython-3.12.14/LICENSE',ROOT/'Build/VirtualAudio/VirtualAudioPackages/InstallVirtualAudio.pkg',ROOT/'Build/VirtualAudio/VirtualAudioPackages/UninstallVirtualAudio.pkg']
 for p in required:
  if not p.is_file():errors.append('missing '+str(p.relative_to(ROOT)))
 if helper.exists():
  if list((helper/'_internal/zeroconf').rglob('*.so')):errors.append('zeroconf native extensions are forbidden by this packaging contract')
 summary=ROOT/'Build/HelperExternalZeroconf/audit-summary.json'
 if not summary.is_file():errors.append('missing actual helper audit')
 else:
  j=json.loads(summary.read_text())
  if not all(j.get(k) for k in ['zeroconf_outside_PYZ','zeroconf_no_extensions','replacement_import']):errors.append('helper replaceability audit failed')
 if errors:
  print('\n'.join('BLOCKED: '+e for e in errors));return 1
 print('PASS: required complete-product inputs and helper packaging structure; release/signing/legal/hardware gates remain separate.');return 0
if __name__=='__main__':sys.exit(main())
