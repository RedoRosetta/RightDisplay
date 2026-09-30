<p align="center">
  <img src="docs/assets/right-display-app-icon.png" width="240" alt="RightDisplay 应用图标">
</p>

<h1 align="center">RightDisplay · 正确显示</h1>

<p align="center">
  看清 Mac 的显示链路，理解状态，验证并安全调整。<br>
  See, understand, verify, and safely adjust your Mac’s display connection.
</p>

<p align="center">
  <a href="https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.3-beta"><strong>下载 0.3 Beta · Download</strong></a>
  · <a href="README.en.md">English</a>
  · <a href="CHANGELOG.md">版本历史 · Changelog</a>
</p>

<p align="center">macOS 14+ · Apple 芯片 / Apple silicon · Build 60</p>

## 看清当前输出 · Understand your display

RightDisplay 是面向外接显示器的 Mac 状态栏工具：把显示状态、可用控制与判断依据放在一起，不把设备声明的能力当作当前输出。

概览集中展示输出时序、HiDPI 界面分辨率、刷新率、连接、颜色格式、色深，以及 HDR、VRR 和 DSC 的证据。

A menu-bar utility for external displays, bringing current status, supported controls and their evidence into one place.

<p align="center"><img src="assets/screenshots/overview.png" width="960" alt="RightDisplay 概览：显示状态与证据标签"></p>

以上及下方图片为用户提供的 0.3 界面开发预览；可见的内部版本标识不代表独立公开发行，不是最终发行构建的截图。

Screenshots are development previews, not captures of the final release build.

## 常用控制，随手可及 · Quick Control

在状态栏快捷面板调整常用显示设置、亮度与设备音量，与高级设置共享同一份显示状态。无需为了每次小调整打开完整窗口。

Frequently used settings, brightness and device volume, right from the menu bar.

<p align="center"><img src="assets/screenshots/quick-control.png" width="380" alt="状态栏快捷面板：亮度、音量、颜色格式、色深、HDR 与 VRR"></p>

## 显示与输出 · Display & Output

集中选择显示器分辨率、HiDPI 界面分辨率、刷新率和受支持的颜色设置。需要确认的模式切换提供倒计时，并在未确认时尝试恢复原设置；支持的调整在操作后检查回读。

“配置保护”可锁定高级设置与快捷面板中的手动显示调整，同时保留亮度和音量控制。它是界面保护，不是系统级安全隔离。

Supported display settings with confirmation and readback checks. Configuration Protection locks manual display adjustments without locking brightness or volume.

<p align="center"><img src="assets/screenshots/display-output.png" width="960" alt="显示与输出：分辨率、HiDPI、刷新率、配置保护、颜色格式与色深"></p>

显示链路测试用于检查当前连接的稳定颜色格式、色深与 HDR／SDR 组合，开始前需确认。切换与测试可能短暂黑屏；恢复是尝试，不是保证。

Display Link Test checks combinations on the current connection. Testing may interrupt the display; recovery is attempted, not guaranteed.

## 亮度与声音 · Brightness & Sound

同一页面管理受支持的显示器亮度、可写系统音频音量和兼容 Apple TV 的音频输出音量。支持的路径可启用键盘音量键控制。

HomePod 音量跟随 Apple TV 当前选择／默认音频输出，不承诺直接控制所有 HomePod 或 AirPlay 音箱。

Supported brightness and audio-output volume together, including compatible Apple TV output control and optional keyboard volume keys.

<p align="center"><img src="assets/screenshots/brightness-sound.png" width="960" alt="亮度与声音：显示器亮度、音频设备选择及兼容 Apple TV 输出音量"></p>

## 证据与诊断 · Evidence & diagnostics

- **当前回读／已验证、推断、设备声明能力**分开呈现；缺少证据时保留未知。
- EDID 可解读与导出，但它声明的是能力，不等于当前输出。
- DSC 及部分时序／传输信息为推断，不是接收端实测。
- 诊断报告由用户主动保存到本地，不会自动提交 GitHub；分享前检查设备名称、错误信息与原始 EDID。

Current readings, inference and advertised capabilities stay distinct. Reports are saved locally on request; review every attachment before sharing. See [隐私说明 / Privacy](PRIVACY.md).

## 下载与安装 · Installation

1. 从[官方发行页](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.3-beta)下载 `RightDisplay-0.3-Beta.zip` 和 `SHA256SUMS.txt`，核对 SHA-256。
2. 退出旧版，解压并将 `Right Display.app` 放入“应用程序”，正常尝试打开。
3. 本 Beta 使用 **ad-hoc 签名，尚未经过 Apple 公证**。若 macOS 阻止首次运行，前往**系统设置 → 隐私与安全性 → 仍要打开**并确认；也可在系统提供此操作时从 Finder 手动选择**打开**。

Download the ZIP and matching checksum from the official release, verify, extract and move the App to Applications. This Beta is ad-hoc signed, **not Apple notarized**; if blocked, use **System Settings → Privacy & Security → Open Anyway**, or Finder’s manual **Open** where available.

不需要关闭 Gatekeeper 或 SIP。完整步骤见[安装说明 / Installation guide](INSTALLATION.md)。

## 使用范围与限制 · Requirements & limitations

- macOS 14 或更新版本；当前发行架构为 Apple silicon arm64，不提供 Intel 包。
- 功能取决于 Mac、系统、显示器、转接器／扩展坞、线材和连接；不能保证每个颜色／色深／HDR 请求都生效。
- Apple TV 控制取决于兼容设备、网络、必要配对与音量可写性。仅在相关功能需要时授予本地网络或辅助功能权限。
- 测试通过只覆盖当次连接与观察窗口；Beta 兼容性不代表所有设备均获认证。
- 提供跟随系统、简体中文、English 界面语言，浅色／深色外观及首次使用引导。

Requires macOS 14+ and Apple silicon. Controls, recovery, reconnection and volume availability vary with hardware and network; test success is not universal certification.

## 反馈与版本 · Feedback & releases

查看 [0.3 更新说明 / Release notes](releases/0.3-beta.md)与[公开版本历史 / Changelog](CHANGELOG.md)。欢迎通过 [Issues](https://github.com/RedoRosetta/RightDisplay/issues) 提交可复现问题，上传附件前请先检查隐私。

本仓库仅提供发行材料，不公开自有应用源码。第三方遵循各自许可，参见 [发行范围 / Notice](NOTICE.md) 与[第三方说明 / Third-party information](THIRD_PARTY_LICENSES.md)。

## 支持开发 · Support development

如果 RightDisplay 对你有帮助，欢迎自愿支持开发。谢谢你的使用、反馈与支持。

If RightDisplay helps you, you’re welcome to support its development. Thank you.

<table align="center">
  <tr>
    <td align="center"><img src="assets/sponsor/alipay.png" width="260" alt="支付宝赞助 RightDisplay"></td>
    <td align="center"><img src="assets/sponsor/wechat-pay.png" width="260" alt="微信支付赞助 RightDisplay"></td>
  </tr>
</table>

图片已移除外侧名称，保留原始收款二维码与头像；支付平台仍可能在付款前显示收款方信息。

Outer names have been removed; the original QR payloads are preserved. Payment services may still show recipient details.
