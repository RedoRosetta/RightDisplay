<p align="center">
  <img src="docs/assets/right-display-app-icon.png" width="240" alt="RightDisplay 应用图标">
</p>

<h1 align="center">RightDisplay · 正确显示</h1>

<p align="center">
  看清 Mac 外接显示器真正发生了什么。<br>
  查看状态、调整输出、验证显示链路。
</p>

<p align="center">
  <a href="https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.3-beta"><strong>下载 0.3 Beta</strong></a>
  · <a href="README.en.md">English</a>
  · <a href="CHANGELOG.md">版本历史</a>
</p>

<p align="center">macOS 14+ · Apple silicon · arm64</p>

## RightDisplay 是什么？

RightDisplay 是一款面向 Mac 外接显示器的状态栏工具。

它把 macOS 中分散、隐藏或难以确认的显示信息集中起来，让你更直观地查看和调整：

- 分辨率与 HiDPI
- 固定刷新率与 VRR
- RGB / YCbCr 颜色格式
- 8 / 10 / 12-bit 色深
- HDR
- DSC
- 显示器 EDID 与能力
- 亮度与音频输出

无论是普通显示器、高刷电竞屏，还是通过 HDMI 连接的 4K 电视，RightDisplay 都希望回答一个最简单的问题：

**我的 Mac 现在到底在输出什么？**

<p align="center">
  <img src="assets/screenshots/overview.png" width="960" alt="RightDisplay 概览">
</p>

## 看清当前输出

概览集中展示当前显示器最重要的状态：

**输出时序 · HiDPI · 刷新率 · 连接 · 颜色格式 · 色深 · HDR · VRR · DSC**

RightDisplay 不只展示显示器“支持什么”，也尽可能区分：

- macOS 当前报告的状态
- 显示器声明的能力
- 根据链路信息得到的推断

缺少可靠证据时，不会把推测包装成确定结果。

## 控制显示输出

在「显示与输出」中，可以统一管理当前显示器的主要输出设置：

- 分辨率
- HiDPI 界面分辨率
- 刷新率
- VRR
- RGB / YCbCr
- 色深
- HDR

RightDisplay 基于 macOS 实际提供的模式和连接组合进行控制，不凭空生成显示器不存在的输出状态。

<p align="center">
  <img src="assets/screenshots/display-output.png" width="960" alt="RightDisplay 显示与输出">
</p>

对于可能引起重新握手或短暂黑屏的调整，RightDisplay 会检查操作后的系统回读；需要确认的模式切换提供倒计时，并在未确认时尝试恢复原设置。

## 刷新率与 VRR

RightDisplay 可以区分固定刷新率与可变刷新率模式，并保留不同显示时序之间的差异。

根据显示器和当前连接，可能包括：

`120 Hz` · `119.88 Hz` · `60 Hz` · `59.94 Hz` · `40–120 Hz VRR`

VRR 范围优先读取当前系统实际提供的数据，不写死特定显示器的刷新率范围。

具体可用模式取决于显示器、分辨率、HDR 状态以及连接方式。

## 颜色格式与色深

查看并调整 macOS 当前连接实际提供的颜色输出组合，例如：

`RGB · 12-bit · Full · HDR10`

`RGB · 10-bit · Full · HDR10`

`YCbCr 4:4:4 · 10-bit · Limited · HDR10`

可用组合由当前显示链路决定。

RightDisplay 会保留颜色格式、色深、范围和 HDR 状态之间的完整组合关系，避免在调整单个项目时静默改变其他输出属性。

## 显示链路测试

不知道自己的 Mac、线材和显示器到底能稳定跑哪些组合？

「显示链路测试」可以检查当前连接下不同：

**颜色格式 × 色深 × HDR / SDR**

组合的实际系统回读结果。

它适合排查：

- 为什么只能使用 YCbCr
- 为什么无法进入 10-bit / 12-bit
- HDR 开启后为什么颜色格式发生变化
- 某个刷新率下哪些输出组合可用

