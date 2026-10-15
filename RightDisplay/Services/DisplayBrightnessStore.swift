// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import CoreGraphics
import Darwin
import Foundation

struct BrightnessDragProtection {
    static let stop = 0.20
    private(set) var shouldWarn = false
    private var warned = false
    private var editing = false
    mutating func begin(current: Double) {
        editing = true; shouldWarn = false; warned = current < Self.stop
    }
    mutating func apply(_ proposed: Double, current: Double) -> Double {
        shouldWarn = false
        guard proposed.isFinite else { return current }
        let value = min(1, max(0, proposed))
        if value > Self.stop { warned = false }
        if editing && !warned && current >= Self.stop && value <= Self.stop {
            warned = true; shouldWarn = true
            // Pause at the threshold for one update; the same drag may continue.
            return Self.stop
        }
        return value
    }
    mutating func end() { editing = false; shouldWarn = false }
    mutating func reset() { self = Self() }
}

@MainActor
final class DisplayBrightnessStore: ObservableObject {
    static let shared = DisplayBrightnessStore()

    @Published private(set) var value: Double = 0.5
    @Published private(set) var warningSequence: UInt64 = 0
    private(set) var warningSource: String?
    @Published private(set) var isAvailable = false
    @Published private(set) var statusText = "系统未提供亮度控制"

    private typealias GetBrightness = @convention(c) (
        UInt32,
        UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private var timer: Timer?
    private var activeDisplayID: CGDirectDisplayID = 0
    private var dragProtection = BrightnessDragProtection()

    private init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        frameworkHandle = handle
        if let handle,
           let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
           let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") {
            getBrightness = unsafeBitCast(getSymbol, to: GetBrightness.self)
            setBrightness = unsafeBitCast(setSymbol, to: SetBrightness.self)
        } else {
            getBrightness = nil
            setBrightness = nil
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func selectDisplay(_ displayID: CGDirectDisplayID) {
        if activeDisplayID != displayID { dragProtection.reset() }
        activeDisplayID = displayID
        refresh()
    }

    func refresh() {
        guard activeDisplayID != 0, let getBrightness else {
            if isAvailable { isAvailable = false }
            if statusText != "系统未提供亮度控制" { statusText = "系统未提供亮度控制" }
            return
        }
        var brightness: Float = 0
        guard getBrightness(activeDisplayID, &brightness) == 0,
              brightness.isFinite else {
            if isAvailable { isAvailable = false }
            if statusText != "此显示器不接受系统亮度控制" { statusText = "此显示器不接受系统亮度控制" }
            return
        }
        let observed = min(1, max(0, Double(brightness)))
        if value != observed { value = observed }
        if !isAvailable { isAvailable = true }
        if statusText != "与 macOS 显示器亮度同步" { statusText = "与 macOS 显示器亮度同步" }
    }

    func editingChanged(_ editing: Bool) {
        if editing { dragProtection.begin(current:value) } else { dragProtection.end() }
    }

    func set(_ newValue: Double, source: String? = nil) {
        guard activeDisplayID != 0, let setBrightness, isAvailable else { return }
        let clamped = dragProtection.apply(newValue, current:value)
        if dragProtection.shouldWarn { warningSource = source; warningSequence &+= 1 }
        value = clamped
        let result = setBrightness(activeDisplayID, Float(clamped))
        if result != 0 {
            statusText = "macOS 未能写入亮度"
            refresh()
        }
    }
}
