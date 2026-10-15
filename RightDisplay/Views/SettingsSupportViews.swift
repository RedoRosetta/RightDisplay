// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import SwiftUI

enum RightDisplayUI {
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 18
    static let submenuIndent: CGFloat = 8
    static let rowHeight: CGFloat = 46
    static let rowIconSize: CGFloat = 30
    static let cardIconSize: CGFloat = 33
    static let cardIconFontSize: CGFloat = 14.3
    static let sectionSpacing: CGFloat = 14
    static let overviewGridSpacing: CGFloat = 14
    static let quickRowHeight: CGFloat = 58

    static let cardTitle: Font = .headline
    static let primaryValue: Font = .title3.weight(.semibold)
    static let rowLabel: Font = .callout.weight(.medium)
    static let secondary: Font = .caption
}

struct DisplayConfirmationView: View {
    @EnvironmentObject private var store: DisplayStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "display.and.arrow.down")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(spacing: 7) {
                if store.pendingModeConfirmation {
                    Text("显示链路已稳定").font(.title2.weight(.semibold))
                    Text(AppLocalization.string(store.pendingVerificationText)).font(.callout.weight(.medium))
                    Text("是否保留此设置？").font(.callout)
                    Text("\(store.confirmationSeconds) 秒后将自动恢复原设置。")
                        .foregroundStyle(.secondary)
                } else {
                    Text("正在切换显示链路").font(.title2.weight(.semibold))
                    Text(AppLocalization.format("目标：%@", AppLocalization.string(store.pendingChangeSummary)))
                        .font(.callout.weight(.medium))
                    ProgressView()
                        .controlSize(.small)
                    Text(AppLocalization.string(store.verifiedLinkApplyStatus))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if store.pendingModeConfirmation {
                HStack(spacing: 12) {
                    Button("恢复") { store.restorePendingModeIfNeeded() }
                        .keyboardShortcut(.cancelAction)
                    Button("保留") { store.confirmPendingMode() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!store.linkVerificationComplete)
                }
            } else {
                Button("取消并恢复") { store.restorePendingModeIfNeeded() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 390)
    }
}

enum AdvancedPage: String, CaseIterable, Identifiable {
    case overview, displayOutput, sound, colorProfiles, edid, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .displayOutput: AppLocalization.isEnglish ? "Display" : "显示"
        case .colorProfiles: "ICC"
        case .edid: "EDID"
        case .sound: AppLocalization.isEnglish ? "Audio" : "音频"
        case .general: "通用"
        }
    }

    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .displayOutput: "display"
        case .colorProfiles: "doc.richtext"
        case .edid: "doc.text.magnifyingglass"
        case .sound: "waveform"
        case .general: "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: AppLocalization.isEnglish ? "Display status and common actions" : "当前显示状态与常用操作"
        case .displayOutput: AppLocalization.isEnglish ? "Brightness, resolution and display link settings" : "亮度、分辨率与显示链路设置"
        case .sound: AppLocalization.isEnglish ? "Volume adjustment, virtual audio and Apple TV audio controls" : "调节音量、虚拟音频与 Apple TV 音频控制"
        case .colorProfiles: AppLocalization.isEnglish ? "Profiles, color characteristics and calibration curves" : "描述文件管理、色彩特性与校准曲线"
        case .edid: AppLocalization.isEnglish ? "Display identification data and capability analysis" : "显示器识别数据与能力解析"
        case .general: AppLocalization.isEnglish ? "Language, launch, diagnostics and app information" : "语言、启动、诊断与应用信息"
        }
    }
}

enum SettingsTarget: String, Hashable {
    case displayMode
    case refreshRate
    case pixelFormat
    case bitDepth
    case vrr
    case dsc
    case hdr
    case capabilityTest
}

enum DisplayEncodingOptions {
    struct Choice: Identifiable {
        let title: String
        let raw: UInt32
        var id: UInt32 { raw }
    }

