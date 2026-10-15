# RightDisplay 1.0 · Build45 安装与卸载

[首页](../../README.md) · [English](#english) · [签名说明](../development/SIGNING.md)

## 安装

1. 从[正式 Release](https://github.com/RedoRosetta/RightDisplay/releases/tag/v1.0.0)下载 `RightDisplay-1.0-Build45.dmg`，核对 Release 提供的 SHA-256；Source code ZIP/TAR 是源码，不是应用。
2. 退出旧版本，保留需要的回退副本。挂载 DMG，将 Right Display.app 拖到 Applications。
3. 此包为 Ad-hoc 签名，未经过 Apple 公证，不是 Developer ID 签名。先正常打开；如被系统阻止，核对来源后在“系统设置 → 隐私与安全性”使用系统提供的“仍要打开”并确认。系统不提供允许选项时不要绕过策略，不关闭 Gatekeeper/SIP。

基础应用要求 macOS14+、Apple silicon arm64。Virtual Audio 为可选组件，另需 macOS27+；只使用显示、EDID、ICC或Apple TV功能无需安装HAL组件。

## 可选 Virtual Audio

由应用打开 macOS Installer，用户自行批准安装。软件音量只调节转发音频，不改变电视硬件音量。应用不自动修改系统默认输出或重启音频服务。按界面选择真实目标、将系统输出设为虚拟设备并启用转发；没有Mac扬声器fallback。

发行包对Driver/Broker采用精确内容绑定。不同发行组件可能不能直接覆盖；使用原发行附带的匹配卸载器安全卸载后再安装新组件，详见[签名与升级边界](../development/SIGNING.md)。三项原Build45本机验收通过，不表示重打包后已完成完整硬件或跨机回归。

## 卸载

先停止转发，将系统输出改回其他设备并结束虚拟设备客户端，再从应用打开匹配的卸载包。卸载程序的安全检查不通过时不要手工强删已加载组件或强制重启音频服务。应用本身正常退出后可从Applications移到废纸篓。保留或删除个人设置和诊断由用户自行决定；这些数据不会因本说明而自动清理。

## English

Download the official 1.0 Build45 DMG, verify its published SHA-256, quit the old app and drag the app to Applications. Source archives are not installers. This package is Ad-hoc signed and not notarized. Where macOS offers it, verify the source and use Privacy & Security → Open Anyway. Never disable Gatekeeper/SIP or bypass an unavailable allow action.

Base app: macOS14+ on Apple silicon; optional Virtual Audio: macOS27+. Audio installation uses user-authorized macOS Installer. Exact component pins restrict upgrades: use the matching previous uninstaller when required. To remove components, stop forwarding, select another system output and stop virtual-device clients before running the matching uninstaller. Quit and remove the app separately. No automatic audio restart or private-data cleanup is prescribed.

[Privacy](PRIVACY.md) · [Release notes](../releases/1.0.0.md)
