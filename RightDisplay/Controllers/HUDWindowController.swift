// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import Combine
import SwiftUI

@MainActor
final class HUDWindowController {
    private let store: DisplayStore
    private let preferences: Preferences
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var hideWorkItem: DispatchWorkItem?
    private var showingCapabilityTest = false
    private var escapeMonitor: Any?

    init(store: DisplayStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
    }

    func start() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53,
                  self?.store.capabilityTestStage.isRunning == true,
                  self?.store.capabilityTestStage != .restoring else { return event }
            self?.store.stopCapabilityTest()
            return nil
        }
        Publishers.CombineLatest4(
            store.$displays,
            store.$selectedDisplayID,
            preferences.$hudEnabled,
            preferences.objectWillChange
        )
        .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            guard self?.panel?.isVisible == true else { return }
            self?.updatePanel()
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .signalHUDRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.showTemporarily() }
        .store(in: &cancellables)

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.syncCapabilityTestHUD() }
            }
            .store(in: &cancellables)
    }

    private func syncCapabilityTestHUD() {
        if store.capabilityTestStage.isRunning {
            showingCapabilityTest = true
            hideWorkItem?.cancel()
            updatePanel()
        } else if showingCapabilityTest {
            showingCapabilityTest = false
            panel?.orderOut(nil)
        }
    }

    private func showTemporarily() {
        guard preferences.hudEnabled else { return }
        hideWorkItem?.cancel()
        updatePanel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.hudDuration, execute: workItem)
    }

    private func updatePanel() {
        let isCapabilityTest = store.capabilityTestStage.isRunning
        guard (isCapabilityTest || preferences.hudEnabled), let screen = selectedScreen() else {
            panel?.orderOut(nil)
            return
        }

        let root = Group {
            if isCapabilityTest {
                CapabilityTestHUDView(
                    progress: store.capabilityTestProgress,
                    total: store.capabilityTestTotal,
                    candidate: store.capabilityTestCurrent,
                    status: store.capabilityTestDetail,
                    environment: store.capabilityTestEnvironment,
                    readback: store.capabilityTestReadback
                )
            } else {
                HUDView(display: store.selectedDisplay)
                    .scaleEffect(preferences.hudScale)
                    .opacity(preferences.hudOpacity)
            }
        }

        let host = NSHostingView(rootView: root)
        host.frame = isCapabilityTest
            ? NSRect(origin: .zero, size: screen.frame.size)
            : NSRect(x: 0, y: 0, width: 380, height: 110)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = self.panel ?? makePanel()
        panel.contentView = host
        panel.ignoresMouseEvents = isCapabilityTest ? false : preferences.clickThrough
        panel.setContentSize(host.frame.size)
        if isCapabilityTest {
            panel.setFrame(screen.frame, display: true)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.setFrameOrigin(origin(for: screen, panelSize: host.frame.size))
            panel.orderFrontRegardless()
        }
        self.panel = panel
    }

    private func makePanel() -> NSPanel {
        let panel = CapabilityTestPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        return panel
    }

    private func selectedScreen() -> NSScreen? {
        if let testDisplayID = store.capabilityTestDisplayID {
            return NSScreen.screens.first { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == testDisplayID
            }
        }
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == store.selectedDisplayID
        } ?? NSScreen.main
    }

    private func origin(for screen: NSScreen, panelSize: CGSize) -> CGPoint {
        let frame = screen.visibleFrame
        let margin: CGFloat = 12
        switch preferences.hudCorner {
        case .topLeading:
            return CGPoint(x: frame.minX + margin, y: frame.maxY - panelSize.height - margin)
        case .topTrailing:
            return CGPoint(x: frame.maxX - panelSize.width - margin, y: frame.maxY - panelSize.height - margin)
        case .bottomLeading:
            return CGPoint(x: frame.minX + margin, y: frame.minY + margin)
        case .bottomTrailing:
            return CGPoint(x: frame.maxX - panelSize.width - margin, y: frame.minY + margin)
        }
    }
}

private final class CapabilityTestPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
