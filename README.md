<p align="center"><img src="right-display-app-icon.png" width="88" alt="Right Display 应用图标"></p>

<h1 align="center">Right Display · 正确显示</h1>

<p align="center"><strong>Mac 外接显示器的状态查看与快捷控制工具。</strong><br>看清分辨率、刷新率、HDR 与颜色输出，把常用设置放进菜单栏。</p>

<p align="center"><a href="https://github.com/RedoRosetta/RightDisplay/releases/download/v0.4-beta-rc/RightDisplay-0.4-Beta-RC-arm64.zip"><strong>下载 0.4 Beta RC</strong></a> · <a href="INSTALLATION.md">安装指南</a> · <a href="releases/0.4-beta-rc.md">更新说明</a> · <a href="https://github.com/RedoRosetta/RightDisplay/issues/new/choose">反馈</a> · <a href="README.en.md">English</a></p>

<p align="center">macOS 14+ · Apple 芯片 Mac（不支持 Intel）· 公开测试候选版</p>

> **下载前请了解：** 本 RC 尚未经过 Apple 公证，首次打开可能需要系统确认。**Virtual Audio 软件音量存在已知分发问题，可能无法启用，且要求 macOS 27+；如果你主要需要 HDMI / DP 软件音量，建议等待后续修复。** [查看已知问题与安装步骤](INSTALLATION.md)

<p align="center"><img src="assets/screenshots/0.4-beta/overview.png" width="960" alt="概览：在同一页查看分辨率、刷新率、HDR、颜色格式与信息来源"></p>

*0.4 界面预览。截图中的设备、120 Hz 和 12-bit 是拍摄时的配置，不代表所有连接的可用能力，也不是当前 RC 的运行验证。界面支持简体中文与 English。*

## 看清状态，再决定怎么调

当你想知道“为什么选不到 120 Hz”“现在是否开启 HDR”“显示器支持的模式为什么没有生效”，Right Display 把相关信息集中到一起：

- **看状态：** 分辨率、HiDPI、刷新率、HDR、RGB / YCbCr、色深与输出范围。
- **做调整：** 切换当前连接提供的模式，在菜单栏使用常用显示、亮度与音量控制。
- **查原因：** 查看 EDID 能力、ICC 色彩描述文件，并按需导出本地诊断报告。

**显示器支持什么、macOS 当前报告什么、哪些信息只是推断，会分别说明。** 例如，EDID 声明支持 HDR 不等于当前已开启 HDR；DSC 保持标注为推断。系统报告也不等于显示器接收端的物理测量。

## 常用控制，就在菜单栏

点击菜单栏中的 Right Display 图标，打开 Quick Control 快捷面板。亮度、音量、颜色格式、色深、HDR 和 VRR 等项目可以在「通用」设置中管理；实际可用项目取决于设备和连接。

<p align="center"><img src="assets/screenshots/0.4-beta/quick-control.png" width="380" alt="菜单栏快捷面板：亮度、音量、颜色格式、色深、HDR 和 VRR"></p>

快捷面板与完整窗口共享状态。亮度控制需要 macOS 提供相应接口，音量控制需要所选设备或音频路径支持；截图中出现滑块不代表所有 HDMI 设备都能直接调节音量。

## 调整显示输出

在「显示」页选择分辨率、HiDPI、固定刷新率或 VRR，以及系统提供的颜色输出组合。

<p align="center"><img src="assets/screenshots/0.4-beta/display-output.png" width="960" alt="显示页：亮度、分辨率、HiDPI、刷新率与颜色输出组合"></p>

Right Display 使用 macOS 为当前连接提供的模式，保留 `120 Hz / 119.88 Hz` 等时序差异，并按颜色格式、色深、范围和 HDR 的完整组合处理输出。设置后会重新读取系统状态。

调好后可以开启「配置保护」，避免误改显示设置，同时保留亮度和音量控制。需要确认的模式切换会提供倒计时，未确认时尝试恢复原配置；**切换可能短暂黑屏，恢复并非保证成功。** 显示链路测试用于主动排查连接，不是首次使用的必经步骤。

## ICC 与 EDID：了解色彩和设备能力

**ICC 色彩描述文件：** 查看当前描述文件、检查外部 ICC 文件、在确认后应用可用描述文件；查看白点、原色、色调曲线、色域关系与 VCGT 校准数据。

<p align="center"><img src="assets/screenshots/0.4-beta/color-profiles.png" width="720" alt="ICC 页面：描述文件信息、色彩特性、色域与校准曲线"></p>

ICC 图表描述文件中的模型，不是色度计实测的屏幕色域，也不能证明 GPU 此刻加载了同一组校准数据。只打开文件检查不会自动应用它。

<details>
<summary>查看 EDID 页面</summary>

<p align="center"><img src="assets/screenshots/0.4-beta/edid.png" width="720" alt="EDID 页面：设备声明能力、macOS 解析能力和基础信息"></p>

EDID 整理显示器声明的分辨率、HDR、刷新率与 VRR 等能力，并支持原始数据导出。**设备声明的能力不等于当前输出状态。** 导出文件可能包含序列号，分享前请检查。

