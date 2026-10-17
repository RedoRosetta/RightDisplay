// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation

enum AudioBridgeState: String, Codable {
    case disabled = "DISABLED", ready = "READY", running = "RUNNING"
    case targetUnavailable = "TARGET_UNAVAILABLE", unsupportedFormat = "UNSUPPORTED_FORMAT"
    case formatChanged = "FORMAT_CHANGED", deviceLost = "DEVICE_LOST"
    case stopping = "STOPPING", failed = "FAILED"
}
struct AudioBridgeDevice: Codable, Identifiable, Equatable {
    let uid: String
    let deviceID: UInt32 // Current context only. Never persisted.
    let name: String
    let transport: UInt32
    let rate: Double
    let channels: Int
    let buffer: Int
    let maxBlock: Int
    let latency: Int?
    let safety: Int?
    let eligibility: String
    let physicalBits: Int?
    let physicalFloat: Bool?
    let streamLatency: Int?
    var id: String { uid }
    var usable: Bool { eligibility == "USABLE_DIRECT_PATH" }
}
struct AudioBridgeTelemetry: Codable, Equatable {
    var bufferDetails: String? = nil
    var failureDetail: String? = nil
    var validationPending: Bool? = nil
    var validationSilencedCallbacks: UInt64? = nil
    var transportUnderrun: UInt64? = nil
    var transportOverrun: UInt64? = nil
    var inputCallbacks: UInt64? = nil
    var inputPeak: Float? = nil
    var outputPeak: Float? = nil
    let epoch: UInt64
    let callbacks: UInt64
    let frames: UInt64
    let fill: Int
    let minFill: UInt64
    let maxFill: UInt64
    let capacity: Int
    let targetFill: Int
    let underrun: UInt64
    let overrun: UInt64
    let ringMS: Double
    let bufferMS: Double
    let residenceMS: Double?
    let failure: String
}
// Value-state reducer used by the actual controller and hardware-free integration tests.
struct VirtualVolumeStateModel {
    private(set) var uid: String?
    private(set) var generation: UInt64 = 1
    private(set) var state: AudioBridgeState = .disabled
    private(set) var hasSession = false
    private(set) var starting = false
    private(set) var suspended = false
    private(set) var unexpectedStop = false
    init(uid: String? = nil) { self.uid = uid?.isEmpty == false ? uid : nil; state = self.uid == nil ? .disabled : .targetUnavailable }
    mutating func select(_ uid: String?) {
        unexpectedStop = false
        generation &+= 1;self.uid = uid?.isEmpty == false ? uid : nil
        hasSession = false;starting = false;state = self.uid == nil ? .disabled : .targetUnavailable
    }
    mutating func reconcile(_ devices: [AudioBridgeDevice], generation token: UInt64) {
        guard token == generation, !hasSession, !starting, !suspended, state != .stopping else { return }
        guard let uid else { state = .disabled;return }
        let matches = devices.filter { $0.uid == uid }
        guard matches.count == 1 else { state = .targetUnavailable;return }
        state = matches[0].usable ? .ready : (matches[0].eligibility == "TARGET_UNAVAILABLE" ? .targetUnavailable : .unsupportedFormat)
    }
    mutating func requestStart() -> UInt64? {
        guard state == .ready, !starting, !hasSession, !suspended else { return nil }
        generation &+= 1;starting = true;return generation
    }
    mutating func started(generation token: UInt64, error: String?) {
        guard token == generation, starting else { return }
        if let error { starting = false;state = error.contains("TARGET_UNAVAILABLE") ? .targetUnavailable : error.contains("FORMAT_CHANGED") ? .formatChanged : error.contains("UNSUPPORTED") ? .unsupportedFormat : .failed }
        else { hasSession = true } // HAL request acceptance is not a running callback.
    }
    mutating func observed(_ value: AudioBridgeTelemetry, generation token: UInt64) {
        guard token == generation, hasSession else { return }
        if value.failure == "NONE" {
            if value.callbacks > 0 && value.frames > 0 { starting = false;state = .running;unexpectedStop = false }
        } else {
            unexpectedStop = unexpectedStop || (state == .running && value.failure != "STOPPED")
            hasSession = false;starting = false
            switch value.failure {
            case "STOPPED": state = .ready
            case "TARGET_UNAVAILABLE": state = .deviceLost
            case "FORMAT_CHANGED", "CONTEXT_CHANGED": state = .formatChanged
            default: state = .failed
            }
        }
    }
    mutating func requestStop(suspend: Bool = false) -> UInt64 {
        unexpectedStop = false
        generation &+= 1;hasSession = false;starting = false;suspended = suspend;state = .stopping;return generation
    }
    mutating func stopped(generation token: UInt64, clean: Bool) {
        guard token == generation else { return }
        state = clean ? (uid == nil || suspended ? .disabled : .targetUnavailable) : .failed
    }
    mutating func fail(generation token: UInt64) { guard token == generation else { return };unexpectedStop = unexpectedStop || state == .running;starting = false;hasSession = false;state = .failed }
    mutating func wake() { suspended = false;generation &+= 1;state = uid == nil ? .disabled : .targetUnavailable }
    static func latency(frames: Int, rate: Double) -> Double? {
        guard frames >= 0, rate.isFinite, rate > 0 else { return nil };return Double(frames) * 1000 / rate
    }
}
// Only UID is persisted. Selecting a display never enters this model.
struct AudioTargetPreference {
    static let key = "virtualVolumeAudioUID"
    let defaults: UserDefaults
    var uid: String? { defaults.string(forKey: Self.key) }
    func save(_ uid: String?) { if let uid, !uid.isEmpty { defaults.set(uid, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) } }
}
struct AudioDiagnosticAnonymizer {
    private var aliases: [String: String] = [:]
    mutating func alias(_ uid: String?) -> String {
        guard let uid else { return "None" }
        if let old = aliases[uid] { return old }
        let value = "Audio-\(aliases.count + 1)";aliases[uid] = value;return value
    }
    mutating func redact(_ text: String, uids: [String]) -> String {
        var result = text
        for uid in uids.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: uid, with: alias(uid))
        }
        return result
    }
}