测试会主动改变显示输出，过程中可能发生短暂黑屏或重新握手。

## EDID 与显示器能力

RightDisplay 可以读取和解读显示器 EDID，并结合 macOS 已解析的信息整理显示能力，例如：

- 厂商、型号与基础信息
- 原生分辨率
- HDR / PQ / HLG
- BT.2020
- VRR 与刷新率范围
- 色度坐标
- 其他可识别的显示能力

**EDID 描述的是显示器声明的能力，不等于当前正在使用的输出状态。**

RightDisplay 会尽量保持两者的区别。

## 快捷控制

常用功能不必每次打开完整设置窗口。

状态栏快捷面板可以快速访问显示设置、HDR、颜色输出、亮度和音量。

<p align="center">
  <img src="assets/screenshots/quick-control.png" width="380" alt="RightDisplay 快捷控制">
</p>

快捷面板与高级设置共享同一份显示状态。

## 亮度与声音

RightDisplay 也把与显示器相关的亮度和声音控制集中到了一起：

- 支持的显示器亮度
- macOS 可写音频设备音量
- 兼容 Apple TV 的音频输出音量
- 键盘音量键控制

<p align="center">
  <img src="assets/screenshots/brightness-sound.png" width="960" alt="RightDisplay 亮度与声音">
</p>

部分 Apple TV / HomePod 场景需要本地网络访问及首次配对。

## 诊断与导出

遇到显示异常时，可以导出诊断报告，用于记录当前显示状态、模式信息、EDID 和相关链路证据。

诊断报告只会在你主动操作时保存到本地，不会自动上传。

分享报告前，请检查其中可能包含的设备名称、EDID、设备标识或网络设备信息。

详见 [隐私说明](PRIVACY.md)。

## 下载与安装

从 [Releases](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.3-beta) 下载：

- `RightDisplay-0.3-Beta.zip`
- `SHA256SUMS.txt`

核对 SHA-256 后，解压并将 `Right Display.app` 放入「应用程序」。

### 首次打开

当前 Beta 使用 **ad-hoc 签名，尚未经过 Apple 公证**。

如果 macOS 阻止首次运行，请前往：

**系统设置 → 隐私与安全性 → 仍要打开**

也可以在系统提供该选项时，从 Finder 手动选择 **打开**。

**不需要关闭 Gatekeeper，也不需要关闭 SIP。**

完整步骤见 [安装说明](INSTALLATION.md)。

## 系统要求

- macOS 14 或更新版本
- Apple silicon
- arm64

RightDisplay 能够提供的状态和控制取决于 Mac、macOS、显示器、连接方式、转接器／扩展坞和线材。

部分底层信息来自 macOS 系统接口，并不等同于显示器接收端的物理测量。RightDisplay 会尽量标明信息来源和确定程度，而不是隐藏这种差异。

## Beta 与反馈

RightDisplay 目前处于 Beta 阶段。

如果遇到状态识别错误、模式无法切换、异常黑屏，或者 HDR、VRR、颜色格式、色深与实际情况不符，欢迎通过 [Issues](https://github.com/RedoRosetta/RightDisplay/issues) 提交可复现问题。

查看 [0.3 更新说明](releases/0.3-beta.md) · [版本历史](CHANGELOG.md)

本仓库用于提供 RightDisplay 安装包、文档和公开发行材料，不公开应用自有源码。第三方组件遵循各自许可，详见 [NOTICE](NOTICE.md) 与 [第三方说明](THIRD_PARTY_LICENSES.md)。

## 支持开发

如果 RightDisplay 对你有帮助，欢迎自愿支持开发。

你的使用、测试和反馈同样是在帮助 RightDisplay 变得更好。

<table align="center">
  <tr>
    <td align="center"><img src="assets/sponsor/alipay.png" width="260" alt="支付宝支持 RightDisplay"></td>
    <td align="center"><img src="assets/sponsor/wechat-pay.png" width="260" alt="微信支付支持 RightDisplay"></td>
  </tr>
</table>
