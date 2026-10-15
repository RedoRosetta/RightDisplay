# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
# -*- mode: python ; coding: utf-8 -*-

import os

from PyInstaller.utils.hooks import collect_data_files


spec_directory = os.path.dirname(SPEC)
helper_source = os.path.join(spec_directory, "homepod_audio_helper.py")
zeroconf_sources = collect_data_files(
    "zeroconf",
    include_py_files=True,
    includes=["**/*.py", "py.typed"],
)

a = Analysis(
    [helper_source],
    pathex=[spec_directory],
    binaries=[],
    datas=zeroconf_sources,
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    module_collection_mode={"zeroconf": "py"},
    optimize=0,
)

# zeroconf supports a pure-Python implementation. Keep the package outside
# PYZ and omit Cython extension copies so recipients can replace its sources.
a.binaries = [
    item for item in a.binaries
    if not item[0].startswith("zeroconf/")
]

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="RightDisplayAppleTVHelper",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="RightDisplayAppleTVHelper",
)
