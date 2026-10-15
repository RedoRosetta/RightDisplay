// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import PreferencePanes
import SwiftUI

@objc(RightDisplayPreferencePane)
final class RightDisplayPreferencePane: NSPreferencePane {
    private var hostingView: NSHostingView<AnyView>?

    override func loadMainView() -> NSView {
        MainActor.assumeIsolated {
            let rootView = SystemSettingsPaneView()
                .environmentObject(DisplayStore.shared)
                .environmentObject(Preferences.shared)
            let hostingView = NSHostingView(rootView: AnyView(rootView))
            // A legacy preference pane is already sized by System Settings.
            // Prevent NSHostingView from reporting SwiftUI's unbounded maximum
            // size back to its surrounding scroll view and creating false
            // vertical overflow.
            if #available(macOS 13.0, *) {
                hostingView.sizingOptions = []
            }
            hostingView.frame = NSRect(x: 0, y: 0, width: 668, height: 660)
            hostingView.autoresizingMask = [.width, .height]
            self.hostingView = hostingView
            mainView = hostingView
            return hostingView
        }
    }

    override func didSelect() {
        super.didSelect()
        MainActor.assumeIsolated {
            DisplayStore.shared.startMonitoring()
            DispatchQueue.main.async { [weak self] in
                self?.scrollSystemSettingsToTop()
            }
        }
    }

    private func scrollSystemSettingsToTop() {
        var ancestor = hostingView?.superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView,
               let documentView = scrollView.documentView {
                let clipView = scrollView.contentView
                let topY = documentView.isFlipped
                    ? documentView.bounds.minY
                    : max(documentView.bounds.maxY - clipView.bounds.height, documentView.bounds.minY)
                clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: topY))
                scrollView.reflectScrolledClipView(clipView)
                return
            }
            ancestor = view.superview
        }
    }

    override func willUnselect() {
        MainActor.assumeIsolated {
            DisplayStore.shared.stopMonitoring()
            DisplayStore.shared.restorePendingModeIfNeeded()
        }
        super.willUnselect()
    }
}