    static let choices = LinkPixelEncoding.allCases.map { Choice(title: $0.title, raw: $0.rawValue) }

    static func choices(for display: DisplaySnapshot) -> [Choice] {
        choices.filter { choice in choice.raw != LinkPixelEncoding.yCbCr420.rawValue ||
            display.activeRawPixelEncoding == choice.raw || display.linkCapabilities.contains { $0.rawPixelEncoding == choice.raw } }
    }

    static func title(for raw: UInt32?, fallback: String) -> String {
        raw == nil ? fallback : LinkPixelEncoding.title(for: raw)
    }
}

struct SettingsTargetHighlight: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(active ? 0.13 : 0))
                    .padding(.horizontal, -10)
                    .padding(.vertical, -7)
            )
            .animation(.easeInOut(duration: 0.20), value: active)
    }
}
struct Pair:Identifiable,Hashable { let w:Int;let h:Int;var id:String{"\(w)x\(h)"};init(w:Int,h:Int){self.w=w;self.h=h};init?(id:String){let p=id.split(separator:"x").compactMap{Int($0)};guard p.count==2 else{return nil};w=p[0];h=p[1]} }
// Only child rows inherit indentation; card headings, dividers and trailing controls stay aligned.
private struct CardSubmenuIndentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
extension EnvironmentValues {
    var cardSubmenuIndent: CGFloat {
        get { self[CardSubmenuIndentKey.self] }
        set { self[CardSubmenuIndentKey.self] = newValue }
    }
}
struct CardSubmenuInset: ViewModifier {
    var amount: CGFloat? = nil
    @Environment(\.cardSubmenuIndent) private var inheritedIndent
    func body(content: Content) -> some View {
        content.padding(.leading, amount ?? inheritedIndent)
    }
}

struct GlassCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let icon: String?
    let verticalPadding: CGFloat
    let content: Content
    let fillsAvailableHeight: Bool
    @State private var hovering = false

    init(
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        verticalPadding: CGFloat = RightDisplayUI.cardPadding,
        fillsAvailableHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.verticalPadding = verticalPadding
        self.content = content()
        self.fillsAvailableHeight = fillsAvailableHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(alignment: .center, spacing: 10) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: RightDisplayUI.cardIconFontSize, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: RightDisplayUI.cardIconSize, height: RightDisplayUI.cardIconSize)
                            .background(
                                Color.primary.opacity(hovering ? 0.045 : 0.025),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.string(title)).font(RightDisplayUI.cardTitle)
                        if let subtitle { Text(AppLocalization.string(subtitle)).font(RightDisplayUI.secondary).foregroundStyle(.secondary) }
                    }
                }
            }
            content.environment(\.cardSubmenuIndent, title == nil ? 0 : RightDisplayUI.submenuIndent)
        }
        .frame(maxWidth: .infinity, maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .topLeading)
        .padding(.horizontal, RightDisplayUI.cardPadding)
        .padding(.vertical, verticalPadding)
        .contentShape(RoundedRectangle(cornerRadius: RightDisplayUI.cardRadius, style: .continuous))
        .modifier(AdaptiveGlassCard(hovering: hovering))
        // Keep card coordinates stable during hover/scroll hit testing.
        // The visual surface lifts independently of the content/hit-test coordinates.
        .onHover { if hovering != $0 { hovering = $0 } }
    }
}

struct AdaptiveGlassCard: ViewModifier {
    let hovering: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: RightDisplayUI.cardRadius, style: .continuous)
        content.background {
            // Only the decorative surface moves; charts, controls and hover bounds stay fixed.
            Color.clear
                .modifier(UnifiedGlassSurface(shape: shape))
                .overlay {
                    shape.strokeBorder(
                        Color(nsColor: .separatorColor).opacity(reduceTransparency ? 1 : (hovering ? 0.40 : 0.22)),
                        lineWidth: reduceTransparency ? 1 : 0.7
                    )
                }
                .scaleEffect(!reduceMotion && hovering ? 1.0015 : 1)
                .shadow(color: .black.opacity(colorScheme == .dark ? (hovering ? 0.10 : 0.07) : (hovering ? 0.04 : 0.025)),
                        radius: hovering ? 5 : 4, y: 2)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .allowsHitTesting(false)
        }
    }
}

