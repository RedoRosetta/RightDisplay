# RightDisplay

See the current state, understand the evidence, adjust safely, and recover when possible.

[Download 0.4 Beta RC](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc) · [中文首页](README.md) · [0.4 Beta RC notes](releases/0.4-beta-rc.md) · [Version history](CHANGELOG.md)

<p align="center"><img src="docs/assets/right-display-app-icon.png" width="240" alt="RightDisplay app icon"></p>

**0.4 Beta RC · Apple silicon arm64 · ad-hoc signed.**

RightDisplay is a menu-bar utility for external displays. Version 0.4 organizes the full window into Overview, Display, Audio, ICC, EDID and General, adds ICC inspection and Virtual Audio software volume, and refines the cards, controls and status hints shared with Quick Control.

<p align="center"><img src="assets/screenshots/0.4-beta/overview.png" width="960" alt="Overview: connection, pixel format, depth, HDR, refresh rate and DSC with evidence labels"></p>

Screenshots are user-supplied 0.4 interface captures, not verified captures of this 0.4 Beta RC. The LG TV, 120 Hz and 12-bit values show that capture's setup; they are not receiver-side measurements or promises for every connection.

## Understand your display

Overview brings output timing, HiDPI resolution, refresh rate, connection, pixel format, depth, HDR and DSC into one page, with evidence sources on the cards. System reports, advertised capabilities and inference stay distinct. SLS-reported current color state supports control readback; it is not physical truth at the receiver. Independent receiver-side physical state is generally unavailable. DSC and some transport information remain inferred. Missing evidence stays unknown.

## Display & Output

Choose supported resolution, HiDPI, refresh rate, color format, depth and HDR. Display resolution selects a mode; HiDPI sets interface scaling.

<p align="center"><img src="assets/screenshots/0.4-beta/display-output.png" width="960" alt="Display: brightness, resolution, HiDPI, refresh rate and color output"></p>

Fixed refresh rates and VRR are separate, retaining differences such as 120/119.88 Hz and 60/59.94 Hz. Modes and VRR ranges come from the current connection; advertised VRR support does not mean it is enabled.

RGB, YCbCr 4:4:4/4:2:2/4:2:0 and 8/10/12-bit availability depends on the Mac, display, cable and connection. Controls preserve the complete format/depth/range/HDR combination and check system readback after supported changes.

Configuration Protection locks manual display controls in the full window and Quick Control while keeping brightness and volume available. Mode changes requiring confirmation offer a countdown and attempt recovery if unconfirmed. Display Link Test requires explicit confirmation and checks color/depth/HDR/SDR combinations. Switching/testing can blank the screen. Recovery is attempted, not guaranteed; a successful test covers that connection and observation period, not universal physical-link certification.

## Virtual Audio software volume

Some HDMI/DisplayPort outputs have no writable volume control in macOS. Virtual Audio forwards audio to a selected real device and adjusts volume in software.

<p align="center"><img src="assets/screenshots/0.4-beta/virtual-audio.png" width="960" alt="Audio: Virtual Audio software volume, real HDMI target and forwarding status"></p>

This is **software volume for HDMI/DP**, not TV hardware volume. Install the optional component, choose a real target and send the desired audio to the virtual output. Selecting its volume control in RightDisplay does not automatically change macOS's default output.

Saved targets, conditional auto-start and explicit recovery after abnormal stops are supported. A manual stop is retained. Runtime details show status/reasons; green forwarding status does not prove audible or uninterrupted playback.

Virtual Audio needs a newer macOS; the current component requires macOS 27.0 or later.

Known issue: ad-hoc signing may prevent Virtual Audio forwarding from starting. This version retains some Apple-signature requirements between the App, broker and driver; those checks are incompatible with ad-hoc components. Real forwarding has not been accepted for this RC.

This RC supplies ad-hoc-signed App/helper/Virtual Audio code, unsigned package containers and no Apple notarization. Cross-machine install and real forwarding still need acceptance. See [installation](INSTALLATION.md).

## ICC / Color Profiles

