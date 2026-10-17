#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# Licensed under RNSL 1.0; see LICENSE_SCOPE.md.
"""Hardware-free PCM and production HAL regression; never starts real devices."""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--sanitize', action='store_true', help='Address/undefined sanitizers for PCM and HDMI integration')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
native = root / 'RightDisplay/AudioBridgeRealtime'
flags = ['-std=c++20', '-fblocks', '-Wall', '-Wextra', '-Werror', '-fno-fast-math', '-pthread', '-O2']
frameworks = ['-framework', 'CoreAudio', '-framework', 'CoreFoundation']
with tempfile.TemporaryDirectory(prefix='rightdisplay-hdmi-tests-') as folder:
    for test in ['HDMIPCMTests', 'HDMIPlaybackHALTests', 'AdaptiveFormatGuardTests', 'AdaptivePlaybackHALTests', 'VirtualAudioFakeHALTests', 'AudioBridgeFakeHALTests']:
        extra = ['-O1', '-g', '-fsanitize=address,undefined'] if args.sanitize and test.startswith('HDMI') else []
        executable = str(Path(folder) / test)
        subprocess.run(['xcrun', 'clang++', *flags, *extra, str(root / 'Tests' / (test + '.cpp')), *[str(native / (name + '.cpp')) for name in ['core', 'hal', 'route']], *frameworks, '-o', executable], check=True)
        subprocess.run([executable], check=True)
