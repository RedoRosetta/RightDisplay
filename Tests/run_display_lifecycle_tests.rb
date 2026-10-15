# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
# Exercise actual production entry/restore methods using an offline scheduler.
# Controllers below only supply readbacks; no real display APIs are loaded.
require 'tmpdir'
root = File.expand_path('..', __dir__)
store = File.read(File.join(root, 'RightDisplay/Services/DisplayStore.swift'))
profile = File.read(File.join(root, 'RightDisplay/Models/DisplayCapabilityProfile.swift'))
def slice(text, first, last)
  a = text.index(first) or abort "Missing #{first}"
  b = text.index(last, a) or abort "Missing #{last}"
  text[a...b]
end
models = slice(profile, 'struct DisplayOperationAvailability', 'enum AutoCorrectionPolicy')
models += slice(profile, 'enum CapabilityTestStage:', 'struct CapabilityTestAttemptResult:')
methods = slice(store, '    private var displayOperationAvailability:', '    func reserveColorProfileOperation(')
methods += slice(store, '    func startCapabilityTest()', '        resetLinkTestDiagnostics()') + "        started += 1\n    }\n"
methods += slice(store, '    private func pollCapabilityTestHDRRestore(', '    private func restoreCapabilityTestLink(')
methods += slice(store, '    private func pollCapabilityTestRestore(', '    private func finishCapabilityTestRestore(')
methods += slice(store, '    private func finishCapabilityTestRestore(', "    @discardableResult\n    private func recordCapabilityTestResult(")
candidate = slice(store, '    private func finishCapabilityTestCandidate(', '    private func beginCapabilityTestRestore(')
continuation = candidate[candidate.index('        let completedSessionToken')..]
methods += "    func scheduleCandidateContinuation(session: FakeSession) {\n" + continuation
methods = methods.gsub('private ', '')
# Verify all public control entry points share the tested gate. Continuations
# deliberately keep their existing operation tokens instead of reentering it.
%w[apply applyOutputColor applyOutputEncoding applyBitDepth applyLinkCapability setHDREnabled setVRREnabled setDSCEnabled autoCorrect retrainCurrentLink softReplugSelectedDisplay applyOfferedAlternative].each do |name|
  a = store.index("    func #{name}(") or abort "Missing entry #{name}"
  b = store.index(/^    (?:private )?func /, a + 10) || store.length
  abort "Unguarded entry #{name}" unless store[a...b].include?('canBeginDisplayOperation()')