Inspect the profile currently associated by macOS, open external ICC files, view metadata, white point, primaries, RGB matrix and tone curves, and inspect or apply available profiles with confirmation/system-association readback.

<p align="center"><img src="assets/screenshots/0.4-beta/color-profiles.png" width="800" alt="ICC dark interface: metadata, color characteristics, CIE 1931 xy gamut and VCGT calibration curves"></p>

Gamut plots describe the profile model and reference gamut, not display measurements. VCGT curves describe stored calibration data, not a proven currently loaded GPU LUT. Opening a profile for inspection does not install or apply it.

## EDID & capabilities

The EDID page separates receiver-advertised capabilities, macOS-parsed capabilities and basic fields, with inspection and export. HDR, PQ/HLG, BT.2020 and refresh/VRR ranges retain their sources.

<p align="center"><img src="assets/screenshots/0.4-beta/edid.png" width="800" alt="EDID dark interface: receiver-advertised capabilities, macOS interpretation and basic fields"></p>

**EDID advertises capabilities; it is not current output.** Raw EDID can contain serial numbers. Review exports before sharing.

## Quick Control

Use frequent color-output, HDR, VRR, brightness and volume controls from the menu bar. Quick Control and the full window share state and the selected volume-control device; configure visible controls in General.

<p align="center"><img src="assets/screenshots/0.4-beta/quick-control.png" width="380" alt="Quick Control: brightness, volume, color format, depth, HDR and VRR"></p>

## Brightness, Apple TV & HomePod

Display includes brightness control where macOS supports it. Audio includes writable system-output volume, Virtual Audio and compatible Apple TV output volume, with keyboard volume keys on supported paths. Apple TV requires compatible hardware, network access and pairing where needed. HomePod volume follows Apple TV's selected/default audio output; direct control of every HomePod/AirPlay speaker is not promised.

## Diagnostics & General

Save reports locally on request with display state, modes, EDID, evidence, audio state and recent operations. Reports are not automatically uploaded. Review names, identifiers, paths, errors and raw EDID before sharing. See [privacy](PRIVACY.md).

General includes Follow System/Simplified Chinese/English, login behavior, Quick Control management, Safe Mode and optional display correction. Safe Mode suppresses automatic display correction at launch, connection and wake; it is not a lock on all manual operations.

<p align="center"><img src="assets/screenshots/0.4-beta/general.png" width="960" alt="General English dark interface: language, Quick Control, login, Safe Mode and automatic correction"></p>

## RC & installation

This is a public test candidate. Download it from the [GitHub Release](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc). Assets are `RightDisplay-0.4-Beta-RC-arm64.zip` and `SHA256SUMS.txt`.

Verify the matching digest, quit the old copy, extract and clean-copy `Right Display.app` to Applications. Try opening normally. If blocked, use **System Settings → Privacy & Security → Open Anyway**, or Finder **Open** where offered. Do not disable Gatekeeper or SIP. See [installation](INSTALLATION.md) for optional component update/removal and rollback.

Base requirements are macOS 14+ and Apple silicon arm64. Virtual Audio separately requires macOS 27.0 or later; feature availability depends on the system and hardware. Hardware/network controls, Release runtime, login/wake recovery, other-Mac installation and long playback remain acceptance items. Build/signature checks do not replace them.

Read the [RC notes](releases/0.4-beta-rc.md) and [history](CHANGELOG.md). Use [Issues](https://github.com/RedoRosetta/RightDisplay/issues) for reproducible feedback after reviewing attachments. This repository contains distribution materials, not proprietary source; see [NOTICE](NOTICE.md) and [third-party information](THIRD_PARTY_LICENSES.md).

## Support development

If RightDisplay helps you, you're welcome to support its development. Thank you for using it and sharing feedback.

<table align="center"><tr>
<td align="center"><img src="assets/sponsor/alipay.png" width="260" alt="Support RightDisplay with Alipay"></td>
<td align="center"><img src="assets/sponsor/wechat-pay.png" width="260" alt="Support RightDisplay with WeChat Pay"></td>
</tr></table>
