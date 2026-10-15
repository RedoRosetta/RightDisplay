# Signing / 签名

Copyright © 2026 RedoRosetta

## Ad-hoc 1.0 distribution

`Scripts/build_adhoc.py` builds Broker first, signs it Ad-hoc, and embeds its exact arm64 CodeDirectory hash plus identifier into Driver and App XPC peer requirements. It then signs Driver and embeds Driver's exact hash plus identifier into App verification. Values are build inputs, never a mutable runtime allowlist. `Scripts/verify_adhoc.py` checks the packaged components, false same-name replacement, tampering, and real anonymous XPC positive/negative cases. Content hashes are release-specific integrity pins, not developer/publisher identity or a replacement Team ID.

Installer and matching uninstaller retain fixed paths, symlink guards, strict validation and removal safety checks. They accept the exact current component or the previous official Apple/team policy, never arbitrary Ad-hoc code. Other Ad-hoc versions fail closed; use their own matching safe uninstaller before upgrade. Apple system-producer requirements remain unchanged; consumer console-UID/ownership rules and protocol/epoch/bounds/fail-silent behavior remain unchanged. No new input/capture path or speaker fallback.

Main App, Broker and Driver use Hardened Runtime with Ad-hoc signatures; Helper/native runtime leaves are Ad-hoc signed without Hardened Runtime, with no additional entitlements or microphone permission. No separate embedded XPC bundle exists: the signed Mach-service Broker is the XPC service. The original Apple/team build profile remains the default for non-Ad-hoc builds.

This distribution is not notarized and not Developer ID signed. Local signature verification and anonymous XPC checks do not prove installation/load acceptance on all Macs or reproduce full hardware tests. We do not change Apple hosts, AMFI, SIP, Gatekeeper or their entitlements. If OS policy refuses loading, fail closed. Signing the final app seals the bundled Helper and source/notices; replacing LGPL components requires normal lawful rebuilding/re-signing, never official private keys.

## Rebuild

Build Helper as in BUILDING.md, then run `python3 Scripts/build_adhoc.py` and `python3 Scripts/verify_adhoc.py` from a fresh checkout. In the documented outer sandbox use `--inherit-outer-sandbox`. Preserve failed/completed build directories; select a fresh checkout rather than silently reusing pins. Generated `Build/Adhoc/pins.json` binds that exact binary release; do not copy pins from another build. No author Keychain or certificate is used.
