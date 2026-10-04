<p align="center">
  <img src="docs/assets/right-display-app-icon.png" width="240" alt="RightDisplay 应用图标">
</p>

<h1 align="center">RightDisplay · 正确显示</h1>

<p align="center">
  看清当前状态，理解证据，安全调整；切换异常时尝试恢复。
</p>

<p align="center">
  <a href="https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc"><strong>下载 0.4 Beta RC</strong></a>
  · <a href="releases/0.4-beta-rc.md">更新说明</a>
  · <a href="README.en.md">English</a>
  · <a href="CHANGELOG.md">版本历史</a>
</p>

<p align="center">0.4 Beta RC · Apple silicon · arm64 · ad-hoc 签名</p>

## RightDisplay 是什么？

RightDisplay 是一款面向 Mac 外接显示器的状态栏工具。它把显示状态、可用控制和判断依据放到一起，让分辨率、刷新率、颜色输出和音频设置更容易查看和调整。

0.4 把完整窗口整理为六个页面：概览、显示、音频、ICC、EDID、通用。新增 ICC 描述文件检查和虚拟音频软件音量，也统一了快捷面板与各页的卡片、控件和状态提示。

<p align="center"><img src="assets/screenshots/0.4-beta/overview.png" width="960" alt="0.4 概览：连接、像素格式、色深、HDR、刷新率与 DSC 的系统报告及推断标签"></p>

本文截图由用户提供，展示 0.4 界面；未核定为本次 0.4 Beta RC 的截图。图中的 LG TV、120 Hz、12 bit 等读数只代表该截图场景，不是所有连接的承诺，也不构成接收端实测。

## 看清当前输出

概览集中展示输出时序、HiDPI 界面分辨率、刷新率、连接、像素格式、色深、HDR 与 DSC，并在卡片里保留证据来源。

系统报告、设备声明能力和推断各有含义。SLS 报告的当前颜色组合可以用来检查控制结果，但不等于显示器接收端的物理输出；独立的接收端物理状态通常无法直接获取。DSC 和部分传输信息仍是推断；缺少可靠证据时保留未知。

## 控制显示输出

在「显示」页选择分辨率、HiDPI、刷新率，以及当前连接支持的颜色格式、色深与 HDR。显示器分辨率用于模式选择，HiDPI 决定界面的缩放大小。

<p align="center"><img src="assets/screenshots/0.4-beta/display-output.png" width="960" alt="0.4 显示页：屏幕亮度、分辨率、HiDPI、刷新率和颜色输出组合"></p>

### 刷新率与 VRR

固定刷新率与可变刷新率分开呈现，保留 120 Hz／119.88 Hz、60 Hz／59.94 Hz 等不同系统时序。可用模式和 VRR 范围来自当前连接提供的数据；显示器宣称支持 VRR，不代表它当前已经启用。

### 颜色格式与色深

RGB、YCbCr 4:4:4／4:2:2／4:2:0，以及 8／10／12 bit 是否可用，取决于 Mac、显示器、线材和连接。RightDisplay 保留颜色格式、色深、范围与 HDR 的完整组合关系，操作后检查系统回读，不把一次请求直接当作生效。

### 配置保护与恢复

「配置保护」锁定完整窗口和快捷面板中的手动显示调整，同时保留亮度与音量控制。它用于减少误操作，是界面保护。

需要确认的模式切换提供倒计时，未确认时尝试恢复原设置。显示链路测试需显式确认，会切换颜色格式、色深和 HDR／SDR 组合，可能短暂黑屏或重新握手。回读与测试结果覆盖当次连接及观察窗口；恢复不保证每次成功，也不等于物理链路认证。

## 虚拟音频：给 HDMI／DP 加上软件音量

有些 HDMI／DisplayPort 音频输出在 macOS 中没有可用的音量滑条。0.4 新增虚拟音频输出，把音频转发到所选真实设备，并在软件中调节音量。

<p align="center"><img src="assets/screenshots/0.4-beta/virtual-audio.png" width="960" alt="0.4 音频页：虚拟音频软件音量、HDMI 目标与转发状态"></p>

这是 **HDMI／DP 软件音量**，不会改变电视的硬件音量。使用前需单独安装虚拟音频组件、选择真实输出目标，并将需要转发的声音送到虚拟输出；在应用中选择控制设备，不会自动更改 macOS 默认输出。

支持保存目标设备、在条件满足时自动启动，以及异常停止后的显式恢复。转发状态和原因可以在运行详情中查看。手动停止会被保留；绿色「转发已启用」表示转发已启用，不证明当前有声或长期连续播放通过。

虚拟音频需要较新的 macOS，当前组件要求 macOS 27.0 或更新版本。

已知问题：本 RC 使用 ad-hoc 签名，虚拟音频可能因签名校验导致转发无法启用。所用版本仍保留部分 App／broker／driver 之间的 Apple 签名要求，这些校验与 ad-hoc 组件不兼容；虚拟音频尚未通过本 RC 的实际转发验收。

本 RC 的 App、辅助程序与虚拟音频组件使用 ad-hoc 签名，安装包容器未签名，尚未经过 Apple 公证。其他机器的安装和实际转发仍待验收。详见[安装说明](INSTALLATION.md)。

