// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: DisplayStore
    @EnvironmentObject private var preferences: Preferences
    @StateObject private var brightness = DisplayBrightnessStore.shared
    @StateObject private var appleTV = AppleTVAudioController.shared
    @StateObject private var audioOutput = AudioOutputStore.shared
    @StateObject private var edid = EDIDStore.shared
    @State private var page: AdvancedPage? = .overview
    @AppStorage("advancedSidebarCollapsed") private var sidebarCollapsed = false
    @State private var navigationTarget: SettingsTarget?
    @State private var highlightedTarget: SettingsTarget?
    @State private var showingIdentityEditor = false
    @State private var showingAutoCorrection = false
    @State private var showingReleaseNotes = false
    @State private var capabilityTestDetailsExpanded = false
    @State private var showingCapabilityTestConfirmation = false
    @State private var pendingVerifiedLink: ValidatedLinkMode?
    @State private var launchesAtLogin = false
    @State private var appleTVPIN = ""
    @State private var showingQuickControlManagement = false
    @State private var hoveredSidebarPage: AdvancedPage?

    var body: some View {
        HStack(spacing: 0) {
            customSidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.clear)
        }
        .frame(
            minWidth: AppLocalization.isEnglish ? 900 : 820,
            idealWidth: AppLocalization.isEnglish ? 1040 : 980,
            maxWidth: .infinity,
            minHeight: 540,
            idealHeight: 800,
            maxHeight: .infinity
        )
        .onAppear {
            if let d = store.selectedDisplay { brightness.selectDisplay(d.id) }
            appleTV.resume()
            audioOutput.refresh()
            launchesAtLogin = SMAppService.mainApp.status == .enabled
            if let d = store.selectedDisplay { edid.refresh(for: d) }
        }
        .onChange(of: store.selectedDisplayID) { _, id in
            brightness.selectDisplay(id)
            if let d = store.selectedDisplay { edid.refresh(for: d) }
        }
        .onChange(of: page) { _, selected in
            DiagnosticEvents.record("ui", "advanced.page", target: selected?.rawValue)
        }
        .onChange(of: appleTV.selectedIdentifier) { _, _ in appleTVPIN = "" }
        .alert("无法应用设置", isPresented: errorBinding) {
            if store.linkAlternative != nil {
                Button(store.alternativeButtonTitle) { store.applyOfferedAlternative() }
                    .disabled(!store.alternativeReady)
                Button("取消", role: .cancel) { store.clearLastError() }
            } else {
                Button("好") { store.clearLastError() }
            }
        } message: { Text(AppLocalization.string(store.lastError ?? "未知错误")) }
        .alert("显示链路测试", isPresented: $showingCapabilityTestConfirmation) {
            Button("取消", role: .cancel) {}
            Button("开始链路测试") {
                capabilityTestDetailsExpanded = false
                store.startCapabilityTest()
            }
        } message: {
            Text("RightDisplay 将在当前实际输出 timing 下切换颜色格式、色深与 HDR/SDR 环境。显示器可能短暂黑屏或重新连接，完成后将自动恢复测试前设置。")
        }
        .alert("套用已验证链路", isPresented: Binding(
            get: { pendingVerifiedLink != nil },
            set: { if !$0 { pendingVerifiedLink = nil } }
        )) {
            Button("取消", role: .cancel) { pendingVerifiedLink = nil }
            Button("继续套用") {
                if let mode = pendingVerifiedLink {
                    store.applySessionStableMode(mode)
                }
                pendingVerifiedLink = nil
            }
        } message: {
            Text("切换颜色格式或色深会触发显示链路重新协商。显示器可能短暂黑屏或重新连接，HDR 状态也可能同时发生变化。")
        }
        .sheet(isPresented: $showingIdentityEditor) {
            if let display = store.selectedDisplay {
                IdentityEditor(display: display).environmentObject(store).environmentObject(preferences)
            }
        }
        .sheet(isPresented: $showingAutoCorrection) {
            AutoCorrectionProcessView().environmentObject(store)
        }
        .sheet(isPresented: $showingReleaseNotes) {
            ReleaseHistoryView()
        }
        .sheet(isPresented: $showingQuickControlManagement) {
            quickControlManagementSheet
                .environment(\.locale, preferences.appLanguage.locale)
        }
        .sheet(isPresented: onboardingCompletionBinding) {
            onboardingCompletion
        }
        .sheet(isPresented: linkTransactionPanelBinding) {
            DisplayConfirmationView()
                .environmentObject(store)
                .interactiveDismissDisabled()
        }
        .tint(.accentColor)
        .background(AdvancedWindowMaterial())
        .environment(\.locale, preferences.appLanguage.locale)
    }

    private var customSidebar: some View {
        VStack(spacing: 6) {
            ForEach(AdvancedPage.allCases) { item in
                Button {
                    page = item
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.icon).font(.system(size: 15, weight: .medium)).frame(width: 22)
                        if !sidebarCollapsed { Text(AppLocalization.string(item.title)); Spacer() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .padding(.horizontal, sidebarCollapsed ? 9 : 11)
                    .background(
                        Color.primary.opacity(page == item ? 0.065 : (hoveredSidebarPage == item ? 0.025 : 0)),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredSidebarPage = $0 ? item : nil }
                .help(AppLocalization.string(item.title))
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 8) {
                if !sidebarCollapsed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Right Display").font(.caption.weight(.semibold))
                        Text(RightDisplayReleaseHistory.currentVersion).font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { sidebarCollapsed.toggle() } label: {
                    Image(systemName: sidebarCollapsed ? "sidebar.right" : "sidebar.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(AppLocalization.string(sidebarCollapsed ? "展开侧边栏" : "收起侧边栏"))
            }
        }
        .padding(12)
        .frame(width: sidebarCollapsed ? 62 : 180)
        .modifier(FrostedSidebarSurface())
        .animation(.easeInOut(duration: 0.18), value: sidebarCollapsed)
    }

    @ViewBuilder private var detail: some View {
        if let display = store.selectedDisplay {
            GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(page ?? .overview)
                        Group { switch page ?? .overview {
                        case .overview: overview(display)
                        case .displayOutput: displayOutput(display)
                        case .sound: sound(display)
                        case .edid: edidPage(display)
                        case .colorProfiles: ColorProfilesView(display:display)
                        case .general: general(display)
                        } }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    .frame(width:AdvancedPageGeometry.contentWidth(viewport:viewport.size.width),alignment:.leading)
                    .padding(AdvancedPageGeometry.margin)
                    .frame(width:AdvancedPageGeometry.documentWidth(viewport:viewport.size.width),alignment:.leading)
                    .frame(width:viewport.size.width,alignment:.leading)
                    .background(StablePageScrollGutter())
                }
                .scrollIndicators(.visible)
                .id(page ?? .overview)
                .onChange(of: navigationTarget) { _, target in
                    guard let target else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            }
            }
        } else {
            ContentUnavailableView("没有检测到显示器", systemImage: "display.trianglebadge.exclamationmark")
        }
    }

    private func header(_ page: AdvancedPage) -> some View {
        HStack(spacing: 14) {
            Image(systemName: page.icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.string(page.title)).font(.title2.weight(.semibold))
                Text(AppLocalization.string(page.subtitle)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
    }

    private func overview(_ d: DisplaySnapshot) -> some View {
        VStack(spacing: RightDisplayUI.overviewGridSpacing) {
            OverviewHeroCard {
                HStack(spacing: 14) {
                    DisplayDeviceIcon(size: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Text(d.name)
                                .font(.system(size: 18, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button { showingIdentityEditor = true } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("编辑显示名称与尺寸")
                        }
                        Text("\(d.resolution) · \(d.refreshRate.text)")
                            .font(.system(size: 15, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Text("HiDPI \(d.logicalResolution)").lineLimit(1)
                            Text(AppLocalization.string(d.sizeText)).lineLimit(1)
                            Label(AppLocalization.string(store.selectedInterfaceName.replacingOccurrences(of: "（推断）", with: "")), systemImage: "cable.connector")
                                .lineLimit(1)
                                .help(AppLocalization.format("当前连接方式：%@", AppLocalization.string(store.selectedInterfaceName)))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NativeSelectionPicker(
                        options: store.displays.map { .init(id: String($0.id), title: $0.name) },
                        selectedID: String(d.id), fallbackTitle: d.name
                    ) { id in
                        if let display = store.displays.first(where: { String($0.id) == id }) {
                            store.selectedDisplayID = display.id
                        }
                    }
                    .accessibilityLabel("选择显示器")
                }
            }
            LazyVGrid(columns:[GridItem(.flexible(minimum:0),spacing:RightDisplayUI.overviewGridSpacing), GridItem(.flexible(minimum:0))],
                      alignment:.leading,spacing:RightDisplayUI.overviewGridSpacing) {
                    evidence("连接方式", connectionSummary(d), "cable.connector")
                    evidence("像素格式", d.pixelFormatSignal, "paintpalette", stateColor: d.pixelFormatIndicator.color, destination: .pixelFormat)
                    evidence("色深", d.bitDepth, "circle.lefthalf.filled", destination: .bitDepth)
                    evidence("HDR", d.hdr, "sun.max.fill",
                        stateColor: d.hdrIndicator.color, destination: .hdr)
                    evidence("刷新率", overviewRefreshSignal(d), "speedometer",
                        stateColor: overviewRefreshText(d).value.contains("未知") ? .gray : .green, destination: .refreshRate,
                        detailText: overviewRefreshText(d).status)
                    evidence("DSC", d.dsc, "rectangle.compress.vertical",
                        stateColor: d.dscEnabled == true ? .green : .gray, destination: .dsc)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func displayOutput(_ d: DisplaySnapshot) -> some View {
        let linkControlsBusy = !store.linkVerificationComplete || store.capabilityTestStage.isRunning
        return VStack(spacing: 14) {
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "sun.max")
                        .font(.system(size: RightDisplayUI.cardIconFontSize, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: RightDisplayUI.cardIconSize, height: RightDisplayUI.cardIconSize)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("屏幕亮度").font(.headline)
                        Text(AppLocalization.string("使用 macOS 提供的当前显示器亮度控制。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if brightness.isAvailable {
                        levelControl(
                            value: Binding(get: { brightness.value }, set: { brightness.set($0,source:"advanced-brightness") }),
                            in: 0...1,
                            percent: Int((brightness.value * 100).rounded()),
                            accessibilityLabel: "屏幕亮度",
                            onEditingChanged: brightness.editingChanged
                        )
                            .background(BrightnessWarningAnchor(brightness:brightness.value,sequence:brightness.warningSequence,source:brightness.warningSource,controlID:"advanced-brightness"))
                            .help("使用 macOS 当前显示器可用的原生亮度控制。")
                    } else { Text(AppLocalization.string(brightness.statusText)).foregroundStyle(.secondary) }
                }
                .frame(minHeight: 46)
            }

            GlassCard(title: "显示模式", subtitle: "显示器分辨率用于模式选择；HiDPI 决定界面缩放大小。", icon:"rectangle.3.group") {
                settingRow("显示器分辨率", "display", target: .displayMode) { modePicker(outputResolutionBinding(d), outputResolutions(d), physical: true) }
                Divider()
                settingRow("界面分辨率（HiDPI）", "rectangle.inset.filled") {
                    modePicker(hiDPIBinding(d), hiDPIResolutions(d), physical: false)
                }
                Divider()
                settingRow("刷新率", "arrow.clockwise", target: .refreshRate) {
                    refreshPicker(d)
                }
            }.disabled(preferences.displayOutputControlsLocked || linkControlsBusy)
            Text("切换后会出现确认倒计时；如果画面异常或没有确认，将自动恢复原设置。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6)
            GlassCard(title: "颜色输出", subtitle: "颜色格式与色深必须同时受 Mac、线缆和显示器支持。", icon:"slider.horizontal.3") {
                if d.activeRawPixelEncoding == nil || d.activeBitDepth == nil {
                    Text(AppLocalization.string("未取得系统报告的完整连接状态。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                settingRow("颜色格式", "paintpalette", target: .pixelFormat) {
                    LiquidChoiceControl(
                        choices: DisplayEncodingOptions.choices(for: d).map { ($0.title, $0.raw) },
                        selection: encodingBinding(d)
                    ).frame(minWidth: 360, idealWidth: 460, maxWidth: 460)
                }
                Divider()
                settingRow("色深", "circle.lefthalf.filled", target: .bitDepth) {
                    LiquidChoiceControl(
                        choices: [("8 bit", 8), ("10 bit", 10), ("12 bit", 12)],
                        selection: bitDepthBinding(d)
                    ).frame(minWidth: 210, idealWidth: 270, maxWidth: 270)
                }
                if !d.linkCapabilities.isEmpty {
                    Divider()
                    settingRow("连接组合", "cable.connector") {
                        Menu {
                            ForEach(d.linkCapabilities.sorted(by: capabilitySort), id: \.self) { candidate in
                                Button("\(candidate.encodingText) · \(candidate.bitDepth) bit · \(candidate.identity?.rangeText ?? "Unknown") · \(candidate.identity?.eotfText ?? "Unknown")") {
                                    store.applyLinkCapability(candidate, source: "COMPLETE_CANDIDATE")
                                }.disabled(candidate.identity?.isKnown != true)
                            }
                        } label: { Text("选择系统枚举组合") }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }.disabled(preferences.displayOutputControlsLocked || linkControlsBusy)
            GlassCard(title: "动态与带宽", subtitle: "HDR、VRR 与 DSC 可能触发链路重新协商。", icon:"waveform.path") {
                if d.hdrIsSystemManaged {
                    settingRow("高动态范围（HDR）", "sun.max.fill", target: .hdr) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("系统自动管理").font(.callout.weight(.medium))
                            Text(AppLocalization.string(d.hdr.text)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("内置屏的 HDR / EDR 会随内容、供电状态和参考模式动态变化，无需手动开关。")
                        .font(.caption).foregroundStyle(.secondary).padding(.leading, 31)
                } else {
                    switchRow("高动态范围（HDR）", "扩展亮度与色彩范围。", "sun.max.fill", d.hdrEnabled ?? false, d.hdrEnabled != nil, target: .hdr, applying: store.applyingFeature == .hdr) { store.setHDREnabled(!(d.hdrEnabled ?? false)) }
                }
                Divider()
                switchRow("可变刷新率（VRR）", "使刷新率随画面变化，减少撕裂。", "speedometer", d.vrrEnabled, d.vrrStateKnown, target: .vrr, applying: store.applyingFeature == .vrr) { store.setVRREnabled(!d.vrrEnabled) }
                Divider()
                switchRow("显示流压缩（DSC）", "通过模式选择促使 macOS 重新协商压缩状态；切换可能短暂黑屏。", "rectangle.compress.vertical", d.dscEnabled ?? false, d.dscSupported, target: .dsc, applying: store.applyingFeature == .dsc) { store.setDSCEnabled(!(d.dscEnabled ?? false)) }
            }.disabled(preferences.displayOutputControlsLocked || linkControlsBusy)
            GlassCard {
                switchRow("配置保护", "保护高级设置和快捷面板中的显示配置；亮度与音量仍可调整。", "lock", preferences.displayOutputControlsLocked, true) {
                    preferences.displayOutputControlsLocked.toggle()
                }
            }
            capabilityMatrix(d)
        }
    }

    private func capabilityMatrix(_ d: DisplaySnapshot) -> some View {
        let testRunning = store.capabilityTestStage.isRunning
        let eligibility = store.capabilityTestEligibility(for: d)
        let verifiedModes = deduplicatedCapabilityModes(store.capabilityTestSessionStableModes)
        return GlassCard {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName:"checkmark.shield")
                        .font(.system(size:RightDisplayUI.cardIconFontSize,weight:.semibold)).foregroundStyle(Color.accentColor)
                        .frame(width:RightDisplayUI.cardIconSize,height:RightDisplayUI.cardIconSize)
                        .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
                    Text("显示链路测试").font(.headline)
                    Spacer(minLength: 12)
                    if testRunning {
                        Button("停止测试") { store.stopCapabilityTest() }
                            .buttonStyle(NeutralActionButtonStyle())
                    } else {
                        Button(store.capabilityTestTotal > 0 ? "重新测试" : "开始测试") {
                            showingCapabilityTestConfirmation = true
                        }
                        .buttonStyle(CompactActionButtonStyle(primary: true, minWidth: 90))
                        .tint(.accentColor)
                        .disabled(preferences.displayOutputControlsLocked || !eligibility.isEnabled)
                        .help(AppLocalization.string(eligibility.reason))
                    }
                }
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            Text("验证当前连接下能够稳定工作的颜色格式、色深与 HDR/SDR 组合。")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("当前测试环境")
                    .font(.caption.weight(.semibold))
                Text("\(d.resolution) · \(d.refreshRate.text) · \(AppLocalization.string(store.selectedInterfaceName))")
                    .font(.caption).foregroundStyle(.secondary)
                if let envelope = eligibility.edidEnvelope {
                    Text(AppLocalization.format(
                        "设备声明支持：%@ · %@ bit · %@",
                        envelope.encodingSummary,
                        envelope.declaredBitDepths.map(String.init).joined(separator: "/"),
                        envelope.hasHDR ? "HDR" : "SDR"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("EDID 表示设备声明能力，不代表 macOS 当前正在输出这些状态。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSubmenuInset(amount:RightDisplayUI.submenuIndent))
            if !testRunning, !eligibility.isEnabled {
                Text(AppLocalization.string(eligibility.reason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if testRunning {
                VStack(alignment: .leading, spacing: 6) {
                    if store.capabilityTestTotal > 0 {
                        HStack(spacing: 10) {
                            ProgressView(
                                value: Double(store.capabilityTestProgress),
                                total: Double(store.capabilityTestTotal)
                            )
                            .progressViewStyle(.linear)
                            .frame(maxWidth: .infinity)
                            Text(AppLocalization.format(
                                "%d%%",
                                store.capabilityTestTotal > 0
                                    ? Int((Double(store.capabilityTestProgress) / Double(store.capabilityTestTotal) * 100).rounded())
                                    : 0
                            ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                        }
                    }
                    HStack {
                        Text(AppLocalization.string(store.capabilityTestStage.title))
                            .font(.caption.weight(.semibold))
                    }
                    if !store.capabilityTestDetail.isEmpty {
                        Text(AppLocalization.string(store.capabilityTestDetail))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(AppLocalization.string(store.capabilityTestReadback))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !store.verifiedLinkApplyStatus.isEmpty {
                Text(AppLocalization.string(store.verifiedLinkApplyStatus))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("本次发现的稳定链路").font(.caption.weight(.semibold))
                if !verifiedModes.isEmpty {
                    WrappingHStackLayout(spacing: 8) {
                        ForEach(verifiedModes.prefix(12)) {
                            capabilityResultRow($0, display: d, testRunning: testRunning)
                        }
                    }
                } else {
                    Text("本次测试尚未发现经过完整稳定与观察窗口确认的可用链路。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !store.capabilityTestAttemptResults.isEmpty {
                    Divider()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            capabilityTestDetailsExpanded.toggle()
                        }
                    } label: {
                        let passed = store.capabilityTestAttemptResults.filter(\.passed).count
                        HStack(spacing: 6) {
                            Text(AppLocalization.format(
                                "上次测试 · %d 次探测 · %d 次稳定 · %d 次未稳定",
                                store.capabilityTestAttemptResults.count,
                                passed,
                                store.capabilityTestAttemptResults.count - passed
                            ))
                            Spacer()
                            Image(systemName: capabilityTestDetailsExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if capabilityTestDetailsExpanded {
                        ForEach(store.capabilityTestAttemptResults) { result in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(result.index)").font(.caption.monospacedDigit()).frame(width: 18, alignment: .trailing)
                                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.passed ? .green : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.passed ? "稳定" : "未稳定").font(.caption.weight(.semibold))
                                    if let actual = result.actualLink {
                                        Text(AppLocalization.format("最终链路：%@", actual))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }.modifier(CardSubmenuInset(amount:RightDisplayUI.submenuIndent))
        }
        .id(SettingsTarget.capabilityTest)
    }

    private func capabilityResultRow(
        _ mode: ValidatedLinkMode,
        display: DisplaySnapshot,
        testRunning: Bool
    ) -> some View {
        let reusable = capabilityModeIsReusable(mode, display: display)
        let active = display.currentConnectionIdentity.map {
            $0 == mode.connectionIdentity && $0.isKnown
        } ?? false
        return Button {
            pendingVerifiedLink = mode
        } label: {
            HStack(spacing: 5) {
                Text("\(capabilityEncoding(mode)) · \(mode.bitDepth) bit · \(mode.hdr ? "HDR" : "SDR")")
                    .font(.caption).lineLimit(1)
                if active {
                    Text(AppLocalization.string("· 当前")).font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(active ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 0.7))
        .fixedSize()
        .disabled(!reusable || active || testRunning || preferences.displayOutputControlsLocked)
        .help(AppLocalization.string(
            !reusable && (mode.evidence == .systemReadback || mode.evidence == .userConfirmed)
                ? "该记录缺少安全套用所需的完整链路信息"
                : (mode.failureReason ?? AppLocalization.format("最近验证：%@", mode.lastChecked.formatted(date: .abbreviated, time: .shortened)))
        ))
    }

    private func capabilitySort(_ lhs: DisplayLinkCapability, _ rhs: DisplayLinkCapability) -> Bool {
        if lhs.outputPreference != rhs.outputPreference { return lhs.outputPreference == .rgbFullRange }
        if lhs.rawPixelEncoding != rhs.rawPixelEncoding { return lhs.rawPixelEncoding < rhs.rawPixelEncoding }
        if lhs.bitDepth != rhs.bitDepth { return lhs.bitDepth > rhs.bitDepth }
        if lhs.rawEOTF != rhs.rawEOTF { return (lhs.rawEOTF ?? 0) > (rhs.rawEOTF ?? 0) }
        return (lhs.rawRange ?? 0) > (rhs.rawRange ?? 0)
    }

    private func deduplicatedCapabilityModes(_ modes: [ValidatedLinkMode]) -> [ValidatedLinkMode] {
        var latest: [String: ValidatedLinkMode] = [:]
        for mode in modes.sorted(by: { $0.lastChecked > $1.lastChecked }) {
            let key = mode.deduplicationKey
            if latest[key] == nil { latest[key] = mode }
        }
        return latest.values.sorted { $0.lastChecked > $1.lastChecked }
    }

    private func capabilityForMode(_ mode: ValidatedLinkMode, display: DisplaySnapshot) -> DisplayLinkCapability? {
        guard mode.evidence == .userConfirmed ||
                ((mode.evidence == .systemReadback || mode.evidence == .observedStable) &&
                 mode.engineGeneration == CapabilityTestTiming.engineGeneration),
              mode.persistentIdentity != nil,
              mode.timingIdentity == display.currentTimingIdentity,
              let raw = mode.rawPixelEncoding,
              LinkPixelEncoding.isKnown(raw),
              [8, 10, 12].contains(mode.bitDepth),
              (raw == 0) == (mode.color == .rgbFullRange) else { return nil }
        return DisplayLinkCapability(
            outputPreference: mode.color,
            encodingText: capabilityEncoding(mode),
            rawPixelEncoding: raw,
            bitDepth: mode.bitDepth,
            hdrEnabled: mode.hdr, rawRange: mode.rawRange, rawEOTF: mode.rawEOTF
        )
    }

    private func capabilityModeIsReusable(_ mode: ValidatedLinkMode, display: DisplaySnapshot) -> Bool {
        capabilityForMode(mode, display: display) != nil
    }

    private func capabilityEncoding(_ mode: ValidatedLinkMode) -> String {
        LinkPixelEncoding.title(for: mode.rawPixelEncoding)
    }

    private func signalDetailRow(_ title: String, _ value: SignalValue, icon: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 27)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string(title)).font(.callout.weight(.medium))
                Text(AppLocalization.string(value.text)).font(.caption.weight(.semibold))
                Text(AppLocalization.format("来源：%@", AppLocalization.string(value.source)))
                    .font(.caption2).foregroundStyle(.secondary)
                if !value.detail.isEmpty {
                    Text(AppLocalization.string(value.detail))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func sound(_ d: DisplaySnapshot) -> some View {
        VStack(spacing: RightDisplayUI.sectionSpacing) {
            GlassCard(title: "音响音量", subtitle: "选择后，高级页与状态栏快捷面板会控制同一台设备。", icon: "hifispeaker.2") {
                settingRow("控制设备", "hifispeaker") {
                    NativeSelectionPicker(
                        options: [.init(id: AudioOutputStore.followsSystemTargetID, title: AppLocalization.string("跟随 macOS 当前输出"))]
                            + audioOutput.outputs.map { output in
                                .init(id: audioOutput.targetID(for: output), title: "\(output.controlDisplayTitle)\(output.isDefault ? AppLocalization.string(" · 当前") : "")")
                            }
                            + [.init(id: AudioOutputStore.appleTVTargetID, title: AppLocalization.string("Apple TV 默认音频输出"), separatorBefore: true)],
                        selectedID: audioOutput.selectedControlTargetID, fallbackTitle: controlTargetMenuTitle
                    ) { audioOutput.selectedControlTargetID = $0 }
                }
                Divider()
                if audioOutput.selectedControlTargetID == AudioOutputStore.appleTVTargetID {
                    appleTVSoundControls
                } else {
                    coreAudioSoundControls
                }
            }
            VirtualVolumeView()
        }
    }

    private func levelControl(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        percent: Int,
        accessibilityLabel: String,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        VolumeLevelControl(value:value,range:range,percent:percent,accessibilityLabel:accessibilityLabel,onEditingChanged:onEditingChanged)
    }

    @ViewBuilder private var coreAudioSoundControls: some View {
        if let output = audioOutput.selectedAudioDevice {
            settingRow("设备音量", "speaker.wave.2.fill") {
                if output.systemVolumeWritable, let volume = output.volume {
                    levelControl(
                        value: Binding(
                            get: { audioOutput.selectedAudioDevice?.volume ?? volume },
                            set: { audioOutput.setVolume($0) }
                        ),
                        in: 0...1,
                        percent: Int((volume * 100).rounded()),
                        accessibilityLabel: "设备音量",
                        onEditingChanged: playVolumeConfirmationWhenFinished
                    )
                } else {
                    Text("此设备未向 macOS 开放音量读取或写入")
                        .foregroundStyle(.secondary)
                }
            }
            if !output.systemVolumeWritable {
                Text("请使用显示器按键、遥控器或接收端调节。Right Display 不会显示推算的音量百分比。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            settingRow("键盘音量控制", "keyboard") {
                Text(output.systemVolumeWritable
                     ? (AppLocalization.isEnglish ? "Controlled by macOS" : "由 macOS 原生控制")
                     : (AppLocalization.isEnglish ? "System volume control unavailable" : "系统未提供音量控制"))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("所选音频设备当前不可用，请重新选择。")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var appleTVSoundControls: some View {
        settingRow("Apple TV / AirPlay 设备", "airplayaudio") {
            if !appleTV.hasVolumeControl && !appleTV.isBusy {
                Button("重新搜索") { appleTV.scan() }
                    .buttonStyle(NeutralActionButtonStyle())
            }
            if appleTV.isBusy && !appleTV.selectedIdentifier.isEmpty {
                Text("正在连接…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            NativeSelectionPicker(
                options: appleTV.devices.map { .init(id: $0.id, title: AppLocalization.string(appleTVDeviceLabel($0))) },
                selectedID: appleTV.selectedIdentifier, fallbackTitle: selectedAppleTVMenuTitle
            ) { appleTV.selectedIdentifier = $0 }
            .disabled(appleTV.isBusy || appleTV.devices.isEmpty)
        }
        if appleTV.statusText != "已连接" || appleTV.isBusy || !appleTV.hasVolumeControl {
        HStack(spacing: 10) {
            if appleTV.isBusy { ProgressView().controlSize(.small) }
            Text(AppLocalization.string(appleTV.statusText))
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
            if appleTV.isPairing {
                Button("取消") { appleTV.cancelPairing(); appleTVPIN = "" }
            } else if !appleTV.selectedIdentifier.isEmpty, !appleTV.hasVolumeControl {
                if appleTV.selectedDevice?.paired == true {
                    Button(appleTV.isConnected ? "重新连接" : "连接") { appleTV.reconnect() }
                        .disabled(appleTV.isBusy)
                } else {
                    Button("开始配对") { appleTV.pairSelected() }.disabled(appleTV.isBusy)
                }
                Menu {
                    Button("重新连接") { appleTV.reconnect() }
                    Divider()
                    Button("AirPlay 配对") { appleTV.pairSelected() }
                    Button("Companion 配对（电视未显示验证码时）") {
                        appleTV.pairSelected(protocolName: "companion")
                    }
                    Divider()
                    Button("打开本地网络设置") { openLocalNetworkSettings() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(appleTV.isBusy).help("连接选项")
            }
        }
        .padding(.vertical, 6)
        }
        if appleTV.awaitsPIN {
            settingRow("电视验证码", "number") {
                TextField("PIN", text: $appleTVPIN).frame(width: 90)
                    .onSubmit { appleTV.submitPIN(appleTVPIN); appleTVPIN = "" }
                Button("提交") { appleTV.submitPIN(appleTVPIN); appleTVPIN = "" }
                    .disabled(appleTVPIN.count != 4 || !appleTVPIN.allSatisfy { $0.isASCII && $0.isNumber })
            }
        }
        if appleTV.isConnected {
            Divider()
            settingRow("设备音量", "speaker.wave.2.fill") {
                if let volume = appleTV.volume {
                    levelControl(
                        value: Binding(
                            get: { appleTV.requestedVolume ?? appleTV.volume ?? volume },
                            set: { appleTV.setVolume($0) }
                        ),
                        in: 0...100,
                        percent: Int(volume.rounded()),
                        accessibilityLabel: "设备音量",
                        onEditingChanged: playVolumeConfirmationWhenFinished
                    )
                    .disabled(!appleTV.volumeControlAvailable)
                } else {
                    Text("当前连接未提供音量读数").foregroundStyle(.secondary)
                }
            }
            switchRow(
                "键盘音量控制",
                "将 Mac 音量键发送到 Apple TV 当前默认音频输出，包括 HomePod 立体声组合。",
                "keyboard", appleTV.bindsKeyboardVolumeKeys, appleTV.volumeControlAvailable
            ) { appleTV.bindsKeyboardVolumeKeys.toggle() }
        }
    }

    private func appleTVDeviceLabel(_ device: AppleTVAudioDevice) -> String {
        let state: String
        if device.id == appleTV.selectedIdentifier, appleTV.isConnected {
            state = "已连接"
        } else if device.isOnline {
            state = "在线"
        } else {
            state = "上次连接"
        }
        let cleanName = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isActivelyConnected = device.id == appleTV.selectedIdentifier && appleTV.isConnected
        let visibleName = isActivelyConnected ? device.displayName : cleanName
        return "\(visibleName) · \(state)"
    }

    private var controlTargetMenuTitle: String {
        if audioOutput.selectedControlTargetID == AudioOutputStore.appleTVTargetID {
            return "Apple TV 默认音频输出"
        }
        if audioOutput.selectedControlTargetID == AudioOutputStore.followsSystemTargetID {
            return "跟随 macOS 当前输出"
        }
        if let output = audioOutput.outputs.first(where: {
            audioOutput.targetID(for: $0) == audioOutput.selectedControlTargetID
        }) {
            return "\(output.controlDisplayTitle)\(output.isDefault ? AppLocalization.string(" · 当前") : "")"
        }
        return "没有可用目标"
    }

    private var selectedAppleTVMenuTitle: String {
        guard let device = appleTV.devices.first(where: { $0.id == appleTV.selectedIdentifier }) else {
            return "没有可用目标"
        }
        return device.displayName
    }

    private func openLocalNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork") else { return }
        NSWorkspace.shared.open(url)
    }

    private func edidPage(_ d: DisplaySnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            GlassCard {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: RightDisplayUI.cardIconFontSize, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: RightDisplayUI.cardIconSize, height: RightDisplayUI.cardIconSize)
                        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("EDID 数据").font(.headline)
                        Text(AppLocalization.string(edid.status))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                HStack(alignment: .center, spacing: 8) {
                    Text("EDID 可能包含设备序列号，分享导出文件前请检查隐私信息。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Button("读取") { edid.refresh(for: d) }
                        .buttonStyle(CompactActionButtonStyle(primary: true))
                        .help("重新读取当前显示器的 EDID")
                    Button("导出") { edid.exportBinary() }
                        .buttonStyle(CompactActionButtonStyle())
                        .disabled(edid.data == nil)
                        .help("导出原始 EDID 二进制文件")
                    Button("报告") { edid.exportText() }
                        .buttonStyle(CompactActionButtonStyle())
                        .disabled(edid.fields.isEmpty)
                        .help("导出完整的 EDID 解析报告")
                }
            }
            if !edid.sinkCapabilityFields.isEmpty {
                GlassCard(title: "EDID / 接收端能力", subtitle: "显示器声明支持的能力，不代表当前输出状态。", icon: "list.bullet.rectangle") {
                    ForEach(edid.sinkCapabilityFields) { EDIDFieldDisclosure(field: $0) }
                }
            }
            if !edid.macOSCapabilityFields.isEmpty {
                GlassCard(title: "macOS 解析能力", subtitle: "系统解析的能力范围；具体模式范围见“显示”。", icon: "display") {
                    ForEach(edid.macOSCapabilityFields) { EDIDFieldDisclosure(field: $0) }
                }
            }
            ForEach(edidFieldGroups) { group in
                GlassCard(
                    title: group.title,
                    subtitle: edidGroupSubtitle(group.fields.count),
                    icon: group.icon
                ) {
                    ForEach(Array(group.fields.enumerated()), id: \.element.id) { index, field in
                        EDIDFieldDisclosure(field: field)
                        if index < group.fields.count - 1 { Divider() }
                    }
                }
            }
            EDIDRawGlassCard(hexText: edid.hexText)
        }.onAppear { edid.refresh(for: d) }
    }

    private var edidFieldGroups: [EDIDFieldGroup] {
        var base: [EDIDField] = [], timings: [EDIDField] = [], cta: [EDIDField] = [], other: [EDIDField] = []
        for field in edid.fields {
            let title = field.title
            if title == "扩展区块" {
                base.append(field)
            } else if title.localizedCaseInsensitiveContains("CTA") || title.localizedCaseInsensitiveContains("HDMI") {
                cta.append(field)
            } else if title.localizedCaseInsensitiveContains("DisplayID") || title.hasPrefix("扩展区块") {
                other.append(field)
            } else if title.localizedCaseInsensitiveContains("Timing") || title.contains("时序") || title.contains("描述符") || title.contains("显示范围") {
                timings.append(field)
            } else {
                base.append(field)
            }
        }
        return [
            EDIDFieldGroup(title: "基础 EDID", icon: "info.square", fields: base),
            EDIDFieldGroup(title: "时序与描述符", icon: "clock.arrow.2.circlepath", fields: timings),
            EDIDFieldGroup(title: "CTA‑861 与 HDMI 能力", icon: "cable.connector", fields: cta),
            EDIDFieldGroup(title: "其他扩展区块", icon: "square.stack.3d.up", fields: other)
        ].filter { !$0.fields.isEmpty }
    }

    private func edidGroupSubtitle(_ count: Int) -> String {
        if AppLocalization.isEnglish {
            return "\(count) \(count == 1 ? "item" : "items") · Expand to view parsed fields and raw evidence"
        }
        return AppLocalization.format("%d 项 · 点击查看已解析字段与原始依据", count)
    }

    private var quickControlManagementSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷控制管理").font(.title3.weight(.semibold))
                    Text("决定快捷面板中显示哪些内容。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { showingQuickControlManagement = false }
                    .buttonStyle(.borderedProminent)
            }
            ScrollView {
                GlassCard {
                    Text("显示内容").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    switchRow("显示器信息", "显示当前显示器、分辨率、刷新率与接口。", "display", preferences.quickPanelShowsDisplayInfo, true) { preferences.quickPanelShowsDisplayInfo.toggle() }
                    Divider()
                    switchRow("亮度", "显示当前屏幕可用的亮度控制。", "sun.max", preferences.quickPanelShowsBrightness, true) { preferences.quickPanelShowsBrightness.toggle() }
                    Divider()
                    switchRow("音量", "显示当前音频控制目标的音量。", "speaker.wave.2", preferences.quickPanelShowsVolume, true) { preferences.quickPanelShowsVolume.toggle() }
                    Divider()
                    Text("显示器功能控制").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    switchRow("颜色格式", "在快捷面板显示 RGB / YCbCr 状态与控制。", "paintpalette", preferences.quickPanelShowsColorFormat, true) { preferences.quickPanelShowsColorFormat.toggle() }
                    Divider()
                    switchRow("色深", "在快捷面板显示 8 / 10 / 12 bit 状态与控制。", "circle.lefthalf.filled", preferences.quickPanelShowsBitDepth, true) { preferences.quickPanelShowsBitDepth.toggle() }
                    Divider()
                    switchRow("HDR", "在快捷面板显示高动态范围状态与控制。", "sun.max.fill", preferences.quickPanelShowsHDR, true) { preferences.quickPanelShowsHDR.toggle() }
                    Divider()
                    switchRow("VRR", "在快捷面板显示可变刷新率状态与控制。", "speedometer", preferences.quickPanelShowsVRR, true) { preferences.quickPanelShowsVRR.toggle() }
                }
            }
        }
        .padding(20)
        .frame(width: 570, height: 600)
        .background(AdvancedWindowMaterial())
    }

    private func compactGeneralRow<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: RightDisplayUI.cardIconFontSize, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: RightDisplayUI.cardIconSize, height: RightDisplayUI.cardIconSize)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
            Text(AppLocalization.string(title)).font(RightDisplayUI.cardTitle)
            Spacer(minLength: 14)
            content()
        }
        .frame(height: 42)
    }

    private func general(_ d: DisplaySnapshot) -> some View {
        VStack(spacing: RightDisplayUI.sectionSpacing) {
            GlassCard(verticalPadding: 10) {
                compactGeneralRow("界面语言", icon: "globe") {
                    NativeSelectionPicker(
                        options: AppLanguage.allCases.map { .init(id: $0.id, title: AppLocalization.string($0.titleKey)) },
                        selectedID: preferences.appLanguage.id, fallbackTitle: preferences.appLanguage.titleKey
                    ) { id in
                        if let language = AppLanguage(rawValue: id) { preferences.appLanguage = language }
                    }
                }
            }
            GlassCard(verticalPadding: 10) {
                compactGeneralRow("快捷控制管理", icon: "switch.2") {
                    Button("管理") { showingQuickControlManagement = true }
                        .buttonStyle(NeutralActionButtonStyle())
                        .frame(width: 180, alignment: .trailing)
                }
            }
            GlassCard(title: "启动行为", icon: "play.circle") {
                switchRow("登录时启动","登录 Mac 后在状态栏运行 Right Display。","person.crop.circle.badge.checkmark",launchesAtLogin,true){toggleLaunchAtLogin()}
                Divider()
                switchRow(
                    "登录启动时显示快捷面板",
                    "默认关闭；关闭时仅在状态栏后台运行，不会自行弹出窗口。",
                    "macwindow",
                    preferences.showPanelOnLoginLaunch,
                    launchesAtLogin
                ) { preferences.showPanelOnLoginLaunch.toggle() }
                Divider()
                switchRow(
                    "安全模式",
                    "启动后只读取状态，不执行登录、连接或唤醒自动校正。",
                    "shield.checkered",
                    preferences.safeModeEnabled,
                    true
                ) { toggleSafeMode() }
            }
            GlassCard(title: "自动校正", icon: "wand.and.sparkles") {
                switchRow(
                    "启动后自动校正颜色",
                    "仅在登录启动后的本次开机执行一次，修复部分显示器唤醒时的颜色握手异常；默认关闭。",
                    "paintbrush.pointed",
                    preferences.autoCorrectColorOnLoginLaunch,
                    !preferences.safeModeEnabled
                ) { preferences.autoCorrectColorOnLoginLaunch.toggle() }
                Divider()
                switchRow(
                    "连接显示器后检查",
                    "只在发现当前颜色链路偏离所选规则时自动校正。",
                    "display.2",
                    preferences.autoCorrectColorOnDisplayConnect,
                    !preferences.safeModeEnabled
                ) { preferences.autoCorrectColorOnDisplayConnect.toggle() }
                Divider()
                switchRow(
                    "唤醒后检查",
                    "Mac 从睡眠唤醒后检查握手，仅在状态异常时执行。",
                    "moon.zzz",
                    preferences.autoCorrectColorOnWake,
                    !preferences.safeModeEnabled
                ) { preferences.autoCorrectColorOnWake.toggle() }
            }
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "stethoscope")
                        .font(.system(size:RightDisplayUI.cardIconFontSize,weight:.semibold))
                        .foregroundStyle(Color.accentColor).frame(width:RightDisplayUI.cardIconSize,height:RightDisplayUI.cardIconSize)
                        .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("诊断与支持").font(.headline)
                        Text("包含当前显示与音频状态、最近五分钟操作、脱敏后的链路及 Apple TV 日志；不含配对凭据。显示器名称可能由你自定义。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("导出诊断报告") { _ = DiagnosticReportExporter.export(display:d, brightness:brightness, audio:audioOutput, qmsAssessment:"由显示模式表评估") }
                        .buttonStyle(NeutralActionButtonStyle())
                }
            }
            if let migration = preferences.migrationSummary {
                GlassCard(title:"配置迁移完成",subtitle:"旧版设置已保留并转换为当前格式。",icon:"arrow.triangle.2.circlepath") {
                    Text(AppLocalization.format("配置格式 %d → %d", migration.fromVersion, migration.toVersion)).font(.caption.weight(.semibold))
                    ForEach(migration.notes, id: \.self) { Label(AppLocalization.string($0), systemImage: "checkmark").font(.caption).foregroundStyle(.secondary) }
                }
            }
            GlassCard(verticalPadding: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.system(size: RightDisplayUI.cardIconFontSize, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: RightDisplayUI.cardIconSize, height: RightDisplayUI.cardIconSize)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("版本").font(.headline)
                        HStack(spacing: 4) {
                            Text("当前版本")
                            Text(RightDisplayReleaseHistory.currentVersion)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("关于") { AboutWindowController.shared.show() }
                        .buttonStyle(CompactActionButtonStyle(primary: true))
                    Button("历史更新说明") { showingReleaseNotes = true }
                        .buttonStyle(NeutralActionButtonStyle())
                    Button("查看使用引导") {
                        preferences.onboardingStep = 0
                        preferences.onboardingCompleted = false
                        NotificationCenter.default.post(name: .usageGuideRequested, object: nil)
                    }
                    .buttonStyle(NeutralActionButtonStyle())
                }.frame(minHeight: 42)
            }
        }
    }

    private var onboardingCompletionBinding: Binding<Bool> {
        Binding(
            get: { !preferences.onboardingCompleted && preferences.onboardingStep == 3 },
            set: { _ in }
        )
    }

    private var onboardingCompletion: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("高级设置：完整信息与管理", systemImage: "slider.horizontal.3")
                .font(.title2.weight(.semibold))
            Text("高级设置包含概览、显示、音频、ICC、EDID 和通用设置。")
                .foregroundStyle(.secondary)
            Toggle("登录启动 RightDisplay 时自动显示快捷面板", isOn: $preferences.showPanelOnLoginLaunch)
                .toggleStyle(.switch)
            Text("此选择只控制快捷面板是否自动出现，不会自动修改显示配置。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("开始显示链路测试") {
                    preferences.onboardingCompleted = true
                    preferences.onboardingStep = 0
                    DispatchQueue.main.async {
                        navigate(to: .displayOutput, target: .capabilityTest)
                    }
                }
                Button("完成引导") {
                    preferences.onboardingCompleted = true
                    preferences.onboardingStep = 0
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .frame(width: 470)
        .environment(\.locale, preferences.appLanguage.locale)
    }

    private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            store.reportError(AppLocalization.format("无法修改登录启动设置：%@", error.localizedDescription))
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func toggleSafeMode() {
        preferences.safeModeEnabled.toggle()
        if preferences.safeModeEnabled { store.enterSafeSession() }
        else { store.leaveSafeSession() }
    }

    private func playVolumeConfirmationWhenFinished(_ editing: Bool) {
        if !editing {
            NSSound(named: NSSound.Name("Tink"))?.play()
        }
    }

    private func modePicker(_ binding: Binding<String>, _ values: [Pair], physical: Bool) -> some View {
        let selected = values.first { $0.id == binding.wrappedValue }
        let title = selected.map { physical ? resolutionLabel($0) : "\($0.w) × \($0.h)" } ?? "未提供"
        return NativeSelectionPicker(
            options: values.map { .init(id: $0.id, title: physical ? resolutionLabel($0) : "\($0.w) × \($0.h)") },
            selectedID: binding.wrappedValue, fallbackTitle: title
        ) { binding.wrappedValue = $0 }
        .accessibilityLabel(physical ? "显示器分辨率" : "界面分辨率")
    }

    private func refreshPicker(_ display: DisplaySnapshot) -> some View {
        let modes = refreshModes(display)
        return NativeSelectionPicker(
            options: modes.map { .init(id: $0.selectionKey, title: $0.refreshText) },
            selectedID: display.currentModeKey, fallbackTitle: current(display)?.refreshText ?? "刷新率未知"
        ) { key in
            guard let mode = modes.first(where: { $0.selectionKey == key }) else { return }
            store.apply(mode)
        }
        .accessibilityLabel("刷新率")
    }
    private func evidence(
        _ title: String,
        _ value: SignalValue,
        _ icon: String,
        stateColor: Color? = nil,
        destination: SettingsTarget? = nil,
        detailText: String? = nil
    ) -> some View {
        let displayedStateColor = stateColor ?? (value.verification == .unavailable ? .gray : .green)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: RightDisplayUI.cardIconFontSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(AppLocalization.string(title)).font(RightDisplayUI.cardTitle)
                Spacer()
                Text(AppLocalization.string(value.verification == .verified ? "系统报告" : value.verificationText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(AppLocalization.string(verificationHelp(value)))
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(displayedStateColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: displayedStateColor.opacity(0.32), radius: 3)
                    .accessibilityHidden(true)
                Text(AppLocalization.string(overviewPrimaryText(title: title, value: value)))
                    .font(RightDisplayUI.primaryValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Text(AppLocalization.string(compactEvidenceSource(value.source)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if detailText != nil || !value.detail.isEmpty {
                Text(AppLocalization.string(detailText ?? compactEvidenceDetail(title: title, value: value)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            if let destination { navigate(to: .displayOutput, target: destination) }
        }
    }

    private func overviewRefreshText(_ display: DisplaySnapshot) -> OverviewRefreshText {
        OverviewRefreshText(mode: current(display), fallbackText: display.refreshRate.text,
            reportedVRR: display.vrrStateKnown ? display.vrrEnabled : nil)
    }

    private func overviewRefreshSignal(_ display: DisplaySnapshot) -> SignalValue {
        SignalValue(text: overviewRefreshText(display).value,
            verification: display.refreshRate.verification, source: display.refreshRate.source,
            detail: display.refreshRate.detail)
    }

    private func compactEvidenceSource(_ source: String) -> String {
        if source.contains("ParentBuiltInPortTypeDescription") { return "依据：系统报告的连接接口" }
        if source.contains("SLSGetDisplayOutputModeLinkDescriptions") { return "依据：系统报告" }
        if source.contains("SkyLight") { return "依据：系统当前链路读数" }
        if source.contains("IOKit DP/HDMI") { return "依据：当前模式与链路带宽估算" }
        if source.contains("EDID") { return "依据：显示器声明的能力（非当前状态）" }
        return "依据：系统当前显示状态"
    }

    private func overviewPrimaryText(title: String, value: SignalValue) -> String {
        if title == "DSC", value.verification == .inferred {
            return value.text.contains("已启用") ? "已启用" : "状态未直接确认"
        }
        if title == "像素格式", value.text.hasPrefix("RGB（"), !value.text.contains("帧缓冲") { return "RGB（4:4:4）" }
        if title == "连接方式" { return value.text.replacingOccurrences(of: "（推断）", with: "").replacingOccurrences(of: "输出模式 ", with: "") }
        return value.text
    }

    private func compactEvidenceDetail(title: String, value: SignalValue) -> String {
        if title == "连接方式" {
            if value.detail.contains("HDMI Forum") { return "EDID 提供 HDMI Forum 能力信息；完整路径与推断依据见诊断报告。" }
            return "接口类型由当前显示路径与 EDID 综合识别；完整依据见诊断报告。"
        }
        if title == "DSC" { return "系统未直接报告压缩状态；此处仅根据带宽推断。" }
        if title == "像素格式" || title == "色深" { return "系统报告的输出状态；最终接收端状态可能不同。" }
        if title == "HDR" { return "当前高动态范围状态；系统管理的显示器可能随内容变化。" }
        if title == "VRR" { return "当前模式的可变刷新状态，不等于验证了接收端协议。" }
        return value.detail
    }

    private func connectionSummary(_ display: DisplaySnapshot) -> SignalValue {
        guard edid.connection.text.contains("HDMI") else { return edid.connection }
        guard display.dscEnabled == true else { return edid.connection }
        let inferredMode = display.dscEnabled == true ? "FRL（推断）" : "未确认"
        return SignalValue(
            text: display.dscEnabled == true ? "HDMI · 输出模式 FRL（推断）" : "HDMI · 输出模式未确认",
            verification: inferredMode == "未确认" ? .unavailable : .inferred,
            source: edid.connection.source,
            detail: inferredMode == "未确认"
                ? edid.connection.detail
                : "HDMI 接口已连接；当前 DSC 判断成立时，传输模式倾向 FRL。该结论是链路能力推断，不是 macOS 对 FRL 状态的直接回读。"
        )
    }

    private func verificationHelp(_ value: SignalValue) -> String {
        switch value.verification {
        case .verified:
            "该项来自 macOS 系统读取，不代表物理接收端验证。状态点表示当前状态，不代表证据等级。"
        case .slsReported:
            "系统报告的输出状态；最终接收端状态可能不同。"
        case .inferred:
            "该项来自现有链路信息推断，尚未获得直接确认。状态点表示当前状态，不代表证据等级。"
        case .unavailable:
            "当前系统接口没有提供足够信息，暂时无法验证；不一定代表显示器不支持。"
        }
    }
    private func metricLink(_ t:String,_ v:String,_ i:String,_ destination:AdvancedPage,_ target:SettingsTarget,_ help:String,status:OverviewFeatureState?=nil)->some View { OverviewMetricButton(title:t,value:v,icon:i,help:help,status:status) { navigate(to: destination, target: target) } }
    private func navigate(to destination: AdvancedPage, target: SettingsTarget) {
        page = destination
        navigationTarget = nil
        highlightedTarget = target
        DispatchQueue.main.async { navigationTarget = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if highlightedTarget == target { highlightedTarget = nil }
        }
    }
    private func featureState(supported:Bool,enabled:Bool,enabledHelp:String,availableHelp:String,unsupportedHelp:String)->OverviewFeatureState { if !supported{return .init(level:.unsupported,help:unsupportedHelp)};return enabled ? .init(level:.enabled,help:enabledHelp) : .init(level:.available,help:availableHelp) }
    private func settingRow<Content: View>(
        _ title: String,
        _ icon: String?,
        target: SettingsTarget? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let row = HStack(spacing: 11) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 27, height: 27)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text(AppLocalization.string(title)).font(RightDisplayUI.rowLabel)
            Spacer(minLength: 14)
            content()
        }
        .frame(minHeight: RightDisplayUI.rowHeight)
        .modifier(CardSubmenuInset())
        return Group {
            if let target {
                row.id(target)
                    .modifier(SettingsTargetHighlight(active: highlightedTarget == target))
            } else {
                row
            }
        }
    }

    private func sectionHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppLocalization.string(title)).font(.title3.weight(.semibold))
            Text(AppLocalization.string(subtitle)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func switchRow(
        _ title: String,
        _ subtitle: String,
        _ icon: String,
        _ on: Bool,
        _ enabled: Bool,
        target: SettingsTarget? = nil,
        applying: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let row = HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 27, height: 27)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalization.string(title)).font(.callout.weight(.medium))
                Text(AppLocalization.string(subtitle)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 14)
            if applying {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("正在应用").font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityLabel(AppLocalization.format("%@正在应用并复读", AppLocalization.string(title)))
            } else {
                Toggle("", isOn: Binding(get: { on }, set: { _ in action() }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!enabled)
                    .accessibilityLabel(title)
                    .accessibilityHint(subtitle)
            }
        }
        .frame(minHeight: 46)
        .modifier(CardSubmenuInset())
        return Group {
            if let target {
                row.id(target)
                    .modifier(SettingsTargetHighlight(active: highlightedTarget == target))
            } else {
                row
            }
        }
    }
    private var linkTransactionPanelBinding: Binding<Bool> {
        Binding(
            get: { store.pendingModeConfirmation || !store.verifiedLinkApplyStatus.isEmpty },
            set: { _ in }
        )
    }
    private var errorBinding:Binding<Bool>{Binding(get:{store.lastError != nil},set:{if !$0{store.clearLastError()}})}
    private func current(_ d:DisplaySnapshot)->DisplayModeOption?{d.modes.first{$0.selectionKey==d.currentModeKey}}
    private func unique(_ a:[Pair])->[Pair]{Array(Set(a)).sorted{$0.w==$1.w ? $0.h>$1.h : $0.w>$1.w}}
    private func outputResolutions(_ d:DisplaySnapshot)->[Pair]{unique(d.modes.filter(\.isHiDPI).map{Pair(w:$0.outputWidth,h:$0.outputHeight)})}
    private func hiDPIResolutions(_ d:DisplaySnapshot)->[Pair]{guard let c=current(d)else{return[]};let all=unique(d.modes.filter{$0.isHiDPI && $0.outputWidth==c.outputWidth && $0.outputHeight==c.outputHeight}.map{Pair(w:$0.width,h:$0.height)});return all.filter{(720...1800).contains($0.h) || ($0.w==c.width && $0.h==c.height)}}
    private func refreshModes(_ d: DisplaySnapshot) -> [DisplayModeOption] {
        guard let c = current(d) else { return [] }
        return d.modes.filter { $0.isHiDPI == c.isHiDPI && $0.outputWidth == c.outputWidth &&
            $0.outputHeight == c.outputHeight && $0.width == c.width && $0.height == c.height &&
            $0.pixelWidth == c.pixelWidth && $0.pixelHeight == c.pixelHeight }
    }
    private func outputResolutionBinding(_ d:DisplaySnapshot)->Binding<String>{Binding(get:{current(d).map{"\($0.outputWidth)x\($0.outputHeight)"} ?? ""},set:{id in guard let p=Pair(id:id)else{return};if let m=d.modes.first(where:{$0.isHiDPI && $0.outputWidth==p.w && $0.outputHeight==p.h}){store.apply(m)}})}
    private func hiDPIBinding(_ d:DisplaySnapshot)->Binding<String>{Binding(get:{current(d).map{"\($0.width)x\($0.height)"} ?? ""},set:{id in guard let p=Pair(id:id),let c=current(d),let m=d.modes.first(where:{$0.isHiDPI && $0.outputWidth==c.outputWidth && $0.outputHeight==c.outputHeight && $0.width==p.w && $0.height==p.h})else{return};store.apply(m)})}

    private func encodingBinding(_ d:DisplaySnapshot)->Binding<UInt32>{Binding(get:{d.activeRawPixelEncoding ?? UInt32.max},set:{store.applyOutputEncoding($0)})}
    private func bitDepthBinding(_ d:DisplaySnapshot)->Binding<Int>{Binding(get:{d.activeBitDepth ?? -1},set:{store.applyBitDepth($0)})}
    private func aspectRatio(_ d:DisplaySnapshot)->String{guard let m=current(d)else{return"未知"};return DisplayResolutionCatalog.aspectRatio(width:m.outputWidth,height:m.outputHeight,isBuiltin:d.isBuiltin)}
    private func resolutionLabel(_ p:Pair)->String{let name:String;if p.w==3840 && p.h==2160{name="4K"}else if p.w==2560 && p.h==1440{name="2K / QHD"}else if p.w==1920 && p.h==1080{name="1080p"}else if p.w==1280 && p.h==720{name="720p"}else if Double(p.w)/Double(max(1,p.h))>2{name="超宽屏"}else{name=""};return name.isEmpty ? "\(p.w) × \(p.h)" : "\(name) · \(p.w) × \(p.h)"}
    private func setSize(_ n:Double,_ d:DisplaySnapshot){let c=preferences.correction(for:d.hardwareKey);preferences.setCorrection(DisplayCorrection(alias:c?.alias ?? "",diagonalInches:n,role:c?.role ?? .automatic,outputPreference:c?.outputPreference ?? .automatic),for:d.hardwareKey);store.refresh()}
}

private struct WrappingHStackLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let arrangement = arrange(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        for (index, point) in arrangement.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: min(usedWidth, width), height: y + rowHeight), points)
    }
}
