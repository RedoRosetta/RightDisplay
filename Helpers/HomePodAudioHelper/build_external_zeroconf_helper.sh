#!/bin/sh
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
: "${RIGHTDISPLAY_HELPER_PYTHON:?set explicit CPython 3.12.14 arm64 executable}"
: "${RIGHTDISPLAY_HELPER_WHEELS:?set verified wheel directory}"
exec /usr/bin/python3 "$project_root/Scripts/build_helper.py" --python "$RIGHTDISPLAY_HELPER_PYTHON" --wheels "$RIGHTDISPLAY_HELPER_WHEELS"