## ICC 与 Color Profiles

独立的 ICC 页面显示 macOS 当前关联的描述文件，也可以打开外部 ICC 进行检查，查看来源、版本、色彩空间、白点、原色、RGB 矩阵与色调曲线。可用描述文件支持检查及确认后套用，以系统关联回读确认结果。

<p align="center"><img src="assets/screenshots/0.4-beta/color-profiles.png" width="800" alt="0.4 ICC 深色界面：描述文件信息、色彩特性、CIE 1931 xy 色域和 VCGT 校准曲线"></p>

色域图展示描述文件模型与参考色域的关系，不是屏幕实测。VCGT 展示文件存储的校准曲线，不证明 GPU 当前已加载同一校准 LUT。打开一个文件进行检查，也不等于安装或套用它。

## EDID 与显示器能力

EDID 页面分别整理接收端声明能力、macOS 解析能力和基础字段，可读取、解读与导出 EDID。HDR、PQ／HLG、BT.2020、刷新率与 VRR 范围都保留各自来源。

<p align="center"><img src="assets/screenshots/0.4-beta/edid.png" width="800" alt="0.4 EDID 深色界面：接收端声明能力、macOS 解析能力与基础字段"></p>

**EDID 描述的是设备声明的能力，不等于当前输出状态。** 原始 EDID 可能含序列号，分享前请检查。

## 快捷控制

状态栏快捷面板提供常用颜色输出、HDR、VRR、亮度和音量控制，与完整窗口共享显示状态与控制设备。常用项目可以在通用页管理。

<p align="center"><img src="assets/screenshots/0.4-beta/quick-control.png" width="380" alt="0.4 Quick Control：亮度、音量、颜色格式、色深、HDR 与 VRR"></p>

## 亮度、Apple TV 与 HomePod

「显示」页提供 macOS 支持的屏幕亮度控制，「音频」页管理可写系统音频音量、虚拟音频和兼容 Apple TV 的输出音量。支持的路径可使用键盘音量键。

Apple TV 控制取决于兼容设备、本地网络、必要配对和音量可写性。HomePod 音量跟随 Apple TV 当前选择或默认音频输出，不承诺直接控制所有 HomePod／AirPlay 音箱。

## 诊断与通用设置

诊断报告整合显示状态、模式、EDID、链路证据、音频状态及近期操作，由用户主动保存到本地，不会自动上传。分享前检查设备名称、标识、错误信息、路径与原始 EDID，详见[隐私说明](PRIVACY.md)。

通用页提供跟随系统／简体中文／English、登录启动、快捷控件管理、安全模式和可选自动校正。安全模式抑制启动、连接与唤醒时的显示自动校正，不应当作所有手动操作的锁定。

<p align="center"><img src="assets/screenshots/0.4-beta/general.png" width="960" alt="0.4 General 英文深色界面：语言、快捷控件、登录行为、安全模式及自动校正"></p>

## RC 与安装

0.4 Beta RC 为公开测试候选，请从[GitHub Release](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc)下载。安装包名为 `RightDisplay-0.4-Beta-RC-arm64.zip`，随附 `SHA256SUMS.txt`。

退出旧版、核对校验值，解压后将 `Right Display.app` 放入「应用程序」，先正常打开。若 macOS 阻止运行，前往 **系统设置 → 隐私与安全性 → 仍要打开**并确认；在系统提供此操作时，也可从 Finder 手动选择**打开**。

**不需要关闭 Gatekeeper 或 SIP。** 完整步骤及虚拟音频组件安装、更新与回退见[安装说明](INSTALLATION.md)。

## 系统要求与 Beta 范围

- 基础系统要求为 macOS 14+、Apple silicon arm64。虚拟音频另需 macOS 27.0 或更新版本；各项功能的可用性取决于系统和硬件。
- 功能取决于 Mac、macOS、显示器、转接器／扩展坞和线材；不保证每个颜色、色深、HDR 或 VRR 请求都生效。
- 真实 Release 运行、跨机器安装、登录／唤醒恢复与长时间音频转发仍需验收；编译及签名验证不替代这些测试。

查看[0.4 Beta RC 更新说明](releases/0.4-beta-rc.md)与[版本历史](CHANGELOG.md)。欢迎通过 [Issues](https://github.com/RedoRosetta/RightDisplay/issues) 提交可复现问题，上传附件前请先检查隐私。

本仓库提供安装包、文档和公开发行材料，不公开应用自有源码。第三方组件遵循各自许可，详见 [NOTICE](NOTICE.md) 与[第三方说明](THIRD_PARTY_LICENSES.md)。

## 支持开发

如果 RightDisplay 对你有帮助，欢迎自愿支持开发。你的使用、测试和反馈同样是在帮助 RightDisplay 变得更好。

<table align="center">
  <tr>
    <td align="center"><img src="assets/sponsor/alipay.png" width="260" alt="支付宝支持 RightDisplay"></td>
    <td align="center"><img src="assets/sponsor/wechat-pay.png" width="260" alt="微信支付支持 RightDisplay"></td>
  </tr>
</table>