end
abort 'Delayed candidate lost session ownership' unless store.scan('self.capabilityTestSession?.token == completedSessionToken').length == 2
abort 'Stop can repeat recovery' unless store.include?('guard capabilityTestStage.isRunning, capabilityTestStage != .restoring else { return }')
stubs = <<~'SWIFT'
import Foundation
final class AuditQueue {
    var pending: [() -> Void] = []
    func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { pending.append(execute) }
    func runNext() { precondition(!pending.isEmpty); pending.removeFirst()() }
    func drain() { var n = 0; while !pending.isEmpty { n += 1; precondition(n < 20); runNext() } }
}
enum DispatchQueue { static let main = AuditQueue() }
struct FakeSession {
    let token = UUID()
    var displayID: UInt32 = 7
    var modeID: Int32 = 71
    var hardwareKey = "device-A"
    var originalDescription = "SLS_REPORTED"
    var originalSystemHDR: Bool? = true
    var completionStage: CapabilityTestStage = .cancelled
}
final class CoreDisplayHDRController {
    static let shared = CoreDisplayHDRController()
    var reads: [Bool?] = []
    func isEnabled(displayID: UInt32) -> Bool? { reads.isEmpty ? nil : reads.removeFirst() }
}
extension String { func matches(_ expected: String) -> Bool { self == expected } }
final class DisplayOutputController {
    static let shared = DisplayOutputController()
    struct State { var slsReportedDescription: String? = "SLS_REPORTED" }
    var observed: String? = "SLS_REPORTED"
    func state(displayID: UInt32, modeID: Int32) -> State? { State(slsReportedDescription: observed) }
}
enum AppLocalization {
    static func format(_ text: String, _ count: Int) -> String { String(format: text, count) }
}
final class Harness {
    var linkVerificationComplete = true
    var pendingModeConfirmation = false
    var activeLinkTransaction: Int?
    var verifiedLinkApplyStatus = ""
    var capabilityTestStage: CapabilityTestStage = .idle
    var capabilityTestSession: FakeSession?
    var pendingTimingChange: Int?
    var displayRecoveryToken: UUID?
    var softReplugOperationToken: UUID?
    var colorProfileOperationToken: UUID?
    var automaticCorrectionInProgress = false
    var lastError: String?
    var permitted = true
    var started = 0
    var linkAttemptToken = UUID()
    var capabilityRestoreContext: Int?
    var capabilityTestTotal = 20
    var capabilityTestProgress = 10
    var capabilityTestSessionStableModes: [Int] = []
    var capabilityTestDetail = ""
    var capabilityTestCurrent = "candidate"
    var capabilityTestEnvironment = "HDR"
    var capabilityTestReadback = "pending"
    var capabilityTestDisplayID: UInt32? = 7
    struct Display { var hardwareKey: String }
    var presentHardwareKey: String? = "device-A"
    func displaySnapshot(for id: UInt32) -> Display? { presentHardwareKey.map { Display(hardwareKey: $0) } }
    var contextValid = true
    var invalidateOnRefresh = false
    var refreshCount = 0
    var restoredLinkCount = 0
    var nextCandidateCount = 0
    func runNextCapabilityTestCandidate() { nextCandidateCount += 1 }
    var readbackCount = 0
    var diagnostics: [String] = []
    func canModifyDisplay() -> Bool { permitted }
    func refresh() { refreshCount += 1; if invalidateOnRefresh { contextValid = false } }
    func isCurrentLinkContext(_ context: Int?) -> Bool { context != nil && contextValid }
    func appendLinkTestDiagnostic(_ event: String, _ message: String) { diagnostics.append(event + " " + message) }
    func updateCapabilityTestReadback(hdr: Bool?, link: String?) { readbackCount += 1 }
    func restoreCapabilityTestLink(sessionToken: UUID) {
        precondition(capabilityTestSession?.token == sessionToken)
        restoredLinkCount += 1 // Record action intent; no hardware call.
    }
SWIFT
checks = <<~'SWIFT'
var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    precondition(value(), message)
}
let blockers: [(String, (Harness) -> Void)] = [
    ("verification", { $0.linkVerificationComplete = false }),
    ("confirmation", { $0.pendingModeConfirmation = true }),
    ("transaction", { $0.activeLinkTransaction = 42 }),
    ("preparation", { $0.verifiedLinkApplyStatus = "preparing" }),
    ("stage", { $0.capabilityTestStage = .restoring }),
    ("session", { $0.capabilityTestSession = FakeSession() }),
    ("timing", { $0.pendingTimingChange = 42 }),
    ("recovery", { $0.displayRecoveryToken = UUID() }),
    ("probe", { $0.softReplugOperationToken = UUID() }),
    ("profile", { $0.colorProfileOperationToken = UUID() }),
    ("automatic", { $0.automaticCorrectionInProgress = true }),
    ("protection", { $0.permitted = false })
]
for (name, set) in blockers {
    let h = Harness(); set(h)
    let session = h.capabilityTestSession?.token
    let transaction = h.activeLinkTransaction
    h.startCapabilityTest()
    check(h.started == 0, "Blocked entry advanced: " + name)
    check(h.capabilityTestSession?.token == session && h.activeLinkTransaction == transaction,
          "Blocked entry replaced baseline: " + name)
}
let idle = Harness(); idle.startCapabilityTest(); check(idle.started == 1, "Idle rejected")
let recovery = Harness(); let first = UUID(); let replacement = UUID()
recovery.displayRecoveryToken = first; recovery.linkVerificationComplete = false
recovery.completeDisplayRecovery(token: replacement)
check(recovery.displayRecoveryToken == first && !recovery.linkVerificationComplete, "Foreign release")
recovery.displayRecoveryToken = replacement
recovery.completeDisplayRecovery(token: first)
check(recovery.displayRecoveryToken == replacement, "Stale owner released replacement")
recovery.completeDisplayRecovery(token: replacement)
check(recovery.displayOperationAvailability.canStart, "Completed recovery remains occupied")
for requested: CapabilityTestStage in [.completed, .cancelled, .failedSafely] {
    for confirmed in [true, false] {
        let h = Harness(); h.capabilityTestSession = FakeSession(completionStage: requested)
        h.capabilityTestStage = .restoring; h.capabilityRestoreContext = 7
        h.linkVerificationComplete = false; h.activeLinkTransaction = 42
        let oldToken = h.linkAttemptToken
        h.finishCapabilityTestRestore(confirmed: confirmed, detail: "result")
        check(h.linkVerificationComplete && h.capabilityTestSession == nil && h.activeLinkTransaction == nil && h.capabilityRestoreContext == nil, "Incomplete terminal cleanup")
        check(h.linkAttemptToken != oldToken, "Continuation not invalidated")
        check(h.capabilityTestStage == (confirmed ? requested : .failedSafely), "Wrong terminal")
        check(h.capabilityTestDisplayID == nil && h.capabilityTestCurrent.isEmpty, "Stale UI target")
        check(h.displayOperationAvailability.canStart, "Terminal remains busy")
        check(h.diagnostics.last?.contains("PHYSICAL_VERIFICATION=UNAVAILABLE") == true, "Evidence upgraded")
        if !confirmed { check(h.diagnostics.last?.contains("CONTROL_VERIFICATION=UNCONFIRMED") == true && h.capabilityTestProgress != 100, "Failed restore claimed completion") }
    }
}
func restoring() -> Harness {
    let h = Harness(); h.capabilityTestSession = FakeSession(); h.capabilityTestStage = .restoring
    h.capabilityRestoreContext = 7; h.linkVerificationComplete = false
    return h
}
let detached = restoring(); detached.invalidateOnRefresh = true
let detachedToken = detached.capabilityTestSession!.token
detached.pollCapabilityTestHDRRestore(sessionToken: detachedToken, attempt: 0)
DispatchQueue.main.drain()
check(detached.capabilityTestStage == .failedSafely && detached.linkVerificationComplete && detached.capabilityTestSession == nil, "Context loss stranded session")
check(detached.readbackCount == 0 && detached.restoredLinkCount == 0, "Detached target continued")
let missing = restoring(); missing.capabilityTestSession!.originalSystemHDR = nil
missing.pollCapabilityTestHDRRestore(sessionToken: missing.capabilityTestSession!.token, attempt: 0)
DispatchQueue.main.drain()
check(missing.capabilityTestStage == .failedSafely && missing.displayOperationAvailability.canStart, "Missing baseline stranded session")
let delayed = restoring(); CoreDisplayHDRController.shared.reads = [false, false, true]
delayed.pollCapabilityTestHDRRestore(sessionToken: delayed.capabilityTestSession!.token, attempt: 0)
DispatchQueue.main.runNext(); delayed.startCapabilityTest()
check(delayed.started == 0 && !delayed.linkVerificationComplete, "Retry released ownership")
DispatchQueue.main.drain()
check(delayed.readbackCount == 3 && delayed.restoredLinkCount == 1, "Delayed readback did not advance exactly once")
check(delayed.capabilityTestStage == .restoring && !delayed.linkVerificationComplete, "HDR readback prematurely terminated link restore")
let timeout = restoring(); CoreDisplayHDRController.shared.reads = [false, false, false, false, false]
timeout.pollCapabilityTestHDRRestore(sessionToken: timeout.capabilityTestSession!.token, attempt: 0)
DispatchQueue.main.drain()
check(timeout.capabilityTestStage == .failedSafely && timeout.displayOperationAvailability.canStart && timeout.readbackCount == 5, "Timeout lacks bounded terminal")
let stale = restoring(); let staleToken = stale.capabilityTestSession!.token
stale.pollCapabilityTestHDRRestore(sessionToken: staleToken, attempt: 0)
stale.finishCapabilityTestRestore(confirmed: true, detail: "cancelled")
stale.capabilityTestSession = FakeSession(); stale.capabilityTestStage = .restoring; stale.linkVerificationComplete = false
let replacementToken = stale.capabilityTestSession!.token
DispatchQueue.main.drain()
check(stale.capabilityTestSession?.token == replacementToken && !stale.linkVerificationComplete && stale.readbackCount == 0 && stale.restoredLinkCount == 0, "Old callback mutated replacement session")
let next = restoring()
next.scheduleCandidateContinuation(session: next.capabilityTestSession!)
DispatchQueue.main.drain()
check(next.nextCandidateCount == 0, "Delayed candidate advanced during restore")
next.capabilityTestStage = .waitingForReadback
next.scheduleCandidateContinuation(session: next.capabilityTestSession!)
next.capabilityTestSession = FakeSession()
DispatchQueue.main.drain()
check(next.nextCandidateCount == 0, "Old candidate callback advanced replacement")
next.scheduleCandidateContinuation(session: next.capabilityTestSession!)
DispatchQueue.main.drain()
check(next.nextCandidateCount == 1, "Current session continuation blocked")
let linkSuccess = restoring()
CoreDisplayHDRController.shared.reads = Array(repeating: true, count: 6)
linkSuccess.pollCapabilityTestRestore(stableCount: 0, attempt: 0)
DispatchQueue.main.runNext()
check(!linkSuccess.linkVerificationComplete && linkSuccess.capabilityTestStage == .restoring, "Single observation released restore")
DispatchQueue.main.drain()
check(linkSuccess.capabilityTestStage == .cancelled && linkSuccess.displayOperationAvailability.canStart && linkSuccess.readbackCount == 3, "Stable link restore failed to terminate")
let linkFailure = restoring()
CoreDisplayHDRController.shared.reads = Array(repeating: true, count: 14)
DisplayOutputController.shared.observed = "different connection"
linkFailure.pollCapabilityTestRestore(stableCount: 0, attempt: 0)
DispatchQueue.main.drain()
check(linkFailure.capabilityTestStage == .failedSafely && linkFailure.displayOperationAvailability.canStart && linkFailure.readbackCount == 7, "Link mismatch failed to terminate at existing budget")
DisplayOutputController.shared.observed = "SLS_REPORTED"
let changedDisplay = restoring(); changedDisplay.presentHardwareKey = "device-B"
changedDisplay.pollCapabilityTestRestore(stableCount: 0, attempt: 0)
DispatchQueue.main.drain()
check(changedDisplay.capabilityTestStage == .failedSafely && changedDisplay.readbackCount == 0 && changedDisplay.displayOperationAvailability.canStart, "Replacement display read as original")
let vanished = restoring(); vanished.presentHardwareKey = nil
vanished.pollCapabilityTestRestore(stableCount: 0, attempt: 0)
DispatchQueue.main.drain()
check(vanished.capabilityTestStage == .failedSafely && vanished.displayOperationAvailability.canStart, "Unplug stranded link restore")
let staleLink = restoring()
staleLink.pollCapabilityTestRestore(stableCount: 0, attempt: 0)
staleLink.capabilityTestSession = FakeSession()
let newLinkToken = staleLink.capabilityTestSession!.token
DispatchQueue.main.drain()
check(staleLink.capabilityTestSession?.token == newLinkToken && !staleLink.linkVerificationComplete && staleLink.readbackCount == 0, "Old link callback mutated new session")
print("Display lifecycle tests: \(assertions) assertions PASS; offline, no hardware writes")
SWIFT
Dir.mktmpdir('rightdisplay-lifecycle-tests-', '/private/tmp') do |dir|
  source = File.join(dir, 'main.swift')
  File.write(source, "import Foundation\n" + models + stubs + methods + "}\n" + checks)
  exe = File.join(dir, 'lifecycle-tests')
  abort 'Compile failed' unless system('xcrun', 'swiftc', '-module-cache-path', File.join(dir, 'ModuleCache'), source, '-o', exe)
  abort 'Tests failed' unless system(exe)
end
