# 安装与首次使用 / Installation

[简体中文](#简体中文) · [English](#english) · [返回首页 / Home](README.md)

## 简体中文

### 安装前

- **Mac：** Apple 芯片，macOS 14 或更新版本；当前没有 Intel 安装包。
- **版本：** 0.4 Beta RC，公开测试候选，不是最终 0.4 Beta。
- **首次打开：** 当前 App 使用 ad-hoc 签名，未使用 Developer ID 签名、未经过 Apple 公证，macOS 可能阻止直接打开。
- **Virtual Audio：** 可选，要求 macOS 27+，并存在签名兼容问题，可能无法启用。只使用显示、ICC、EDID 或 Apple TV 功能，无需安装它。

### 下载并安装 App

1. 下载官方 [RightDisplay-0.4-Beta-RC-arm64.zip](https://github.com/RedoRosetta/RightDisplay/releases/download/v0.4-beta-rc/RightDisplay-0.4-Beta-RC-arm64.zip)。[Release 页面](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc)的 **Assets** 中也可找到它；不要把 **Source code** 当作应用安装包。
2. 若已安装旧版，先正常退出，并保留旧 App 副本以便回退。
3. 解压 ZIP，把 `Right Display.app` 拖到「应用程序」。替换整个 App，不要合并新旧 App 内的文件。
4. 从「应用程序」打开 Right Display。

<details>
<summary>核对下载文件（SHA-256）</summary>

下载同一 Release 的 [SHA256SUMS.txt](https://github.com/RedoRosetta/RightDisplay/releases/download/v0.4-beta-rc/SHA256SUMS.txt)。如果 ZIP 位于默认「下载」文件夹，可在「终端」运行：

```sh
shasum -a 256 "$HOME/Downloads/RightDisplay-0.4-Beta-RC-arm64.zip"
```

将输出的校验值与 `SHA256SUMS.txt` 比较。如果不一致，不要打开该文件，重新从官方 Release 下载。校验值用于核对文件完整性，不代表 Apple 公证。

</details>

### 如果 macOS 阻止首次打开

如果提示开发者无法验证，或 Apple 无法检查此 App，确认下载来自上方官方 Release 后：

1. 先尝试打开一次 App，然后进入「系统设置 → 隐私与安全性」。
2. 向下找到被阻止的 Right Display，点击「仍要打开」，按系统提示确认。
3. 系统再次询问时，确认打开。Finder 的手动「打开」仅在系统提供时使用。

**不需要关闭 Gatekeeper 或 SIP，也不要把删除隔离属性作为安装步骤。** 如果找不到「仍要打开」，或提示文件损坏／将损害电脑，不要把这些提示一律当作正常安装提示；记录完整提示，核对下载，并[反馈问题](https://github.com/RedoRosetta/RightDisplay/issues/new/choose)。受管理的 Mac 也可能受组织策略限制。

可参考 [Apple 的官方打开说明](https://support.apple.com/en-us/102445)。

### 第一次打开后做什么

1. 在屏幕顶部菜单栏找到 Right Display 图标，点击打开快捷面板；从面板进入完整窗口。没有自动弹出窗口不一定表示启动失败。
2. 先在「概览」确认选择了正确的外接显示器，查看分辨率、刷新率与 HDR 等状态。
3. 按需进入「显示」调整设置。切换可能短暂黑屏；需要确认的切换会显示倒计时，未确认时尝试恢复。不要把恢复视为一定成功。
4. 只在使用相应功能时授予权限。Apple TV 发现与控制可能需要本地网络权限；键盘控制等功能若提示辅助功能权限，再按需开启。虚拟音频输出不是麦克风功能。

不必先安装虚拟音频，也不必运行链路测试。界面可能显示「0.4 Beta」；反馈时请同时写明下载的是 **0.4 Beta RC** 和 ZIP 文件名，避免与开发版本混淆。

### Virtual Audio：当前已知问题

**如果你主要需要 HDMI / DP 软件音量，建议等待修复。** 当前公开包的组件签名检查与 ad-hoc 分发方式存在兼容问题，可能导致转发无法启动；跨机器安装和实际播放尚未验证完成。

这个组件提供软件音量，不改变电视硬件音量。Apple TV 音量是独立功能。虚拟音频驱动与后台组件使用 ad-hoc 签名，安装包未签名、未公证；具体限制见[安全说明](SECURITY.md)。

<details>
<summary>可选：在 macOS 27+ 上测试虚拟音频</summary>

仅在你愿意测试这项已知有问题的功能时继续。启用失败不是必须通过反复重装才能解决的问题。

1. 先把 macOS 声音输出切到一个真实设备，停止虚拟音频转发，并关闭正在使用虚拟设备的播放器或其他应用。
2. 在「音频 → 虚拟音频」使用安装／更新操作，打开随 App 提供的系统安装包。系统安装器可能要求管理员确认。
3. **只替换 App 不会更新音频组件。** 本 RC 附带组件版本 21；它与同版本号的开发签名组件不同。需要手动更新时，在 Finder 中右键 App → 显示包内容，打开 `Contents/Resources/VirtualAudioPackages/InstallVirtualAudio.pkg`。
4. 如果系统仍在使用旧组件，重新启动 Mac 后再试；不要强制重启音频服务。
5. 打开 App，选择真实 HDMI / DP 输出目标，尝试启动转发。需要转发系统声音时，再在 macOS「声音 → 输出」中选择 Right Display 虚拟输出。应用内的音量控制设备选择不会替你切换系统输出。
6. 从较低软件音量开始实际播放并检查声音。就绪或绿灯不代表已经有声音，也不保证连续播放正常。若失败，切回真实系统输出，记录提示后反馈，不要绕过签名检查。

</details>

### 卸载与回退

**仅安装了 App：** 正常退出后，可移走或删除「应用程序」中的 `Right Display.app`；回退时恢复先前保留的 App 副本。

**还安装了虚拟音频组件：** 先将 macOS 输出切到真实设备，停止转发，关闭使用虚拟设备的应用，再使用 Right Display 音频页的卸载操作。若检查阻止卸载，记录提示并反馈，不要绕过检查或手动删除系统组件；已加载组件可能要重启后才消失。请先处理组件，再删除 App。

App 回退不会自动回退已安装的虚拟音频组件。需要恢复组件时，使用此前保留且已确认可用的安装包，遵循相同的更新／卸载流程。

### 遇到问题

[提交问题](https://github.com/RedoRosetta/RightDisplay/issues/new/choose)，附上版本、Mac 与 macOS、完整错误提示，以及卡在下载、打开还是可选组件安装这一步。偶发问题也可以提交。诊断与截图请先检查设备标识、路径及其他隐私信息。

## English

### Before installing

- **Mac:** Apple silicon with macOS 14 or later. There is no Intel package.
- **Version:** 0.4 Beta RC is a public release candidate, not the final 0.4 Beta.
- **First launch:** The App is ad-hoc signed, without Developer ID signing or Apple notarization. macOS may block it from opening directly.
- **Virtual Audio:** Optional, requires macOS 27+, and has a signature-compatibility issue that may prevent it from starting. Display, ICC, EDID and Apple TV features do not require it.

### Download and install the App

1. Download the official [RightDisplay-0.4-Beta-RC-arm64.zip](https://github.com/RedoRosetta/RightDisplay/releases/download/v0.4-beta-rc/RightDisplay-0.4-Beta-RC-arm64.zip). It is also under **Assets** on the [Release page](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc). The **Source code** archives are not installable apps.
2. If upgrading, quit the old App normally and keep a copy for rollback.
3. Extract the ZIP and drag `Right Display.app` to Applications. Replace the whole App rather than merging files inside old and new copies.
4. Open Right Display from Applications.

<details>
<summary>Check the download with SHA-256</summary>

Download [SHA256SUMS.txt](https://github.com/RedoRosetta/RightDisplay/releases/download/v0.4-beta-rc/SHA256SUMS.txt) from the same Release. If the ZIP is in your default Downloads folder, run this in Terminal:

```sh
shasum -a 256 "$HOME/Downloads/RightDisplay-0.4-Beta-RC-arm64.zip"
```

Compare the result with `SHA256SUMS.txt`. If it differs, do not open the file; download it again from the official Release. A checksum verifies file integrity, not Apple notarization.

</details>

### If macOS blocks the first launch

If macOS cannot verify the developer or check the App, confirm it came from the official Release above, then:

1. Try opening the App once, then open **System Settings → Privacy & Security**.
2. Scroll to the blocked Right Display entry, choose **Open Anyway**, and follow the confirmation prompts.
3. Confirm Open when asked again. Finder’s manual Open is an alternative only where the system offers it.

**Do not disable Gatekeeper or SIP, or remove quarantine attributes as an installation step.** If Open Anyway is missing, or the alert says the App is damaged or will damage your computer, do not treat every warning as routine: record the exact message, check the download, and [report the problem](https://github.com/RedoRosetta/RightDisplay/issues/new/choose). Managed Macs may also have organizational restrictions.

See [Apple’s official guidance](https://support.apple.com/en-us/102445).

### After the first launch

1. Find Right Display in the menu bar at the top of the screen and click it to open Quick Control; open the full window from that panel. No automatic window does not necessarily mean launch failed.
2. In Overview, select the intended external display and inspect resolution, refresh rate and HDR.
3. Adjust settings in Display if needed. Switching may briefly blank the screen. Changes requiring confirmation offer a countdown and attempt recovery if unconfirmed; recovery is not guaranteed.
4. Grant permissions only for features you use. Apple TV discovery/control may need Local Network access; enable Accessibility if requested for features such as keyboard control. The virtual-audio output is not a microphone feature.

Neither Virtual Audio installation nor Display Link Test is required. The interface may show “0.4 Beta”; include **0.4 Beta RC** and the downloaded ZIP filename in feedback to distinguish it from development copies.

### Virtual Audio: known issue

**If HDMI / DP software volume is your main need, we recommend waiting for a fix.** Component signature checks conflict with this ad-hoc distribution and may prevent forwarding. Cross-machine installation and actual playback of the public package have not yet been fully verified.

This component adjusts software volume, not TV hardware volume. Apple TV volume is separate. Virtual-audio driver and background components are ad-hoc signed; their installer is unsigned and not notarized. See [security information](SECURITY.md) for the limitations.

<details>
<summary>Optional: test Virtual Audio on macOS 27+</summary>

Continue only if you want to test this known-limited feature. Repeated installation is not an expected cure for the signature issue.

1. Switch macOS audio output to a real device, stop virtual forwarding and close players or other apps using the virtual device.
2. Use the install/update action in **Audio → Virtual Audio** to open the installer supplied with the App. macOS Installer may request administrator confirmation.
3. **Replacing the App does not update audio components.** This RC includes component version 21, which differs from a development-signed component with the same number. For a manual update, right-click the App in Finder, choose Show Package Contents, and open `Contents/Resources/VirtualAudioPackages/InstallVirtualAudio.pkg`.
4. If the system still uses an older loaded component, restart the Mac before trying again. Do not force-restart audio services.
5. Open the App, choose a real HDMI / DP target and try starting forwarding. To forward system sound, then select the Right Display virtual output in macOS **Sound → Output**. Selecting its volume control in the App does not switch the system output.
6. Start at low software volume and play audio to check it. Ready/green status does not establish audible or uninterrupted playback. If it fails, switch back to a real system output, record the message and report it. Do not bypass signature checks.

</details>

### Removal and rollback

**App only:** Quit normally, then move or delete `Right Display.app` from Applications. Restore a previously saved App copy to roll back.

**Virtual Audio also installed:** Switch macOS to a real output, stop forwarding and close apps using the virtual device, then use the uninstall action on Right Display’s Audio page. If a check blocks removal, record and report the message rather than bypassing it or manually deleting system components. Loaded components may remain until restart. Handle the components before deleting the App.

Rolling back the App does not roll back installed virtual-audio components. To restore components, use a previously retained, known-working package with the same update/removal process.

### Get help

[Report a problem](https://github.com/RedoRosetta/RightDisplay/issues/new/choose) with the version, Mac and macOS, exact error, and whether it occurred during download, launch or optional component installation. Intermittent issues are welcome. Review diagnostics and screenshots for identifiers, paths and private information before attaching them.