</details>

## 音频：Apple TV 与可选的 Virtual Audio

「音频」页支持 macOS 允许调节音量的输出，以及兼容 Apple TV 的输出音量与部分键盘控制。Apple TV 可能需要本地网络权限和配对；HomePod 作为 Apple TV 当前或默认音频输出时，可沿用这条控制路径，不代表可以直接控制任意 HomePod 或 AirPlay 音箱。

**Virtual Audio 是另一条可选路径：** 把系统声音转发到指定的 HDMI / DisplayPort 输出，并调节软件音量，不改变电视或显示器的硬件音量。

> **当前 RC 不建议依赖 Virtual Audio。** 组件签名检查与本次 ad-hoc 分发方式存在兼容问题，可能阻止转发；当前公开包的跨机器安装和实际播放仍未验证完成。该问题针对虚拟音频路径，使用显示、ICC、EDID 或 Apple TV 功能无需安装虚拟音频组件。组件要求 macOS 27+，详见[安装指南](INSTALLATION.md)。

<details>
<summary>查看 Virtual Audio 界面预览与工作方式</summary>

**系统声音 → Right Display Virtual Audio → 软件音量 → 指定的 HDMI / DP 输出**

<p align="center"><img src="assets/screenshots/0.4-beta/virtual-audio.png" width="960" alt="Virtual Audio 界面预览；图中转发状态不代表当前公开 RC 已可用"></p>

*这是 0.4 界面预览，图中的“转发已启用”不代表当前 RC 已验证可用。*

功能设计包括保存真实输出目标、条件满足时自动启动、保留手动停止状态和异常后的显式恢复。选择应用内音量控制设备不会自动切换 macOS 默认输出；目标不可用时不会自动改用 Mac 扬声器。即使显示就绪，也需要实际播放确认声音。

</details>

## 下载、安装与第一次使用

1. 下载 [RightDisplay-0.4-Beta-RC-arm64.zip](https://github.com/RedoRosetta/RightDisplay/releases/download/v0.4-beta-rc/RightDisplay-0.4-Beta-RC-arm64.zip)。这是应用安装包；GitHub 自动生成的 **Source code** 不是可安装应用。
2. 解压，将 `Right Display.app` 拖到「应用程序」，再从那里打开。升级前先正常退出旧版并保留副本。
3. 本 RC 使用 ad-hoc 签名，未经过 Apple 公证。若提示开发者无法验证或 Apple 无法检查，确认来自本仓库后，可按系统提示前往「系统设置 → 隐私与安全性 → 仍要打开」。
4. 打开后点击菜单栏图标，先查看当前显示器状态，再按需要调整。**不必安装 Virtual Audio，也不必先运行链路测试。**

不需要关闭 Gatekeeper 或 SIP。[完整安装、权限、故障处理与卸载指南](INSTALLATION.md) · [Release 页面与校验文件](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc)

## 通用设置与诊断

完整窗口包含「概览、显示、音频、ICC、EDID、通用」六页。通用设置可以选择语言、登录启动行为、快捷控制项目与自动校正选项。

<details>
<summary>查看通用设置（English 界面）</summary>

<p align="center"><img src="assets/screenshots/0.4-beta/general.png" width="960" alt="英文通用设置：语言、快捷控制、登录行为、安全模式与自动校正"></p>

安全模式抑制启动、连接变化和唤醒时的自动显示校正；配置保护用于限制手动显示调整。

</details>

诊断报告只在你主动操作时保存到本地，不会自动上传。分享前检查设备名称、序列号、网络信息和文件路径。[隐私说明](PRIVACY.md)

## Beta 与反馈

0.4 Beta RC 是公开测试候选，**不是最终 0.4 Beta**。当前阶段重点是收集真实反馈、修复明确阻碍使用的问题，并解决 Virtual Audio 分发问题。

[报告问题 / 提问](https://github.com/RedoRosetta/RightDisplay/issues/new/choose)时，请提供应用版本、Mac 与 macOS 版本、发生了什么以及预期结果；偶发问题也欢迎说明，不必先掌握所有显示参数。提交需要 GitHub 账户，附件请先检查隐私。

[0.4 更新说明](releases/0.4-beta-rc.md) · [历史版本](CHANGELOG.md) · [安全说明](SECURITY.md)

<a id="support"></a>

## 支持开发

如果 Right Display 对你有帮助，欢迎自愿支持开发；使用、测试和反馈同样有价值。

<table align="center">
<tr><th>支付宝 Alipay</th><th>微信支付 WeChat Pay</th></tr>
<tr><td align="center"><img src="assets/sponsor/alipay.png" width="220" alt="支付宝支持 Right Display 二维码"></td><td align="center"><img src="assets/sponsor/wechat-pay.png" width="220" alt="微信支付支持 Right Display 二维码"></td></tr>
</table>

无法使用这些支付方式也没有关系，欢迎通过反馈帮助改进。

本仓库提供安装包、文档和公开发行材料，不公开应用自有源码。[NOTICE](NOTICE.md) · [第三方许可证](THIRD_PARTY_LICENSES.md)
