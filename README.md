<p align="center">
  <img src="docs/assets/right-display-app-icon.png" width="240" alt="RightDisplay 应用图标">
</p>

<h1 align="center">RightDisplay · 正确显示</h1>

<p align="center">
  看清 Mac 外接显示器真正发生了什么。<br>
  Understand, control, and troubleshoot your external display on macOS.
</p>

<p align="center">
  <a href="https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.3-beta"><strong>下载 0.3 Beta · Download</strong></a>
  · <a href="README.en.md">English</a>
  · <a href="CHANGELOG.md">版本历史 · Changelog</a>
</p>

<p align="center">macOS 14+ · Apple silicon · arm64</p>

## RightDisplay 是什么？

RightDisplay 是一款面向 Mac 外接显示器的状态栏工具。

它把 macOS 原本分散、隐藏甚至难以判断的显示信息整理到一起，让你更容易确认当前分辨率、刷新率、HDR、颜色格式、色深、VRR、DSC 等状态，并在系统允许时直接进行调整。

它适合这些场景：

- 使用 4K / 5K / 高刷新率显示器或电视
- 需要确认 RGB / YCbCr、8 / 10 / 12-bit、HDR 等输出状态
- 需要切换 HiDPI、刷新率、VRR 或颜色输出模式
- 遇到黑屏、降色深、HDR 异常、刷新率不对等问题
- 想查看显示器 EDID 和实际可用能力
- 想快速调整亮度、音量或兼容 Apple TV 的音频输出

<p align="center">
  <img src="assets/screenshots/overview.png" width="960" alt="RightDisplay 概览">
</p>

## 一眼看懂当前显示状态

概览页集中显示当前显示器最重要的信息：

- 输出分辨率与 HiDPI 界面分辨率
- 当前刷新率与 VRR 状态
- 连接类型
- RGB / YCbCr 颜色格式
- 输出色深
- HDR 状态
- DSC 状态

RightDisplay 会尽量区分“系统当前报告的状态”“显示器声明的能力”和“根据链路推断得到的信息”，避免把能力误认为当前输出。

## 调整分辨率、刷新率和颜色输出

在「显示与输出」中，可以统一管理：

- 分辨率
- HiDPI 界面分辨率
- Fixed / VRR 刷新率模式
- RGB / YCbCr 输出
- 8 / 10 / 12-bit 色深
- HDR

RightDisplay 会基于 macOS 实际枚举出的模式进行选择，不凭空生成显示器并不存在的组合。

<p align="center">
  <img src="assets/screenshots/display-output.png" width="960" alt="RightDisplay 显示与输出">
</p>

对于可能导致黑屏或链路重新协商的调整，RightDisplay 会进行回读检查，并在必要时尝试恢复原设置。

## 快捷控制

不想每次都打开完整设置窗口？

RightDisplay 的状态栏面板可以快速调整常用选项：

- 显示模式
- HDR
- 颜色输出
- 亮度
- 音量

<p align="center">
  <img src="assets/screenshots/quick-control.png" width="380" alt="RightDisplay 快捷控制">
</p>

高级设置与快捷控制共享同一份显示状态，不需要重复配置。

## 刷新率与 VRR

RightDisplay 可以识别 macOS 实际提供的固定刷新率和可变刷新率模式。

例如：

- 120 Hz
- 119.88 Hz
- 60 Hz
- 59.94 Hz
- 40–120 Hz VRR

具体可用模式取决于 Mac、显示器、分辨率、HDR 状态以及连接方式。

VRR 范围不会写死，而是优先读取当前系统为该模式提供的实际范围。

## 显示链路测试

「显示链路测试」可以帮助检查当前连接下哪些颜色格式、色深和 HDR / SDR 组合能够稳定使用。

适合用于排查：

- 为什么只能输出 YCbCr
- 为什么无法进入 10-bit / 12-bit
- HDR 开启后为什么颜色格式发生变化
- 某个刷新率下哪些组合可用

测试过程中显示器可能短暂黑屏或重新握手，因此建议在不影响工作的情况下使用。

## EDID 与显示器能力

RightDisplay 可以读取并解析显示器的 EDID 和 macOS 已识别的显示能力，包括：

- 厂商与型号
- 原生分辨率
- HDR / PQ / HLG 支持
- BT.2020
- VRR
- 刷新率范围
- 色度坐标
- 其他可用显示能力

EDID 描述的是显示器“能够做什么”，不代表当前链路一定正在使用这些能力。

## 亮度与声音

在「亮度与声音」中，可以集中管理：

- 支持的显示器亮度
- macOS 可写音频设备音量
- 兼容 Apple TV 的音频输出音量
- 键盘音量键控制

<p align="center">
  <img src="assets/screenshots/brightness-sound.png" width="960" alt="RightDisplay 亮度与声音">
</p>

部分 Apple TV / HomePod 场景需要本地网络访问和首次配对。

## 诊断与导出

遇到显示问题时，可以生成诊断报告，包含当前显示状态、EDID、模式信息和相关链路数据。

诊断文件只会在你主动导出时保存到本地，不会自动上传。

分享诊断前，建议检查其中是否包含：

- 显示器名称
- EDID
- 设备标识
- 网络设备信息

详细说明见 [隐私说明 / Privacy](PRIVACY.md)。

## 下载与安装

1. 从 [Releases](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.3-beta) 下载 `RightDisplay-0.3-Beta.zip`
2. 解压后将 `Right Display.app` 放入“应用程序”
3. 正常尝试打开

当前 Beta 使用 **ad-hoc 签名，尚未经过 Apple 公证**。

如果 macOS 阻止首次运行，可以前往：

**系统设置 → 隐私与安全性 → 仍要打开**

或在 Finder 中右键 App，选择 **打开**。

不需要关闭 Gatekeeper，也不需要关闭 SIP。

完整步骤见 [安装说明 / Installation guide](INSTALLATION.md)。

## 系统要求

- macOS 14 或更新版本
- Apple silicon
- arm64

实际可用功能取决于：

- Mac 型号
- macOS 版本
- 显示器
- HDMI / DisplayPort 连接方式
- 转接器或扩展坞
- 线材
- 当前分辨率与刷新率

部分显示状态来自 macOS 系统接口，无法等同于显示器接收端的物理测量结果。RightDisplay 会尽量保留这一差异，而不是把不确定信息显示成确定结论。

## Beta 状态

RightDisplay 目前仍处于 Beta 阶段。

如果遇到：

- 模式无法切换
- 状态识别错误
- 显示器异常黑屏
- HDR / VRR / 色深结果与实际不符
- 特定硬件兼容问题

欢迎通过 [Issues](https://github.com/RedoRosetta/RightDisplay/issues) 提交可复现问题。

查看：
[0.3 Release Notes](releases/0.3-beta.md)
· [Changelog](CHANGELOG.md)

本仓库仅用于发布 RightDisplay 安装包、文档和发行材料，不公开应用源码。

## 支持开发

如果 RightDisplay 对你有帮助，欢迎自愿支持开发。

感谢你的使用、反馈和测试。

<table align="center">
  <tr>
    <td align="center"><img src="assets/sponsor/alipay.png" width="260" alt="支付宝赞助 RightDisplay"></td>
    <td align="center"><img src="assets/sponsor/wechat-pay.png" width="260" alt="微信支付赞助 RightDisplay"></td>
  </tr>
</table>
