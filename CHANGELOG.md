# 版本历史 / Version history

## 0.4 Beta RC

- 重新整理六页界面与菜单栏快捷控制；新增独立 ICC 检查与描述文件应用。
  Reorganized six-page interface and menu-bar controls; added dedicated ICC inspection and profile application.
- 固定刷新率、VRR 与完整颜色组合分开说明，设置后重新读取系统状态。
  Clearer fixed-rate, VRR and complete color combinations, with system readback after changes.
- 加入可选 Virtual Audio 软件音量，但当前公开包存在签名兼容问题，可能无法启动转发；要求 macOS 27+，实际播放与跨机器安装仍未验证完成。
  Added optional Virtual Audio software volume, but signature compatibility may prevent forwarding in this public package. It requires macOS 27+; actual playback and cross-machine installation have not yet been fully verified.

**这是公开测试候选，不是最终 0.4 Beta。 / This is a public test candidate, not the final 0.4 Beta.**

[完整说明 / Full notes](releases/0.4-beta-rc.md) · [下载 / Download](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc)

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
