// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import SwiftUI

struct RightDisplayBrandMark: View {
    var size: CGFloat = 30
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "RightDisplay-AppIcon-0.1-Beta-1024",
            withExtension: "png"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DisplayDeviceIcon: View {
    let size: CGFloat
    var glyphFraction: CGFloat = 0.47

    var body: some View {
        Image(systemName: "display")
            .font(.system(size: size * glyphFraction, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.7)
            }
            .accessibilityHidden(true)
    }
}

struct QuickPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: DisplayStore
    @EnvironmentObject private var preferences: Preferences
    @StateObject private var brightness = DisplayBrightnessStore.shared
    @StateObject private var audio = AppleTVAudioController.shared
    @StateObject private var systemAudio = AudioOutputStore.shared
    @State private var showingAutoCorrection = false
    @State private var showingQuitConfirmation = false
    @State private var expandedOutputMenu: String?

    var body: some View {
        VStack(spacing: 0) {

            if let display = store.selectedDisplay {
                VStack(spacing: 12) {
                    if isShowingGuide, preferences.onboardingStep == 0 {
                        guideCallout(
                            title: "看清 Mac 正在输出什么",
                            detail: "先从当前显示器开始：这里集中显示分辨率、刷新率、HiDPI 与接口状态。",
                            icon: "display",
                            actionTitle: "下一步"
                        ) { preferences.onboardingStep = 1 }
                    }
                    if preferences.quickPanelShowsDisplayInfo || isShowingGuide {
                        displaySummary(display)
                            .modifier(GuideTargetHighlight(active: isShowingGuide && preferences.onboardingStep == 0))
                    }
                    if isShowingGuide, preferences.onboardingStep == 1 {
                        guideCallout(
                            title: "直接认识快捷控制",
                            detail: "亮度、音量和显示器功能都在真实面板中；完成引导后可在通用设置中隐藏不需要的模块。",
                            icon: "slider.horizontal.3",
                            actionTitle: "下一步"
                        ) { preferences.onboardingStep = 2 }
                    }
                    if preferences.quickPanelShowsBrightness || preferences.quickPanelShowsVolume || isShowingGuide {
                        levelControls(display)
                            .modifier(GuideTargetHighlight(active: isShowingGuide && preferences.onboardingStep == 1))
                    }
                    if isShowingGuide, preferences.onboardingStep == 2 {
                        guideCallout(
                            title: "认识显示器功能控制",
                            detail: "这里显示颜色格式、色深、HDR 与 VRR 的当前状态。只有你主动选择时，RightDisplay 才会请求改变显示配置。",
                            icon: "waveform.path.ecg",
                            actionTitle: "下一步"
                        ) { preferences.onboardingStep = 3 }
                    }
                    if preferences.quickPanelShowsColorFormat || preferences.quickPanelShowsBitDepth ||
                        preferences.quickPanelShowsHDR || preferences.quickPanelShowsVRR || isShowingGuide {
                        outputStatusAndControls(display)
                            .modifier(GuideTargetHighlight(active: isShowingGuide && preferences.onboardingStep == 2))
                            .disabled(preferences.displayOutputControlsLocked)
                        if preferences.displayOutputControlsLocked {
                            HStack {
                                Label("显示配置已锁定", systemImage: "lock.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("解锁") { preferences.displayOutputControlsLocked = false }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    if isShowingGuide, preferences.onboardingStep == 3 {
                        guideCallout(
                            title: "继续前往高级设置",
                            detail: "点击下方“高级”查看完整状态概览、显示与输出、声音、EDID 和通用设置，然后完成最后一个选择。",
                            icon: "arrow.down",
                            actionTitle: "打开高级设置"
                        ) { AdvancedWindowController.shared.show() }
                    }
                    if let error = store.lastError { quickError(error) }
                }
                .padding(14)
            } else {
                ContentUnavailableView(
                    "没有检测到显示器",
                    systemImage: "display.trianglebadge.exclamationmark",
                    description: Text("连接显示器后会自动刷新。")
                )
                .frame(height: 300)
            }

            Divider().opacity(0.55)
            footer
        }
        .frame(width: 430)
        .background { ActivePopoverMaterial() }
        .tint(.accentColor)
        .environment(\.locale, preferences.appLanguage.locale)
        .onAppear {
            if let display = store.selectedDisplay {
                brightness.selectDisplay(display.id)
                EDIDStore.shared.refresh(for: display)
            }
            audio.resume()
            systemAudio.refresh()
        }
        .onChange(of: store.selectedDisplayID) { _, displayID in
            brightness.selectDisplay(displayID)
            if let display = store.selectedDisplay { EDIDStore.shared.refresh(for: display) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoCorrectionProcessRequested)) { _ in
            showingAutoCorrection = true
        }
        .sheet(isPresented: $showingAutoCorrection) {
            AutoCorrectionProcessView()
                .environmentObject(store)
        }
        .sheet(isPresented: Binding(get: { store.pendingModeConfirmation }, set: { _ in })) {
            DisplayConfirmationView()
                .environmentObject(store)
                .interactiveDismissDisabled()
        }
        .alert("退出 Right Display？", isPresented: $showingQuitConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { NSApp.terminate(nil) }
        } message: {
            Text("这会退出整个 App，而不只是关闭快捷面板。")
        }
    }

    private var isShowingGuide: Bool { !preferences.onboardingCompleted }

    private func guideCallout(
        title: String,
        detail: String,
        icon: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Color.accentColor)
                Text(AppLocalization.string(title)).font(.headline)
                Spacer()
                Text(AppLocalization.format("第 %d 步，共 4 步", min(preferences.onboardingStep + 1, 4)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(AppLocalization.string(detail))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Image(systemName: "arrow.down").foregroundStyle(Color.accentColor)
                Spacer()
                if preferences.onboardingStep > 0 {
                    Button("上一步") { preferences.onboardingStep -= 1 }
                }
                Button(AppLocalization.string(actionTitle), action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor.opacity(0.35)) }
    }

    private func displaySummary(_ display: DisplaySnapshot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if store.displays.count > 1 {
                    NativeSelectionPicker(
                        options: store.displays.map { .init(id: String($0.id), title: $0.name) },
                        selectedID: String(display.id), fallbackTitle: display.name
                    ) { id in
                        if let item = store.displays.first(where: { String($0.id) == id }) {
                            store.selectDisplay(item.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help("选择要查看和控制的显示器")
                } else {
                    HStack(spacing: 7) {
                        Text(display.name).font(.title3.weight(.semibold))
                        Label(AppLocalization.string(store.selectedInterfaceName.replacingOccurrences(of: "（推断）", with: "")), systemImage: "cable.connector")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if store.selectedInterfaceName.contains("（推断）") { Text(AppLocalization.string("推断")).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                HStack(spacing:7) {
                    Circle().fill(display.refreshRate.verification == .unavailable || display.refreshRate.text.contains("未知") ? Color.gray : Color.green).frame(width:6,height:6).accessibilityHidden(true)
                    Text("\(display.resolution)  ·  \(display.refreshRate.text)")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                }
                Text("HiDPI \(display.logicalResolution)  ·  \(AppLocalization.string(display.sizeText))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DisplayDeviceIcon(size: 47, glyphFraction: 0.57)
        }
        .padding(13)
        .modifier(QuickGlass(shape: RoundedRectangle(cornerRadius: QuickPanelGeometry.sectionRadius, style: .continuous)))
    }

    private func levelControls(_ display: DisplaySnapshot) -> some View {
        VStack(spacing: 0) {
            if preferences.quickPanelShowsBrightness || isShowingGuide {
                brightnessControl(display)
            }
            if (preferences.quickPanelShowsBrightness && preferences.quickPanelShowsVolume) || isShowingGuide {
                Divider().padding(.leading, 30)
            }
            if preferences.quickPanelShowsVolume || isShowingGuide {
                audioControl
            }
        }
        .padding(.horizontal, 12)
        .modifier(QuickGlass(shape: RoundedRectangle(cornerRadius: QuickPanelGeometry.sectionRadius, style: .continuous)))
    }

    private func brightnessControl(_ display: DisplaySnapshot) -> some View {
        controlRow(title: "亮度", icon: "sun.max") {
            if brightness.isAvailable {
                Slider(value: Binding(
                    get: { brightness.value },
                    set: { brightness.set($0,source:"quick-brightness") }
                ), in: 0...1, onEditingChanged: brightness.editingChanged)
                .background(BrightnessWarningAnchor(brightness:brightness.value,sequence:brightness.warningSequence,source:brightness.warningSource,controlID:"quick-brightness"))
                .accessibilityLabel("屏幕亮度")
                Text("\(Int((brightness.value * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            } else {
                Spacer()
                Text("不可用").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var audioControl: some View {
        if systemAudio.selectedControlTargetID == AudioOutputStore.appleTVTargetID {
            if audio.volumeControlAvailable, let volume = audio.volume {
                controlRow(title: "音量", icon: "homepod.2.fill") {
                    Slider(
                        value: Binding(get: { audio.requestedVolume ?? audio.volume ?? volume }, set: { audio.setVolume($0) }),
                        in: 0...100,
                        onEditingChanged: playVolumeConfirmationWhenFinished
                    )
                    .accessibilityLabel("Apple TV 默认音频输出音量")
                    Text("\(Int((audio.requestedVolume ?? volume).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            } else {
                unavailableAudioControl(audio.isBusy
                    ? "Apple TV 音量控制正在连接…"
                    : audio.statusText)
            }
        } else if let output = systemAudio.selectedAudioDevice,
                  output.systemVolumeWritable,
                  let volume = output.volume {
            controlRow(title: "音量", icon: "speaker.wave.2.fill") {
                Slider(value: Binding(
                    get: { systemAudio.selectedAudioDevice?.volume ?? volume },
                    set: { systemAudio.setVolume($0) }
                ), in: 0...1, onEditingChanged: playVolumeConfirmationWhenFinished)
                .accessibilityLabel("音响音量")
                Text("\(Int((volume * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        } else {
            unavailableAudioControl("所选设备不支持 Mac 音量控制")
        }
    }

    private func unavailableAudioControl(_ message: String) -> some View {
        controlRow(title: "音量", icon: "speaker.slash") {
            Spacer()
            Text(AppLocalization.string(message))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func outputStatusAndControls(_ display: DisplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if preferences.quickPanelShowsColorFormat || isShowingGuide {
                outputMenuRow(
                title: "颜色格式",
                value: display.pixelFormatSignal.text,
                icon: "paintpalette",
                verification: display.pixelEncoding.verification,
                status: display.pixelFormatIndicator
            ) {
                ForEach(DisplayEncodingOptions.choices(for: display)) { choice in
                    outputChoice(choice.title, selected: display.activeRawPixelEncoding == choice.raw, alignedEncoding: true) {
                        store.applyOutputEncoding(choice.raw)
                    }
                }
                }
            }

            if preferences.quickPanelShowsBitDepth || isShowingGuide {
                outputMenuRow(
                title: "色深",
                value: display.bitDepth.text,
                icon: "circle.lefthalf.filled",
                verification: display.bitDepth.verification
            ) {
                ForEach([8, 10, 12], id: \.self) { depth in
                    outputChoice("\(depth) bit", selected: display.activeBitDepth == depth) {
                        store.applyBitDepth(depth)
                    }
                }
                }
            }

            if (preferences.quickPanelShowsHDR || isShowingGuide), display.hdrIsSystemManaged {
                outputManagedStatusRow(
                    title: "高动态范围",
                    value: display.hdr.text,
                    icon: "sun.max.fill",
                    verification: display.hdr.verification,
                    status: display.hdrIndicator,
                    trailing: "系统自动"
                )
            } else if preferences.quickPanelShowsHDR || isShowingGuide {
                outputActionRow(
                    title: "高动态范围",
                    value: display.hdr.text,
                    icon: "sun.max.fill",
                    verification: display.hdr.verification,
                    status: display.hdrIndicator,
                    isOn: display.hdrEnabled ?? false,
                    supported: display.hdrSupported,
                    interactive: true,
                    applying: store.applyingFeature == .hdr
                ) { store.setHDREnabled(!(display.hdrEnabled ?? false)) }
            }

            if preferences.quickPanelShowsVRR || isShowingGuide {
                outputActionRow(
                    title: "可变刷新率",
                    value: display.vrr.text,
                    icon: "speedometer",
                    verification: display.vrr.verification,
                    status: display.vrrIndicator,
                    isOn: display.vrrEnabled,
                    supported: display.vrrSupported,
                    interactive: true,
                    applying: store.applyingFeature == .vrr
                ) { store.setVRREnabled(!display.vrrEnabled) }
            }
        }
        .padding(12)
        .modifier(QuickGlass(shape: RoundedRectangle(cornerRadius: QuickPanelGeometry.sectionRadius, style: .continuous)))
    }

    private func outputMenuRow<Content: View>(
        title: String,
        value: String,
        icon: String,
        verification: Verification,
        status: DisplayStatusIndicator? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    expandedOutputMenu = expandedOutputMenu == title ? nil : title
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppLocalization.string(title)).font(.callout.weight(.semibold))
                        HStack(spacing: 8) {
                            verificationDot(verification, status: status)
                            Text(AppLocalization.string(value))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colorScheme == .dark ? Color.secondary : Color.primary.opacity(0.38))
                        .rotationEffect(.degrees(expandedOutputMenu == title ? 180 : 0))
                }
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, minHeight: RightDisplayUI.quickRowHeight)
                .contentShape(RoundedRectangle(cornerRadius: QuickPanelGeometry.nestedRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string(title))
            .accessibilityValue(value)
            .help(AppLocalization.format("选择%@", AppLocalization.string(title)))
            if expandedOutputMenu == title {
                Divider().padding(.horizontal, 12)
                VStack(spacing: 0, content: content)
                    .padding(.vertical, 4)
                    .background(
                        Color.primary.opacity(0.018),
                        in: RoundedRectangle(cornerRadius: QuickPanelGeometry.optionsRadius, style: .continuous)
                    )
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .modifier(QuickGlass(shape: RoundedRectangle(cornerRadius: QuickPanelGeometry.nestedRadius, style: .continuous), functionSurface: true))
    }

    private func outputChoice(_ title: String, selected: Bool, alignedEncoding: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            expandedOutputMenu = nil
            action()
        } label: {
            HStack {
                if alignedEncoding {
                    let parts = title.split(separator: " ", maxSplits: 1).map(String.init)
                    HStack(spacing: 8) {
                        Text(parts.first ?? title)
                            .frame(width: ceil(NSAttributedString(string: "YCbCr", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).size().width), alignment: .leading)
                        Text(parts.count > 1 ? parts[1] : "")
                    }.font(.callout.weight(selected ? .semibold : .regular))
                } else {
                    Text(AppLocalization.string(title))
                        .font(.callout.weight(selected ? .semibold : .regular))
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 32)
            .modifier(RowHoverBackground(radius: QuickPanelGeometry.selectedRadius,
                selected: selected, hoverColor: .primary, hoverOpacity: 0.025))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .contentShape(RoundedRectangle(cornerRadius: QuickPanelGeometry.selectedRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func outputActionRow(
        title: String,
        value: String,
        icon: String,
        verification: Verification,
        status: DisplayStatusIndicator,
        isOn: Bool,
        supported: Bool,
        interactive: Bool,
        applying: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLocalization.string(title)).font(.callout.weight(.semibold))
                    HStack(spacing: 8) {
                        verificationDot(verification, status: status)
                        Text(AppLocalization.string(value))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if applying {
                    ProgressView().controlSize(.small)
                } else {
                    Toggle("", isOn: Binding(get: { isOn }, set: { _ in action() }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!interactive)
                        .accessibilityLabel(AppLocalization.format("%@：%@", AppLocalization.string(title), AppLocalization.string(isOn ? "关闭" : "开启")))
                }
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: RightDisplayUI.quickRowHeight,
                   maxHeight: RightDisplayUI.quickRowHeight)
            .contentShape(RoundedRectangle(cornerRadius: QuickPanelGeometry.nestedRadius, style: .continuous))
        .opacity(interactive ? 1 : 0.52)
        .modifier(QuickGlass(shape: RoundedRectangle(cornerRadius: QuickPanelGeometry.nestedRadius, style: .continuous), functionSurface: true))
        .help(interactive
              ? (applying
                 ? AppLocalization.format("正在应用并复读 %@ 状态", AppLocalization.string(title))
                 : AppLocalization.string("使用右侧开关尝试切换，并以系统复读结果为准"))
              : AppLocalization.string("当前项目由系统管理"))
        .accessibilityLabel(AppLocalization.string(title))
        .accessibilityValue(AppLocalization.format("%@，%@", AppLocalization.string(value), AppLocalization.string(isOn ? "已开启" : "已关闭")))
    }

    private func outputManagedStatusRow(
        title: String,
        value: String,
        icon: String,
        verification: Verification,
        status: DisplayStatusIndicator,
        trailing: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalization.string(title)).font(.callout.weight(.semibold))
                HStack(spacing: 8) {
                    verificationDot(verification, status: status)
                    Text(AppLocalization.string(value)).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(AppLocalization.string(trailing))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: RightDisplayUI.quickRowHeight,
               maxHeight: RightDisplayUI.quickRowHeight)
        .modifier(QuickGlass(shape: RoundedRectangle(cornerRadius: QuickPanelGeometry.nestedRadius, style: .continuous), functionSurface: true))
        .help(AppLocalization.string("内置屏的 HDR / EDR 由 macOS 按内容和参考模式自动管理"))
        .accessibilityLabel(AppLocalization.string(title))
        .accessibilityValue(AppLocalization.format("%@，由系统自动管理", AppLocalization.string(value)))
    }

    private func verificationDot(_ verification: Verification, status: DisplayStatusIndicator? = nil) -> some View {
        Circle()
            .fill(status?.color ?? (verification == .verified || verification == .slsReported ? Color.green : (verification == .inferred ? Color.orange : Color.secondary)))
            .frame(width: 6, height: 6)
            .help(AppLocalization.string(verification == .verified || verification == .slsReported ? "系统报告；不代表物理接收端验证" : verification == .inferred ? "由系统信息推断" : "当前不可验证"))
    }

    private func featureStatusDot(isOn: Bool, supported: Bool, title: String) -> some View {
        let color: Color = isOn && supported ? .green : .gray
        let localizedTitle = AppLocalization.string(title)
        let explanation = !supported
            ? AppLocalization.format("当前显示模式不支持%@", localizedTitle)
            : (isOn ? AppLocalization.format("%@已启用", localizedTitle)
                : AppLocalization.format("支持%@，当前未启用", localizedTitle))
        return Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay { Circle().strokeBorder(Color.white.opacity(0.50), lineWidth: 0.5) }
            .shadow(color: color.opacity(0.35), radius: 2.5)
            .help(AppLocalization.string(explanation))
            .accessibilityLabel(AppLocalization.string(explanation))
    }

    private func quickError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(AppLocalization.string(message)).font(.caption).lineLimit(store.linkAlternative == nil ? 2 : nil)
            Spacer(minLength: 4)
            Button { store.clearLastError() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        }
            if store.linkAlternative != nil {
                Button(store.alternativeButtonTitle) { store.applyOfferedAlternative() }
                    .disabled(!store.alternativeReady)
            }
        }
        .padding(10)
        .modifier(QuickGlass(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)))
    }

    private func controlRow<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 18)
            Text(AppLocalization.string(title))
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .frame(width: 82, alignment: .leading)
            content()
        }
        .padding(.vertical, 11)
    }

    private func playVolumeConfirmationWhenFinished(_ editing: Bool) {
        if !editing {
            DiagnosticEvents.record("quick-control", "volume.drag.finished", method: "slider", result: "write requested; readback pending")
            NSSound(named: NSSound.Name("Tink"))?.play()
        }
    }

    private var footer: some View {
        HStack {
            Button("高级") {
                AdvancedWindowController.shared.show()
            }
            .buttonStyle(.plain)
            .fontWeight(.medium)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .modifier(QuickGlass(shape: Capsule()))
            Spacer()
            Button("退出") { showingQuitConfirmation = true }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
    }
}

private struct GuideTargetHighlight: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: QuickPanelGeometry.sectionRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(active ? 0.85 : 0), lineWidth: 2)
                    .shadow(color: Color.accentColor.opacity(active ? 0.28 : 0), radius: 7)
            }
            .animation(.easeInOut(duration: 0.2), value: active)
    }
}

struct AutoCorrectionProcessView: View {
    @EnvironmentObject private var store: DisplayStore
    @Environment(\.dismiss) private var dismiss

    private var plan: AutoCorrectionPlan? { store.currentAutoCorrectionPlan }
    private var isRunning: Bool {
        store.autoCorrectionStage == .inspecting ||
        store.autoCorrectionStage == .applying ||
        store.autoCorrectionStage == .verifying
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("自动校正颜色模式").font(.title3.weight(.semibold))
                    Text("检查可用链路、执行切换，并读取系统结果进行验证。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                processRow("当前链路", value: plan?.current ?? "正在读取…", icon: "cable.connector")
                Divider().padding(.leading, 32)
                processRow("建议目标", value: plan?.target ?? "正在分析…", icon: "arrow.right.circle")
                Divider().padding(.leading, 32)
                processRow(store.autoCorrectionStage.title,
                           value: store.autoCorrectionDetail.isEmpty ? (plan?.explanation ?? "等待执行") : store.autoCorrectionDetail,
                           icon: stageIcon)
            }
            .padding(.horizontal, 12)
            .modifier(UnifiedGlassSurface(shape: RoundedRectangle(cornerRadius: 15, style: .continuous)))

            HStack {
                if store.pendingModeConfirmation {
                    Button("恢复原设置") { store.restorePendingModeIfNeeded() }
                    Spacer()
                    Text(AppLocalization.format("%lld 秒后自动恢复", Int64(store.confirmationSeconds)))
                        .font(.caption).foregroundStyle(.secondary)
                    Button("保留设置") { store.confirmPendingMode() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.linkVerificationComplete)
                } else {
                    Button("关闭") { dismiss() }
                    Spacer()
                    if store.autoCorrectionStage == .failed || store.autoCorrectionStage == .completed {
                        Button("重新检查") { _ = store.autoCorrectionPlan() }
                    }
                    if !isRunning, plan?.canApply == true, store.autoCorrectionStage != .completed {
                        Button("执行自动校正") { store.autoCorrect() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear {
            if store.currentAutoCorrectionPlan == nil && !isRunning {
                _ = store.autoCorrectionPlan()
            }
        }
    }

    private var stageIcon: String {
        switch store.autoCorrectionStage {
        case .idle: "pause.circle"
        case .inspecting: "magnifyingglass.circle"
        case .applying: "arrow.triangle.2.circlepath.circle"
        case .verifying: "checkmark.circle.badge.questionmark"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func processRow(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalization.string(title)).font(.callout.weight(.medium))
                Text(AppLocalization.string(value)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isRunning && title == store.autoCorrectionStage.title {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 11)
    }
}

private enum QuickPanelGeometry {
    static let sectionRadius: CGFloat = 21
    static let nestedRadius: CGFloat = 14
    static let optionsRadius: CGFloat = 11
    static let selectedRadius: CGFloat = 9
}

private struct QuickGlass<S: Shape>: ViewModifier {
    let shape: S
    var functionSurface = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    @ViewBuilder func body(content: Content) -> some View {
        content.background {
            Color.clear.modifier(UnifiedGlassSurface(shape: shape, lightweight: functionSurface))
            .overlay {
                shape.fill(Color.primary.opacity(hovering ? 0.022 : 0)).allowsHitTesting(false)
            }
            .overlay {
                shape.stroke(Color(nsColor: .separatorColor).opacity(reduceTransparency ? 1 : (hovering ? 0.30 : (functionSurface ? 0.10 : 0.18))), lineWidth: reduceTransparency ? 1 : 0.65)
                    .allowsHitTesting(false)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .allowsHitTesting(false)
        }
        .onHover { inside in
            guard hovering != inside else { return }
            hovering = inside
        }
    }
}

private struct ActivePopoverMaterial: NSViewRepresentable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = reduceTransparency ? .windowBackground : .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = reduceTransparency ? .windowBackground : .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.isEmphasized = true
    }
}
