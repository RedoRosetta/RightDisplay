// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import SwiftUI

struct SystemSettingsPaneView: View {
    @EnvironmentObject private var store: DisplayStore
    @EnvironmentObject private var preferences: Preferences
    @StateObject private var brightness = DisplayBrightnessStore.shared
    @StateObject private var audio = AudioOutputStore.shared
    @StateObject private var appleTVAudio = AppleTVAudioController.shared

    @State private var showingSizeEditor = false
    @State private var showingAppleTVGuide = false
    @State private var diagnosticError: String?
    @State private var displaySectionExpanded = true
    @State private var mediaSectionExpanded = true
    @State private var signalSectionExpanded = true
    @State private var outputSectionExpanded = true
    @State private var modeSectionExpanded = true

    var body: some View {
        GeometryReader { geometry in
            if let display = store.selectedDisplay {
                ScrollView(.vertical) {
                    paneContent(display)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .scrollBounceBehavior(.basedOnSize)
                .contentMargins(.trailing, 8, for: .scrollIndicators)
                .sheet(isPresented: $showingSizeEditor) {
                    SystemSizeEditor(display: display)
                        .environmentObject(store)
                        .environmentObject(preferences)
                }
            } else {
                ContentUnavailableView(
                    "没有检测到显示器",
                    systemImage: "display.trianglebadge.exclamationmark",
                    description: Text("连接显示器后，Right Display 会自动刷新。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: confirmationBinding) {
            OutputConfirmationSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingAppleTVGuide) {
            AppleTVAudioGuide(controller: appleTVAudio)
        }
        .alert("无法应用设置", isPresented: errorBinding) {
            Button("好") { store.clearLastError() }
        } message: {
            Text(store.lastError ?? "未知错误")
        }
        .alert("无法导出诊断报告", isPresented: diagnosticErrorBinding) {
            Button("好") { diagnosticError = nil }
        } message: {
            Text(diagnosticError ?? "未知错误")
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { store.pendingModeConfirmation },
            set: { presented in
                if !presented && store.pendingModeConfirmation {
                    store.restorePendingModeIfNeeded()
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { presented in
                if !presented { store.clearLastError() }
            }
        )
    }

    private var diagnosticErrorBinding: Binding<Bool> {
        Binding(
            get: { diagnosticError != nil },
            set: { if !$0 { diagnosticError = nil } }
        )
    }

    private func paneContent(_ display: DisplaySnapshot) -> some View {
        VStack(spacing: 10) {
            displaySection(display)
            mediaSection(display)
            signalSection(display)
            outputSection(display)
            modeSection(display)
        }
        .padding(.leading, 18)
        // System Settings uses an overlay scroller for legacy preference panes.
        // Keep controls inside a permanent trailing safe area at narrow widths.
        .padding(.trailing, 18)
        // The legacy preference pane is drawn beneath System Settings' own
        // toolbar. Keep the first section title below that overlay region.
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func mediaSection(_ display: DisplaySnapshot) -> some View {
        SettingsGroup(title: "亮度与声音", isExpanded: $mediaSectionExpanded) {
            SettingsRow(
                "亮度",
                icon: "sun.max",
                subtitle: brightness.statusText
            ) {
                if brightness.isAvailable {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { brightness.value },
                                set: { brightness.set($0) }
                            ),
                            in: 0...1
                        )
                        .frame(width: 190)
                        Text("\(Int((brightness.value * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                } else {
                    Text("不可用").foregroundStyle(.secondary)
                }
            }
            SettingsDivider()
            SignalSettingsRow("声音输出设备", audio.current.name, icon: "speaker.wave.2")
            SettingsDivider()
            SettingsRow(
                "Mac 音量",
                icon: "speaker.wave.3",
                subtitle: audio.current.systemVolumeWritable
                    ? "控制当前声音输出设备的系统音量。"
                    : "当前设备不支持由 macOS 调节音量，请使用接收端控制。"
            ) {
                if audio.current.systemVolumeWritable, let volume = audio.current.volume {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { volume },
                                set: { audio.setVolume($0) }
                            ),
                            in: 0...1
                        )
                        .frame(width: 190)
                        Text("\(Int((volume * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                } else {
                    Text("由接收端控制").foregroundStyle(.secondary)
                }
            }
            SettingsDivider()
            SettingsRow(
                "Apple TV／HomePod 音量",
                icon: "homepod.2.fill",
                subtitle: appleTVAudio.statusText
            ) {
                if appleTVAudio.isConnected, let volume = appleTVAudio.volume {
                    HStack(spacing: 8) {
                        Button { appleTVAudio.volumeDown() } label: {
                            Image(systemName: "speaker.minus")
                        }
                        .buttonStyle(.borderless)
                        Slider(
                            value: Binding(
                                get: { volume },
                                set: { appleTVAudio.setVolume($0) }
                            ),
                            in: 0...100
                        )
                        .frame(width: 160)
                        Button { appleTVAudio.volumeUp() } label: {
                            Image(systemName: "speaker.plus")
                        }
                        .buttonStyle(.borderless)
                        Text("\(Int(volume.rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                } else {
                    Button("查找与配对…") { showingAppleTVGuide = true }
                }
            }
            SettingsDivider()
            SettingsRow(
                "使用键盘音量键控制",
                icon: "keyboard.badge.ellipsis",
                subtitle: "将 Apple 键盘的音量加、减和静音键发送到已连接的 Apple TV／HomePod。"
            ) {
                Toggle("", isOn: $appleTVAudio.bindsKeyboardVolumeKeys)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .onAppear {
            brightness.selectDisplay(display.id)
            audio.refresh()
            appleTVAudio.resume()
        }
        .onChange(of: display.id) { _, displayID in
            brightness.selectDisplay(displayID)
        }
    }

    @ViewBuilder
    private func displaySection(_ display: DisplaySnapshot) -> some View {
        SettingsGroup(title: "显示器", isExpanded: $displaySectionExpanded) {
            SettingsRow("所选显示器", icon: "display") {
                Picker("", selection: Binding(
                    get: { store.selectedDisplayID },
                    set: { id in
                        guard id != store.selectedDisplayID else { return }
                        store.selectDisplay(id)
                    }
                )) {
                    ForEach(store.displays) { item in
                        Text(item.name).tag(item.id)
                    }
                }
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            SettingsDivider()
            SettingsRow("当前分辨率", icon: "rectangle.on.rectangle") {
                Text("\(display.resolution) @ \(display.refreshRate.text)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            SettingsDivider()
            SignalSettingsRow("显示比例", currentAspectRatio(display), icon: "aspectratio")
            SettingsDivider()
            SettingsRow("界面分辨率（HiDPI）", icon: "textformat.size") {
                Text(display.logicalResolution)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            SettingsDivider()
            SettingsRow("屏幕尺寸", icon: "ruler") {
                HStack(spacing: 8) {
                    Text(display.sizeText).foregroundStyle(.secondary)
                    Button("校正…") { showingSizeEditor = true }
                }
            }
            SettingsDivider()
            SettingsRow(
                "显示器预设",
                icon: "externaldrive.badge.timemachine",
                subtitle: savedSettingsSubtitle(display)
            ) {
                HStack(spacing: 8) {
                    Button("保存当前设置") { saveCurrentSettings(display) }
                    Button("应用预设") { applySavedSettings(display) }
                        .disabled(preferences.savedSettings(for: display.hardwareKey) == nil)
                    Button("清除") { preferences.removeSavedSettings(for: display.hardwareKey) }
                        .disabled(preferences.savedSettings(for: display.hardwareKey) == nil)
                }
            }
            SettingsDivider()
            SettingsRow(
                "诊断报告",
                icon: "doc.text.magnifyingglass",
                subtitle: "导出显示链路与模式信息；不包含序列号、配对凭据、用户名或文件路径。"
            ) {
                Button("导出…") {
                    diagnosticError = DiagnosticReportExporter.export(
                        display: display,
                        brightness: brightness,
                        audio: audio,
                        qmsAssessment: qmsAssessment(display).text
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func signalSection(_ display: DisplaySnapshot) -> some View {
        SettingsGroup(title: "当前信号", isExpanded: $signalSectionExpanded) {
            EvidenceSignalRow("像素格式", display.pixelEncoding, icon: "paintpalette")
            SettingsDivider()
            EvidenceSignalRow("色域", display.colorGamut, icon: "camera.filters")
            SettingsDivider()
            EvidenceSignalRow("色深", display.bitDepth, icon: "circle.lefthalf.filled")
            SettingsDivider()
            EvidenceSignalRow("高动态范围（HDR）", display.hdr, icon: "sun.max")
            SettingsDivider()
            EvidenceSignalRow("可变刷新率（VRR）", display.vrr, icon: "speedometer")
            SettingsDivider()
            EvidenceSignalRow("显示流压缩（DSC）", display.dsc, icon: "arrow.left.arrow.right")
        }
    }

    @ViewBuilder
    private func outputSection(_ display: DisplaySnapshot) -> some View {
        SettingsGroup(title: "视频输出", isExpanded: $outputSectionExpanded) {
            SettingsRow("颜色格式", icon: "paintpalette.fill") {
                HStack(spacing: 0) {
                    outputChoice(
                        "自动",
                        value: .automatic,
                        display: display,
                        help: "由 macOS 根据显示模式和链路带宽自动选择颜色格式与位深。"
                    )
                    outputChoice(
                        "RGB",
                        value: .rgbFullRange,
                        display: display,
                        help: colorCapabilityHelp(.rgbFullRange, display: display)
                    )
                    outputChoice(
                        "YCbCr",
                        value: .yCbCr,
                        display: display,
                        help: colorCapabilityHelp(.yCbCr, display: display)
                    )
                }
                .frame(width: 270)
                .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            SettingsDivider()
            SettingsRow("色深", icon: "circle.lefthalf.filled") {
                HStack(spacing: 0) {
                    ForEach([8, 10, 12], id: \.self) { depth in
                        bitDepthChoice(depth, display: display)
                    }
                }
                .frame(width: 190)
                .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            SettingsDivider()
            SettingsRow(
                "可变刷新率（VRR）",
                icon: "speedometer",
                subtitle: "使刷新率随画面帧率变化，减少撕裂并改善游戏流畅度。"
            ) {
                ExplicitBooleanButton(
                    isOn: display.vrrEnabled,
                    isEnabled: display.vrrSupported,
                    accessibilityLabel: "可变刷新率（VRR）"
                ) {
                    store.setVRREnabled(!display.vrrEnabled)
                }
            }
            SettingsDivider()
            SettingsRow(
                "高动态范围（HDR）",
                icon: "sun.max.fill",
                subtitle: "输出更宽的亮度和色彩范围；切换时可能同步调整颜色格式与色深。"
            ) {
                ExplicitBooleanButton(
                    isOn: display.hdrEnabled ?? false,
                    isEnabled: display.hdrSupported,
                    accessibilityLabel: "高动态范围（HDR）"
                ) {
                    store.setHDREnabled(!(display.hdrEnabled ?? false))
                }
            }
            SettingsDivider()
            SettingsRow(
                "显示流压缩（DSC）",
                icon: "arrow.left.arrow.right",
                subtitle: "以视觉无损压缩降低链路带宽；切换时可能短暂黑屏。"
            ) {
                ExplicitBooleanButton(
                    isOn: display.dscEnabled ?? false,
                    isEnabled: display.dscSupported,
                    accessibilityLabel: "显示流压缩（DSC）",
                    hoverHelp: "DSC（Display Stream Compression）通过视觉无损压缩降低视频链路带宽，使高分辨率、高刷新率、HDR 和高色深能够同时传输。切换会重新训练显示链路，可能短暂黑屏。关闭 DSC 时，Right Display 会改用未压缩链路可承载的最高模式，可能降低刷新率、色深、HDR 或最高分辨率。"
                ) {
                    store.setDSCEnabled(!(display.dscEnabled ?? false))
                }
            }
        }
    }

    private func outputChoice(
        _ title: String,
        value: OutputPreference,
        display: DisplaySnapshot,
        help: String
    ) -> some View {
        let binding = colorBinding(display)
        return SegmentChoiceButton(
            title: title,
            selected: binding.wrappedValue == value,
            help: help
        ) {
            binding.wrappedValue = value
        }
    }

    private func bitDepthChoice(_ depth: Int, display: DisplaySnapshot) -> some View {
        let binding = bitDepthBinding(display)
        let supported = display.linkCapabilities.contains { $0.bitDepth == depth }
        return SegmentChoiceButton(
            title: "\(depth) bit",
            selected: binding.wrappedValue == depth,
            help: bitDepthCapabilityHelp(depth, display: display),
            available: supported
        ) {
            guard supported else { return }
            binding.wrappedValue = depth
        }
    }

    private func colorCapabilityHelp(
        _ preference: OutputPreference,
        display: DisplaySnapshot
    ) -> String {
        let matches = display.linkCapabilities.filter { $0.outputPreference == preference }
        guard !matches.isEmpty else { return "当前显示模式不支持此颜色格式。" }
        return "支持位深：" + capabilityDepthSummary(matches)
    }

    private func bitDepthCapabilityHelp(_ depth: Int, display: DisplaySnapshot) -> String {
        let matches = display.linkCapabilities.filter { $0.bitDepth == depth }
        guard !matches.isEmpty else { return "当前显示模式不支持 \(depth) bit 输出。" }

        var parts: [String] = []
        for hdr in [true, false] {
            let names = Set(matches.filter { $0.hdrEnabled == hdr }.map(\.encodingText))
                .sorted()
                .joined(separator: "、")
            guard !names.isEmpty else { continue }
            parts.append("\(hdr ? "HDR" : "SDR")：\(names)")
        }
        return "支持颜色格式：" + parts.joined(separator: "；")
    }

    private func capabilityDepthSummary(_ capabilities: [DisplayLinkCapability]) -> String {
        var parts: [String] = []
        for hdr in [true, false] {
            let depths = Set(capabilities.filter { $0.hdrEnabled == hdr }.map(\.bitDepth)).sorted()
            guard !depths.isEmpty else { continue }
            let values = depths.map { "\($0) bit" }.joined(separator: "、")
            parts.append("\(hdr ? "HDR" : "SDR")：\(values)")
        }
        return parts.joined(separator: "；")
    }

    @ViewBuilder
    private func modeSection(_ display: DisplaySnapshot) -> some View {
        SettingsGroup(title: "显示模式", isExpanded: $modeSectionExpanded) {
            SettingsRow("输出分辨率", icon: "rectangle.on.rectangle") {
                Picker("", selection: outputResolutionBinding(display)) {
                    ForEach(outputResolutions(display)) { item in
                        Text(item.physicalText).tag(item.id)
                    }
                }
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            SettingsDivider()
            SettingsRow("界面分辨率（HiDPI）", icon: "textformat.size") {
                Picker("", selection: hiDPIBinding(display)) {
                    ForEach(hiDPIResolutions(display)) { item in
                        Text(item.text).tag(item.id)
                    }
                }
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            SettingsDivider()
            SettingsRow("刷新率", icon: "arrow.clockwise") {
                Picker("", selection: refreshBinding(display)) {
                    ForEach(refreshRates(display), id: \.self) { rate in
                        Text(refreshText(rate)).tag(rate)
                    }
                }
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            SettingsDivider()
            EvidenceSignalRow("快速媒体切换（QMS）", qmsAssessment(display), icon: "bolt.horizontal.circle")
        }
    }

    private func qmsAssessment(_ display: DisplaySnapshot) -> SignalValue {
        guard let current = currentMode(display) else {
            return SignalValue(text: "无法评估", verification: .unavailable, source: "当前模式不可用")
        }
        let alternatives = display.modes.filter {
            $0.outputWidth == current.outputWidth && $0.outputHeight == current.outputHeight &&
            $0.width == current.width && $0.height == current.height &&
            abs($0.refreshRate - current.refreshRate) >= 0.01
        }
        guard !alternatives.isEmpty, display.vrrSupported else {
            return SignalValue(
                text: "需要链路重新同步",
                verification: .inferred,
                source: "显示模式表与 VRR 能力",
                detail: "没有保持物理分辨率和 HiDPI 不变的其他刷新率，或当前显示器没有 VRR 模式。"
            )
        }
        return SignalValue(
            text: "具备基础条件（信令未验证）",
            verification: .inferred,
            source: "显示模式表与 VRR 能力",
            detail: "存在相同分辨率与 HiDPI 的其他刷新率，并具有 VRR 模式；尚不能确认 Mac 与接收端已协商 HDMI QMS。"
        )
    }

    private func saveCurrentSettings(_ display: DisplaySnapshot) {
        guard let mode = currentMode(display) else { return }
        preferences.setSavedSettings(
            SavedDisplaySettings(
                outputPreference: display.activeOutputPreference ?? .automatic,
                bitDepth: display.activeBitDepth,
                hdrEnabled: display.hdrEnabled,
                vrrEnabled: display.vrrEnabled,
                dscEnabled: display.dscEnabled,
                brightness: brightness.isAvailable ? brightness.value : nil,
                physicalWidth: mode.outputWidth,
                physicalHeight: mode.outputHeight,
                logicalWidth: mode.width,
                logicalHeight: mode.height,
                refreshRate: mode.refreshRate,
                savedAt: Date()
            ),
            for: display.hardwareKey
        )
    }

    private func applySavedSettings(_ display: DisplaySnapshot) {
        guard let saved = preferences.savedSettings(for: display.hardwareKey) else { return }
        store.applySavedSettings(saved)
        if let savedBrightness = saved.brightness, brightness.isAvailable {
            brightness.set(savedBrightness)
        }
    }

    private func savedSettingsSubtitle(_ display: DisplaySnapshot) -> String {
        guard let saved = preferences.savedSettings(for: display.hardwareKey) else {
            return "未保存预设；打开 Right Display 时只读取当前设置。"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "已保存于 \(formatter.string(from: saved.savedAt))；选择“应用预设”后才会生效。"
    }

    private func currentAspectRatio(_ display: DisplaySnapshot) -> String {
        guard let mode = currentMode(display), mode.outputHeight > 0 else { return "未知" }
        return DisplayResolutionCatalog.aspectRatio(
            width: mode.outputWidth,
            height: mode.outputHeight,
            isBuiltin: display.isBuiltin
        )
    }

    private func colorBinding(_ display: DisplaySnapshot) -> Binding<OutputPreference> {
        Binding(
            get: {
                if let requested = store.requestedOutputPreference { return requested }
                let saved = preferences.correction(for: display.hardwareKey)?.outputPreference ?? .automatic
                if saved == .automatic { return .automatic }
                return display.activeOutputPreference ?? saved
            },
            set: { store.applyOutputColor($0) }
        )
    }

    private func bitDepthBinding(_ display: DisplaySnapshot) -> Binding<Int> {
        Binding(
            get: {
                store.requestedBitDepth
                    ?? display.activeBitDepth
                    ?? display.supportedBitDepths.first
                    ?? 10
            },
            set: { store.applyBitDepth($0) }
        )
    }

    private func outputResolutionBinding(_ display: DisplaySnapshot) -> Binding<String> {
        Binding(
            get: { currentMode(display).map { "\($0.outputWidth)x\($0.outputHeight)" } ?? "" },
            set: { id in
                guard id != currentMode(display).map({ "\($0.outputWidth)x\($0.outputHeight)" }) else {
                    return
                }
                guard let item = outputResolutions(display).first(where: { $0.id == id }) else { return }
                let current = currentMode(display)
                let modes = display.modes.filter {
                    $0.isHiDPI && $0.outputWidth == item.width && $0.outputHeight == item.height
                }
                if let mode = preferredMode(modes, preserving: current) { store.apply(mode) }
            }
        )
    }

    private func hiDPIBinding(_ display: DisplaySnapshot) -> Binding<String> {
        Binding(
            get: { currentMode(display).map { "\($0.width)x\($0.height)" } ?? "" },
            set: { id in
                guard id != currentMode(display).map({ "\($0.width)x\($0.height)" }) else { return }
                guard let item = hiDPIResolutions(display).first(where: { $0.id == id }),
                      let current = currentMode(display) else { return }
                let modes = display.modes.filter {
                    $0.isHiDPI && $0.outputWidth == current.outputWidth &&
                    $0.outputHeight == current.outputHeight &&
                    $0.width == item.width && $0.height == item.height
                }
                if let mode = preferredMode(modes, preserving: current) { store.apply(mode) }
            }
        )
    }

    private func refreshBinding(_ display: DisplaySnapshot) -> Binding<Double> {
        Binding(
            get: { currentMode(display)?.refreshRate ?? 0 },
            set: { rate in
                guard let activeRate = currentMode(display)?.refreshRate,
                      abs(activeRate - rate) >= 0.01 else { return }
                guard let current = currentMode(display),
                      let mode = display.modes.first(where: {
                          $0.isHiDPI && $0.outputWidth == current.outputWidth &&
                          $0.outputHeight == current.outputHeight &&
                          $0.width == current.width && $0.height == current.height &&
                          abs($0.refreshRate - rate) < 0.01
                      }) else { return }
                store.apply(mode)
            }
        )
    }

    private func currentMode(_ display: DisplaySnapshot) -> DisplayModeOption? {
        display.modes.first { $0.selectionKey == display.currentModeKey }
    }

    private func outputResolutions(_ display: DisplaySnapshot) -> [NativeResolution] {
        unique(display.modes.filter(\.isHiDPI).map {
            NativeResolution(width: $0.outputWidth, height: $0.outputHeight)
        })
    }

    private func hiDPIResolutions(_ display: DisplaySnapshot) -> [NativeResolution] {
        guard let current = currentMode(display) else { return [] }
        return unique(display.modes.filter {
            $0.isHiDPI && $0.outputWidth == current.outputWidth && $0.outputHeight == current.outputHeight
        }.map { NativeResolution(width: $0.width, height: $0.height) })
    }

    private func refreshRates(_ display: DisplaySnapshot) -> [Double] {
        guard let current = currentMode(display) else { return [] }
        var seen = Set<Int>()
        return display.modes.filter {
            $0.isHiDPI && $0.outputWidth == current.outputWidth &&
            $0.outputHeight == current.outputHeight &&
            $0.width == current.width && $0.height == current.height
        }.compactMap { mode in
            let key = Int((mode.refreshRate * 100).rounded())
            return seen.insert(key).inserted ? mode.refreshRate : nil
        }.sorted(by: >)
    }

    private func unique(_ values: [NativeResolution]) -> [NativeResolution] {
        Array(Set(values)).sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            return $0.height > $1.height
        }
    }

    private func preferredMode(
        _ modes: [DisplayModeOption],
        preserving current: DisplayModeOption?
    ) -> DisplayModeOption? {
        modes.max { lhs, rhs in
            score(lhs, current) < score(rhs, current)
        }
    }

    private func score(_ mode: DisplayModeOption, _ current: DisplayModeOption?) -> Double {
        guard let current else { return mode.refreshRate }
        var value = mode.refreshRate / 1_000
        if mode.isHiDPI { value += 50 }
        if mode.width == current.width && mode.height == current.height { value += 100 }
        if abs(mode.refreshRate - current.refreshRate) < 0.01 { value += 10 }
        return value
    }

    private func refreshText(_ value: Double) -> String {
        value > 0 ? String(format: "%.0f Hz", value) : "动态"
    }
}

private struct LGTVConnectionGuide: View {
    @ObservedObject var controller: LGTVController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "tv.and.mediabox")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("连接 LG webOS 电视")
                        .font(.title2.weight(.semibold))
                    Text("用于向电视发送相对的音量降低／提高命令。")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("1. 选择连接方式", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                    Picker("", selection: $controller.connectionMode) {
                        ForEach(LGTVConnectionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    if controller.connectionMode == .automatic {
                        automaticControls
                    } else {
                        manualControls
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("2. 在电视上允许连接", systemImage: "checkmark.rectangle.stack")
                        .font(.headline)
                    Text("首次连接时，请在电视弹窗中选择“允许”。如果没有弹窗，请在 LG 设置的“常规 → 外部设备 → 连接移动设备”中启用 LG Connect Apps；部分型号还需要启用“通过 Wi‑Fi 开机”。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            HStack(spacing: 8) {
                statusIcon
                Text(controller.statusText)
                    .foregroundStyle(controller.isConnected ? .primary : .secondary)
                    .lineLimit(2)
                Spacer()
                if controller.isConnected || controller.isPairing {
                    Button("忘记配对并重试") { controller.forgetPairingAndReconnect() }
                    Button("断开") { controller.disconnect() }
                }
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear {
            if controller.connectionMode == .automatic,
               !controller.isConnected,
               !controller.isDiscovering,
               controller.discoveredDevices.isEmpty {
                controller.startDiscovery()
            }
        }
        .onChange(of: controller.connectionMode) { _, mode in
            if mode == .automatic {
                controller.startDiscovery()
            } else {
                controller.stopDiscovery()
            }
        }
    }

    @ViewBuilder
    private var automaticControls: some View {
        HStack(spacing: 8) {
            if controller.discoveredDevices.isEmpty {
                Text(controller.isDiscovering ? "正在搜索同一局域网…" : "尚未发现电视")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("电视", selection: $controller.selectedHost) {
                    ForEach(controller.discoveredDevices) { device in
                        Text("\(device.displayName) · \(device.host)").tag(device.host)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            if controller.isDiscovering {
                ProgressView().controlSize(.small)
            }
            Button("重新搜索") { controller.startDiscovery() }
                .disabled(controller.isDiscovering)
            Button("连接") { controller.connectSelectedDevice() }
                .buttonStyle(.borderedProminent)
                .disabled(controller.selectedHost.isEmpty || controller.isPairing)
        }
    }

    private var manualControls: some View {
        HStack(spacing: 8) {
            TextField("例如 192.168.1.50", text: $controller.host)
                .textFieldStyle(.roundedBorder)
            Button("查找并连接") { controller.connectManualHost() }
                .buttonStyle(.borderedProminent)
                .disabled(controller.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.isPairing)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if controller.isConnected {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if controller.isPairing || controller.isDiscovering {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
    }
}

private struct AppleTVAudioGuide: View {
    @ObservedObject var controller: AppleTVAudioController
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "homepod.2.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("连接 Apple TV／HomePod")
                        .font(.title2.weight(.semibold))
                    Text("连接 Apple TV，并控制它当前使用的 HomePod 或其他默认音频输出。")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("1. 选择 Apple TV", systemImage: "appletv.fill")
                        .font(.headline)
                    HStack(spacing: 8) {
                        if controller.devices.isEmpty {
                            Text(controller.isScanning ? "正在搜索同一局域网…" : "尚未发现 Apple TV")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Picker("Apple TV", selection: $controller.selectedIdentifier) {
                                ForEach(controller.devices) { device in
                                    Text("\(device.name) · \(device.address)").tag(device.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                        if controller.isScanning { ProgressView().controlSize(.small) }
                        Button("重新搜索") { controller.scan() }
                            .disabled(controller.isScanning || controller.isPairing)
                        Button(controller.isConnected ? "重新配对" : "配对") {
                            controller.pairSelected()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.selectedIdentifier.isEmpty || controller.isPairing)
                    }
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("2. 输入电视上的验证码", systemImage: "rectangle.and.pencil.and.ellipsis")
                        .font(.headline)
                    Text("配对开始后，Apple TV 会在电视画面上显示四位验证码。此操作只需进行一次。")
                        .foregroundStyle(.secondary)
                    if controller.awaitsPIN {
                        HStack(spacing: 8) {
                            TextField("四位验证码", text: $pin)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                            Button("提交") {
                                controller.submitPIN(pin)
                                pin = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(pin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            HStack(spacing: 8) {
                if controller.isConnected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if controller.isPairing || controller.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                Text(controller.statusText)
                    .foregroundStyle(controller.isConnected ? .primary : .secondary)
                Spacer()
                if controller.isConnected {
                    Button("刷新音量") { controller.refresh() }
                }
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 580)
        .onAppear {
            if controller.devices.isEmpty { controller.scan() }
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let isExpanded: Binding<Bool>?
    private let content: Content

    init(
        _ title: String,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.isExpanded = isExpanded
        self.content = content()
    }

    init(
        title: String,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, isExpanded: isExpanded, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let isExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                        Spacer()
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            } else {
                Text(title)
                    .font(.headline)
                    .padding(.leading, 10)
            }

            if isExpanded?.wrappedValue ?? true {
                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let icon: String?
    let subtitle: String?
    private let content: Content

    init(
        _ title: String,
        icon: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            compactLayout
        }
        .frame(minHeight: 30)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
    }

    private var horizontalLayout: some View {
        HStack(spacing: 12) {
            rowLabel
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 12)
            content
                .font(.callout)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            rowLabel
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .font(.callout)
            }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 15)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SignalSettingsRow: View {
    let title: String
    let value: String
    let icon: String?

    init(_ title: String, _ value: String, icon: String? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    var body: some View {
        SettingsRow(title, icon: icon) {
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EvidenceSignalRow: View {
    let title: String
    let value: SignalValue
    let icon: String?

    @State private var showingEvidence = false

    init(_ title: String, _ value: SignalValue, icon: String? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    var body: some View {
        SettingsRow(title, icon: icon) {
            HStack(spacing: 6) {
                Text(value.text)
                    .foregroundStyle(.secondary)
                Button {
                    showingEvidence.toggle()
                } label: {
                    Image(systemName: evidenceIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(evidenceColor)
                }
                .buttonStyle(.plain)
                .help(evidenceHelp)
                .popover(isPresented: $showingEvidence, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(value.verificationText, systemImage: evidenceIcon)
                            .font(.headline)
                        Text("来源：\(value.source)")
                            .font(.callout.weight(.medium))
                        if !value.detail.isEmpty {
                            Text(value.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(width: 330, alignment: .leading)
                }
            }
        }
    }

    private var evidenceIcon: String {
        switch value.verification {
        case .verified: "checkmark.seal.fill"
        case .inferred: "waveform.path.ecg"
        case .unavailable: "questionmark.diamond.fill"
        }
    }

    private var evidenceColor: Color {
        switch value.verification {
        case .verified: .green
        case .inferred: .orange
        case .unavailable: .secondary
        }
    }

    private var evidenceHelp: String {
        let detail = value.detail.isEmpty ? "" : "\n\(value.detail)"
        return "\(value.verificationText) · 来源：\(value.source)\(detail)"
    }
}

private struct ExplicitBooleanButton: View {
    let isOn: Bool
    let isEnabled: Bool
    let accessibilityLabel: String
    var hoverHelp: String? = nil
    let action: () -> Void

    var body: some View {
        Toggle("", isOn: Binding(
            get: { isOn },
            set: { newValue in
                guard newValue != isOn else { return }
                action()
            }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
        .help(hoverHelp ?? "")
    }
}

private struct SegmentChoiceButton: View {
    let title: String
    let selected: Bool
    let help: String
    var available = true
    let action: () -> Void

    @State private var showingHoverHelp = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            selected ? Color.accentColor : Color.clear,
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .opacity(available ? 1 : 0.45)
        .help(help)
        .onHover { hovering in
            showingHoverHelp = hovering
        }
        .popover(isPresented: $showingHoverHelp, arrowEdge: .bottom) {
            Text(help)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(width: 280)
        }
        .accessibilityValue(selected ? "已选择" : (available ? "可用" : "不可用"))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
    }
}

private struct OutputConfirmationSheet: View {
    @EnvironmentObject private var store: DisplayStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "display.badge.checkmark")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("保留这组显示设置？")
                    .font(.title3.weight(.semibold))
                Text(store.pendingChangeSummary)
                    .font(.callout.weight(.medium))
                Label(store.pendingVerificationText, systemImage: "checkmark.arrow.trianglehead.counterclockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("如果画面显示异常，Right Display 将在 \(store.confirmationSeconds) 秒后自动恢复原设置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Button("恢复原设置") {
                    store.restorePendingModeIfNeeded()
                }
                .keyboardShortcut(.cancelAction)

                Button("保留设置") {
                    store.confirmPendingMode()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 430, height: 245)
        .interactiveDismissDisabled()
    }
}

private struct NativeResolution: Identifiable, Hashable {
    let width: Int
    let height: Int
    var id: String { "\(width)x\(height)" }
    var text: String { "\(width) × \(height)" }

    var physicalText: String {
        let name: String?
        switch (width, height) {
        case (1920, 1080): name = "1080p"
        case (2560, 1440): name = "2K"
        case (3840, 2160): name = "4K"
        case (4096, 2160): name = "DCI 4K"
        case (7680, 4320): name = "8K"
        default: name = nil
        }
        return name.map { "\($0) / \(width) × \(height)" } ?? "\(width) × \(height)"
    }
}

private struct SystemSizeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DisplayStore
    @EnvironmentObject private var preferences: Preferences

    let display: DisplaySnapshot
    @State private var sizeText: String

    init(display: DisplaySnapshot) {
        self.display = display
        _sizeText = State(initialValue: display.correctedDiagonalInches.map {
            String(format: "%.0f", $0)
        } ?? "")
    }

    var body: some View {
        Form {
            Section("显示器尺寸校正") {
                LabeledContent("系统报告") {
                    Text(display.reportedDiagonalInches.map {
                        String(format: "%.1f 英寸", $0)
                    } ?? "未知")
                }
                TextField("实际对角线尺寸（英寸）", text: $sizeText)
                Picker("常用尺寸", selection: $sizeText) {
                    Text("请选择").tag("")
                    ForEach([42, 48, 55, 65, 77], id: \.self) { size in
                        Text("\(size) 英寸").tag("\(size)")
                    }
                }
            }
            HStack {
                Button("恢复系统值") { save(nil) }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save(Double(sizeText)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(Double(sizeText) == nil)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 430, height: 310)
    }

    private func save(_ size: Double?) {
        let existing = preferences.correction(for: display.hardwareKey)
        preferences.setCorrection(
            DisplayCorrection(
                alias: existing?.alias ?? "",
                diagonalInches: size,
                role: existing?.role ?? .automatic,
                outputPreference: existing?.outputPreference ?? .automatic
            ),
            for: display.hardwareKey
        )
        store.refresh()
        dismiss()
    }
}
