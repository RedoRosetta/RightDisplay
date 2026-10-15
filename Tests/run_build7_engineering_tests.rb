# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
# Actual production functions/value models with fake display/process I/O and clock.
require 'tmpdir'
root = File.expand_path('..', __dir__)
def section(text, first, last)
  a = text.index(first) or abort "Missing #{first}"
  b = text.index(last, a) or abort "Missing #{last}"
  text[a...b]
end
snapshot = File.read(File.join(root, 'RightDisplay/Models/DisplaySnapshot.swift'))
profile = File.read(File.join(root, 'RightDisplay/Models/DisplayCapabilityProfile.swift'))
store = File.read(File.join(root, 'RightDisplay/Services/DisplayStore.swift'))
helper = File.read(File.join(root, 'RightDisplay/Services/AppleTVAudioController.swift'))
exporter = File.read(File.join(root, 'RightDisplay/Services/DiagnosticReportExporter.swift'))
models = section(snapshot, 'struct DisplayDeviceDescriptor:', 'struct ModeRefreshRange:')
models += section(snapshot, 'struct ConnectionIdentity:', 'struct DisplayLinkCapability:')
models += section(snapshot, 'struct TimingConnectionProtection', 'enum AutoCorrectionStage:')
models += section(profile, 'enum AutoCorrectionPolicy:', 'enum CapabilityEvidence:')
models += section(profile, 'struct DisplayCapabilityProfile:', 'struct PreferenceMigrationSummary:')
models += section(profile, 'enum CapabilityEvidence:', 'enum CapabilityTestStage:')
models += section(profile, 'struct ValidatedLinkMode:', 'struct DisplayCapabilityProfile:')
models += section(exporter, 'struct DiagnosticPrivacyRedactor', 'struct DiagnosticEvent:')
models += section(helper, 'enum HelperExitOutcome:', '@MainActor')
methods = section(store, '    private func finishTimingRestore(', '    private func linkPreferenceScore(')
methods += section(store, '    private func modeRequiresDSC(', '    private func displayPortLink(')
methods += section(store, '    private func completeDisplayRecovery(', '    func reserveColorProfileOperation(')
helper_method = section(helper, '    private func waitForServiceExit(', '    private var helperURL:')
# Integration checks: formatting is never a complete-history identity input.
preferences = File.read(File.join(root, 'RightDisplay/Models/Preferences.swift'))
abort 'Preferences dedup bypasses complete identity' unless section(preferences, '    private func capabilityModeIdentity(', '    private func migrateIfNeeded').include?('mode.deduplicationKey')
abort 'Export boundary not sanitized' unless exporter.include?('return privacy.redact(VirtualVolumeController.shared.redactDiagnostics(report, uids: audioUIDs))')
%w[TIMING_PRECHECK TIMING_READBACK TIMING_RESTORE_RESULT].each { |event| abort "Missing #{event} export" unless exporter.include?("[#{event}]") }
abort 'Implicit RGB sampling default' if store.include?('componentMultiplier: Double = 3')
abort 'Control omitted current sampling' unless section(store, '    func setDSCEnabled(', '    func confirmPendingMode').include?('link: link, componentMultiplier: componentMultiplier')
abort 'Reassociation still uses first hardware match' if section(store, '    func softReplugSelectedDisplay()', '    private func beginLinkControl').include?('displays.first(where: { $0.hardwareKey')
preferences_methods = section(preferences, '    func capabilityProfile(', '    func clearCapabilityHistory(')
preferences_methods += section(preferences, '    private func capabilityProfileKey(', '    private func migrateIfNeeded(')
stubs = <<~'SWIFT'
import Foundation
enum OutputPreference: String, Codable { case automatic, rgbFullRange, yCbCr }
struct DisplayLinkDescription: Equatable {
    var identity: ConnectionIdentity
    var bandwidthComponentMultiplier: Double? { LinkPixelEncoding(rawValue: identity.pixelEncoding)?.bandwidthComponentMultiplier }
}
struct DisplayModeOption {
    var id: Int32 = 71
    var displayID: UInt32 = 7
    var hardwareKey = "device-A"
    var timingIdentity = "timing-A"
    var outputWidth = 3840
    var outputHeight = 2160
    var refreshRate = 120.0
}
struct TimingChange {
    var original = DisplayModeOption()
    var protection: TimingConnectionProtection
    var generation: UUID
}
final class Clock { static let shared = Clock(); var now = 0.0 }
final class ProcessInfo { static let processInfo = ProcessInfo(); var systemUptime: Double { Clock.shared.now } }
final class AuditQueue {
    var pending: [() -> Void] = []
    func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { pending.append(execute) }
    func runNext() { precondition(!pending.isEmpty); Clock.shared.now += 0.05; pending.removeFirst()() }
    func drain() { var n = 0; while !pending.isEmpty { n += 1; precondition(n < 200); runNext() } }
}
enum DispatchQueue { static let main = AuditQueue() }
enum Hardware { static var online: UInt32 = 1 }
func CGDisplayIsOnline(_ id: UInt32) -> UInt32 { Hardware.online }
final class CoreDisplayHDRController {
    static let shared = CoreDisplayHDRController()
    var hdr: Bool? = false
    var writes: [Bool] = []
    var acceptWrites = true
    var didWrite: (() -> Void)?
    func isEnabled(displayID: UInt32) -> Bool? { hdr }
    func setEnabled(_ value: Bool, displayID: UInt32) -> Bool {
        writes.append(value); if acceptWrites { hdr = value }; didWrite?(); return acceptWrites
    }
}
final class DisplayOutputController {
    static let shared = DisplayOutputController()
    struct State { var descriptions: [DisplayLinkDescription]; var slsReportedDescription: DisplayLinkDescription? }
    var snapshot = State(descriptions: [], slsReportedDescription: nil)
    var writes: [UInt32] = []
    var acceptWrites = true
    func state(displayID: UInt32, modeID: Int32) -> State? { snapshot }
    func setOutputMode(displayID: UInt32, modeID: Int32, index: UInt32) -> Int32 {
        precondition(Int(index) < snapshot.descriptions.count)
        writes.append(index)
        if acceptWrites { snapshot.slsReportedDescription = snapshot.descriptions[Int(index)] }
        return acceptWrites ? 0 : 1
    }
}
final class TimingHarness {
    var displayRecoveryToken: UUID?
    var modeAttemptToken = UUID()
    var linkContextGeneration = UUID()
    var linkVerificationComplete = false
    var pendingVerificationText = ""
    var timingReady = true
    var hardwareKey = "device-A"
    var isBuiltin = false
    var diagnostics: [String] = []
    func refresh() {}
    struct Snapshot { var hardwareKey: String; var isBuiltin: Bool }
    func displaySnapshot(for id: UInt32) -> Snapshot? { Snapshot(hardwareKey: hardwareKey, isBuiltin: isBuiltin) }
    func allModes(for id: UInt32) -> [DisplayModeOption] { [] }
    func currentTiming(displayID: UInt32, modes: [DisplayModeOption]) -> DisplayModeOption? { timingReady ? DisplayModeOption() : nil }
    func appendApplyDiagnostic(_ event: String, _ text: String) { diagnostics.append(event + text) }
SWIFT
preferences_stubs = <<~'SWIFT'
enum CapabilityTestTiming { static let engineGeneration = 1 }
final class PreferencesHarness {
    var capabilityProfiles: [String: DisplayCapabilityProfile] = [:]
SWIFT
helper_stubs = <<~'SWIFT'
final class Process {
    var isRunning = true
    let processIdentifier: Int32
    var terminates = 0
    init(_ id: Int32) { processIdentifier = id }
    func terminate() { terminates += 1 }
}
final class HelperHarness {
    var serviceProcess: Process?
    var reconnectGeneration = 1
    var events: [String] = []
    var stops = 0
    func log(_ event: String, _ fields: [String: Any]) { events.append(event) }
    func stopService(error: String? = nil, terminateProcess: Bool = true) { stops += 1; serviceProcess = nil }
SWIFT
checks = <<~'SWIFT'
var count = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) { count += 1; precondition(condition(), message) }
let expected = ConnectionIdentity(pixelEncoding: 0, depth: 12, range: 1, eotf: 2)
let wrong = ConnectionIdentity(pixelEncoding: 1, depth: 10, range: 0, eotf: 2)
func newTiming() -> (TimingHarness, TimingChange, UUID) {
    Hardware.online = 1
    let h = TimingHarness(); let token = h.modeAttemptToken; h.displayRecoveryToken = token
    CoreDisplayHDRController.shared.hdr = false; CoreDisplayHDRController.shared.writes = []
    CoreDisplayHDRController.shared.acceptWrites = true; CoreDisplayHDRController.shared.didWrite = nil
    DisplayOutputController.shared.snapshot = .init(descriptions: [], slsReportedDescription: .init(identity: wrong))
    DisplayOutputController.shared.writes = []; DisplayOutputController.shared.acceptWrites = true
    return (h, TimingChange(protection: .init(original: expected, systemHDR: true), generation: h.linkContextGeneration), token)
}
let (ready, change, token) = newTiming()
ready.finishTimingRestore(change, token: token, timingAccepted: true, attempt: 0, stable: 0)
DispatchQueue.main.runNext()
check(DisplayOutputController.shared.writes.isEmpty && CoreDisplayHDRController.shared.writes.isEmpty, "Unavailable candidate consumed action")
check(ready.displayRecoveryToken == token && !ready.linkVerificationComplete, "Readiness wait released owner")
DisplayOutputController.shared.snapshot.descriptions = [.init(identity: wrong), .init(identity: expected)]
DispatchQueue.main.runNext()
check(DisplayOutputController.shared.writes == [1] && CoreDisplayHDRController.shared.writes == [true], "Delayed readiness failed exact fresh restore")
DispatchQueue.main.drain()
check(DisplayOutputController.shared.writes.count == 1 && CoreDisplayHDRController.shared.writes.count == 1, "Duplicate restore write")
check(ready.linkVerificationComplete && ready.displayRecoveryToken == nil && ready.diagnostics.last?.contains("PASS") == true, "Stable restore stranded")
let (lateTiming, lateChange, lateToken) = newTiming(); lateTiming.timingReady = false
DisplayOutputController.shared.snapshot.descriptions = [.init(identity: expected)]
lateTiming.finishTimingRestore(lateChange, token: lateToken, timingAccepted: true, attempt: 0, stable: 0)
DispatchQueue.main.runNext(); check(DisplayOutputController.shared.writes.isEmpty, "Wrong timing written")
lateTiming.timingReady = true; DispatchQueue.main.drain()
check(DisplayOutputController.shared.writes.count == 1, "Late timing readiness lost action")
let (expired, expiredChange, expiredToken) = newTiming()
expired.finishTimingRestore(expiredChange, token: expiredToken, timingAccepted: true, attempt: 0, stable: 0)
DispatchQueue.main.drain()
check(expired.linkVerificationComplete && expired.displayRecoveryToken == nil && expired.diagnostics.last?.contains("UNCONFIRMED") == true, "Timeout permanent busy/false PASS")
for invalid in ["generation", "hardware", "offline", "token"] {
    let (h, c, t) = newTiming()
    DisplayOutputController.shared.snapshot.descriptions = [.init(identity: expected)]
    h.finishTimingRestore(c, token: t, timingAccepted: true, attempt: 0, stable: 0)
    switch invalid { case "generation": h.linkContextGeneration = UUID(); case "hardware": h.hardwareKey = "sibling"; case "offline": Hardware.online = 0; default: h.modeAttemptToken = UUID(); h.displayRecoveryToken = UUID() }
    DispatchQueue.main.drain()
    check(DisplayOutputController.shared.writes.isEmpty && CoreDisplayHDRController.shared.writes.isEmpty, "Invalid context wrote: " + invalid)
    if invalid != "token" { check(h.displayRecoveryToken == nil && h.linkVerificationComplete, "Invalid context stranded") }
}
let (failed, failedChange, failedToken) = newTiming()
DisplayOutputController.shared.snapshot.descriptions = [.init(identity: expected)]
DisplayOutputController.shared.acceptWrites = false; CoreDisplayHDRController.shared.acceptWrites = false
failed.finishTimingRestore(failedChange, token: failedToken, timingAccepted: true, attempt: 0, stable: 0)
DispatchQueue.main.drain()
check(DisplayOutputController.shared.writes.count == 1 && CoreDisplayHDRController.shared.writes.count == 1 && failed.diagnostics.last?.contains("UNCONFIRMED") == true, "Rejected restore repeatedly written/PASS")
let (freshIndex, freshChange, freshToken) = newTiming()
DisplayOutputController.shared.snapshot.descriptions = [.init(identity: wrong), .init(identity: expected)]
CoreDisplayHDRController.shared.didWrite = { DisplayOutputController.shared.snapshot.descriptions = [.init(identity: expected), .init(identity: wrong)] }
freshIndex.finishTimingRestore(freshChange, token: freshToken, timingAccepted: true, attempt: 0, stable: 0)
DispatchQueue.main.drain()
check(DisplayOutputController.shared.writes == [0], "Restore reused pre-HDR candidate index")
for other in [ConnectionIdentity(pixelEncoding: 0, depth: 12, range: 0, eotf: 2), ConnectionIdentity(pixelEncoding: 0, depth: 12, range: 1, eotf: 3)] {
    let (h,c,t) = newTiming()
    DisplayOutputController.shared.snapshot.descriptions = [.init(identity: other)]
    h.finishTimingRestore(c, token: t, timingAccepted: true, attempt: 0, stable: 0)
    DispatchQueue.main.drain()
    check(DisplayOutputController.shared.writes.isEmpty && CoreDisplayHDRController.shared.writes.isEmpty && h.linkVerificationComplete, "Incomplete range/EOTF match restored")
}
func timing(_ hz: Double = 120, _ vrr: Bool = false) -> PersistentTimingIdentity {
    PersistentTimingIdentity(TimingIdentity(displayID: 7, hardwareKey: "device", cgsIndex: 3, ioModeID: 71, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, rawRefreshRate: hz, vrr: vrr, ioFlags: 3))
}
func record(range: UInt32? = 1, eotf: UInt32? = 2, rate: String = "120 Hz", identity: PersistentTimingIdentity? = timing()) -> ValidatedLinkMode {
    ValidatedLinkMode(signature: "old-display-wording", timingIdentity: identity, resolution: "3840 × 2160", refreshRate: rate, color: .rgbFullRange, rawPixelEncoding: 0, rawRange: range, rawEOTF: eotf, bitDepth: 12, hdr: true, resultingRawPixelEncoding: nil, resultingBitDepth: nil, resultingHDR: nil, engineGeneration: 1, vrr: false, dsc: nil, evidence: .systemReadback, lastChecked: Date(), failureReason: nil)
}
check(record().deduplicationKey != record(range: 0).deduplicationKey, "Range identity lost")
check(record().deduplicationKey != record(eotf: 3).deduplicationKey, "Raw EOTF identity lost")
check(record(rate: "120 Hz").deduplicationKey != record(rate: "120 Hz", identity: timing(119.88)).deduplicationKey, "Formatted timing collision")
check(record(rate: "120 Hz（固定）").deduplicationKey == record(rate: "120 Hz").deduplicationKey, "Wording affects identity")
check(record(identity: timing(120, true)).deduplicationKey != record().deduplicationKey, "VRR/fixed conflated")
check(record(range: nil).persistentIdentity == nil && record(eotf: nil).persistentIdentity == nil && record(identity: nil).persistentIdentity == nil, "Incomplete legacy upgraded")
var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record())) as! [String: Any]
legacyJSON.removeValue(forKey: "timingIdentity"); legacyJSON.removeValue(forKey: "rawRange"); legacyJSON.removeValue(forKey: "rawEOTF")
let legacy = try JSONDecoder().decode(ValidatedLinkMode.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
check(legacy.persistentIdentity == nil && legacy.rawRange == nil && legacy.rawEOTF == nil, "Legacy migration fabricated")
let roundtrip = try JSONDecoder().decode(ValidatedLinkMode.self, from: JSONEncoder().encode(record(identity: timing(119.88))))
check(roundtrip.persistentIdentity == record(identity: timing(119.88)).persistentIdentity, "Timing identity changed across Codable persistence")
for (a, b) in [(120.0,119.88),(60,59.94),(30,29.97),(24,23.98)] { check(timing(a) != timing(b), "Fractional lost") }
var registry = DisplayIdentityRegistry()
let a = DisplayDeviceDescriptor(displayID: 7, vendor: 1, model: 2, serial: 0)
let b = DisplayDeviceDescriptor(displayID: 8, vendor: 1, model: 2, serial: nil)
registry.update([a,b]); let ida = registry.identity(for: 7)!; let idb = registry.identity(for: 8)!
check(ida.persistentKey == nil && idb.persistentKey == nil && ida.storageKey != idb.storageKey, "Serial-less siblings share history key")
let prefs = PreferencesHarness()
prefs.recordLinkMode(record(), for: ida.storageKey, interfaceName: "HDMI")
check(prefs.capabilityProfile(for: ida.storageKey, interfaceName: "HDMI").modes.count == 1 && prefs.capabilityProfile(for: idb.storageKey, interfaceName: "HDMI").modes.isEmpty, "Production profile isolation failed")
prefs.recordLinkMode(record(range: 0), for: ida.storageKey, interfaceName: "HDMI")
prefs.recordLinkMode(record(eotf: 3), for: ida.storageKey, interfaceName: "HDMI")
prefs.recordLinkMode(record(rate: "120 Hz", identity: timing(119.88)), for: ida.storageKey, interfaceName: "HDMI")
check(prefs.capabilityProfile(for: ida.storageKey, interfaceName: "HDMI").modes.count == 4, "Production complete dedup discarded range/EOTF/timing")
prefs.recordLinkMode(record(rate: "120 Hz（固定）"), for: ida.storageKey, interfaceName: "HDMI")
check(prefs.capabilityProfile(for: ida.storageKey, interfaceName: "HDMI").modes.count == 4, "Wording split production persistence")
prefs.recordLinkMode(legacy, for: ida.storageKey, interfaceName: "HDMI")
check(prefs.capabilityProfile(for: ida.storageKey, interfaceName: "HDMI").modes.filter { $0.persistentIdentity != nil }.count == 4, "Legacy replaced complete record")
check(DisplayDeviceIdentity.uniqueReassociation(ida, among: [idb]) == nil, "Reassociated serial-less sibling")
check(DisplayDeviceIdentity.uniqueReassociation(ida, among: [ida,idb]) == 7, "Unique current instance rejected")
registry.invalidate(7); registry.update([a,b]); let replacement = registry.identity(for: 7)!
check(replacement.connectionInstanceKey != ida.connectionInstanceKey && replacement.storageKey != ida.storageKey, "Old attachment identity reused")
check(DisplayDeviceIdentity.uniqueReassociation(ida, among: [replacement,idb]) == nil, "Old transaction migrated")
var reliable = DisplayIdentityRegistry(); let c = DisplayDeviceDescriptor(displayID: 9, vendor: 1, model: 2, serial: 99)
reliable.update([c]); let original = reliable.identity(for: 9)!
check(original.persistentKey != nil, "Reliable serial ignored")
check(DisplayDeviceIdentity.uniqueReassociation(original, among: [original,original]) == nil, "Ambiguous re-association accepted")
check(DisplayDeviceIdentity.uniqueReassociation(original, among: [original]) == 9, "Unique persistent match rejected")
reliable.update([c,DisplayDeviceDescriptor(displayID: 10,vendor: 1,model: 2,serial: 99)])
check(reliable.identity(for: 9)!.persistentKey == nil && reliable.identity(for: 9)!.storageKey != reliable.identity(for: 10)!.storageKey, "Duplicated serial trusted")
let dsc = TimingHarness()
for (raw, multiplier): (UInt32, Double?) in [(0,3),(1,3),(2,2),(3,1.5),(99,nil)] {
    let desc = DisplayLinkDescription(identity: .init(pixelEncoding: raw, depth: 10, range: 1, eotf: 0))
    check(desc.bandwidthComponentMultiplier == multiplier, "Sampling changed")
    if let multiplier = desc.bandwidthComponentMultiplier {
        let result = dsc.modeRequiresDSC(DisplayModeOption(), bitDepth: 10, link: (8.1e9,4), componentMultiplier: multiplier)
        check(result == (raw <= 1), "Status/control sampling differs")
    }
}
let rawKey = "00000001-00000002-1234ABCD"
let privateModel = "identity=7|\(rawKey)|71 detail=\(rawKey) serial=\(UInt32(0x1234ABCD)) hex=1234ABCD nested={selectionKey:\(rawKey)}"
var privacy = DiagnosticPrivacyRedactor(hardwareKeys: [rawKey])
let exported = privacy.redact(privateModel + "\nevent hardwareKey=\(rawKey)\nTIMING_READBACK identity=\(rawKey)")
check(!exported.contains(rawKey) && !exported.contains("1234ABCD") && !exported.contains(String(UInt32(0x1234ABCD))), "Serial escaped via nested identity")
check(exported.components(separatedBy: "Display-A").count == 6, "Device event association lost")
check(!privacy.redact("serial=0x1234abcd value=1234abcd").lowercased().contains("1234abcd"), "Alternate serial encoding leaked")
check(privateModel.contains(rawKey) && privateModel.contains("1234ABCD"), "Internal identity mutated")
let historic = privacy.redact("hardwareKey=00000001-00000002-87654321 serial=2271560481 nested=00000001-00000002-87654321")
check(!historic.contains("87654321") && !historic.contains("2271560481"), "Historical disconnected device leak")
var shortSerials = DiagnosticPrivacyRedactor(hardwareKeys: ["00000001-00000002-0000000A", "00000001-00000002-0000000B"])
let shortReport = shortSerials.redact("event1 hardwareKey=00000001-00000002-0000000A serial=10\nevent2 hardwareKey=00000001-00000002-0000000B serial=11")
check(shortReport.contains("Display-A") && shortReport.contains("Display-B") && !shortReport.contains("serial=10") && !shortReport.contains("serial=11"), "Short serials collapsed anonymous devices")
for kind in ["wedged", "exited", "replacement", "generation"] {
    Clock.shared.now = 0
    let h = HelperHarness(); let p = Process(41); h.serviceProcess = p
    var outcomes: [HelperExitOutcome] = []
    h.waitForServiceExit(p, pid: 41, generation: 1) { outcomes.append($0) }
    switch kind { case "exited": p.isRunning = false; case "replacement": h.serviceProcess = Process(42); case "generation": h.reconnectGeneration = 2; default: break }
    DispatchQueue.main.drain()
    check(outcomes.count == 1, "Helper completion not exactly once")
    if kind == "wedged" {
        check(outcomes == [.timedOut] && Clock.shared.now < 4.2 && p.terminates == 1 && h.stops == 1, "Helper wait unbounded")
    } else if kind == "exited" { check(outcomes == [.exited] && p.terminates == 0, "Exited helper forced") }
    else { check(outcomes == [.superseded] && p.terminates == 0 && h.stops == 0, "Replacement generation terminated") }
}
print("Build 7 engineering tests: \(count) assertions PASS; offline, no hardware I/O")
SWIFT
Dir.mktmpdir('rightdisplay-b7-tests-', '/private/tmp') do |dir|
  source = File.join(dir, 'main.swift')
  File.write(source, "import Foundation\n" + models + stubs + methods.gsub('private ', '') + "}\n" + helper_stubs + helper_method.gsub('private ', '') + "}\n" + preferences_stubs + preferences_methods.gsub('private ', '') + "}\n" + checks)
  exe = File.join(dir, 'engineering-tests')
  abort 'Compile failed' unless system('xcrun', 'swiftc', '-module-cache-path', File.join(dir, 'ModuleCache'), File.join(root, 'RightDisplay/Models/LinkPixelEncoding.swift'), source, '-o', exe)
  abort 'Tests failed' unless system(exe)
end