struct OverviewHeroCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .modifier(OverviewHeroSurface())
    }
}

struct OverviewHeroSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovering = false

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .modifier(UnifiedGlassSurface(shape: shape))
            .overlay {
                shape.fill(Color.primary.opacity(hovering ? 0.025 : 0)).allowsHitTesting(false)
            }
            .overlay { shape.strokeBorder(Color(nsColor: .separatorColor).opacity(hovering ? 0.35 : 0.15), lineWidth: 0.7).allowsHitTesting(false) }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct OverviewMetricButton: View {
    let title: String
    let value: String
    let icon: String
    let help: String
    let status: OverviewFeatureState?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(hovering ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(AppLocalization.string(title))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text(AppLocalization.string(value))
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if let status {
                        Circle()
                            .fill(status.color)
                            .frame(width: 8, height: 8)
                            .overlay { Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.6) }
                            .shadow(color: status.color.opacity(0.40), radius: 3)
                            .help(AppLocalization.string(status.help))
                            .accessibilityLabel(AppLocalization.string(status.accessibilityLabel))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .modifier(OverviewMetricSurface(hovering: hovering))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 96)
        .scaleEffect(hovering ? 1.008 : 1)
        .animation(.easeOut(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
        .help(AppLocalization.string(help))
        .accessibilityLabel(AppLocalization.string(title))
        .accessibilityValue(AppLocalization.string(value))
    }
}

struct OverviewFeatureState {
    enum Level { case enabled, available, unsupported }
    let level: Level
    let help: String

    var color: Color {
        switch level {
        case .enabled: .green
        case .available: .yellow
        case .unsupported: .red
        }
    }

    var accessibilityLabel: String {
        switch level {
        case .enabled: "已启用"
        case .available: "支持但未启用"
        case .unsupported: "不支持"
        }
    }
}

struct OverviewMetricSurface: ViewModifier {
    let hovering: Bool
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
        content.modifier(UnifiedGlassSurface(shape: shape))
            .overlay { shape.strokeBorder(Color.primary.opacity(hovering ? 0.13 : 0.07), lineWidth: 0.7) }
    }
}

struct LiquidChoiceControl<Value: Hashable>: View {
    let choices: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 5) {
            ForEach(choices.indices, id: \.self) { index in
                let choice = choices[index]
                LiquidChoiceButton(
                    title: choice.0,
                    selected: selection == choice.1
                ) { selection = choice.1 }
            }
        }
        .padding(4)
        .modifier(LiquidControlGroupSurface())
    }
}

// One card material at every existing card radius; system glass owns the blur and boundary.
struct UnifiedGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var lightweight = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: shape)
        } else if #available(macOS 26.0, *) {
            content.background {
                shape.fill(Color(nsColor: .controlBackgroundColor).opacity(lightweight ? 0.10 : 0.18))
                    .glassEffect(.clear, in: shape)
                    .opacity(lightweight ? 0.60 : 0.78)
            }
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

