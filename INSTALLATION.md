# Installation / 安装

RightDisplay 0.4 Beta RC is a public test candidate. Download the ZIP and matching checksum from the [official GitHub Release](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc).

本次为公开测试候选。主 App 为 ad-hoc 签名，尚未经过 Apple 公证。虚拟音频组件同样为 ad-hoc 签名，另有系统要求，见下文。

## App / 应用

1. Obtain `RightDisplay-0.4-Beta-RC-arm64.zip` with its matching `SHA256SUMS.txt`. Compare SHA-256; if it does not match, do not open it.
   核对候选 ZIP 与随附文件的 SHA-256，不一致时不要打开。
2. Quit the old App normally and keep a copy for rollback. Extract the ZIP and move `Right Display.app` into Applications. Replace with a clean copy; do not merge old bundle contents.
   正常退出旧版并保留回退副本，解压后将 App 干净复制到「应用程序」，不要合并旧包内容。
3. Try opening normally. If macOS blocks it, use **System Settings → Privacy & Security → Open Anyway**, then confirm. Finder's manual **Open** can be used where the system offers it.
   先正常打开；被阻止时使用**系统设置 → 隐私与安全性 → 仍要打开**并确认。系统提供时可使用 Finder 手动**打开**。
4. Confirm About shows version 0.4 Beta. Grant only permissions required by the features you use.
   检查版本 0.4 Beta，仅授予实际功能需要的权限。

No need to disable Gatekeeper or SIP. Do not remove quarantine attributes as an installation step.

不需要关闭 Gatekeeper／SIP，也不将删除隔离属性作为安装步骤。

Base requirements: macOS 14+, Apple silicon arm64. Virtual Audio needs a newer macOS and currently requires macOS 27.0 or later; this is a feature requirement, separate from the App’s base requirements.

## Virtual Audio / 虚拟音频

已知问题：本 RC 使用 ad-hoc 签名，虚拟音频可能因签名校验导致转发无法启用。所用版本仍保留部分 App／broker／driver 之间的 Apple 签名要求，这些校验与 ad-hoc 组件不兼容；虚拟音频尚未通过本 RC 的实际转发验收。

Known issue: ad-hoc signing may prevent Virtual Audio forwarding from starting. This version retains some Apple-signature requirements between the App, broker and driver; those checks are incompatible with ad-hoc components. Real forwarding has not been accepted for this RC.

Virtual Audio is optional. It provides software volume, not TV hardware volume. This RC uses ad-hoc signatures for driver, broker and removal-check code; `.pkg` containers are unsigned and not notarized. Cross-machine install and real forwarding remain acceptance items. The original component integrity and Apple/Team-signature checks are retained. Broker authentication of Apple OS audio producers remains.

虚拟音频为可选组件：驱动、broker 和安全卸载检查程序使用 ad-hoc 签名，安装包容器未签名、未公证。虚拟音频需要较新的 macOS，当前组件要求 macOS 27.0 或更新版本；跨机器安装及转发仍待验收。保留原版本的完整性及部分 Apple／Team 签名校验。

1. Before installing/updating, choose another real system audio output and stop forwarding and virtual-device clients. Record the intended real output target.
   安装／更新前先选择其他真实系统音频输出，停止转发和使用虚拟设备的客户端，并记录目标。
2. Use Audio → Virtual Audio's explicit install/update action to open the normal macOS Installer. Only approve the candidate's supplied package. The supplied component version is 21. Its ad-hoc package differs from a development-signed component with the same version number; App replacement alone does not update the broker. The packaged installer is at `Right Display.app/Contents/Resources/VirtualAudioPackages/InstallVirtualAudio.pkg` if a manual update is required.
   用音频页安装／更新操作打开系统安装器。所附组件版本为 21，其 ad-hoc 包与同版本开发签名组件不同；只换 App 不会更新 broker。需要时手动打开本 App 内上述安装包。
3. A previously loaded component may require restarting the Mac to use the new installation. Do not force-restart CoreAudio services.
   已加载组件可能需要重启 Mac 才使用新安装内容，不强制重启音频服务。
4. Reopen the App, confirm component readiness, choose one real HDMI/DP output target and start forwarding. To forward system audio, explicitly choose the Right Display virtual output in macOS. Choosing its volume control in the App alone does not switch the system output.
   重新打开 App，确认组件就绪，选择真实 HDMI／DP 目标并启动转发；需要转发系统声音时，在 macOS 中显式选择虚拟输出。应用内控制设备选择与系统默认输出不同。
5. Start at low software volume and check mute, keyboard volume, stop/restart and target recovery yourself. A ready/green status is not an audible-playback test.
   从较低软件音量开始，人工检查静音、键盘音量、停止／重启及目标恢复。就绪或绿灯不等于播放验收。

The virtual path is output-only; it is not a microphone feature. Do not grant microphone access for this path.

此路径仅提供输出，不是麦克风功能。

## Removal and rollback / 卸载与回退

Switch macOS away from the virtual output, stop forwarding and close its clients before using the explicit uninstall action. Integrity/safe-removal checks can block removal; do not bypass them. Loaded components may remain until restart.

卸载前切换其他系统输出、停止转发并关闭客户端，使用现有卸载流程。不要绕过完整性／安全卸载检查。

To roll back the App, quit it and restore the saved working copy. That restores only the App: installed audio components are separate. Do not assume swapping ZIPs rolls back the broker/driver; keep their accepted package and follow the same explicit safe update/removal workflow.

App 回退只恢复应用，不能代替驱动／broker 回退。显示调整前保留可用配置；遇到异常先停止操作，使用原有恢复流程。
