// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import CoreText
import Combine
import CoreGraphics
import Network
import QuartzCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusBarController: StatusBarController?
    private var localNetworkBrowser: NWBrowser?
    private var audioInterruptionPanel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private let appleTVAudio = AppleTVAudioController.shared
    private let hudController = HUDWindowController(
        store: .shared,
        preferences: .shared
    )
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DiagnosticEvents.record("app", "launch", result: "menu-bar process started")
        if Preferences.shared.safeModeEnabled {
            DisplayStore.shared.enterSafeSession()
        }
        DisplayStore.shared.startMonitoring()
        let virtualVolume = VirtualVolumeController.shared
        virtualVolume.$model.map(\.unexpectedStop).removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                // @Published delivers before assignment. Present after the reducer settles.
                DispatchQueue.main.async { self?.presentAudioInterruption() }
            }.store(in: &cancellables)
        virtualVolume.startMonitoring()
        let audioOutput = AudioOutputStore.shared
        let usesAppleTV = audioOutput.selectedControlTargetID == AudioOutputStore.appleTVTargetID
        if usesAppleTV { requestLocalNetworkAccess() }
        appleTVAudio.start(active: usesAppleTV)
        audioOutput.$selectedControlTargetID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] target in
                let active = target == AudioOutputStore.appleTVTargetID
                self?.appleTVAudio.setUsageEnabled(active)
                if active { self?.requestLocalNetworkAccess() }
            }
            .store(in: &cancellables)
        hudController.start()
        statusBarController = StatusBarController(store: .shared, preferences: .shared)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.statusBarController?.showLaunchToast()
        }
        if !Preferences.shared.onboardingCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.statusBarController?.showMainPanel()
            }
        }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-advanced") {
            DispatchQueue.main.async { AdvancedWindowController.shared.show() }
        }
#endif
        if Preferences.shared.onboardingCompleted,
           SMAppService.mainApp.status == .enabled,
           Preferences.shared.showPanelOnLoginLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.statusBarController?.showMainPanel()
            }
        }
        if !DisplayStore.shared.safeSessionActive,
           SMAppService.mainApp.status == .enabled,
           Preferences.shared.claimLoginLaunchAutoCorrection() {
            performLoginAutoCorrection(attempt: 0)
        }
    }

    private func presentAudioInterruption() {
        let controller = VirtualVolumeController.shared
        guard controller.model.unexpectedStop, controller.isSystemRoute,
              audioInterruptionPanel == nil else { return }
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:420,height:215),
                            styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.title = AppLocalization.isEnglish ? "Audio forwarding interrupted" : "虚拟音频转发中断"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let content = NSHostingView(rootView:AudioInterruptionNotice(controller:controller) { [weak self, weak panel] in
            panel?.close(); self?.audioInterruptionPanel = nil
        })
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
        audioInterruptionPanel = panel
        panel.center(); panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }

    func windowWillClose(_ notification: Notification) {
        if let panel = notification.object as? NSPanel, panel === audioInterruptionPanel {
            audioInterruptionPanel = nil
        }
    }

    private func requestLocalNetworkAccess() {
        guard localNetworkBrowser == nil else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_airplay._tcp", domain: nil),
            using: parameters
        )
        localNetworkBrowser = browser
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready, .failed:
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.localNetworkBrowser?.cancel()
                    self?.localNetworkBrowser = nil
                }
            default:
                break
            }
        }
        browser.start(queue: .main)
    }

    private func performLoginAutoCorrection(attempt: Int) {
        guard Preferences.shared.autoCorrectColorOnLoginLaunch else { return }
        DisplayStore.shared.refresh()
        DisplayStore.shared.scheduleConditionalCorrection(reason: "登录启动")
        if Preferences.shared.showPanelOnLoginLaunch {
            statusBarController?.showAutoCorrectionProcess()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticEvents.record("app", "terminate", result: "normal termination")
        VirtualVolumeController.shared.shutdown()
        DisplayStore.shared.stopMonitoring()
        DisplayStore.shared.restoreCapabilityTestForTerminationIfNeeded()
        DisplayStore.shared.restorePendingModeIfNeeded()
    }
}