struct NativeSelectionPicker: NSViewRepresentable {
    struct Option: Equatable {
        let id: String
        let title: String
        var separatorBefore = false
    }
    let options: [Option]
    let selectedID: String
    let fallbackTitle: String
    var prominent = false
    let onSelect: (String) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = HoverSelectionButton(frame: .zero, pullsDown: false)
        button.prominent = prominent
        button.isBordered = false
        button.alignment = .right
        button.font = .systemFont(ofSize: 13)
        button.menu?.autoenablesItems = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        (button as? HoverSelectionButton)?.prominent = prominent
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        let previousSelection = coordinator.selectedID
        let previousTitle = button.title
        let previousEnabled = button.isEnabled
        coordinator.selectedID = selectedID
        coordinator.validIDs = Set(options.map(\.id))
        let missing = !options.contains { $0.id == selectedID }
        let displayed = missing ? [Option(id: selectedID, title: AppLocalization.string(fallbackTitle))] + options : options
        if coordinator.displayed != displayed {
            button.removeAllItems()
            for option in displayed {
                if option.separatorBefore { button.menu?.addItem(.separator()) }
                let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
                item.representedObject = option.id
                item.isEnabled = coordinator.validIDs.contains(option.id)
                button.menu?.addItem(item)
            }
            coordinator.displayed = displayed
        }
        for item in button.itemArray {
            let matches = (item.representedObject as? String) == selectedID
            let state: NSControl.StateValue = matches && !missing ? .on : .off
            if item.state != state { item.state = state }
            if matches && button.selectedItem !== item { button.select(item) }
        }
        let enabled = isEnabled && !options.isEmpty
        if button.isEnabled != enabled { button.isEnabled = enabled }
        // AppKit selection already invalidates when it changes. Do not create
        // a SwiftUI/AppKit layout feedback loop on every unchanged update.
        if previousTitle != button.title { button.invalidateIntrinsicContentSize() }
        if previousSelection != selectedID || previousEnabled != button.isEnabled { button.needsDisplay = true }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let width = (nsView.title as NSString).size(withAttributes: [.font: nsView.font ?? NSFont.systemFont(ofSize: 13)]).width
        // Full title + leading/trailing padding + gap + arrow footprint.
        return CGSize(width: ceil(width) + 48, height: 30)
    }

    final class Coordinator: NSObject {
        var displayed: [Option] = []
        var validIDs: Set<String> = []
        var selectedID = ""
        var onSelect: ((String) -> Void)?
        @objc func select(_ sender: NSPopUpButton) {
            guard let id = sender.selectedItem?.representedObject as? String, validIDs.contains(id) else { return }
            // The menu is not an independent source of truth. Keep the last model value
            // visible until the existing binding/readback publishes the next value.
            for item in sender.itemArray {
                let matches = (item.representedObject as? String) == selectedID
                item.state = matches ? .on : .off
                if matches { sender.select(item) }
            }
            onSelect?(id)
        }
    }
}

// Only paint the trigger surface; AppKit still owns menu tracking, positioning,
// keyboard navigation, selection and focus rendering.
private final class HoverSelectionButton: NSPopUpButton {
    var prominent = false { didSet { if oldValue != prominent { needsDisplay = true } } }
    private var hoverArea: NSTrackingArea?
    private var hovering = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // Draw the trigger once. AppKit still owns the popup cell, menu tracking,
        // selection, keyboard and accessibility; do not redraw its interior over
        // this surface or squeeze its title frame to make room for an arrow.
        let arrowRect = NSRect(x: bounds.maxX - 30, y: bounds.midY - 10, width: 20, height: 20)
        if prominent {
            NSColor.controlAccentColor.withAlphaComponent(isEnabled ? 1 : 0.45).setFill()
            NSBezierPath(roundedRect:bounds,xRadius:9,yRadius:9).fill()
            if hovering && isEnabled {
                NSColor.white.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect:bounds,xRadius:9,yRadius:9).fill()
            }
        } else if hovering && isEnabled {
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        } else {
            NSColor.labelColor.withAlphaComponent(isEnabled ? 0.055 : 0.025).setFill()
            NSBezierPath(ovalIn: arrowRect).fill()
        }
        let foreground = prominent ? NSColor.white : (isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor)
        let text = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: foreground
        ])
        let textSize = text.size()
        text.draw(at: NSPoint(x: arrowRect.minX - 8 - textSize.width, y: bounds.midY - textSize.height / 2))
        let symbol = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [foreground]))
        symbol?.draw(in: arrowRect.insetBy(dx: 4, dy: 3))
    }
}

