# Right Display

See what your Mac is actually sending to your display.

Right Display is a display signal diagnostics and safe display control utility for macOS.

> **Current release: Right Display 0.1 Beta (Build 1)**
>
> [Download Right Display 0.1 Beta](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.1)

This is an early testing release. Back up important work and record your current display settings before testing display-mode changes.

## Download

Download **Right-Display-0.1-Beta.zip** from the [v0.1 release page](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.1).

SHA-256: **da1270012eb18402b152af4d87a4e003de26c8e1c0ac9ccf90245c9b0b549792**

The release also provides Apple TV helper rebuild materials and the exact corresponding source for zeroconf 0.150.0.

## Main features

- Distinguishes physical output resolution, HiDPI logical resolution, and rendering-buffer size.
- Reports refresh rate and the VRR modes exposed by macOS.
- Reports HDR/SDR and available RGB or YCbCr signal information.
- Reports available bit-depth information.
- Estimates whether DSC is likely in use. DSC is explicitly shown as an inference, not a receiver-reported fact.
- Reads and exports EDID and display diagnostics.
- Changes supported resolution and refresh-rate modes with confirmation and attempted automatic recovery.
- Controls brightness when macOS exposes a writable control for the display.
- Controls writable Core Audio outputs and provides optional Apple TV/HomePod-compatible audio functionality.

## Screenshots

Screenshots will be added as testing expands. The 0.1 Beta can be downloaded now from the release page.

## Compatibility and requirements

- macOS 14 or later.
- Apple silicon Mac build.
- Some diagnostics and controls are available only for external displays.
- Feature availability depends on the Mac, macOS version, display, dock or adapter, cable, and connection type.
- Accessibility permission is required for relevant display-control features.
- Local Network permission is required for Apple TV/HomePod discovery and control.

Not every display supports every control. Right Display reports unavailable or inferred information where macOS does not provide a verified value.

## Known limitations

- macOS and the display driver negotiate many RGB/YCbCr and bit-depth combinations. Right Display cannot guarantee that every requested combination will be accepted or remain active.
- DSC status is inferred from mode and bandwidth information; it is not read directly from the display receiver.
- HDR control depends partly on macOS interfaces that may change between system releases.
- VRR, brightness, HDR, color-format, bit-depth, and audio behavior vary by hardware and connection path.
- Apple TV/HomePod discovery has been tested. Existing Apple TV pairing recovery, status, volume reading, and volume changes have been tested. First-time pairing and every HomePod configuration have not yet been fully verified.
- This Beta is ad-hoc signed, is not signed with an Apple Developer ID, and is not notarized.

## Installation

1. Download and extract **Right-Display-0.1-Beta.zip**.
2. Move **Right Display.app** to the Applications folder.
3. Open the app.
4. If macOS blocks the first launch, open **System Settings → Privacy & Security** and choose **Open Anyway** for Right Display.
5. Grant Accessibility or Local Network access only if you want to use the related features.

Do not disable SIP. Do not disable Gatekeeper, and do not use **spctl --master-disable**.

## Feedback and issues

Use [GitHub Issues](https://github.com/RedoRosetta/RightDisplay/issues) and select the bug report template.

Please include your Mac model, macOS version, display model, connection type, resolution, refresh rate, HDR state, a clear problem description, and reproduction steps. Right Display diagnostic information can help when available.

Diagnostic reports and EDID data can contain device names, serial numbers, display identifiers, network details, or other personal information. Review and redact files before uploading them publicly. Never post passwords, tokens, Apple IDs, pairing credentials, or other secrets.

## Third-party licenses

The downloadable app includes required third-party license and notice files. The Apple TV/HomePod helper rebuild bundle and corresponding source materials are available on the [v0.1 release page](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.1).

See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for the public distribution summary.

## Source availability

Right Display's proprietary Swift display-control source and private Xcode project are not published in this repository.

Source and rebuild materials required for the separately packaged Apple TV/HomePod helper's third-party license compliance are provided as a release asset.

