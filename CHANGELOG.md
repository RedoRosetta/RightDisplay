# Public version history / 公开版本历史

## 0.4 Beta RC

- Virtual Audio software volume for HDMI/DP outputs; saved target, conditional auto-start and explicit recovery after an abnormal stop.
  新增 HDMI／DP 虚拟音频软件音量、保存目标、条件满足时自动启动与异常停止后的显式恢复。
- A dedicated ICC page for current association, external-file inspection, profile selection, gamut and stored calibration curves.
  新增 ICC 独立页面，检查当前关联及外部文件、选择描述文件、查看色域与文件内校准曲线。
- Refined Overview, Display, Audio, ICC, EDID and General pages, with shared controls and evidence labels.
  整理六个页面的卡片、控件和状态提示，保留系统报告、推断和能力来源。
- Refined EDID, link-test evidence, local diagnostics and interaction updates. No universal performance or physical-output verification claim.
  完善 EDID、链路测试证据、本地诊断及交互更新；不宣称通用性能或物理输出验证。
- Repackaged from the existing 0.4 Beta code without audio logic changes. All supplied code is ad-hoc signed and not notarized. Virtual Audio requires macOS 27.0 or later.
  基于现有 0.4 Beta 重新签名打包，未更改音频逻辑。所供代码均为 ad-hoc 签名、未公证；虚拟音频要求 macOS 27.0 或更新版本。

- Known issue: ad-hoc signing may prevent Virtual Audio forwarding from starting. This version retains some Apple-signature requirements between the App, broker and driver; those checks are incompatible with ad-hoc components. Real forwarding has not been accepted for this RC.
  已知问题：本 RC 使用 ad-hoc 签名，虚拟音频可能因签名校验导致转发无法启用。所用版本仍保留部分 App／broker／driver 之间的 Apple 签名要求，这些校验与 ad-hoc 组件不兼容；虚拟音频尚未通过本 RC 的实际转发验收。

[Download / 下载](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc) · [RC notes / RC 说明](releases/0.4-beta-rc.md)

## 0.3 Beta — Build 60

- Separate current readback, inference and device-declared capabilities; preserve unknown states.
  区分当前回读、推断与设备声明能力，保留未知。
- Display Link Test for stable combinations on the current connection, with confirmation/readback and recovery handling.
  新增当前连接的稳定组合测试，配合确认、回读与恢复处理。
- Shared Quick Control/advanced state and Configuration Protection for manual display adjustments.
  快捷控制与高级设置共用状态，配置保护锁定手动显示调整。
- Expanded EDID interpretation and local diagnostics with evidence and recent events.
  完善 EDID 解读及本地诊断，提供证据与近期事件。
- Refined Light/Dark materials, compact controls, device icons, guidance and About information.
  收敛浅色／深色材质、紧凑控件、设备图标、引导与关于信息。
- Consolidated brightness/audio controls, compatible Apple TV output volume and optional keyboard control.
  整合亮度／声音控制，保留兼容 Apple TV 输出音量与可选键盘控制。

[Complete notes / 完整说明](releases/0.3-beta.md)

## 0.2 Beta

Based on [published 0.2 notes](https://github.com/RedoRosetta/RightDisplay/releases/tag/RightDisplay0.2Beta).

- Follow System, Simplified Chinese and English language choices.
  新增跟随系统、简体中文和 English 语言选择。
- Improved English layouts and dynamic display, EDID and audio text.
  完善英文排版及显示、EDID、音频动态内容。
- Full Apple TV reconnection after lock/sleep; restore the saved device and refresh connection, volume and keyboard-control readiness without deleting pairing credentials.
  完善锁屏／休眠后的 Apple TV 重连，恢复设备并刷新连接、音量与键盘可用性，不删除配对凭据。

## 0.1 Beta

Based on [published 0.1 notes](https://github.com/RedoRosetta/RightDisplay/releases/tag/RightDisplay0.1Beta).

- Initial public beta: display mode/HiDPI/refresh information, HDR/color/depth readings, DSC inference, EDID and diagnostics.
  首个公开 Beta：显示模式／HiDPI／刷新率、HDR／颜色／色深读取、DSC 推断、EDID 与诊断。
- Supported mode changes with confirmation/recovery attempts, writable brightness and compatible Apple TV volume/keyboard controls; limited tested combinations.
  支持的模式切换带确认／恢复尝试、可写亮度及兼容 Apple TV 音量／键盘控制，验证范围有限。
- Display-and-signal visual identity; ad-hoc signature, no notarization at that release.
  建立显示器与信号曲线视觉标识；当时为 ad-hoc 签名，未公证。