struct CompactActionButtonStyle: ButtonStyle {
    var primary = false
    var minWidth: CGFloat = 58
    func makeBody(configuration: Configuration) -> some View {
        Face(label: configuration.label, pressed: configuration.isPressed, primary: primary, minWidth: minWidth)
    }
    private struct Face<Label: View>: View {
        let label: Label
        let pressed: Bool
        let primary: Bool
        let minWidth: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            label.font(.callout.weight(.medium))
                .foregroundStyle(primary ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .frame(minWidth: minWidth, minHeight: 30)
                .background(primary ? Color.accentColor : Color(nsColor: .controlColor), in: shape)
                .overlay(shape.fill(Color.primary.opacity(pressed ? 0.09 : (hovering ? 0.035 : 0))).allowsHitTesting(false))
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor).opacity(primary ? 0 : 0.6), lineWidth: 0.7))
                .contentShape(shape).opacity(enabled ? 1 : 0.45)
                .onHover { hovering = $0 }
        }
    }
}

struct NeutralActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NeutralActionFace(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct NeutralActionFace<Label: View>: View {
        let label: Label
        let pressed: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            label
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(Color(nsColor: .controlColor), in: shape)
                .overlay(shape.fill(Color.primary.opacity(pressed ? 0.08 : (hovering ? 0.035 : 0))).allowsHitTesting(false))
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.7))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
        }
    }
}

struct LiquidChoiceButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(AppLocalization.string(title))
                .font(.callout.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.90))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 26)
                .padding(.horizontal, 8)
                .background(
                    selected ? Color.accentColor : (hovering ? Color.primary.opacity(0.07) : Color.clear),
                    in: Capsule()
                )
                .overlay {
                    Capsule().strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.easeOut(duration: 0.14), value: selected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct LiquidControlGroupSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(Color.primary.opacity(0.035), in: Capsule())
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    final class Coordinator {
        var appliedInitialSize = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, coordinator: context.coordinator) }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.title = title
        window.styleMask.insert(.resizable)
        window.minSize = NSSize(width: 760, height: 540)
        window.maxSize = NSSize(width: 10_000, height: 10_000)
        window.contentMinSize = NSSize(width: 760, height: 500)
        window.contentMaxSize = NSSize(width: 10_000, height: 10_000)
        window.isRestorable = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        if !coordinator.appliedInitialSize {
            coordinator.appliedInitialSize = true
            let availableHeight = max(540, (window.screen?.visibleFrame.height ?? 920) - 72)
            let targetHeight = min(840, availableHeight)
            if window.contentLayoutRect.height < targetHeight {
                window.setContentSize(NSSize(width: window.contentLayoutRect.width, height: targetHeight))
            }
        }
    }
}

struct RightDisplayBackdrop: View {
    var body: some View {
        WindowFrostedMaterial()
        .allowsHitTesting(false)
    }
}

struct WindowFrostedMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.isEmphasized = true
    }
}

struct FrostedSidebarSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(0.015))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 0.7)
            }
    }
}

struct AdvancedWindowMaterial: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                WindowFrostedMaterial()
                    .overlay(Color(nsColor: .controlBackgroundColor).opacity(0.32))
            }
        }.ignoresSafeArea()
    }
}

struct EDIDFieldGroup: Identifiable {
    let title: String
    let icon: String
    let fields: [EDIDField]
    var id: String { title }
}

// Hover state belongs to the decoration, keeping parent rows and panels stable.
struct RowHoverBackground: ViewModifier {
    let radius: CGFloat
    var selected = false
    var hoverColor: Color = .accentColor
    var hoverOpacity: Double = 0.055
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.085) : hoverColor.opacity(hovering ? hoverOpacity : 0))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .allowsHitTesting(false)
        }
        .onHover { inside in
            guard hovering != inside else { return }
            hovering = inside
        }
    }
}

