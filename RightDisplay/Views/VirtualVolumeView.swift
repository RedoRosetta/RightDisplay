// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import SwiftUI
import CoreAudio

struct VirtualVolumeView: View {
    @StateObject private var controller = VirtualVolumeController.shared
    @StateObject private var systemAudio = AudioOutputStore.shared
    @StateObject private var virtualDevice = VirtualAudioDeviceStore.shared
    @State private var packagePrompt = false
    @State private var uninstallPackage = false
    @State private var detailsExpanded = false
    @State private var driverHintPresented = false
    @State private var feedbackSound: NSSound?
    private func l(_ chinese: String, _ english: String) -> String { AppLocalization.isEnglish ? english : chinese }
    var body: some View {
        VStack(spacing:RightDisplayUI.sectionSpacing) {
        GlassCard {
            VStack(alignment:.leading,spacing:14) {
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.center,spacing:16) {
                        virtualAudioHeading.fixedSize(horizontal:true,vertical:false)
                        Spacer(minLength:16)
                        HStack(spacing:8) { routeButton; driverButtons }
                            .buttonStyle(CompactActionButtonStyle()).fixedSize()
                    }
                    VStack(alignment:.leading,spacing:14) {
                        virtualAudioHeading
                        installationControls
                    }
                }
                if let failure = virtualDevice.failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
                Divider()
                HStack(spacing:11) {
                    rowIcon("hifispeaker")
                    Text(l("虚拟对象","Virtual target")).font(RightDisplayUI.rowLabel)
                    Spacer()
                    HStack(spacing:6) {
                        Circle().fill(controller.model.unexpectedStop ? Color.yellow : controller.forwardingEnabled ? Color.green : controller.canStart ? Color.accentColor : Color.secondary.opacity(0.5)).frame(width:7,height:7)
                        Text(stateText).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    }
                    NativeSelectionPicker(
                        options:[.init(id:"",title:l("请选择设备","Select a device"))] + controller.devices.map { .init(id:$0.uid,title:"\($0.name) · \(transport($0.transport))") },
                        selectedID:controller.model.uid ?? "",
                        fallbackTitle:l("所选设备不可用","Selected device unavailable")
                    ) { controller.select($0.isEmpty ? nil : $0) }.disabled(controller.busy)
                }.frame(minHeight:RightDisplayUI.rowHeight)
                 .modifier(CardSubmenuInset(amount:RightDisplayUI.submenuIndent))
                Divider()
                HStack(spacing:11) {
                    rowIcon("speaker.wave.2.fill")
                    VStack(alignment:.leading,spacing:3) {
                        Text(l("虚拟音量","Virtual volume")).font(RightDisplayUI.rowLabel)
                        Text(l("虚拟音量通过软件调节声音并转发至所选真实输出；使用前需将系统输出设为虚拟设备，并启用转发。","Virtual volume adjusts audio in software and forwards it to the selected physical output. To use it, select the virtual device as the system output and enable forwarding."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer()
                    if let output = systemAudio.virtualOutput, let volume = output.volume, output.systemVolumeWritable {
                        VolumeLevelControl(value:Binding(get:{systemAudio.virtualOutput?.volume ?? volume},set:{systemAudio.setVirtualVolume($0)}),percent:Int(((systemAudio.virtualOutput?.volume ?? volume)*100).rounded()),accessibilityLabel:l("虚拟音量","Virtual volume"),onEditingChanged:playVolumeFeedback)
                    } else { Text(l("不可用","Unavailable")).foregroundStyle(.secondary) }
                }.frame(minHeight:RightDisplayUI.rowHeight)
                 .modifier(CardSubmenuInset(amount:RightDisplayUI.submenuIndent))
                Divider()
                Button { detailsExpanded.toggle() } label: {
                    HStack(spacing:11) {
                        rowIcon("list.bullet.rectangle")
                        Text(l("运行详情","Runtime details")).font(RightDisplayUI.rowLabel)
                        Spacer()
                        Image(systemName:detailsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }.frame(minHeight:RightDisplayUI.rowHeight)
                 .modifier(CardSubmenuInset(amount:RightDisplayUI.submenuIndent))
                     .frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                 .accessibilityValue(detailsExpanded ? l("已展开","Expanded") : l("已折叠","Collapsed"))
                if detailsExpanded { audioDetails }

            }
        }
        }.onAppear { virtualDevice.refresh(); controller.refresh();systemAudio.refresh() }
         .confirmationDialog(l("虚拟音频设备", "Virtual audio device"),isPresented:$packagePrompt,titleVisibility:.visible) {
             Button(uninstallPackage ? l("打开卸载器","Open uninstaller") : l("打开安装器","Open installer")) { virtualDevice.openPackage(uninstall:uninstallPackage) }
             Button(l("取消","Cancel"),role:.cancel) {}
         } message: {
             Text(l("将打开 macOS 安装器并请求系统授权。这是本地测试安装包；完成后请重新启动 Mac。不会自动更改音频输出或重启音频服务。","Opens macOS Installer for system authorization. This is a local development package. Restart the Mac afterwards; no automatic output change or audio-service restart."))
         }
    }
    private func playVolumeFeedback(_ editing: Bool) {
        guard !editing, controller.forwardingEnabled else { return }
        systemAudio.refresh()
        guard let output = systemAudio.virtualOutput, (output.volume ?? 0) > 0, output.isMuted != true,
              let sound = NSSound(named:NSSound.Name("Tink"))?.copy() as? NSSound else { return }
        // A private sound instance avoids changing the output of other UI sounds.
        sound.playbackDeviceIdentifier = output.id
        guard sound.playbackDeviceIdentifier == output.id else { return }
        feedbackSound?.stop();feedbackSound = sound
        sound.play()
    }
    private var virtualAudioHeading: some View {
        HStack(spacing:12) {
                    rowIcon("point.3.connected.trianglepath.dotted", primary: true)
                    VStack(alignment:.leading,spacing:4) {
                        HStack(spacing:12) {
                            Text(l("虚拟音频","Virtual Audio")).font(RightDisplayUI.cardTitle)
                        }
                        Text(l("将系统音频转发到所选设备，支持软件音量调节。","Forward system audio to the selected device with software volume control."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
    }
    private var audioDetails: some View {
        VStack(alignment:.leading,spacing:14) {
                if let error = controller.lastFailure {
                    Text(failureDescription(error)).font(.callout)
                    Text(error).font(.caption.monospaced()).textSelection(.enabled)
                    if let origin = controller.telemetry?.failureDetail, origin != "UNAVAILABLE" {
                        Text(stallDescription(origin)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if controller.needsRestart { Text(l("音频路径未能确认退出，请重新启动 App。","Audio teardown unconfirmed. Restart the app before testing again.")).font(.caption).foregroundStyle(.secondary) }
                }
            HStack(alignment:.top,spacing:32) {
                VStack(alignment:.leading,spacing:10) {
                    Text(l("格式与信号","Format and signal")).font(.caption.weight(.semibold))
                    detail(l("驱动状态","Driver status"),installationText)
                    detail(l("虚拟设备","Virtual device"),l("Right Display 虚拟音频","Right Display Virtual Audio"))
                    detail(l("虚拟采样率","Virtual sample rate"),virtualDevice.status.loaded ? String(format:"%g kHz",virtualDevice.status.rate/1000) : "—")
                    detail(l("处理格式","Processing format"),"Float32 PCM")
                    if let d = controller.selectedDevice {
                        detail(l("输出采样率","Output sample rate"),String(format:"%g kHz",d.rate/1000))
                        detail(l("输出声道","Output channels"),String(d.channels))
                        detail(l("输出格式","Output format"),physicalFormat(d))
                    }
                    if let t = controller.telemetry {
                        if let peak = t.inputPeak { detail(l("输入峰值","Input peak"),String(format:"%.5f",peak)) }
                        if let peak = t.outputPeak { detail(l("输出峰值","Output peak"),String(format:"%.5f",peak)) }
                    }
                }.frame(maxWidth:.infinity,alignment:.topLeading)
                VStack(alignment:.leading,spacing:10) {
                    Text(l("缓冲与时序","Buffers and timing")).font(.caption.weight(.semibold))
                    if let d = controller.selectedDevice {
                        detail(l("输出缓冲区","Output buffer"),"\(d.buffer) frames · " + String(format:"%.2f ms",VirtualVolumeStateModel.latency(frames:d.buffer,rate:d.rate) ?? 0))
                        detail(l("设备延迟","Device latency"),d.latency.map { "\($0) frames" } ?? "—")
                        detail(l("安全偏移","Safety offset"),d.safety.map { "\($0) frames" } ?? "—")
                    }
                    if let t = controller.telemetry {
                        detail(l("环形缓冲估算","Ring estimate"),String(format:"%.2f ms",t.ringMS))
                        detail(l("缓冲占用","Buffer occupancy"),"\(t.fill) / \(t.capacity) frames")
                        detail(l("输出回调／帧","Output callbacks / frames"),"\(t.callbacks) / \(t.frames)")
                        if let blocks = t.inputCallbacks { detail(l("虚拟输出数据块","Virtual output blocks"),String(blocks)) }
                    }
                }.frame(maxWidth:.infinity,alignment:.topLeading)
            }
            Text(l("系统转发补偿设备时钟漂移；缓冲估算不等于实测端到端延迟，Float32 不代表物理输出位深。","Forwarding compensates device clock drift; buffer estimates are not measured end-to-end latency, and Float32 is not physical output depth."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.top,4)
    }
    private func detail(_ label:String,_ value:String) -> some View {
        HStack(alignment:.firstTextBaseline,spacing:16) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength:8)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.caption)
    }
    private func rowIcon(_ symbol: String, primary: Bool = false) -> some View {
        Image(systemName:symbol).font(.system(size:primary ? 13.2 : 12,weight:.semibold))
            .foregroundStyle(Color.accentColor).frame(width:primary ? 29.7 : 27,height:primary ? 29.7 : 27)
            .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:8,style:.continuous))
    }
    private var routeTransition: Bool { (controller.model.starting && !controller.forwardingEnabled) || controller.model.state == .stopping }
    private var canStartRoute: Bool {
        controller.canStart && virtualDevice.installed && virtualDevice.status.loaded
            && virtualDevice.status.rate == 48000
            && controller.selectedDevice.map { [44100.0,48000,88200,96000,176400,192000].contains($0.rate) } == true
    }
    private var routeButtonTitle: String {
        if controller.model.starting && !controller.forwardingEnabled { return l("正在启用…","Starting…") }
        if controller.model.state == .stopping { return l("正在停止…","Stopping…") }
        return controller.busy ? l("停止转发","Stop forwarding") : l("启用转发","Start forwarding")
    }
    private var routeButton: some View {
        Button(routeButtonTitle) {
            if controller.busy { controller.stop() } else { controller.startRoute() }
        }.buttonStyle(CompactActionButtonStyle(primary:true)).fixedSize(horizontal:true,vertical:false)
         .disabled(routeTransition || (!controller.busy && !canStartRoute))
    }
    private var driverActionTitle: String {
        if virtualDevice.updateAvailable { return l("更新驱动","Update driver") }
        return virtualDevice.installed ? l("卸载驱动","Uninstall driver") : l("安装驱动","Install driver")
    }
    private var driverActionDisabled: Bool {
        controller.busy || virtualDevice.identityUnconfirmed
            || (virtualDevice.installed && !virtualDevice.status.safeToRemove)
    }
    private var driverActionHelp: String {
        if virtualDevice.identityUnconfirmed {
            return l("驱动身份尚未确认，暂时无法安装或卸载。请确认已安装的是 Right Display 提供的驱动。","Driver identity is unconfirmed. Verify that the installed driver was provided by Right Display before installing or removing it.")
        }
        return l("请先点击「停止转发」，再到 macOS「系统设置 → 声音 → 输出」选择真实音频设备，并停止其他应用对虚拟音频的使用。随后即可卸载或更新驱动；完成后需重启 Mac。","Stop forwarding, select a physical output in macOS System Settings → Sound → Output, and stop other apps using virtual audio. You can then uninstall or update the driver; restart the Mac afterwards.")
    }
    @ViewBuilder private var driverButtons: some View {
        HStack(spacing:0) {
            Button(driverActionTitle) {
                uninstallPackage = virtualDevice.installed && !virtualDevice.updateAvailable
                packagePrompt = true
            }.disabled(driverActionDisabled)
        }.contentShape(Rectangle())
         .onHover { driverHintPresented = $0 && driverActionDisabled }
         .onChange(of:driverActionDisabled) { _, disabled in
             if !disabled { driverHintPresented = false }
         }
         .popover(isPresented:$driverHintPresented,arrowEdge:.top) {
             Text(driverActionHelp).font(.callout).padding(14).frame(width:310,alignment:.leading)
         }
         .accessibilityHint(driverActionHelp)
    }
    private var installationControls: some View {
        VStack(alignment:.leading,spacing:10) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:8) { Spacer(minLength:0); routeButton; driverButtons }
                VStack(alignment:.trailing,spacing:8) {
                    routeButton
                    HStack(spacing:8) { driverButtons }
                }.frame(maxWidth:.infinity,alignment:.trailing)
            }.buttonStyle(CompactActionButtonStyle()).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var installationText: String {
        if virtualDevice.identityUnconfirmed { return l("同名组件身份未确认；不自动覆盖或卸载","Component identity unconfirmed; no automatic replacement or removal") }
        if virtualDevice.status.matches > 1 { return l("设备身份不唯一；不可启用","Ambiguous device identity; unavailable") }
        if virtualDevice.updateAvailable { return l("驱动需要更新；停止使用后更新并重启 Mac","Driver update required; stop all clients, update and restart Mac") }
        if virtualDevice.installed && virtualDevice.status.loaded { return virtualDevice.status.isDefault ? l("系统已识别 · 当前系统输出","System recognized · current output") : l("系统已识别","System recognized") }
        if virtualDevice.installed { return l("已安装 · 尚未确认加载，请重启 Mac","Installed · not confirmed loaded; restart Mac") }
        if virtualDevice.status.loaded { return l("文件已移除 · 设备仍已加载，请重启 Mac","Files removed · still loaded; restart Mac") }
        return l("未安装","Not installed")
    }
    private var stateText: String {
        if controller.model.unexpectedStop { return l("转发已停止","Forwarding stopped") }
        if controller.forwardingEnabled { return l("转发已启用","Forwarding enabled") }
        if controller.model.starting { return controller.isSystemRoute ? l("正在准备系统音频转发","Preparing system forwarding") : l("正在启动测试音","Starting test") }
        switch controller.model.state {
        case .disabled:return l("未启用","Disabled")
        case .ready:return l("已就绪；转发未启用","Ready; forwarding stopped")
        case .running:return controller.isSystemRoute ? l("系统音频转发中","System audio forwarding") : l("测试音运行中","Test running")
        case .targetUnavailable:return l("输出设备不可用","Target unavailable")
        case .unsupportedFormat:
            switch controller.selectedDevice?.eligibility {
            case "CHANNEL_LAYOUT_UNAVAILABLE": return l("无法确认输出左右声道布局", "Output left/right channel layout unavailable")
            case "UNSUPPORTED_STREAM_LAYOUT", "UNSUPPORTED_BUFFER_LAYOUT": return l("输出缓冲区布局不支持", "Unsupported output buffer layout")
            case "UNSUPPORTED_RATE": return l("输出采样率不支持", "Unsupported output sample rate")
            case "UNSUPPORTED_BUFFER_SIZE": return l("输出缓冲区大小不支持", "Unsupported output buffer size")
            default: return l("无法建立兼容的 PCM 输出路径", "No compatible PCM output path")
            }
        case .formatChanged:return l("格式已变化；测试已停止","Format changed; stopped")
        case .deviceLost:return l("设备已断开；测试已停止","Device lost; stopped")
        case .stopping:return l("正在停止","Stopping")
        case .failed:
            let reason = controller.lastFailure ?? ""
            if reason.contains("PERMISSION") || reason.contains("not permitted") { return l("音频设备访问被系统拒绝", "Audio device access denied") }
            if reason.contains("HAL_CREATE_FAILED") { return l("输出设备初始化失败", "Output device initialization failed") }
            if reason.contains("HAL_START_FAILED") { return l("输出设备启动失败", "Output device start failed") }
            if reason.contains("SOURCE_FORMAT_UNAVAILABLE") || reason.contains("BROKER") || reason.contains("XPC") { return l("虚拟音频驱动或连接未就绪", "Virtual audio driver or connection not ready") }
            return l("音频路径失败", "Audio path failed")
        }
    }
    private func failureDescription(_ reason: String) -> String {
        switch reason {
        case "CONTEXT_CHANGED": return l("音频传输会话发生变化，已安全停止转发。","The audio transport session changed; forwarding stopped safely.")
        case "FORMAT_CHANGED": return l("输出设备的音频格式发生变化，已安全停止转发。","The output audio format changed; forwarding stopped safely.")
        case "TARGET_UNAVAILABLE": return l("所选输出设备已不可用，已安全停止转发。","The selected output is unavailable; forwarding stopped safely.")
        case "STOPPED": return l("转发已正常停止。","Forwarding stopped normally.")
        default: return l("音频路径发生异常，已停止转发。","The audio path encountered an error; forwarding stopped.")
        }
    }
    private func stallDescription(_ origin: String) -> String {
        switch origin {
        case "CONTROL_HEARTBEAT_EXPIRED": return l("控制心跳已过期", "Control heartbeat expired")
        case "VIRTUAL_INPUT_NOT_ADVANCING": return l("虚拟输入回调已停止推进", "Virtual input callbacks stopped advancing")
        case "PHYSICAL_OUTPUT_NOT_ADVANCING": return l("实际输出回调已停止推进", "Physical output callbacks stopped advancing")
        case "BOTH_IO_CALLBACKS_NOT_ADVANCING": return l("输入和输出回调均已停止推进", "Both input and output callbacks stopped advancing")
        default: return origin
        }
    }
    private func physicalFormat(_ d: AudioBridgeDevice) -> String {
        guard let bits = d.physicalBits,let fp = d.physicalFloat else { return l("不可用","Unavailable") }
        return "\(bits)-bit " + (fp ? l("浮点 PCM","float PCM") : l("整数 PCM","integer PCM"))
    }
    private func transport(_ t: UInt32) -> String {
        switch t {
        case kAudioDeviceTransportTypeHDMI:return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort:return "DisplayPort"
        case kAudioDeviceTransportTypeBuiltIn:return l("内建","Built-in")
        case kAudioDeviceTransportTypeUSB:return "USB"
        case kAudioDeviceTransportTypeBluetooth,kAudioDeviceTransportTypeBluetoothLE:return l("蓝牙","Bluetooth")
        case kAudioDeviceTransportTypeThunderbolt:return "Thunderbolt"
        case kAudioDeviceTransportTypeFireWire:return "FireWire"
        case kAudioDeviceTransportTypePCI:return "PCI"
        default:return l("未知","Unknown")
        }
    }
}