struct VirtualAudioDeviceStatus: Decodable, Equatable {
    var matches: Int = 0
    var loaded = false
    var defaultKnown = false
    var isDefault = false
    var rate: Double = 0
    var safeToRemove: Bool { defaultKnown && !isDefault && matches <= 1 }
}

// One automatic attempt per virtual-output selection; manual stop persists.
struct VirtualAudioAutoStartPolicy {
    static func virtualSelected(systemDefault: Bool, controlUID: String?) -> Bool {
        systemDefault || controlUID == "RightDisplay.VirtualVolume"
    }
    var manuallyDisabled: Bool
    var attemptedForCurrentSelection = false
    mutating func shouldStart(virtualSelected: Bool, eligible: Bool) -> Bool {
        if !virtualSelected { attemptedForCurrentSelection = false; return false }
        guard !manuallyDisabled, !attemptedForCurrentSelection, eligible else { return false }
        attemptedForCurrentSelection = true
        return true
    }
    mutating func userStarted() { manuallyDisabled = false; attemptedForCurrentSelection = true }
    mutating func userStopped() { manuallyDisabled = true }
    mutating func targetSelected() { attemptedForCurrentSelection = false }
}

// One attempt after a previously running system route loses its selected target.
// Manual stop, target selection and unrelated failures cancel this intent.
struct VirtualAudioTargetReturnPolicy {
    private(set) var pendingUID: String?
    mutating func arm(uid: String?, wasRunning: Bool, systemRoute: Bool,
                      failure: String, cleanupOK: Bool, removalConfirmed: Bool = false) {
        pendingUID = wasRunning && systemRoute && failure == "TARGET_UNAVAILABLE" && cleanupOK && removalConfirmed ? uid : nil
    }
    mutating func cancel() { pendingUID = nil }
    mutating func consume(uid: String?, eligible: Bool, virtualSelected: Bool,
                          manuallyDisabled: Bool) -> Bool {
        guard let pendingUID else { return false }
        guard !manuallyDisabled, uid == pendingUID else { cancel();return false }
        guard eligible, virtualSelected else { return false }
        cancel();return true // consumed before attempting; never a retry loop
    }
}
