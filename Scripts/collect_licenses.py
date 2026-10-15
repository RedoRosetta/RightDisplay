#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Copy legal texts from installed distributions including vendored notices."""
from pathlib import Path
import importlib.metadata as md,sys,json,shutil
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True);rows=[]
for d in md.distributions():
 copied=[]
 for f in d.files or []:
  p=Path(d.locate_file(f));parts=Path(str(f)).parts
  if '..' in parts or not p.is_file():continue
  if any(s in p.name.lower() for s in ['license','copying','notice','authors','sbom','cyclonedx']):
   target=out/(d.metadata['Name']+'-'+d.version)/str(f);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target);copied.append(str(target.relative_to(out)))
 rows.append({'name':d.metadata['Name'],'version':d.version,'files':copied})
(out/'inventory.json').write_text(json.dumps(rows,indent=2))
