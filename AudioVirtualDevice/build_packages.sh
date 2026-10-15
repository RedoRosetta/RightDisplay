#!/bin/sh
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:?output directory required}
identity=${2:?code signing identity required}
team=${3:-45F25M3DS7}
case "$team" in *[!A-Z0-9]*|'') echo "invalid component team" >&2; exit 64;; esac
[ "${#team}" -eq 10 ] || { echo "component team must be 10 uppercase letters/digits" >&2; exit 64; }
# Non-ad-hoc identities must match the compiled trust policy. Ad-hoc is compile-only.

/bin/mkdir -p "$out/payload/Library/Audio/Plug-Ins/HAL/RightDisplayVirtualVolume.driver/Contents/MacOS" "$out/install-scripts" "$out/uninstall-scripts" "$out/VirtualAudioPackages"
driver="$out/payload/Library/Audio/Plug-Ins/HAL/RightDisplayVirtualVolume.driver"
/usr/bin/xcrun clang "-DRD_SIGNING_TEAM=\"$team\"" -arch arm64 -std=c11 -fblocks -O2 -bundle -framework CoreAudio -framework CoreFoundation -Wall -Wextra -Werror "$root/Driver/VirtualVolume.c" -o "$driver/Contents/MacOS/VirtualVolume"
/bin/cp "$root/Driver/Info.plist" "$driver/Contents/Info.plist"
/bin/mkdir -p "$driver/Contents/Resources"
/bin/cp "$root/Driver/APPLE-LICENSE.txt" "$driver/Contents/Resources/APPLE-LICENSE.txt"
/usr/bin/codesign --force --sign "$identity" --options runtime "$driver"
/usr/bin/codesign --verify --deep --strict "$driver"
/usr/bin/xcrun clang "-DRD_SIGNING_TEAM=\"$team\"" -arch arm64 -O2 -Wall -Wextra -Werror "$root/Packaging/CheckRemoval.c" -framework CoreAudio -framework CoreFoundation -o "$out/CheckRemoval"
/usr/bin/codesign --force --sign "$identity" --options runtime "$out/CheckRemoval"
/bin/cp "$root/Packaging/install/preinstall" "$out/install-scripts/"
/bin/cp "$root/Packaging/uninstall/postinstall" "$out/uninstall-scripts/"
# Bake the validated build-time team into Installer scripts, never read mutable install-time settings.
/usr/bin/python3 - "$out/install-scripts/preinstall" "$out/uninstall-scripts/postinstall" "$team" <<'PYTEAM'
from pathlib import Path
import sys
for name in sys.argv[1:3]:
 p=Path(name);text=p.read_text();assert text.count('45F25M3DS7')==2
 p.write_text(text.replace('45F25M3DS7',sys.argv[3]))
PYTEAM

/bin/cp "$out/CheckRemoval" "$out/install-scripts/CheckRemoval"
/bin/cp "$out/CheckRemoval" "$out/uninstall-scripts/CheckRemoval"
/bin/chmod 755 "$out/install-scripts/preinstall" "$out/uninstall-scripts/postinstall" "$out/install-scripts/CheckRemoval" "$out/uninstall-scripts/CheckRemoval"
# Authenticated, event-only Mach broker. Installed by the user's Installer request.
/bin/mkdir -p "$out/payload/Library/PrivilegedHelperTools" "$out/payload/Library/LaunchDaemons"
/usr/bin/xcrun clang "-DRD_SIGNING_TEAM=\"$team\"" -arch arm64 -std=c11 -fblocks -O2 -Wall -Wextra -Werror "$root/Broker/main.c" -framework CoreFoundation -framework SystemConfiguration -o "$out/payload/Library/PrivilegedHelperTools/com.rightdisplay.audio.Transport"
/usr/bin/codesign --force --sign "$identity" --identifier com.rightdisplay.audio.Transport --options runtime "$out/payload/Library/PrivilegedHelperTools/com.rightdisplay.audio.Transport"
/usr/bin/codesign --verify --deep --strict "$out/payload/Library/PrivilegedHelperTools/com.rightdisplay.audio.Transport"
/bin/cp "$root/Broker/com.rightdisplay.audio.Transport.plist" "$out/payload/Library/LaunchDaemons/"
/bin/chmod 644 "$out/payload/Library/LaunchDaemons/com.rightdisplay.audio.Transport.plist"
if [ "$identity" != "-" ]; then
 for item in "$driver" "$out/payload/Library/PrivilegedHelperTools/com.rightdisplay.audio.Transport"; do
  actual=$(/usr/bin/codesign -dv --verbose=4 "$item" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')
  [ "$actual" = "$team" ] || { echo "signer team does not match component policy" >&2; exit 1; }
 done
else
 echo "COMPILE ONLY: ad-hoc identity does not satisfy Apple/team authentication; do not install as a supported release." >&2
fi
/usr/bin/pkgbuild --analyze --root "$out/payload" "$out/components.plist"
/usr/bin/plutil -replace 0.BundleIsRelocatable -bool NO "$out/components.plist"
/usr/bin/pkgbuild --root "$out/payload" --component-plist "$out/components.plist" --identifier com.rightdisplay.audio.VirtualVolume.install --version 21 --scripts "$out/install-scripts" --install-location / "$out/VirtualAudioPackages/InstallVirtualAudio.pkg"
/usr/bin/pkgbuild --nopayload --identifier com.rightdisplay.audio.VirtualVolume.uninstall --version 21 --scripts "$out/uninstall-scripts" "$out/VirtualAudioPackages/UninstallVirtualAudio.pkg"
# Local development packages. Payload is Apple Development signed; .pkg containers
# are not Developer ID Installer signed. No public distribution claim.
