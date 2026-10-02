<p align="center">
  <img src="docs/assets/right-display-app-icon.png" width="240" alt="RightDisplay app icon">
</p>

<h1 align="center">RightDisplay</h1>

<p align="center">
  See what your Mac is really sending to your external display.<br>
  Understand the state, adjust the output, and verify the connection.
</p>

<p align="center">
  <a href="https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.3-beta"><strong>Download 0.3 Beta</strong></a>
  · <a href="README.md">中文</a>
  · <a href="CHANGELOG.md">Changelog</a>
</p>

<p align="center">macOS 14+ · Apple silicon · arm64</p>

## What is RightDisplay?

RightDisplay is a menu-bar utility for external displays on macOS.

It brings together display information that macOS often scatters, hides, or makes difficult to verify, giving you a clearer view of — and more control over:

- Resolution and HiDPI
- Fixed and variable refresh rates
- RGB / YCbCr pixel encoding
- 8 / 10 / 12-bit color depth
- HDR
- DSC
- EDID and display capabilities
- Brightness and audio output

Whether you use a regular desktop monitor, a high-refresh-rate display, or a 4K TV over HDMI, RightDisplay is built around one simple question:

**What is my Mac actually outputting right now?**

<p align="center">
  <img src="assets/screenshots/overview.png" width="960" alt="RightDisplay Overview">
</p>

## Understand the current output

Overview brings the most important display information together:

**Output timing · HiDPI · Refresh rate · Connection · Pixel encoding · Color depth · HDR · VRR · DSC**

RightDisplay also tries to keep different kinds of information separate:

- What macOS currently reports
- What the display advertises as supported
- What can only be inferred from the available link information

When reliable evidence is unavailable, RightDisplay avoids presenting an assumption as a confirmed result.

## Control the display output

Display & Output provides one place to manage the major output settings available for the current display:

- Resolution
- HiDPI resolution
- Refresh rate
- VRR
- RGB / YCbCr
- Color depth
- HDR

RightDisplay works with modes and connection combinations actually exposed by macOS instead of inventing output states that may not exist.

<p align="center">
  <img src="assets/screenshots/display-output.png" width="960" alt="RightDisplay Display & Output settings">
</p>

For changes that may renegotiate the display link or temporarily blank the screen, RightDisplay checks the resulting system readback. Mode changes that require confirmation use a countdown and can attempt to restore the previous setting if left unconfirmed.

## Refresh rate & VRR

RightDisplay distinguishes fixed refresh rates from variable-refresh-rate modes while preserving different timing identities.

Depending on the display and connection, available modes may include:

`120 Hz` · `119.88 Hz` · `60 Hz` · `59.94 Hz` · `40–120 Hz VRR`

VRR ranges are read from the system when available rather than being hard-coded for a particular display.

Available modes depend on the display, resolution, HDR state, connection, and what macOS exposes for the current configuration.

## Pixel encoding & color depth

RightDisplay can show and adjust connection combinations exposed by macOS, such as:

`RGB · 12-bit · Full · HDR10`

`RGB · 10-bit · Full · HDR10`

`YCbCr 4:4:4 · 10-bit · Limited · HDR10`

The available combinations depend on the current display link.

RightDisplay keeps pixel encoding, color depth, range, and HDR state together when evaluating a connection, helping avoid silently accepting changes to other output properties when adjusting a single setting.

## Display Link Test

Not sure which combinations your Mac, cable, adapter, and display can actually sustain?

Display Link Test can check combinations of:

**Pixel encoding × Color depth × HDR / SDR**

against the current connection and its system readback.

It can help investigate questions such as:

- Why is the display using YCbCr instead of RGB?
- Why is 10-bit or 12-bit unavailable?
- Why does the pixel encoding change when HDR is enabled?
- Which output combinations are available at a particular refresh rate?

The test actively changes display output and may cause temporary blanking or link renegotiation while running.

## EDID & display capabilities

RightDisplay can read and interpret EDID together with display capabilities recognized by macOS, including information such as:

- Manufacturer, model, and basic display information
- Native resolution
- HDR / PQ / HLG support
- BT.2020 support
- VRR and refresh-rate ranges
- Chromaticity information
- Other recognized display capabilities

**EDID describes what a display advertises as supported. It does not describe the current output state.**

RightDisplay keeps that distinction visible wherever possible.

## Quick Control

Common controls do not require opening the full settings window.

Quick Control in the menu bar provides fast access to display settings, HDR, color output, brightness, and volume.

<p align="center">
  <img src="assets/screenshots/quick-control.png" width="380" alt="RightDisplay Quick Control">
</p>

Quick Control and the main settings window share the same display state.

## Brightness & Sound

RightDisplay also brings display-related brightness and audio controls together:

- Supported display brightness
- Writable macOS audio-device volume
- Compatible Apple TV audio-output volume
- Optional keyboard volume-key control

<p align="center">
  <img src="assets/screenshots/brightness-sound.png" width="960" alt="RightDisplay Brightness & Sound">
</p>

Some Apple TV / HomePod configurations require Local Network access and initial pairing.

## Diagnostics & export

When something goes wrong, RightDisplay can export a diagnostic report containing the current display state, mode information, EDID, and related connection evidence.

Diagnostic reports are saved locally only when you explicitly export them. They are not uploaded automatically.

Before sharing a report, review it for information such as:

- Display names
- EDID data
- Device identifiers
- Network-device information

See [Privacy](PRIVACY.md) for details.

## Download & installation

Download the following from [Releases](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.3-beta):

- `RightDisplay-0.3-Beta.zip`
- `SHA256SUMS.txt`

Verify the SHA-256 checksum, extract the archive, and move `Right Display.app` to Applications.

### First launch

The current Beta uses **ad-hoc code signing and is not Apple notarized**.

If macOS blocks the first launch, go to:

**System Settings → Privacy & Security → Open Anyway**

You can also use Finder's manual **Open** option where available.

**You do not need to disable Gatekeeper or SIP.**

See the full [Installation Guide](INSTALLATION.md) for details.

## Requirements

- macOS 14 or later
- Apple silicon
- arm64

Available information and controls depend on the Mac, macOS version, display, connection type, adapter or dock, and cable.

Some low-level display information comes from macOS system interfaces and should not be treated as a physical measurement at the display receiver. RightDisplay keeps those limitations visible instead of hiding the distinction.

## Beta & feedback

RightDisplay is currently in Beta.

If you encounter incorrect state detection, failed mode changes, unexpected blanking, or HDR, VRR, pixel-encoding, or color-depth results that do not match what you observe, reproducible reports are welcome through [Issues](https://github.com/RedoRosetta/RightDisplay/issues).

See the [0.3 Release Notes](releases/0.3-beta.md) · [Changelog](CHANGELOG.md)

This repository contains RightDisplay releases, documentation, and other public distribution materials. Proprietary application source code is not published here.

Third-party components remain subject to their respective licenses. See [NOTICE](NOTICE.md) and [Third-party information](THIRD_PARTY_LICENSES.md).

## Support development

If RightDisplay is useful to you, you are welcome to support its continued development.

Using it, testing it, and sharing useful feedback all help make RightDisplay better.

<table align="center">
  <tr>
    <td align="center"><img src="assets/sponsor/alipay.png" width="260" alt="Support RightDisplay with Alipay"></td>
    <td align="center"><img src="assets/sponsor/wechat-pay.png" width="260" alt="Support RightDisplay with WeChat Pay"></td>
  </tr>
</table>