// App-level notice remains available when the Audio page is not visible.
// Recovery is an explicit user request through the existing validated route start.
private struct AudioInterruptionNotice: View {
    @ObservedObject var controller: VirtualVolumeController
    @ObservedObject private var virtualDevice = VirtualAudioDeviceStore.shared
    let close: () -> Void
    private func l(_ cn:String,_ en:String) -> String { AppLocalization.isEnglish ? en : cn }
    private var recoveryAvailable: Bool {
        controller.canStart && virtualDevice.installed && virtualDevice.status.loaded
            && virtualDevice.status.matches == 1 && virtualDevice.status.rate == 48000
            && controller.selectedDevice.map { [44100.0,48000,88200,96000,176400,192000].contains($0.rate) } == true
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Label(l("虚拟音频转发已中断","Virtual audio forwarding was interrupted"),systemImage:"exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text(l("转发已停止。你可以重新启动转发，具体原因可在音频页的「运行详情」中查看。",
                   "Forwarding has stopped. You can restart it; details are available under Audio → Runtime details."))
                .font(.callout).fixedSize(horizontal:false,vertical:true)
            if controller.needsRestart {
                Text(l("音频路径未确认退出，请先重新启动 App。","Audio teardown is unconfirmed. Restart the app first."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if !controller.canStart && !controller.busy {
                Text(l("正在确认音频设备；若仍无法恢复，请到音频页检查目标设备及运行详情。",
                       "Checking the audio device. If recovery remains unavailable, check the target and runtime details on the Audio page."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing:10) {
                Spacer()
                Button(l("关闭","Close"),action:close).buttonStyle(NeutralActionButtonStyle())
                Button(l(controller.busy ? "正在恢复…" : "重新启动转发",controller.busy ? "Restarting…" : "Restart forwarding")) {
                    controller.startRoute()
                }.buttonStyle(CompactActionButtonStyle(primary:true)).disabled(!recoveryAvailable)
            }
        }.padding(22).frame(width:420)
        .onAppear { virtualDevice.refresh(); controller.refresh() }
        .onChange(of:controller.model.unexpectedStop) { _, stopped in
            if !stopped && controller.forwardingEnabled { close() }
        }
    }
}

@MainActor
final class AdvancedWindowController: NSObject, NSWindowDelegate {
    static let shared = AdvancedWindowController()

    private var window: NSWindow?

    func show() {
        DiagnosticEvents.record("ui", "advanced.opened")
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsView()
            .environmentObject(DisplayStore.shared)
            .environmentObject(Preferences.shared)
        let hostingController = NSHostingController(rootView: root)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let defaultSize = NSSize(
            width: min(1080, visibleFrame.width - 80),
            height: min(740, visibleFrame.height - 64)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Right Display"
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(width: 820, height: 560)
        window.minSize = NSSize(width: 820, height: 588)
        window.maxSize = NSSize(width: 10_000, height: 10_000)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.delegate = self
        window.setContentSize(defaultSize)
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AboutWindowController: NSObject {
    static let shared = AboutWindowController()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let size = NSSize(width: 360, height: 250)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppLocalization.string("关于 RightDisplay")
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: AboutRightDisplayView())
        window.setContentSize(size)
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AboutRightDisplayView: View {
    @State private var showingSponsor = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 9) {
            RightDisplayBrandMark(size: 60)
            Text("RightDisplay")
                .font(.title3.weight(.semibold))
            Text("\(RightDisplayReleaseHistory.currentVersion) · Build \(build)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AppLocalization.string("RightDisplay | 正确显示，用于查看、解释、验证并安全校正 Mac 的显示链路。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
            HStack(spacing:12) {
            Button("GitHub") {
                // The public project URL is documented in README.md.
                if let url = URL(string: "https://github.com/RedoRosetta/RightDisplay") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(NeutralActionButtonStyle())
            .padding(.top, 2)
            Button(AppLocalization.isEnglish ? "Sponsor" : "赞助") { showingSponsor = true }.buttonStyle(NeutralActionButtonStyle())
            }
        }
        .sheet(isPresented:$showingSponsor) {
            VStack(spacing:16) {
                Text(AppLocalization.isEnglish ? "Support development" : "支持开发").font(.title2.weight(.semibold))
                HStack(alignment:.top,spacing:20) {
                    sponsorCode("alipay",title:AppLocalization.isEnglish ? "Alipay" : "支付宝")
                    sponsorCode("wechat-pay",title:AppLocalization.isEnglish ? "WeChat Pay" : "微信支付")
                }
                Button(AppLocalization.isEnglish ? "Close" : "关闭") { showingSponsor = false }.keyboardShortcut(.cancelAction)
            }.padding(24)
        }
        .frame(width: 360, height: 250)
        .background(AdvancedWindowMaterial())
    }
    @ViewBuilder private func sponsorCode(_ name:String,title:String) -> some View {
        VStack(spacing:8) {
            Text(title).font(.headline)
            if let url = Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"Sponsor"), let image = NSImage(contentsOf:url) {
                Image(nsImage:image).resizable().interpolation(.high).scaledToFit().frame(width:210,height:280)
            } else { Text(AppLocalization.isEnglish ? "Image unavailable" : "收款码不可用").frame(width:210,height:280) }
        }
    }
}

@MainActor
private final class StatusBarController: NSObject {
    private let store: DisplayStore
    private let preferences: Preferences
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var launchToast: NSPanel?
    private var didShowLaunchToast = false
    private var cancellables = Set<AnyCancellable>()

    init(store: DisplayStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
        super.init()

        if let button = statusItem.button {
            button.image = Self.makeStatusIcon()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemPressed(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        let popoverController = NSHostingController(
            rootView: QuickPanelView()
                .environmentObject(store)
                .environmentObject(preferences)
        )
        popover.contentViewController = popoverController
        popoverController.view.layoutSubtreeIfNeeded()
        let fittingSize = popoverController.view.fittingSize
        popover.contentSize = NSSize(
            width: 390,
            height: min(620, max(360, fittingSize.height))
        )

        Publishers.CombineLatest(store.$displays, store.$selectedDisplayID)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .automaticCorrectionTriggered)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.showAutoCorrectionProcess() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .usageGuideRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.showMainPanel() }
            .store(in: &cancellables)
        updateStatusItem()
    }

    @objc private func statusItemPressed(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu(for: sender, event: event)
        } else {
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            DiagnosticEvents.record("ui", "quick-panel.opened")
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.async { [weak self] in
                self?.configurePopoverWindow()
            }
        }
    }

    private func showContextMenu(for button: NSStatusBarButton, event: NSEvent) {
        popover.performClose(nil)
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: button)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("显示快捷面板", action: #selector(openMainPanel), key: ""))
        menu.addItem(menuItem("立即刷新", action: #selector(refresh), key: "r"))
        menu.addItem(.separator())

        let launchItem = menuItem("登录时启动", action: #selector(toggleLaunchAtLogin), key: "")
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)
        let safeItem = menuItem("安全模式", action: #selector(toggleSafeMode), key: "")
        safeItem.state = store.safeSessionActive ? .on : .off
        menu.addItem(safeItem)
        menu.addItem(menuItem("高级", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem("关于 Right Display", action: #selector(showAbout), key: ""))
        menu.addItem(menuItem("退出 Right Display", action: #selector(quit), key: "q"))
        return menu
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: AppLocalization.string(title), action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openMainPanel() {
        guard let button = statusItem.button else { return }
        togglePopover(relativeTo: button)
    }

    func showAutoCorrectionProcess() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            configurePopoverWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .autoCorrectionProcessRequested, object: nil)
        }
    }

    func showMainPanel() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async { [weak self] in
            self?.configurePopoverWindow()
        }
    }

    func showLaunchToast() {
        guard !didShowLaunchToast else { return }
        didShowLaunchToast = true
        let button = statusItem.button
        let buttonWindow = button?.window
        guard let screen = buttonWindow?.screen ?? NSScreen.main else { return }
        let target = button.flatMap { item in
            buttonWindow.map { $0.convertToScreen(item.convert(item.bounds, to: nil)) }
        }
        let visible = screen.visibleFrame
        let textSize = LaunchStrokeText.intrinsicSize
        let size = NSSize(width: ceil(textSize.width + 28), height: ceil(textSize.height + 18))
        let x = max(visible.minX + 8, min((target?.midX ?? visible.maxX) - size.width / 2,
            visible.maxX - size.width - 8))
        let y = max(visible.minY + 8, (target?.minY ?? visible.maxY) - size.height - 12)
        let panel = NSPanel(
            contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.contentView = NSHostingView(rootView:
            LaunchSignatureView(reduceTransparency: reduceTransparency, reduceMotion: reduceMotion)
                .frame(width: size.width, height: size.height)
        )
        launchToast = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : 0.22
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.75 : 2.95)) { [weak self, weak panel] in
            guard let self, let panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0.18 : 0.40
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self, weak panel] in
                guard let panel else { return }
                panel.alphaValue = 0
                panel.orderOut(nil)
                DispatchQueue.main.async { [weak self, weak panel] in
                    panel?.close()
                    self?.launchToast = nil
                }
            }
        }
    }

    @objc private func refresh() {
        store.refresh()
    }

    @objc private func openSettings() {
        AdvancedWindowController.shared.show()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            presentError(AppLocalization.format("无法修改登录启动设置：%@", error.localizedDescription))
        }
    }

    @objc private func toggleSafeMode() {
        if store.safeSessionActive {
            Preferences.shared.safeModeEnabled = false
            store.leaveSafeSession()
        } else {
            Preferences.shared.safeModeEnabled = true
            store.enterSafeSession()
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("Right Display｜正确显示")
        alert.informativeText = "\(RightDisplayReleaseHistory.currentVersion)\n\(AppLocalization.string("查看、解释、验证并安全校正 Mac 的显示链路。"))"
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppLocalization.string("好"))
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateStatusItem() {
        statusItem.button?.title = ""
        statusItem.button?.toolTip = store.selectedDisplay.map {
            "\($0.name) · \($0.resolution) · \($0.refreshRate.text)"
        } ?? "Right Display"
    }

    private func configurePopoverWindow() {
        guard let window = popover.contentViewController?.view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.makeKey()
    }

    private static func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.translateX(by: 10, yBy: 9)
            transform.scale(by: 1.06)
            transform.translateX(by: -10, yBy: -9)
            transform.concat()
            NSColor.black.setStroke()

            func strokeSpline(_ points: [NSPoint], lineWidth: CGFloat) {
                guard points.count > 1 else { return }
                let path = NSBezierPath()
                path.move(to: points[0])
                for index in 0..<(points.count - 1) {
                    let p0 = points[max(0, index - 1)]
                    let p1 = points[index]
                    let p2 = points[index + 1]
                    let p3 = points[min(points.count - 1, index + 2)]
                    path.curve(
                        to: p2,
                        controlPoint1: NSPoint(
                            x: p1.x + (p2.x - p0.x) / 6,
                            y: p1.y + (p2.y - p0.y) / 6
                        ),
                        controlPoint2: NSPoint(
                            x: p2.x - (p3.x - p1.x) / 6,
                            y: p2.y - (p3.y - p1.y) / 6
                        )
                    )
                }
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }

            let screen = NSBezierPath(
                roundedRect: NSRect(x: 1.3, y: 4.5, width: 17.4, height: 10),
                xRadius: 1.25,
                yRadius: 1.25
            )
            screen.lineWidth = 1.2
            screen.stroke()

            // Both centerlines are sampled from the supplied full-logo reference.
            strokeSpline([
                NSPoint(x: 1.50, y: 8.14),
                NSPoint(x: 2.50, y: 8.16),
                NSPoint(x: 3.50, y: 7.93),
                NSPoint(x: 4.50, y: 7.57),
                NSPoint(x: 5.50, y: 7.57),
                NSPoint(x: 6.50, y: 7.68),
                NSPoint(x: 7.50, y: 8.15),
                NSPoint(x: 8.50, y: 8.69),
                NSPoint(x: 9.50, y: 9.64),
                NSPoint(x: 10.50, y: 9.81),
                NSPoint(x: 11.50, y: 9.97),
                NSPoint(x: 12.50, y: 9.31),
                NSPoint(x: 13.50, y: 8.81),
                NSPoint(x: 14.50, y: 7.97),
                NSPoint(x: 15.50, y: 7.92),
                NSPoint(x: 16.50, y: 8.10),
                NSPoint(x: 17.50, y: 8.70),
                NSPoint(x: 18.50, y: 9.48)
            ], lineWidth: 1.05)

            strokeSpline([
                NSPoint(x: 2.40, y: 2.55),
                NSPoint(x: 2.94, y: 2.94),
                NSPoint(x: 4.03, y: 3.26),
                NSPoint(x: 5.11, y: 3.23),
                NSPoint(x: 6.20, y: 2.87),
                NSPoint(x: 7.29, y: 2.55),
                NSPoint(x: 8.37, y: 2.60),
                NSPoint(x: 9.46, y: 2.98),
                NSPoint(x: 10.54, y: 3.48),
                NSPoint(x: 11.63, y: 3.86),
                NSPoint(x: 12.71, y: 4.00),
                NSPoint(x: 13.80, y: 3.94),
                NSPoint(x: 14.89, y: 3.67),
                NSPoint(x: 15.97, y: 3.20),
                NSPoint(x: 17.06, y: 2.74),
                NSPoint(x: 17.60, y: 2.55)
            ], lineWidth: 0.75)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Right Display"
        return image
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Right Display"
        alert.informativeText = AppLocalization.string(message)
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct LaunchSignatureView: View {
    let reduceTransparency: Bool
    let reduceMotion: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        LaunchStrokeText(reduceMotion: reduceMotion)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                : AnyShapeStyle(.ultraThinMaterial),
            in: shape
        )
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 0.5))
    }
}

private struct LaunchStrokeText: View {
    private struct Glyph: Identifiable {
        let id: Int
        let path: Path
    }

    // Installed system font: restrained italic between plain text and handwriting.
    private static let font = CTFontCreateWithName(
        (NSFont(name: "AvenirNext-MediumItalic", size: 23)
            ?? NSFont.systemFont(ofSize: 23, weight: .medium)).fontName as CFString,
        23,
        nil
    )
    private static let layout: (glyphs: [Glyph], size: CGSize) = {
        let text = NSAttributedString(
            string: "Your display, right now.",
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        var output: [Glyph] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, 0), &positions)
            for index in 0..<count {
                guard let outline = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                var transform = CGAffineTransform(
                    a: 1, b: 0, c: 0, d: -1,
                    tx: positions[index].x + 3,
                    ty: ascent + 4 - positions[index].y
                )
                if let placed = outline.copy(using: &transform) {
                    output.append(Glyph(id: output.count, path: Path(placed)))
                }
            }
        }
        let pathExtent = output.reduce(CGRect.null) { $0.union($1.path.boundingRect) }
        let periodMaxX = output.last?.path.boundingRect.maxX ?? 0
        return (output, CGSize(
            width: ceil(max(width + 6, pathExtent.maxX + 3, periodMaxX + 6)),
            height: ceil(max(ascent + descent + 8, pathExtent.maxY + 3))
        ))
    }()

    static var intrinsicSize: CGSize { layout.size }

    let reduceMotion: Bool
    @State private var progress: CGFloat = 0
    @State private var revealStarted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.layout.glyphs) { glyph in
                glyph.path.fill(Color.primary)
            }
        }
        .frame(width: Self.layout.size.width, height: Self.layout.size.height)
        .mask {
            LaunchTextReveal(progress: reduceMotion ? 1 : progress)
                .fill(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your display, right now.")
        .task {
            guard !reduceMotion, !revealStarted else { return }
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            guard !Task.isCancelled else { return }
            revealStarted = true
            withAnimation(.linear(duration: 1.70)) { progress = 1 }
        }
    }
}

// A growing mask keeps every revealed pixel visible, including punctuation.
private struct LaunchTextReveal: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY,
                    width: rect.width * min(1, max(0, progress)), height: rect.height))
    }
}