struct EDIDFieldDisclosure: View {
    let field: EDIDField
    @State private var expanded = false

    init(field: EDIDField) { self.field = field }

    var body: some View {
        Button { expanded.toggle() } label: {
            VStack(alignment: .leading, spacing: expanded ? 9 : 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(AppLocalization.string(field.title))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 16)
                    Text(AppLocalization.string(field.value))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(expanded ? nil : 2)
                    Image(systemName: "chevron.forward")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                if expanded {
                    Text(AppLocalization.string(field.detail))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.trailing, 22)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .modifier(RowHoverBackground(radius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }
}

struct EDIDRawGlassCard: View {
    let hexText: String
    @State private var expanded = false
    @State private var copied = false

    var body: some View {
        GlassCard(title: "EDID 原文", subtitle: "按 16 字节分行显示 macOS 提供的原始数据。", icon: "chevron.left.forwardslash.chevron.right") {
            HStack {
                Button { expanded.toggle() } label: {
                    HStack {
                    Text(AppLocalization.string(expanded ? "收起十六进制数据" : "显示十六进制数据"))
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hexText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(hexText.isEmpty)
            }.modifier(CardSubmenuInset())
            if expanded {
                ScrollView(.horizontal) {
                    Text(AppLocalization.string(hexText.isEmpty ? "macOS 当前未向应用提供完整的 EDID 原文。" : hexText))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }
}

struct IdentityEditor: View {
    private var parsedSize:Double? {
        guard let value = Double(size.replacingOccurrences(of:",",with:".")), value.isFinite, value > 0 else { return nil }; return value
    }
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DisplayStore
    @EnvironmentObject private var preferences: Preferences
    let display: DisplaySnapshot
    @State private var name: String
    @State private var size: String
    init(display: DisplaySnapshot) {
        self.display=display
        let correction=Preferences.shared.correction(for:display.hardwareKey)
        _name=State(initialValue:correction?.alias ?? "")
        _size=State(initialValue:correction?.diagonalInches.map{String(format:"%.1f",$0)} ?? "")
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Label("编辑显示器信息",systemImage:"pencil.and.outline").font(.title2.weight(.semibold))
            Text("只修正 Right Display 中显示的名称与尺寸，不会修改系统 EDID。")
                .foregroundStyle(.secondary)
            Form {
                TextField("设备名称",text:$name)
                TextField("实际对角线尺寸（英寸）",text:$size)
            }.formStyle(.grouped)
            HStack { Button("恢复系统值"){preferences.removeCorrection(for:display.hardwareKey);store.refresh();dismiss()};Spacer();Button("取消"){dismiss()};Button("保存") { let old=preferences.correction(for:display.hardwareKey);preferences.setCorrection(DisplayCorrection(alias:name.trimmingCharacters(in:.whitespacesAndNewlines),diagonalInches:parsedSize,role:old?.role ?? .automatic,outputPreference:old?.outputPreference ?? .automatic),for:display.hardwareKey);store.refresh();dismiss() }.buttonStyle(.borderedProminent).disabled(!size.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && parsedSize == nil) }
        }.padding(22).frame(width:460)
    }
}

struct VolumeLevelControl: View {
    let value: Binding<Double>
    var range: ClosedRange<Double> = 0...1
    let percent: Int
    let accessibilityLabel: String
    var onEditingChanged: (Bool) -> Void = { _ in }
    var body: some View {
        HStack(spacing:10) {
            Slider(value:value,in:range,onEditingChanged:onEditingChanged)
                .controlSize(.regular).frame(width:278,height:28).accessibilityLabel(accessibilityLabel)
            Text("\(percent)%").font(.callout.weight(.medium)).monospacedDigit().frame(width:38,alignment:.trailing)
        }.frame(width:326,height:32,alignment:.trailing)
    }
}

// Scope scrollbar policy to the advanced page's own scroll container.
struct StablePageScrollGutter: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.configureScrollView() }
    final class Marker: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureScrollView()
            DispatchQueue.main.async { [weak self] in self?.configureScrollView() }
        }
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureScrollView()
        }
        func configureScrollView() {
            guard let scroll = enclosingScrollView else { return }
            scroll.scrollerStyle = .overlay
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsets()
            scroll.scrollerInsets = NSEdgeInsets()
        }
    }
}

// All six pages receive one viewport-constrained content width, irrespective of
// the intrinsic width of a card, picker or overview grid.
enum AdvancedPageGeometry {
    static let margin: CGFloat = 24
    static func documentWidth(viewport: CGFloat) -> CGFloat {
        max(0, viewport - NSScroller.scrollerWidth(for:.regular,scrollerStyle:.legacy))
    }
    static func contentWidth(viewport: CGFloat) -> CGFloat {
        max(0, documentWidth(viewport:viewport) - 2 * margin)
    }
}

enum BrightnessWarningPresentation {
    static let duration: TimeInterval = 2
    static func shouldHide(brightness: Double) -> Bool {
        // CoreGraphics reads Float values; tolerate rounding at exactly 20%.
        !brightness.isFinite || brightness > Double(Float(BrightnessDragProtection.stop))
    }
}

struct BrightnessWarningAnchor: NSViewRepresentable {
    let brightness: Double
    let sequence: UInt64
    let source: String?
    let controlID: String
    func makeCoordinator() -> Coordinator { Coordinator(sequence:sequence) }
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) {
        if BrightnessWarningPresentation.shouldHide(brightness:brightness) {
            context.coordinator.sequence = sequence
            context.coordinator.hide()
            return
        }
        guard context.coordinator.sequence != sequence else { return }
        context.coordinator.sequence = sequence
        if source == controlID { context.coordinator.show(below:view) }
    }
    static func dismantleNSView(_ view: Marker, coordinator: Coordinator) { coordinator.hide() }
    final class Marker: NSView {
        override func hitTest(_ point:NSPoint) -> NSView? { nil }
    }
    final class Coordinator {
        var sequence: UInt64
        private var panel: NSPanel?
        private var dismissal: DispatchWorkItem?
        init(sequence: UInt64) { self.sequence = sequence }
        func show(below anchor: NSView) {
            guard let window = anchor.window, window.isVisible, let screen = window.screen else { return }
            hide()
            let message = AppLocalization.isEnglish
                ? "Low brightness may make screen content difficult to see. You can continue dragging to lower it."
                : "亮度过低可能导致屏幕内容难以辨认，你仍可继续拖动调低。"
            let content = Text(message).font(.callout).padding(12).frame(width:310)
                .background(.regularMaterial,in:RoundedRectangle(cornerRadius:10))
            let hosting = NSHostingView(rootView:content)
            let size = hosting.fittingSize
            let target = window.convertToScreen(anchor.convert(anchor.bounds,to:nil))
            let visible = screen.visibleFrame
            let origin = NSPoint(x:max(visible.minX+8,min(target.maxX-size.width,visible.maxX-size.width-8)),
                                 y:max(visible.minY+8,min(target.minY-size.height-8,visible.maxY-size.height-8)))
            let panel = NSPanel(contentRect:NSRect(origin:origin,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.isReleasedWhenClosed = false; panel.hasShadow = true
            panel.level = .popUpMenu; panel.ignoresMouseEvents = true
            panel.contentView = hosting
            self.panel = panel
            panel.orderFrontRegardless()
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            dismissal = work
            DispatchQueue.main.asyncAfter(deadline:.now()+BrightnessWarningPresentation.duration,execute:work)
        }
        func hide() { dismissal?.cancel();dismissal = nil;panel?.orderOut(nil);panel?.close();panel = nil }
    }
}
