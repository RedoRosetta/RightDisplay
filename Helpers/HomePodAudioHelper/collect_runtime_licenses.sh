#!/bin/sh
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
set -eu
test "$#" -eq 2 || { echo "usage: $0 explicit-python output-directory" >&2; exit 64; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$1" -I "$root/Scripts/collect_licenses.py" "$2"
