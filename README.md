# RightDisplay

See, understand, verify, and safely adjust your Mac's display connection.

[简体中文](README.zh-CN.md) · [Releases](https://github.com/RedoRosetta/RightDisplay/releases) · [Version history](CHANGELOG.md)

<p align="center"><img src="docs/assets/right-display-app-icon.png" width="112" alt="RightDisplay app icon"></p>

**[Download RightDisplay 0.3 Beta](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.3-beta)** · macOS 14+ · Apple silicon · Build 60.

<p align="center"><img src="assets/screenshots/overview.png" width="960" alt="RightDisplay Overview with display status and evidence labels"></p>

## A closer look

Development previews of the 0.3 interface. Visible internal version labels are not separate public releases; these are not captures of the final release build.

<p align="center"><img src="assets/screenshots/quick-control.png" width="360" alt="RightDisplay menu-bar Quick Control for brightness, volume and display settings"></p>

<details>
<summary>Display &amp; Output · Brightness &amp; Sound</summary>

<p><img src="assets/screenshots/display-output.png" width="960" alt="Display modes, Configuration Protection, color format and color depth"></p>
<p><img src="assets/screenshots/brightness-sound.png" width="960" alt="Display brightness and compatible Apple TV audio-output controls"></p>

</details>

## Understand your display

RightDisplay is a menu-bar utility for Macs with external displays. It brings display status, supported controls and the evidence behind them into one place.

- **Display status:** output timing, HiDPI resolution, refresh rate, connection, color format/depth, HDR, VRR and DSC evidence.
- **Display Link Test:** check stable color-format, depth and HDR/SDR combinations on the current connection. Testing can interrupt the display and requires confirmation before starting.
- **Safer adjustments:** supported settings use readback checks. Mode changes requiring confirmation offer a countdown and attempt to restore the previous setting if you do not confirm. Recovery is not guaranteed on every connection.
- **Quick Control:** frequently used settings, brightness and device volume from the menu bar, sharing the same display state as advanced settings.
- **Brightness & Sound:** supported display brightness, writable system-audio volume, and compatible Apple TV audio-output volume. HomePod volume follows the Apple TV's selected/default output; direct control of every HomePod or AirPlay speaker is not promised. Optional keyboard volume-key control is available on supported paths.
- **Configuration Protection:** lock manual display controls in advanced settings and Quick Control while retaining brightness and volume. This is UI protection, not an operating-system security boundary.
- **EDID & diagnostics:** inspect/export device-declared capabilities and save diagnostic reports for troubleshooting.

Follow-system, Simplified Chinese and English interface options; Light/Dark appearance; a first-use guide.

## Evidence, not assumptions

RightDisplay distinguishes **current readback/verified state**, **inferred state** and **device-declared capability**. EDID advertises capabilities, not current output. DSC and some timing/transport information are inferred, not receiver measurements. A successful test covers the tested connection and observation period, not all future setups.

## Requirements

- macOS 14 or later, per the current deployment target. Newer visual effects fall back on older systems.
- Apple silicon: the currently checked build is arm64. No Intel distribution is promised for this candidate.
- Controls depend on the Mac, system, display, adapter/dock, cable and connection.
- Apple TV control requires a compatible device, network access and pairing where needed. Some features require Local Network or Accessibility permission; grant them only when needed.

## Installation

RightDisplay 0.3 Beta uses **ad-hoc signing and is not Apple notarized**. macOS may block the first launch. Try opening normally; if blocked, use **System Settings → Privacy & Security → Open Anyway**, or Finder's manual **Open** where available. No need to disable Gatekeeper or SIP.

Download `RightDisplay-0.3-Beta.zip` and `SHA256SUMS.txt` from [the release](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.3-beta), compare SHA-256, extract and move `Right Display.app` to Applications. See [installation](INSTALLATION.md).

## Privacy & diagnostics

Reports are saved locally on request, not automatically submitted to GitHub. They include display/audio state, system/app information, recent operations and selected troubleshooting excerpts. Structured redaction excludes some identifiers and sensitive fields; it does not guarantee that every free-text field is anonymous. Review names, errors and raw EDID before sharing. See [privacy](PRIVACY.md).

## Current limitations

macOS and hardware negotiate display settings; not every color/depth/HDR request can be applied. Unknown data stays unknown. Switching/testing may briefly blank the screen. Recovery, reconnection and volume availability vary by device and network. Beta compatibility remains limited to tested configurations.

## Version & feedback

Read the [0.3 release notes](releases/0.3-beta.md) and [public history](CHANGELOG.md). Use [Issues](https://github.com/RedoRosetta/RightDisplay/issues) for reproducible feedback after reviewing attachments for privacy.

This repository contains distribution materials, not proprietary application source. See [NOTICE](NOTICE.md) and [third-party information](THIRD_PARTY_LICENSES.md).

## Support development

Optional sponsorship helps support development. Names have been removed from these cards; the original QR payloads are preserved. Payment services may still show recipient information before payment.

<p><img src="assets/sponsor/alipay.png" width="240" alt="Support RightDisplay with Alipay"> <img src="assets/sponsor/wechat-pay.png" width="240" alt="Support RightDisplay with WeChat Pay"></p>
