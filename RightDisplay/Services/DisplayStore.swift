// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import Combine
import CoreGraphics
import Darwin
import IOKit

#if DEBUG
private let displayObservationValidationTraceEnabled = ProcessInfo.processInfo.environment["RIGHTDISPLAY_PERF_TRACE"] == "1"
#endif

enum DisplayFeatureChange: Equatable {
    case hdr, vrr, dsc
}

private struct CapabilityTestSession {
    let token: UUID
    let displayID: CGDirectDisplayID
    let hardwareKey: String
    let interfaceName: String
    let modeID: Int32
    let originalIndex: UInt32
    let originalDescription: DisplayLinkDescription
    let originalSystemHDR: Bool?
    var candidates: [DisplayLinkCapability]
    var nextIndex: Int
    var consecutiveWriteFailures: Int
    var completionStage: CapabilityTestStage
    var successfulSemanticStates: Set<String>
    var successCount: Int
    var reconfirmedCount: Int
    var failureCount: Int
    var unconfirmedCount: Int
}

enum CapabilityTestTiming {
    static let negotiationGracePeriod: TimeInterval = 3.0
    static let minimumStableDuration: TimeInterval = 3.0
    static let observationWindow: TimeInterval = 4.0
    static let maximumCandidateTimeout: TimeInterval = 15.0
    static let readbackInterval: TimeInterval = 0.75
    static let engineGeneration = 4
}

struct CapabilityTestEligibility {
    enum Level: String {
        case enabled = "ENABLED"
        case limitedSystemEnumeration = "LIMITED_SYSTEM_ENUMERATION"
        case limitedDeviceCapability = "LIMITED_DEVICE_CAPABILITY"
        case unavailable = "UNAVAILABLE"
    }

    let level: Level
    let rawDescriptionCount: Int
    let normalizedStateCount: Int
    let edidEnvelope: EDIDCapabilityEnvelope?
    let candidateSemanticStateCount: Int
    let observedStableCount: Int
    let applyConfirmedCount: Int

    var isEnabled: Bool { level == .enabled }

    var reason: String {
        switch level {
        case .enabled: ""
        case .limitedSystemEnumeration: "设备声明或历史证据包含多个链路状态，但系统当前未提供足够的可切换链路状态"
        case .limitedDeviceCapability: "当前可信证据只包含一个有意义的链路状态"
        case .unavailable: "无法获得足够可信的链路能力证据"
        }
    }

    var diagnosticSummary: String {
        let envelope = edidEnvelope
        return "edidPresent=\(envelope != nil) edidEncodings=\(envelope?.encodingSummary ?? "unavailable") edidBitDepths=\(envelope?.declaredBitDepths.map(String.init).joined(separator: ",") ?? "unavailable") edidHDR=\(envelope.map { $0.hasHDR ? $0.hdrEOTFs.joined(separator: ",") : "SDR-only" } ?? "unavailable") interfaceEvidence=\(envelope?.interfaceEvidence.joined(separator: ",") ?? "unavailable") rawDescriptions=\(rawDescriptionCount) normalizedStates=\(normalizedStateCount) candidateSemanticStates=\(candidateSemanticStateCount) executableProbes=\(normalizedStateCount) observedStable=\(observedStableCount) applyConfirmed=\(applyConfirmedCount) eligibility=\(level.rawValue) reason=\(reason.isEmpty ? "enough-executable-semantic-states" : reason)"
    }
}

// Presentation inventory only. Transaction callers never consult this cache.
// The timer still reads active state; expensive capability enumeration is rebuilt
// on events, changed active identity, or conservative monotonic reconciliation.
struct DisplayObservationInventory<Value> {
    private struct Entry { let key: String; let builtAt: TimeInterval; let value: Value }
    private var entries: [UInt32: Entry] = [:]
    let reconciliationInterval: TimeInterval = 120
    mutating func value(for id: UInt32, key: String, now: TimeInterval,
                        forceFresh: Bool, build: () -> Value) -> Value {
        if !forceFresh, let entry = entries[id], entry.key == key,
           now >= entry.builtAt, now - entry.builtAt < reconciliationInterval { return entry.value }
        let value = build()
        entries[id] = Entry(key: key, builtAt: now, value: value)
        return value
    }
    mutating func invalidate(_ id: UInt32) { entries.removeValue(forKey: id) }
    mutating func retain(_ ids: Set<UInt32>) { entries = entries.filter { ids.contains($0.key) } }
}

private struct DisplayPresentationInventory {
    let modes: [DisplayModeOption]
    let compatibleLinks: [DisplayLinkDescription]
}

@MainActor
final class DisplayStore: ObservableObject {
    static let shared = DisplayStore()

    @Published private(set) var displays: [DisplaySnapshot] = []
    @Published var selectedDisplayID: CGDirectDisplayID = 0
    @Published private(set) var pendingModeConfirmation = false
    @Published private(set) var confirmationSeconds = 0
    @Published private(set) var lastError: String?
    @Published private(set) var requestedOutputPreference: OutputPreference?
    @Published private(set) var requestedBitDepth: Int?
    @Published private(set) var pendingChangeSummary = "显示设置"
    @Published private(set) var pendingVerificationText = "正在复读系统状态…"
    @Published private(set) var linkVerificationComplete = true
    @Published private(set) var autoCorrectionStage: AutoCorrectionStage = .idle
    @Published private(set) var autoCorrectionDetail = ""
    @Published private(set) var currentAutoCorrectionPlan: AutoCorrectionPlan?
    @Published private(set) var safeSessionActive = false
    @Published private(set) var applyingFeature: DisplayFeatureChange?
    @Published private(set) var capabilityTestStage: CapabilityTestStage = .idle
    @Published private(set) var capabilityTestProgress = 0
    @Published private(set) var capabilityTestTotal = 0
    @Published private(set) var capabilityTestCurrent = ""
    @Published private(set) var capabilityTestDetail = ""
    @Published private(set) var capabilityTestEnvironment = "—"
    @Published private(set) var capabilityTestReadback = "HDR：—\n链路：—"
    @Published private(set) var capabilityTestDisplayID: CGDirectDisplayID?
    @Published private(set) var capabilityTestSuccessCount = 0
    @Published private(set) var capabilityTestReconfirmedCount = 0
    @Published private(set) var capabilityTestFailureCount = 0
    @Published private(set) var capabilityTestUnconfirmedCount = 0
    @Published private(set) var capabilityTestAttemptResults: [CapabilityTestAttemptResult] = []
    @Published private(set) var capabilityTestSessionStableModes: [ValidatedLinkMode] = []
    @Published private(set) var verifiedLinkApplyStatus = ""
    @Published private(set) var softReplugStatus = ""

    private var previousMode: (displayID: CGDirectDisplayID, mode: CGDisplayMode)?
    private var previousOutputMode: (displayID: CGDirectDisplayID, modeID: Int32, index: UInt32, description: DisplayLinkDescription?)? {
        didSet { previousOutputContext = previousOutputMode.flatMap { linkContext(for: $0.displayID) } }
    }
    private var previousOutputContext: LinkOperationContext?
    private var linkContextGeneration = UUID()
    private var linkTopology: [String] = []
    private var displayIdentityRegistry = DisplayIdentityRegistry()
    private var observationInventory = DisplayObservationInventory<DisplayPresentationInventory>()
    private var automaticScheduleToken = UUID()
    private var manualPreparationToken = UUID()
    private var capabilityRestoreContext: LinkOperationContext?
    private var displayRecoveryToken: UUID?
    private var softReplugOperationToken: UUID?
    private var colorProfileOperationToken: UUID?
    var colorProfileGeneration: UUID { linkContextGeneration }

    private var displayOperationAvailability: DisplayOperationAvailability {
        DisplayOperationAvailability(
            verificationPending: !linkVerificationComplete,
            confirmationPending: pendingModeConfirmation,
            linkTransactionActive: activeLinkTransaction != nil,
            linkPreparationActive: !verifiedLinkApplyStatus.isEmpty || colorProfileOperationToken != nil,
            capabilityTestActive: capabilityTestStage.isRunning || capabilityTestSession != nil,
            timingChangeActive: pendingTimingChange != nil,
            recoveryActive: displayRecoveryToken != nil,
            probeActive: softReplugOperationToken != nil,
            automaticCorrectionActive: automaticCorrectionInProgress)
    }

    private func canBeginDisplayOperation() -> Bool {
        guard canModifyDisplay() else { return false }
        guard displayOperationAvailability.canStart else {
            lastError = "当前显示操作、确认或恢复尚未结束，请稍后再试。"
            return false
        }
        return true
    }

    private func completeDisplayRecovery(token: UUID) {
        guard displayRecoveryToken == token else { return }
        displayRecoveryToken = nil
        linkVerificationComplete = true
    }


    func reserveColorProfileOperation(_ device: DisplayDeviceIdentity) -> UUID? {
        guard canBeginDisplayOperation(), CGDisplayIsOnline(device.descriptor.displayID) != 0,
              displayIdentityRegistry.identity(for: device.descriptor.displayID)?.connectionInstanceKey == device.connectionInstanceKey else { return nil }
        let token = UUID(); colorProfileOperationToken = token; return token
    }
    func releaseColorProfileOperation(_ token: UUID) {
        if colorProfileOperationToken == token { colorProfileOperationToken = nil }
    }

    private func linkContext(for id: CGDirectDisplayID) -> LinkOperationContext? {
        guard let display = displaySnapshot(for: id),
              CGDisplayIsOnline(id) != 0,
              let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        return LinkOperationContext(displayID: id, hardwareKey: display.hardwareKey,
            modeID: mode.ioDisplayModeID, pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate,
            generation: linkContextGeneration)
    }

    private func isCurrentLinkContext(_ context: LinkOperationContext?) -> Bool {
        guard let context else { return false }
        return linkContext(for: context.displayID) == context
    }

    private func automaticOptionEnabled(reason: String) -> Bool {
        switch reason {
        case "Mac 唤醒": return Preferences.shared.autoCorrectColorOnWake
        case "显示器已连接": return Preferences.shared.autoCorrectColorOnDisplayConnect
        case "登录启动": return Preferences.shared.autoCorrectColorOnLoginLaunch
        default: return false
        }
    }

    private var confirmationTimer: Timer?
    private var refreshTimer: Timer?
    private var automaticCorrectionInProgress = false
    private var knownDisplayHardwareKeys: Set<String>?
    private var wakeObserver: NSObjectProtocol?
    private var pendingCapabilityRecord: ValidatedLinkMode?
    private var featureAttemptToken = UUID()
    private var linkAttemptToken = UUID()
    private var modeAttemptToken = UUID()
    private var activeLinkTransaction: LinkControlTransaction?
    private var capabilityTestSession: CapabilityTestSession?
    private var verifiedLinkApplyToken = UUID()
    private var verifiedLinkOriginalHDR: Bool?
    private var verifiedLinkApplyStartedAt: Date?
    private var capabilityTestSessionReplayProbes: [String: DisplayLinkCapability] = [:]

    @Published private(set) var linkAlternative: DesiredLinkState?
    @Published private(set) var alternativeReady = false
    private var manualEditedField: LinkEditedField?
    private var failedEditedField: LinkEditedField?
    private var alternativeOfferContext: LinkOperationContext?

    var alternativeButtonTitle: String {
        guard let alternative = linkAlternative else { return "" }
        return AppLocalization.format("尝试 %@", "\(alternative.encodingText) · \(alternative.bitDepth)-bit · \(alternative.hdrEnabled ? "HDR" : "SDR")")
    }

    func applyOfferedAlternative() {
        guard canBeginDisplayOperation() else { return }
        guard let alternative = linkAlternative, alternativeReady,
              selectedDisplayID == alternativeOfferContext?.displayID,
              isCurrentLinkContext(alternativeOfferContext), !capabilityTestStage.isRunning,
              activeLinkTransaction == nil, !pendingModeConfirmation else { return }
        linkAlternative = nil
        alternativeReady = false
        lastError = nil
        applyLinkCapability(alternative.capability, source: "USER_CONFIRMED_ALTERNATIVE")
    }

    private func findLinkAlternative(primary: DisplayLinkCapability) -> DesiredLinkState? {
        guard let field = failedEditedField, let saved = alternativeOfferContext,
              selectedDisplayID == saved.displayID, isCurrentLinkContext(saved),
              let display = displaySnapshot(for: saved.displayID),
              let state = DisplayOutputController.shared.state(displayID: saved.displayID, modeID: saved.modeID),
              let context = transitionContext(displayID: saved.displayID, actual: state.slsReportedDescription,
                hdr: CoreDisplayHDRController.shared.isEnabled(displayID: saved.displayID), stable: false) else { return nil }
        let confirmed = Set(Preferences.shared.capabilityProfile(for: display.hardwareKey,
            interfaceName: interfaceName(for: display)).modes.compactMap { mode -> DesiredLinkState? in
                guard mode.evidence == .userConfirmed, let raw = mode.rawPixelEncoding else { return nil }
                return DesiredLinkState(rawPixelEncoding: raw, bitDepth: mode.bitDepth, hdrEnabled: mode.hdr, rawRange: mode.rawRange, rawEOTF: mode.rawEOTF)
            })
        return LinkAlternativeSelector.best(primary: DesiredLinkState(rawPixelEncoding: primary.rawPixelEncoding,
            bitDepth: primary.bitDepth, hdrEnabled: primary.hdrEnabled, rawRange: primary.rawRange, rawEOTF: primary.rawEOTF), field: field, context: context,
            descriptions: state.descriptions, history: transitionHistory, session: evidenceSessionID, confirmed: confirmed)
    }

    // Presentation-only snapshots: never used to plan or execute a display write.
    private var failureDesiredCapability: DisplayLinkCapability?
    private var failureExplanationPrefix: String?
    private var presentedFailureExplanation: String?
    private var failurePresentation: (desired: DisplayLinkCapability, actual: DisplayLinkDescription?, hdr: Bool?, reason: String)?
    private var restoreExplanation = "无法确认原配置恢复状态。"

    private func failureActualText(_ actual: DisplayLinkDescription?, systemHDR: Bool?) -> String {
        let encoding = LinkPixelEncoding.title(for: actual?.pixelEncoding)
        let depth = actual.flatMap { [UInt32(8), 10, 12].contains($0.bitDepth) ? "\($0.bitDepth) bit" : nil }
            ?? AppLocalization.string("位深未知")
        let hdr: String
        if let actual, let systemHDR, actual.isHDR == systemHDR {
            hdr = systemHDR ? "HDR" : "SDR"
        } else if actual != nil, systemHDR != nil {
            hdr = AppLocalization.string("HDR 状态冲突")
        } else {
            hdr = AppLocalization.string("HDR 状态未知")
        }
        return "\(encoding) · \(depth) · \(hdr)"
    }

    private func showLinkFailure(desired: DisplayLinkCapability, actual: DisplayLinkDescription?, systemHDR: Bool?, reason: String) {
        failurePresentation = (desired, actual, systemHDR, reason)
        var prefix = AppLocalization.format(
            "macOS 未确认请求的完整链路状态。\n请求：%@\n实际（失败时复读）：%@\n%@",
            linkTestTargetText(desired), failureActualText(actual, systemHDR: systemHDR), reason)
        linkAlternative = findLinkAlternative(primary: desired)
        alternativeReady = restoreExplanation == "已恢复原配置。"
        if let alternative = linkAlternative {
            var changes: [String] = []
            if alternative.hdrEnabled != desired.hdrEnabled {
                changes.append(AppLocalization.string(alternative.hdrEnabled ? "开启 HDR" : "关闭 HDR"))
            }
            if alternative.rawPixelEncoding != desired.rawPixelEncoding {
                changes.append(AppLocalization.format("颜色格式改为 %@", alternative.encodingText))
            }
            if alternative.bitDepth != desired.bitDepth {
                changes.append(AppLocalization.format("色深改为 %d-bit", alternative.bitDepth))
            }
            prefix += "\n\n" + AppLocalization.format("当前连接已发现另一种稳定状态：%@。\n选择后将同时%@。恢复确认后可手动尝试。",
                "\(alternative.encodingText) · \(alternative.bitDepth)-bit · \(alternative.hdrEnabled ? "HDR" : "SDR")", changes.joined(separator: "、"))
        }
        failureExplanationPrefix = prefix
        let text = prefix + "\n" + AppLocalization.string(restoreExplanation)
        presentedFailureExplanation = text
        lastError = text
    }

    private func updateRestoreExplanation(_ text: String) {
        let previous = AppLocalization.string(restoreExplanation)
        restoreExplanation = text
        alternativeReady = text == "已恢复原配置。"
        // Never reopen a dismissed alert or replace another transaction's error.
        if text == "已恢复原配置。", lastError != nil, lastError == presentedFailureExplanation,
           let failure = failurePresentation {
            showLinkFailure(desired: failure.desired, actual: failure.actual, systemHDR: failure.hdr, reason: failure.reason)
            return
        }
        if let prefix = failureExplanationPrefix,
           let presented = presentedFailureExplanation, lastError == presented {
            let updated = prefix + "\n" + AppLocalization.string(text)
            presentedFailureExplanation = updated
            lastError = updated
        } else if lastError == previous {
            lastError = AppLocalization.string(text)
        }
    }

    private let evidenceSessionID = UUID()
    private lazy var transitionHistory: [LinkTransitionEvidence] = {
        guard let data = UserDefaults.standard.data(forKey: "linkTransitionEvidence.v1"),
              let records = try? JSONDecoder().decode([LinkTransitionEvidence].self, from: data) else { return [] }
        return Array(records.filter { $0.context.timingIdentity != nil }.suffix(80))
    }()
    private var plannerDeadline: Date?
    private var plannerSource = "MANUAL"
    private var plannerPathContext: LinkTransitionContext?
    private var plannerActions: [LinkTransitionAction] = []
    private var plannerExecuted: [LinkExecutedAction] = []
    private var plannerSLSCount = 0
    private var plannerHDRCount = 0
    private struct ActionVisit: Hashable {
        let context: LinkTransitionContext
        let action: LinkTransitionAction
    }
    private var plannerVisits: Set<ActionVisit> = []
    private var testBudget: LinkTestBudget?
    private var testScheduledProbe: DisplayLinkDescription?
    private var testBaselinePending = false
    private struct TestProbeVisit: Hashable {
        let probe: DisplayLinkDescription
        let environment: Bool
    }
    private var testProbeVisits: Set<TestProbeVisit> = []
    private var testEnvironmentVisits: Set<Bool> = []
    private var testResultLoops: Set<ActionVisitResult> = []
    private struct ActionVisitResult: Hashable {
        let context: LinkTransitionContext
        let actions: [LinkExecutedAction]
        let actual: DisplayLinkDescription?
    }
    private var testLoopDetected = false
    private var linkTestDiagnosticSessionID = "unassigned"
    private var linkTestDiagnosticStartedAt: Date?
    private var linkTestSchedulerIteration = 0
    private var linkTestStopLogged = false

    private func updateTestProgress() {
        capabilityTestTotal = 100
        capabilityTestProgress = max(capabilityTestProgress, testBudget?.progress ?? 0)
    }

    private func testMayContinue(observing: Bool = false) -> Bool {
        guard let budget = testBudget,
              (observing ? Date() < budget.deadline : !budget.shouldStop(now: Date()) && !testLoopDetected),
              isCurrentLinkContext(capabilityRestoreContext), !safeSessionActive,
              !Preferences.shared.safeModeEnabled else { return false }
        return true
    }

    private func recordTestInformation(actual: DisplayLinkDescription?, stable: Bool) {
        testBudget?.observe(stable ? actual : nil, actionCount: testExecutedActions.count)
        if let context = testTransitionContext, !testExecutedActions.isEmpty {
            let result = ActionVisitResult(context: context, actions: testExecutedActions, actual: actual)
            if !testResultLoops.insert(result).inserted { testLoopDetected = true }
        }
        updateTestProgress()
    }

    private var testTransitionContext: LinkTransitionContext?
    private var testExecutedActions: [LinkExecutedAction] = []
    private var lastTestStableActual: DisplayLinkDescription?

    private func transitionContext(displayID: CGDirectDisplayID, actual: DisplayLinkDescription?, hdr: Bool?, stable: Bool) -> LinkTransitionContext? {
        guard let display = displaySnapshot(for: displayID),
              let timing = currentTiming(displayID: displayID, modes: allModes(for: displayID)) else { return nil }
        let identity = PersistentTimingIdentity(timing.timingIdentity)
        return LinkTransitionContext(hardwareKey: display.hardwareKey,
            interfaceEvidence: interfaceName(for: display), timing: "v2|\(identity.key)", timingIdentity: identity,
            startingActual: actual, systemHDR: hdr, startingStable: stable,
            engineVersion: LinkEvidencePlanner.engineVersion,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString)
    }

    private func recordTransition(context: LinkTransitionContext?, actions: [LinkExecutedAction], actual: DisplayLinkDescription?, hdr: Bool?, stable: Bool, desired: DesiredLinkState?, source: String) {
        guard let context, !actions.isEmpty else { return }
        let matched = stable && desired.map { LinkEvidencePlanner.exact($0, actual: actual, hdr: hdr) } == true
        transitionHistory.append(LinkTransitionEvidence(context: context, actions: actions,
            actual: actual, systemHDR: hdr, desired: desired, stable: stable, exactMatch: matched,
            source: source, session: evidenceSessionID, timestamp: Date()))
        if transitionHistory.count > 80 { transitionHistory.removeFirst(transitionHistory.count - 80) }
        if let data = try? JSONEncoder().encode(transitionHistory) {
            UserDefaults.standard.set(data, forKey: "linkTransitionEvidence.v1")
        }
        let related = transitionHistory.filter { $0.context == context && $0.actions.map(\.action) == actions.map(\.action) }
        appendApplyDiagnostic("TRANSITION_RESULT", "source=\(source) start=\(linkTestSemanticText(context.startingActual)) actions=\(actions.map { String(describing: $0.action) }) stableActual=\(linkTestSemanticText(actual)) stable=\(stable) desiredMatch=\(matched)")
        appendApplyDiagnostic("EVIDENCE_UPDATED", "successCount=\(related.filter(\.exactMatch).count) failureCount=\(related.filter { !$0.exactMatch }.count)")
    }

    private func plannerDesired(_ transaction: LinkControlTransaction) -> DesiredLinkState? {
        guard let capability = transaction.finalExpectedCapability else { return nil }
        return DesiredLinkState(rawPixelEncoding: capability.rawPixelEncoding,
            bitDepth: capability.bitDepth, hdrEnabled: capability.hdrEnabled, rawRange: capability.rawRange, rawEOTF: capability.rawEOTF)
    }

    private func finishPlannerObservation(_ transaction: LinkControlTransaction, actual: DisplayLinkDescription, hdr: Bool?) -> Bool {
        guard let desired = plannerDesired(transaction) else { return false }
        if plannerSLSCount == 0 && plannerHDRCount == 0,
           let state = DisplayOutputController.shared.state(displayID: transaction.displayID, modeID: transaction.modeID),
           state.slsReportedDescription == actual {
            previousOutputMode = (transaction.displayID, transaction.modeID, state.activeIndex, actual)
            verifiedLinkOriginalHDR = hdr
        }
        recordTransition(context: plannerPathContext, actions: plannerExecuted, actual: actual,
            hdr: hdr, stable: true, desired: desired, source: plannerSource)
        if LinkEvidencePlanner.exact(desired, actual: actual, hdr: hdr) { return true }
        appendApplyDiagnostic("REPLAN", "reason=complete-desired-mismatch")
        advanceEvidencePlanner(token: transaction.token, actual: actual, hdr: hdr)
        return false
    }

    private func advanceEvidencePlanner(token: UUID, actual: DisplayLinkDescription, hdr: Bool?) {
        guard var transaction = activeLinkTransaction, transaction.token == token,
              linkAttemptToken == token, transaction.usesEvidencePlanner,
              let desired = plannerDesired(transaction),
              let capability = transaction.finalExpectedCapability else { return }
        guard isCurrentLinkContext(transaction.context), !safeSessionActive,
              !Preferences.shared.safeModeEnabled, let deadline = plannerDeadline, Date() < deadline,
              let context = transitionContext(displayID: transaction.displayID, actual: actual, hdr: hdr, stable: true),
              let state = DisplayOutputController.shared.state(displayID: transaction.displayID, modeID: transaction.modeID) else {
            failVerifiedLinkApply(capability, displayID: transaction.displayID, actual: actual, reason: "链路上下文失效或已达到总时间限制。")
            return
        }
        if plannerActions.isEmpty {
            plannerExecuted = []
            plannerPathContext = context
            let paths = LinkEvidencePlanner.rankedPaths(desired: desired, context: context,
                descriptions: state.descriptions, history: transitionHistory, session: evidenceSessionID)
            if let path = paths.first(where: { path in
                path.actions.first.map { !plannerVisits.contains(ActionVisit(context: context, action: $0)) } == true
            }) {
                plannerActions = path.actions
                appendApplyDiagnostic("PATH_SELECTED", "evidenceRelevance=\(path.relevance) successCount=\(path.successes) failureCount=\(path.failures) actions=\(path.actions)")
            } else {
                // A same-name description is only a fallback stimulus, not a final-state command.
                let direct = state.descriptions.first {
                    LinkEvidencePlanner.exact(desired, actual: $0, hdr: $0.isHDR) &&
                        !plannerVisits.contains(ActionVisit(context: context, action: .sls($0)))
                }
                if hdr != desired.hdrEnabled,
                   !plannerVisits.contains(ActionVisit(context: context, action: .hdr(desired.hdrEnabled))) {
                    plannerActions = [.hdr(desired.hdrEnabled)]
                } else if let direct {
                    plannerActions = [.sls(direct)]
                }
                appendApplyDiagnostic("PATH_SELECTED", "evidenceRelevance=DIRECT_CANDIDATE actions=\(plannerActions)")
            }
        }
        guard !plannerActions.isEmpty else {
            failVerifiedLinkApply(capability, displayID: transaction.displayID, actual: actual,
                reason: "当前没有已知可靠路径；可先运行 Display Link Test 收集路径证据。")
            return
        }
        let action = plannerActions.removeFirst()
        guard plannerVisits.insert(ActionVisit(context: context, action: action)).inserted else {
            failVerifiedLinkApply(capability, displayID: transaction.displayID, actual: actual, reason: "相同上下文与动作已尝试，停止重复路径。")
            return
        }
        let accepted: Bool
        switch action {
        case .hdr(let enabled):
            guard plannerHDRCount < 2 else {
                failVerifiedLinkApply(capability, displayID: transaction.displayID, actual: actual, reason: "已达到环境操作次数限制。")
                return
            }
            plannerHDRCount += 1
            accepted = CoreDisplayHDRController.shared.setEnabled(enabled, displayID: transaction.displayID)
        case .sls(let probe):
            guard plannerSLSCount < 3,
                  let fresh = DisplayOutputController.shared.state(displayID: transaction.displayID, modeID: transaction.modeID),
                  let index = fresh.descriptions.firstIndex(of: probe) else {
                failVerifiedLinkApply(capability, displayID: transaction.displayID, actual: actual, reason: "探测项当前不可定位或已达到探测次数限制。")
                return
            }
            plannerSLSCount += 1
            accepted = DisplayOutputController.shared.setOutputMode(displayID: transaction.displayID,
                modeID: transaction.modeID, index: UInt32(index)) == 0
        }
        plannerExecuted.append(LinkExecutedAction(action: action, accepted: accepted))
        appendApplyDiagnostic("ACTION_EXECUTED", "action=\(action) accepted=\(accepted)")
        guard accepted else {
            recordTransition(context: plannerPathContext, actions: plannerExecuted, actual: actual, hdr: hdr,
                stable: false, desired: desired, source: plannerSource)
            failVerifiedLinkApply(capability, displayID: transaction.displayID, actual: actual, reason: "系统未接受链路动作。")
            return
        }
        transaction.writeAccepted = true
        transaction.writeStartedAt = Date()
        transaction.stableObservation = nil
        transaction.stableStartedAt = nil
        transaction.observationStartedAt = nil
        transaction.stableReadCount = 0
        transaction.sawTarget = false
        activeLinkTransaction = transaction
        verifiedLinkApplyStatus = "正在确认协商后的实际输出…"
        pollLinkTransaction(token: token)
    }

    private var linkTestDiagnosticURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RightDisplay", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("LinkTest-Diagnostics.log")
    }

    private func resetLinkTestDiagnostics() {
        linkTestDiagnosticSessionID = String(UUID().uuidString.prefix(8)).uppercased()
        linkTestDiagnosticStartedAt = Date()
        linkTestSchedulerIteration = 0
        linkTestStopLogged = false
        appendLinkTestDiagnostic("SESSION_START", "engineGeneration=\(CapabilityTestTiming.engineGeneration)")
    }

    private func linkTestCandidateKey(_ item: DisplayLinkDescription) -> String {
        "enc\(item.pixelEncoding)-d\(item.bitDepth)-r\(item.range)-e\(item.eotf)"
    }

    private func linkTestCandidateFields(_ item: DisplayLinkDescription) -> String {
        let encoding = item.encodingText.replacingOccurrences(of: " ", with: "_")
        return "key=\(linkTestCandidateKey(item)) encodingRaw=\(item.pixelEncoding) encoding=\(encoding) bitDepth=\(item.bitDepth) range=\(item.range) eotf=\(item.eotf) hdr=\(item.isHDR)"
    }

    private func linkTestProbeScore(_ probe: DisplayLinkDescription, context: LinkTransitionContext,
                                    seen: Set<DisplayLinkDescription>, declaredDepths: Set<Int>) -> (Int, String) {
        let evidence = transitionHistory.filter { $0.context.hardwareKey == context.hardwareKey &&
            $0.context.timing == context.timing && $0.actions.contains { $0.action == .sls(probe) } }
        let novel = evidence.filter { $0.stable && $0.actual.map { !seen.contains($0) } == true }
        let relevant = novel.contains { $0.context.interfaceEvidence == context.interfaceEvidence &&
            $0.context.startingActual == context.startingActual && $0.context.systemHDR == context.systemHDR }
        let historyBonus = relevant ? 120 : (novel.isEmpty ? 0 : 70)
        let encodingBonus = seen.contains { $0.pixelEncoding == probe.pixelEncoding } ? 0 : 30
        let depthBonus = seen.contains { $0.bitDepth == probe.bitDepth } ? 0 : 20
        let edidBonus = declaredDepths.contains(Int(probe.bitDepth)) ? 3 : 0
        let failurePenalty = min(30, evidence.filter { !$0.stable }.count * 5)
        let duplicatePenalty = min(20, evidence.filter { $0.actual.map { seen.contains($0) } == true }.count * 2)
        let score = historyBonus + encodingBonus + depthBonus + edidBonus + 10 - failurePenalty - duplicatePenalty
        return (score, "history=\(historyBonus) unseenEncoding=\(encodingBonus) unseenDepth=\(depthBonus) edid=\(edidBonus) base=10 failurePenalty=-\(failurePenalty) duplicatePenalty=-\(duplicatePenalty)")
    }

    private func appendLinkTestPoolDiagnostics(state: DisplayOutputState, context: LinkTransitionContext,
                                               hdr: Bool, budget: LinkTestBudget,
                                               declaredDepths: Set<Int>, ranked: [DisplayLinkDescription]) {
        appendLinkTestDiagnostic("CANDIDATE_POOL", "iteration=\(linkTestSchedulerIteration) rawCount=\(state.descriptions.count)")
        for (index, item) in state.descriptions.enumerated() {
            appendLinkTestDiagnostic("RAW_CANDIDATE", "iteration=\(linkTestSchedulerIteration) index=\(index) \(linkTestCandidateFields(item))")
            let reason: String?
            if !LinkPixelEncoding.isKnown(item.pixelEncoding) { reason = "unsupported-encoding" }
            else if ![UInt32(8), 10, 12].contains(item.bitDepth) { reason = "unsupported-depth" }
            else if item.isRGB && !item.isFullRange { reason = "rgb-non-full-range" }
            else { reason = nil }
            if let reason {
                appendLinkTestDiagnostic("FILTERED_CANDIDATE", "iteration=\(linkTestSchedulerIteration) \(linkTestCandidateFields(item)) reason=\(reason)")
            } else {
                appendLinkTestDiagnostic("NORMALIZED_CANDIDATE", "iteration=\(linkTestSchedulerIteration) semanticKey=\(capabilityTestSemanticKey(item)) \(linkTestCandidateFields(item))")
            }
        }
        let eligible = Set(state.descriptions.filter {
            LinkPixelEncoding.isKnown($0.pixelEncoding) && [UInt32(8), 10, 12].contains($0.bitDepth) &&
                ($0.pixelEncoding != 0 || $0.range == 1)
        })
        for item in eligible {
            let details = linkTestProbeScore(item, context: context, seen: budget.seen, declaredDepths: declaredDepths)
            if details.0 <= 0 {
                appendLinkTestDiagnostic("FILTERED_CANDIDATE", "iteration=\(linkTestSchedulerIteration) \(linkTestCandidateFields(item)) reason=score-zero finalScore=\(details.0) components=\(details.1)")
            }
        }
        for (rank, item) in ranked.enumerated() {
            let details = linkTestProbeScore(item, context: context, seen: budget.seen, declaredDepths: declaredDepths)
            let visited = testProbeVisits.contains(TestProbeVisit(probe: item, environment: hdr))
            appendLinkTestDiagnostic("RANKED_CANDIDATE", "iteration=\(linkTestSchedulerIteration) rank=\(rank + 1) finalScore=\(details.0) environmentMatch=\(item.isHDR == hdr) visited=\(visited) \(linkTestCandidateFields(item)) components=\(details.1)")
            if visited {
                appendLinkTestDiagnostic("PROBE_SKIPPED", "iteration=\(linkTestSchedulerIteration) \(linkTestCandidateFields(item)) reason=already-visited-in-current-environment")
            }
        }
    }

    private func appendLinkTestBudgetState(_ phase: String, ranked: [DisplayLinkDescription] = []) {
        guard let budget = testBudget else { return }
        let remaining = max(0, budget.deadline.timeIntervalSinceNow)
        let remainingEligible = ranked.filter {
            !testProbeVisits.contains(TestProbeVisit(probe: $0, environment: $0.isHDR))
        }.count
        let unseenEncoding = ranked.contains { item in !budget.seen.contains { $0.pixelEncoding == item.pixelEncoding } }
        let unseenDepth = ranked.contains { item in !budget.seen.contains { $0.bitDepth == item.bitDepth } }
        let unvisitedEnvironment = ranked.contains { !testEnvironmentVisits.contains($0.isHDR) }
        let elapsedText = String(format: "%.1f", 120 - remaining)
        let remainingText = String(format: "%.1f", remaining)
        appendLinkTestDiagnostic("BUDGET_STATE", "phase=\(phase) iteration=\(linkTestSchedulerIteration) sls=\(budget.slsActions)/6 environment=\(budget.environmentChanges)/2 noNew=\(budget.noNewResults)/3 elapsed=\(elapsedText) remaining=\(remainingText) visited=\(testProbeVisits.count) remainingEligible=\(remainingEligible) unseenEncoding=\(unseenEncoding) unseenDepth=\(unseenDepth) unvisitedEnvironment=\(unvisitedEnvironment) loop=\(testLoopDetected)")
    }

    private func appendLinkTestStop(_ primary: String, active: [String] = []) {
        guard !linkTestStopLogged else { return }
        linkTestStopLogged = true
        let activeText = (active.isEmpty ? [primary] : active).joined(separator: ",")
        appendLinkTestDiagnostic("SCHEDULER_STOP", "primary=\(primary) active=\(activeText)")
    }

    private func appendLinkTestDiagnostic(_ stage: String, _ fields: String) {
        let fields = "\(fields) controlSource=SLS_REPORTED PHYSICAL_VERIFICATION=UNAVAILABLE"
        if ["SESSION_START", "SCHEDULER_STOP", "STABLE_ACTUAL", "RESTORE_RESULT"].contains(stage) {
            DiagnosticEvents.record("link-test", stage.lowercased(), method: "existing LinkTest diagnostics", result: stage == "SESSION_START" ? "started" : "observed")
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) [LinkTest][Session \(linkTestDiagnosticSessionID)][Attempt \(capabilityTestAttemptResults.count + 1)][\(stage)] \(fields)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = linkTestDiagnosticURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                NSLog("Right Display link-test diagnostics write failed: %@", error.localizedDescription)
            }
        } else {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("Right Display link-test diagnostics write failed: %@", error.localizedDescription)
            }
        }
        NSLog("%@", line.trimmingCharacters(in: .newlines))
    }

    private func appendApplyDiagnostic(_ stage: String, _ fields: String) {
        let fields = "\(fields) controlSource=SLS_REPORTED PHYSICAL_VERIFICATION=UNAVAILABLE"
        if ["UI_USER_INTENT", "PATH_SELECTED", "ACTION_EXECUTED", "FINAL_RESULT", "RESTORE_START", "RESTORE_RESULT", "SOFT_REPLUG"].contains(stage) {
            DiagnosticEvents.record("display", stage.lowercased(), target: selectedDisplay?.name,
                requested: stage == "UI_USER_INTENT" ? fields : nil,
                observed: stage == "FINAL_RESULT" ? fields : nil,
                method: "existing Apply diagnostics",
                result: stage == "FINAL_RESULT" ? "completed; see readback" : "recorded")
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let elapsed = verifiedLinkApplyStartedAt.map { String(format: "%.2fs", Date().timeIntervalSince($0)) } ?? "n/a"
        let line = "\(timestamp) [Apply][\(stage)] elapsed=\(elapsed) \(fields)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = linkTestDiagnosticURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
        NSLog("%@", line.trimmingCharacters(in: .newlines))
    }

    private func linkTestHDRText(_ value: Bool?) -> String {
        value.map { $0 ? "true" : "false" } ?? "unavailable"
    }

    private func linkTestSemanticText(_ value: DisplayLinkDescription?) -> String {
        guard let value else { return "unavailable" }
        return "\(value.encodingText) / \(value.bitDepth)-bit / \(value.identity.rangeText) / \(value.identity.eotfText) [\(value.identity.detail)]"
    }

    private func linkTestTargetText(_ capability: DisplayLinkCapability) -> String {
        "\(capability.encodingText) / \(capability.bitDepth)-bit / \(capability.identity?.rangeText ?? "Unknown") / \(capability.identity?.eotfText ?? "Unknown") [Range=\(capability.rawRange.map(String.init) ?? "unknown"); EOTF=\(capability.rawEOTF.map(String.init) ?? "unknown")]"
    }

    private func capabilityTestSemanticKey(_ value: DisplayLinkDescription) -> String {
        "\(value.pixelEncoding)|\(value.bitDepth)|\(value.eotf)|\(value.range)"
    }

    private func capabilityTestCapability(from value: DisplayLinkDescription) -> DisplayLinkCapability {
        DisplayLinkCapability(
            outputPreference: value.isRGB ? .rgbFullRange : .yCbCr,
            encodingText: value.encodingText,
            rawPixelEncoding: value.pixelEncoding,
            bitDepth: Int(value.bitDepth),
            hdrEnabled: value.isHDR, rawRange: value.range, rawEOTF: value.eotf
        )
    }

    private func normalizedCapabilityProbes(
        from descriptions: [DisplayLinkDescription]
    ) -> [DisplayLinkCapability] {
        Array(Set(descriptions.compactMap { item -> DisplayLinkCapability? in
            guard LinkPixelEncoding.isKnown(item.pixelEncoding),
                  [8, 10, 12].contains(Int(item.bitDepth)),
                  !item.isRGB || item.isFullRange else { return nil }
            return capabilityTestCapability(from: item)
        })).sorted(by: capabilityTestSort)
    }

    func capabilityTestEligibility(for display: DisplaySnapshot) -> CapabilityTestEligibility {
        let envelope = EDIDStore.shared.capabilityEnvelope.flatMap {
            $0.hardwareKey == display.hardwareKey ? $0 : nil
        }
        let profile = Preferences.shared.capabilityProfile(
            for: display.hardwareKey,
            interfaceName: interfaceName(for: display)
        )
        func evidenceKey(_ mode: ValidatedLinkMode) -> String {
            "\(mode.rawPixelEncoding.map(String.init) ?? "unknown")|\(mode.bitDepth)|\(mode.rawRange.map(String.init) ?? "unknown")|\(mode.rawEOTF.map(String.init) ?? "unknown")"
        }
        let observedKeys = Set(profile.modes.filter {
            ($0.evidence == .observedStable || $0.evidence == .systemReadback) &&
                $0.engineGeneration == CapabilityTestTiming.engineGeneration
        }.map(evidenceKey))
        let confirmedKeys = Set(profile.modes.filter { $0.evidence == .userConfirmed }.map(evidenceKey))
        let observed = observedKeys.count
        let confirmed = confirmedKeys.count
        let state = CGDisplayCopyDisplayMode(display.id).flatMap {
            DisplayOutputController.shared.state(displayID: display.id, modeID: $0.ioDisplayModeID)
        }
        let normalized = normalizedCapabilityProbes(from: state?.descriptions ?? [])
        let potentialCount = max(envelope?.semanticCapabilityCount ?? 0, observedKeys.union(confirmedKeys).count)
        let level: CapabilityTestEligibility.Level
        if normalized.count >= 2 {
            level = .enabled
        } else if potentialCount >= 2 {
            level = .limitedSystemEnumeration
        } else if normalized.count == 1 || potentialCount == 1 {
            level = .limitedDeviceCapability
        } else {
            level = .unavailable
        }
        return CapabilityTestEligibility(
            level: level,
            rawDescriptionCount: state?.descriptions.count ?? 0,
            normalizedStateCount: normalized.count,
            edidEnvelope: envelope,
            candidateSemanticStateCount: potentialCount,
            observedStableCount: observed,
            applyConfirmedCount: confirmed
        )
    }

    private func updateCapabilityTestReadback(
        hdr: Bool?,
        link: DisplayLinkDescription?
    ) {
        guard let link else {
            capabilityTestReadback = "链路暂时无法读取"
            return
        }
        let actual = linkTestSemanticText(link).replacingOccurrences(of: " / ", with: " · ")
        if let hdr, hdr != link.isHDR {
            capabilityTestReadback = "\(actual)\n系统 HDR 状态尚未同步"
        } else {
            capabilityTestReadback = actual
        }
    }

    var selectedDisplay: DisplaySnapshot? {
        displays.first(where: { $0.id == selectedDisplayID })
    }

    private var pendingTargetDisplayID: CGDirectDisplayID? {
        activeLinkTransaction?.displayID
            ?? previousOutputMode?.displayID
            ?? previousMode?.displayID
    }

    private func displaySnapshot(for displayID: CGDirectDisplayID) -> DisplaySnapshot? {
        displays.first(where: { $0.id == displayID })
    }

    private func interfaceName(for display: DisplaySnapshot) -> String {
        guard display.id == selectedDisplayID else {
            return display.isBuiltin ? "内建显示接口" : "当前外接接口"
        }
        return selectedInterfaceName
    }

    var menuBarTitle: String {
        guard let display = selectedDisplay else { return "—" }
        return "\(display.resolution)  \(display.refreshRate.text)"
    }

    private init() {}

    func startMonitoring() {
        refresh()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                guard Preferences.shared.autoCorrectColorOnWake else { return }
                self?.scheduleConditionalCorrection(reason: "Mac 唤醒")
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshObservation(forceInventoryRefresh: false) }
        }
    }

    func stopMonitoring() {
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, nil)
        refreshTimer?.invalidate()
        confirmationTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func displayConnectionChanged(_ displayID: UInt32) {
        observationInventory.invalidate(displayID)
        displayIdentityRegistry.invalidate(displayID)
        linkContextGeneration = UUID()
    }

    func refresh() {
        refreshObservation(forceInventoryRefresh: true)
    }

    private func refreshObservation(forceInventoryRefresh: Bool) {
#if DEBUG
        let trace = displayObservationValidationTraceEnabled
        if trace { fputs("DISPLAY_REFRESH_START machTicks=\(mach_absolute_time()) forced=\(forceInventoryRefresh)\n", stderr) }
        defer { if trace { fputs("DISPLAY_REFRESH_END machTicks=\(mach_absolute_time())\n", stderr) } }
#endif
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return }

        displayIdentityRegistry.update(ids.map {
            DisplayDeviceDescriptor(displayID: $0, vendor: CGDisplayVendorNumber($0),
                model: CGDisplayModelNumber($0), serial: CGDisplaySerialNumber($0))
        })
        observationInventory.retain(Set(ids))
        let snapshots = ids.compactMap { makeSnapshot($0, reuseObservationInventory: !forceInventoryRefresh) }
        let sorted = snapshots.sorted { lhs, rhs in
            if lhs.isBuiltin != rhs.isBuiltin { return !lhs.isBuiltin }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        if displays.count != sorted.count || !zip(displays, sorted).allSatisfy({ $0.hasSamePresentation(as: $1) }) {
            displays = sorted
        }

        let topology = snapshots.map { "\($0.id)|\($0.hardwareKey)" }.sorted()
        if topology != linkTopology {
            linkContextGeneration = UUID()
            linkTopology = topology
        }
        let currentKeys = Set(snapshots.map(\.hardwareKey))
        if let knownDisplayHardwareKeys {
            let connected = currentKeys.subtracting(knownDisplayHardwareKeys)
            if !connected.isEmpty,
               Preferences.shared.autoCorrectColorOnDisplayConnect,
               !Preferences.shared.safeModeEnabled,
               !safeSessionActive {
                if let newlyConnected = snapshots.first(where: { connected.contains($0.hardwareKey) }) {
                    selectedDisplayID = newlyConnected.id
                    Preferences.shared.selectedDisplayID = newlyConnected.id
                    EDIDStore.shared.refresh(for: newlyConnected)
                }
                scheduleConditionalCorrection(reason: "显示器已连接")
            }
        }
        knownDisplayHardwareKeys = currentKeys

        let preferred = CGDirectDisplayID(Preferences.shared.selectedDisplayID)
        if displays.contains(where: { $0.id == preferred }) {
            if selectedDisplayID != preferred { selectedDisplayID = preferred }
        } else if !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displays.first(where: { !$0.isBuiltin })?.id ?? displays.first?.id ?? 0
            Preferences.shared.selectedDisplayID = selectedDisplayID
        }
    }

    func clearLastError() {
        lastError = nil
    }

    func enterSafeSession() {
        if pendingModeConfirmation { restorePendingModeIfNeeded() }
        if capabilityTestStage.isRunning { beginCapabilityTestRestore(completion: .failedSafely) }
        safeSessionActive = true
        automaticCorrectionInProgress = false
        autoCorrectionStage = .idle
        autoCorrectionDetail = "本次启动处于安全模式，不会自动修改显示设置。"
    }

    func leaveSafeSession() {
        safeSessionActive = false
    }

    func reportError(_ message: String) {
        lastError = message
    }

    func selectDisplay(_ id: CGDirectDisplayID) {
        selectedDisplayID = id
        Preferences.shared.selectedDisplayID = id
        DiagnosticEvents.record("display", "target.selected", target: selectedDisplay?.name, result: "selected")
    }

    var selectedInterfaceName: String {
        guard let display = selectedDisplay else { return "未知接口" }
        if display.isBuiltin { return "内建显示接口" }
        let text = EDIDStore.shared.connection.text
        if text.contains("HDMI") {
            return display.dscEnabled == true ? "HDMI · FRL（推断）" : "HDMI · 输出模式未确认"
        }
        return text == "无法识别" || text == "接口未验证" ? "当前外接接口" : text
    }

    var selectedCapabilityProfile: DisplayCapabilityProfile? {
        guard let display = selectedDisplay else { return nil }
        return Preferences.shared.capabilityProfile(
            for: display.hardwareKey,
            interfaceName: selectedInterfaceName
        )
    }

    func setAutoCorrectionPolicy(_ policy: AutoCorrectionPolicy) {
        guard let display = selectedDisplay else { return }
        Preferences.shared.setCorrectionPolicy(
            policy,
            for: display.hardwareKey,
            interfaceName: selectedInterfaceName
        )
        _ = autoCorrectionPlan()
    }

    func scheduleConditionalCorrection(reason: String) {
        guard automaticOptionEnabled(reason: reason),
              !Preferences.shared.safeModeEnabled, !Preferences.shared.displayOutputControlsLocked, !safeSessionActive,
              let context = linkContext(for: selectedDisplayID) else { return }
        let token = UUID()
        automaticScheduleToken = token
        let authorizationGeneration = Preferences.shared.automaticAuthorizationGeneration
        let transactionToken = linkAttemptToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            self.refresh()
            guard self.automaticScheduleToken == token,
                  Preferences.shared.automaticAuthorizationGeneration == authorizationGeneration,
                  self.automaticOptionEnabled(reason: reason),
                  self.linkAttemptToken == transactionToken,
                  self.selectedDisplayID == context.displayID,
                  self.isCurrentLinkContext(context),
                  !Preferences.shared.safeModeEnabled, !Preferences.shared.displayOutputControlsLocked, !self.safeSessionActive,
                  self.linkVerificationComplete, self.verifiedLinkApplyStatus.isEmpty,
                  self.activeLinkTransaction == nil, !self.capabilityTestStage.isRunning,
                  !self.pendingModeConfirmation, !self.automaticCorrectionInProgress,
                  self.automaticCorrectionNeeded() else { return }
            self.autoCorrect()
            self.autoCorrectionDetail = "触发原因：\(reason)。\(self.autoCorrectionDetail)"
            NotificationCenter.default.post(name: .automaticCorrectionTriggered, object: nil)
        }
    }

    private struct TimingChange {
        let original: DisplayModeOption
        let target: DisplayModeOption
        let protection: TimingConnectionProtection
        let generation: UUID
    }
    private var pendingTimingChange: TimingChange?

    func apply(_ option: DisplayModeOption) {
        guard canBeginDisplayOperation(), linkVerificationComplete, !capabilityTestStage.isRunning, activeLinkTransaction == nil,
              verifiedLinkApplyStatus.isEmpty else { return }
        if pendingModeConfirmation {
            guard linkVerificationComplete else { lastError = "请等待当前切换完成验证。"; return }
            confirmPendingMode()
        }
        let targetID = selectedDisplayID
        guard let display = displaySnapshot(for: targetID),
              let target = allModes(for: targetID).first(where: { $0.timingIdentity == option.timingIdentity }),
              let current = currentTiming(displayID: targetID, modes: allModes(for: targetID)),
              CGDisplayIsOnline(targetID) != 0 else {
            lastError = "所选时序已不在当前系统枚举中，请重新选择。"; return
        }
        let before = DisplayOutputController.shared.state(displayID: targetID, modeID: current.id)
        let hdr = CoreDisplayHDRController.shared.isEnabled(displayID: targetID)
        let protection = TimingConnectionProtection(original: before?.slsReportedDescription?.identity, systemHDR: hdr)
        // Internal displays do not use the external SLS color-link controller.
        if !display.isBuiltin {
            guard protection.canVerify else {
                lastError = "当前系统报告的连接状态不完整，无法保护颜色组合；未切换时序。"; return
            }
            guard let candidateState = DisplayOutputController.shared.state(displayID: targetID, modeID: target.id),
                  protection.targetExists(in: candidateState.descriptions) else {
                lastError = "目标时序没有枚举到当前完整颜色组合。未切换；请明确选择兼容连接组合后重试。"; return
            }
        }
        let token = UUID()
        modeAttemptToken = token
        pendingTimingChange = TimingChange(original: current, target: target, protection: protection, generation: linkContextGeneration)
        previousMode = current.mode.map { (targetID, $0) }
        linkVerificationComplete = false
        lastError = nil
        appendApplyDiagnostic("TIMING_PRECHECK", "original=\(current.selectionKey) target=\(target.selectionKey) SLS_REPORTED=\(protection.original?.detail ?? "UNAVAILABLE") systemHDR=\(linkTestHDRText(hdr)) PHYSICAL_VERIFICATION=UNAVAILABLE")
        let error = setTiming(target)
        guard error == .success else {
            pendingTimingChange = nil; previousMode = nil; linkVerificationComplete = true
            lastError = "无法切换显示模式（Core Graphics 错误 \(error.rawValue)）"; return
        }
        beginConfirmationCountdown(summary: "\(target.outputResolutionText) · \(target.resolutionText) · \(target.refreshText)")
        verifyDisplayMode(target, displayID: targetID, token: token, attempt: 0)
    }

    private func setTiming(_ option: DisplayModeOption) -> CGError {
        if let mode = option.mode { return CGDisplaySetDisplayMode(option.displayID, mode, nil) }
        return DisplayTimingController.shared.applyCGS(option)
    }

    func applyOutputColor(_ preference: OutputPreference) {
        guard canBeginDisplayOperation() else { return }
        if preference == .automatic {
            autoCorrect()
        } else {
            let raw: UInt32 = preference == .rgbFullRange
                ? 0
                : (selectedDisplay?.activeRawPixelEncoding.flatMap(LinkPixelEncoding.init(rawValue:))
                    .flatMap { $0 == .rgb ? nil : $0.rawValue } ?? LinkPixelEncoding.yCbCr422.rawValue)
            applyOutputEncoding(raw)
        }
    }

    func applyOutputEncoding(_ rawPixelEncoding: UInt32) {
        guard LinkPixelEncoding.isKnown(rawPixelEncoding) else {
            lastError = "像素编码未知，不能生成可写目标。"
            return
        }
        guard linkVerificationComplete, activeLinkTransaction == nil,
              verifiedLinkApplyStatus.isEmpty, !pendingModeConfirmation else { return }
        guard selectedDisplay?.activeRawPixelEncoding != nil else {
            lastError = "当前活动链路不完整，无法形成安全的完整目标状态。"
            return
        }
        appendApplyDiagnostic("UI_USER_INTENT", "field=encoding target=\(rawPixelEncoding)")
        guard canBeginDisplayOperation() else { return }
        prepareManualLinkChange(encoding: rawPixelEncoding)
    }

    func applyBitDepth(_ bitDepth: Int) {
        guard linkVerificationComplete, activeLinkTransaction == nil,
              verifiedLinkApplyStatus.isEmpty, !pendingModeConfirmation else { return }
        guard selectedDisplay?.activeBitDepth != nil else {
            lastError = "当前活动链路不完整，无法形成安全的完整目标状态。"
            return
        }
        appendApplyDiagnostic("UI_USER_INTENT", "field=bitDepth target=\(bitDepth)")
        guard canBeginDisplayOperation() else { return }
        prepareManualLinkChange(bitDepth: bitDepth)
    }

    private func prepareManualLinkChange(encoding: UInt32? = nil, bitDepth: Int? = nil, hdr: Bool? = nil) {
        guard let display = selectedDisplay,
              let mode = CGDisplayCopyDisplayMode(display.id),
              DisplayOutputController.shared.state(displayID: display.id, modeID: mode.ioDisplayModeID)?.slsReportedDescription != nil else {
            lastError = DisplayOutputState.currentUnavailableMessage
            return
        }
        guard linkVerificationComplete, activeLinkTransaction == nil,
              !pendingModeConfirmation, !capabilityTestStage.isRunning,
              verifiedLinkApplyStatus.isEmpty, canModifyDisplay(),
              let context = linkContext(for: selectedDisplayID) else { return }
        let token = UUID()
        manualPreparationToken = token
        linkAttemptToken = UUID()
        let transactionToken = linkAttemptToken
        verifiedLinkApplyStatus = "正在确认操作前的稳定链路…"
        func poll(_ previous: DisplayLinkDescription?, _ stableSince: Date?, _ started: Date) {
            guard manualPreparationToken == token, linkAttemptToken == transactionToken else { return }
            guard selectedDisplayID == context.displayID, isCurrentLinkContext(context),
                  !safeSessionActive, !Preferences.shared.safeModeEnabled else {
                verifiedLinkApplyStatus = ""
                lastError = "操作前上下文已改变，未发送显示写入。"
                return
            }
            let actual = DisplayOutputController.shared.state(displayID: context.displayID, modeID: context.modeID)?.slsReportedDescription
            let systemHDR = CoreDisplayHDRController.shared.isEnabled(displayID: context.displayID)
            let now = Date()
            let valid = actual.map { LinkPixelEncoding.isKnown($0.pixelEncoding) &&
                [UInt32(8), 10, 12].contains($0.bitDepth) && systemHDR == $0.isHDR } ?? false
            let since = valid && actual == previous ? (stableSince ?? now) : now
            if valid, let actual, now.timeIntervalSince(since) >= CapabilityTestTiming.minimumStableDuration {
                verifiedLinkApplyStatus = ""
                guard let fresh = DisplayOutputController.shared.state(displayID: context.displayID, modeID: context.modeID),
                      hdr == nil,
                      let desired = ConnectionTargetResolver.singleField(current: actual.identity,
                          candidates: fresh.descriptions, encoding: encoding, depth: bitDepth) else {
                    lastError = "未找到唯一的系统枚举组合；请使用“连接组合”明确选择，未发送显示写入。"
                    return
                }
                if desired.exactlyMatches(rawPixelEncoding: actual.pixelEncoding,
                    bitDepth: Int(actual.bitDepth), hdr: actual.isHDR, systemHDR: systemHDR, rawRange: actual.range, rawEOTF: actual.eotf) {
                    pendingVerificationText = "当前稳定输出已满足完整目标，未发送显示写入。"
                    return
                }
                manualEditedField = bitDepth != nil ? .bitDepth : (encoding != nil ? .encoding : .hdr)
                applyDesiredLinkState(desired)
            } else if now.timeIntervalSince(started) >= CapabilityTestTiming.maximumCandidateTimeout {
                verifiedLinkApplyStatus = ""
                lastError = "操作前活动链路不完整或不稳定，未发送显示写入。"
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + CapabilityTestTiming.readbackInterval) {
                    poll(actual, valid ? since : nil, started)
                }
            }
        }
        poll(nil, nil, Date())
    }

    private func applyDesiredLinkState(_ desired: DesiredLinkState) {
        guard canModifyDisplay() else { return }
        applyLinkCapability(desired.capability, source: "MANUAL")
    }

    func applySessionStableMode(_ mode: ValidatedLinkMode) {
        guard mode.persistentIdentity != nil, let display = selectedDisplay,
              mode.timingIdentity == display.currentTimingIdentity else {
            lastError = "记录缺少完整时序／连接身份，或不属于当前时序；未复用旧证据。"; return
        }
        guard let raw = mode.rawPixelEncoding,
              LinkPixelEncoding.isKnown(raw) else {
            lastError = "本次测试没有保留该稳定链路的可重放探测路径。"
            return
        }
        let expected = DisplayLinkCapability(
            outputPreference: raw == 0 ? .rgbFullRange : .yCbCr,
            encodingText: LinkPixelEncoding.title(for: raw),
            rawPixelEncoding: raw,
            bitDepth: mode.bitDepth,
            hdrEnabled: mode.hdr, rawRange: mode.rawRange, rawEOTF: mode.rawEOTF
        )
        applyLinkCapability(expected, source: "STABLE_APPLY")
    }

    func applyLinkCapability(
        _ capability: DisplayLinkCapability,
        source: String = "APPLY",
        finalExpectedCapability: DisplayLinkCapability? = nil
    ) {
        guard canBeginDisplayOperation() else { return }
        guard let identity = capability.identity, identity.isKnown,
              identity.hdrEnabled == capability.hdrEnabled else {
            lastError = "连接目标缺少完整 Range/EOTF 证据（UNAVAILABLE），未发送显示写入。"
            return
        }
        guard !capabilityTestStage.isRunning, !pendingModeConfirmation,
              let display = selectedDisplay,
              !display.isBuiltin,
              let mode = CGDisplayCopyDisplayMode(display.id),
              let state = DisplayOutputController.shared.state(
                  displayID: display.id,
                  modeID: mode.ioDisplayModeID
              ),
              state.slsReportedDescription != nil else {
            lastError = DisplayOutputState.currentUnavailableMessage
            return
        }
        guard state.descriptions.contains(where: { $0.identity == identity }) else {
            lastError = "当前模式未枚举此完整连接组合，未发送显示写入。"
            return
        }

        let token = UUID()
        verifiedLinkApplyToken = token
        verifiedLinkApplyStartedAt = Date()
        failureDesiredCapability = finalExpectedCapability ?? capability
        failedEditedField = source == "MANUAL" ? manualEditedField : nil
        linkAlternative = nil
        alternativeReady = false
        alternativeOfferContext = linkContext(for: display.id)
        failureExplanationPrefix = nil
        presentedFailureExplanation = nil
        failurePresentation = nil
        linkAttemptToken = token
        activeLinkTransaction = nil
        previousOutputMode = (display.id, mode.ioDisplayModeID, state.activeIndex, state.slsReportedDescription)
        verifiedLinkOriginalHDR = CoreDisplayHDRController.shared.isEnabled(displayID: display.id)
        pendingCapabilityRecord = nil
        linkVerificationComplete = false
        lastError = nil
        pendingChangeSummary = "\(capability.encodingText) · \(capability.bitDepth) bit · \(capability.hdrEnabled ? "HDR" : "SDR")"
        verifiedLinkApplyStatus = capability.hdrEnabled
            ? "正在设置 HDR 环境…"
            : "正在设置 SDR 环境…"

        appendApplyDiagnostic(
            "TRANSACTION_START",
            "source=\(source) displayID=\(display.id) hardwareKey=\(display.hardwareKey) modeID=\(mode.ioDisplayModeID) desired=\(linkTestTargetText(capability)) preSystemHDR=\(linkTestHDRText(verifiedLinkOriginalHDR)) preActualLink=\(linkTestSemanticText(state.slsReportedDescription))"
        )
        guard let active = state.slsReportedDescription, let context = linkContext(for: display.id) else { return }
        let desiredCapability = finalExpectedCapability ?? capability
        plannerSource = source == "STABLE_APPLY" ? "STABLE_APPLY" :
            (source == "USER_CONFIRMED_ALTERNATIVE" ? source : "MANUAL")
        plannerDeadline = Date().addingTimeInterval(60)
        plannerPathContext = nil
        plannerActions = []
        plannerExecuted = []
        plannerVisits = []
        plannerSLSCount = 0
        plannerHDRCount = 0
        appendApplyDiagnostic("PLANNER_START", "desired=\(linkTestTargetText(desiredCapability)) startActual=\(linkTestSemanticText(active))")
        activeLinkTransaction = LinkControlTransaction(token: token, displayID: display.id,
            modeID: mode.ioDisplayModeID, intent: .capability(desiredCapability), orderedCandidates: [],
            attempted: [], expected: active, stableObservation: nil, stableReadCount: 0, pollCount: 0,
            summary: pendingChangeSummary, joiningTransaction: true, purpose: .userChange,
            writeAccepted: false, writeStartedAt: Date(), stableStartedAt: nil,
            observationStartedAt: nil, sawTarget: false, finalExpectedCapability: desiredCapability,
            allowsPostSLSEnvironmentDrift: true, context: context, usesEvidencePlanner: true)
        verifiedLinkApplyStatus = "正在确认操作前的稳定链路…"
        pollLinkTransaction(token: token)
    }

    private func pollVerifiedLinkHDREnvironment(
        _ capability: DisplayLinkCapability,
        displayID: CGDirectDisplayID,
        modeID: Int32,
        token: UUID,
        startedAt: Date,
        stableObservation: DisplayLinkDescription?,
        stableStartedAt: Date?,
        finalExpectedCapability: DisplayLinkCapability?
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + CapabilityTestTiming.readbackInterval) { [weak self] in
            guard let self,
                  self.verifiedLinkApplyToken == token,
                  self.linkAttemptToken == token else { return }

            guard self.isCurrentLinkContext(self.previousOutputContext) else {
                self.failVerifiedLinkApply(
                    capability,
                    displayID: displayID,
                    actual: nil,
                    reason: "目标显示器已断开。"
                )
                return
            }

            self.refresh()
            let now = Date()
            let elapsed = now.timeIntervalSince(startedAt)
            let hdr = CoreDisplayHDRController.shared.isEnabled(displayID: displayID)
            let active = DisplayOutputController.shared.state(
                displayID: displayID,
                modeID: modeID
            )?.slsReportedDescription

            let nextObservation: DisplayLinkDescription?
            let nextStableStartedAt: Date?
            if hdr == capability.hdrEnabled,
               let active,
               active.isHDR == capability.hdrEnabled {
                if active == stableObservation {
                    nextObservation = active
                    nextStableStartedAt = stableStartedAt ?? now
                } else {
                    nextObservation = active
                    nextStableStartedAt = now
                }
            } else {
                nextObservation = nil
                nextStableStartedAt = nil
            }

            let stableDuration = nextStableStartedAt.map { now.timeIntervalSince($0) } ?? 0
            if stableDuration >= CapabilityTestTiming.minimumStableDuration {
                self.appendApplyDiagnostic(
                    "ENV_READBACK",
                    "result=stable systemHDR=\(self.linkTestHDRText(hdr)) actualLink=\(self.linkTestSemanticText(active))"
                )
                self.verifiedLinkApplyStatus = "正在切换显示链路…"
                self.beginLinkControl(
                    .capability(capability),
                    targetDisplayID: displayID,
                    joiningTransaction: true,
                    summaryOverride: capability.hdrEnabled
                        ? "套用已验证 HDR 链路"
                        : "套用已验证 SDR 链路",
                    allowEquivalentModeFallback: false,
                    finalExpectedCapability: finalExpectedCapability,
                    allowsPostSLSEnvironmentDrift: finalExpectedCapability != nil
                )
                return
            }

            if elapsed >= CapabilityTestTiming.maximumCandidateTimeout {
                self.appendApplyDiagnostic(
                    "ENV_READBACK",
                    "result=timeout systemHDR=\(self.linkTestHDRText(hdr)) actualLink=\(self.linkTestSemanticText(active))"
                )
                self.failVerifiedLinkApply(
                    capability,
                    displayID: displayID,
                    actual: active,
                    reason: "目标 HDR/SDR 环境未能稳定建立。"
                )
            } else {
                self.verifiedLinkApplyStatus = hdr == capability.hdrEnabled
                    ? "正在等待显示器重新协商…"
                    : (capability.hdrEnabled ? "正在设置 HDR 环境…" : "正在设置 SDR 环境…")
                self.pollVerifiedLinkHDREnvironment(
                    capability,
                    displayID: displayID,
                    modeID: modeID,
                    token: token,
                    startedAt: startedAt,
                    stableObservation: nextObservation,
                    stableStartedAt: nextStableStartedAt,
                            finalExpectedCapability: finalExpectedCapability
                )
            }
        }
    }

    private func failVerifiedLinkApply(
        _ capability: DisplayLinkCapability,
        displayID: CGDirectDisplayID,
        actual: DisplayLinkDescription?,
        reason: String
    ) {
        let systemHDR = CoreDisplayHDRController.shared.isEnabled(displayID: displayID)
        appendApplyDiagnostic(
            "FINAL_RESULT",
            "result=failed target=\(linkTestTargetText(capability)) actual=\(linkTestSemanticText(actual)) reason=\(reason)"
        )
        verifiedLinkApplyToken = UUID()
        verifiedLinkApplyStatus = ""
        restorePendingModeIfNeeded()
        showLinkFailure(desired: failureDesiredCapability ?? capability, actual: actual, systemHDR: systemHDR, reason: reason)
    }

    private var standaloneHDRToken = UUID()

    func setHDREnabled(_ enabled: Bool) {
        guard canBeginDisplayOperation(), linkVerificationComplete, !pendingModeConfirmation,
              activeLinkTransaction == nil, !capabilityTestStage.isRunning,
              verifiedLinkApplyStatus.isEmpty, let display = selectedDisplay,
              !display.isBuiltin, let context = linkContext(for: display.id) else { return }
        standaloneHDRToken = UUID()
        let token = standaloneHDRToken
        linkAttemptToken = UUID()
        lastError = nil
        linkAlternative = nil
        alternativeReady = false
        appendApplyDiagnostic("UI_USER_INTENT", "field=SYSTEM_HDR target=\(enabled) preserveEncoding=false preserveBitDepth=false rollback=false")
        if CoreDisplayHDRController.shared.isEnabled(displayID: display.id) == enabled {
            refresh()
            return
        }
        applyingFeature = .hdr
        linkVerificationComplete = false
        guard CoreDisplayHDRController.shared.setEnabled(enabled, displayID: display.id) else {
            applyingFeature = nil
            linkVerificationComplete = true
            lastError = "macOS 未接受 HDR 开关请求；未执行恢复。"
            return
        }
        verifySystemHDR(enabled, context: context, token: token, attempt: 0)
    }

    private func verifySystemHDR(_ enabled: Bool, context: LinkOperationContext, token: UUID, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self, self.standaloneHDRToken == token else { return }
            self.refresh()
            guard self.isCurrentLinkContext(context) else {
                self.applyingFeature = nil
                self.linkVerificationComplete = true
                self.lastError = "显示器上下文已改变，HDR 开关结果未确认；未执行恢复。"
                return
            }
            let actual = CoreDisplayHDRController.shared.isEnabled(displayID: context.displayID)
            if actual == enabled || attempt >= 7 {
                self.applyingFeature = nil
                self.linkVerificationComplete = true
                self.appendApplyDiagnostic("SYSTEM_HDR_RESULT", "requested=\(enabled) actual=\(self.linkTestHDRText(actual)) rollback=false")
                if actual != enabled { self.lastError = "系统 HDR 开关未确认采用请求；未执行恢复。" }
            } else {
                self.verifySystemHDR(enabled, context: context, token: token, attempt: attempt + 1)
            }
        }
    }

    func setVRREnabled(_ enabled: Bool) {
        guard canBeginDisplayOperation(), linkVerificationComplete, !pendingModeConfirmation,
              !capabilityTestStage.isRunning, activeLinkTransaction == nil,
              verifiedLinkApplyStatus.isEmpty else { return }
        let modes = allModes(for: selectedDisplayID)
        guard let current = currentTiming(displayID: selectedDisplayID, modes: modes) else {
            lastError = "无法读取当前显示模式。"; return
        }
        if current.vrrState == enabled { return }
        // The toggle preserves the exact nominal timing and render dimensions.
        // Multiple identities require an explicit selection in the timing menu.
        let candidates = modes.filter {
            $0.isHiDPI == current.isHiDPI &&
            $0.width == current.width && $0.height == current.height &&
            $0.pixelWidth == current.pixelWidth && $0.pixelHeight == current.pixelHeight &&
            $0.outputWidth == current.outputWidth && $0.outputHeight == current.outputHeight &&
            $0.refreshRate == current.refreshRate && $0.vrrState == enabled
        }
        guard candidates.count == 1, let option = candidates.first else {
            lastError = candidates.isEmpty
                ? "当前时序没有唯一对应的固定／可变模式；请在刷新率菜单明确选择。"
                : "存在多个固定／可变时序，请在刷新率菜单明确选择。"
            return
        }
        beginFeatureAttempt(.vrr)
        apply(option)
        if pendingTimingChange == nil { finishFeatureAttempt(.vrr) }
    }

    func setDSCEnabled(_ enabled: Bool) {
        guard canBeginDisplayOperation() else { return }
        beginFeatureAttempt(.dsc)
        guard let display = selectedDisplay,
              let current = display.modes.first(where: { $0.selectionKey == display.currentModeKey }),
              let link = displayPortLink(for: display.id),
              let activeLink = DisplayOutputController.shared.state(displayID: display.id, modeID: current.id)?.slsReportedDescription,
              [UInt32(8), 10, 12].contains(activeLink.bitDepth),
              let componentMultiplier = activeLink.bandwidthComponentMultiplier else {
            lastError = "当前链路带宽或像素采样格式未知，不能安全调整 DSC。"
            finishFeatureAttempt(.dsc)
            return
        }
        let bitDepth = Int(activeLink.bitDepth)
        let compatible = display.modes.filter {
            $0.isHiDPI == current.isHiDPI &&
            $0.width == current.width && $0.height == current.height &&
            $0.outputWidth == current.outputWidth && $0.outputHeight == current.outputHeight &&
            modeRequiresDSC($0, bitDepth: bitDepth, link: link, componentMultiplier: componentMultiplier) == enabled
        }
        guard let target = compatible.max(by: { $0.refreshRate < $1.refreshRate }) else {
            lastError = enabled
                ? "当前分辨率没有可用于协商 DSC 的高带宽模式。"
                : "当前分辨率没有可在未压缩带宽内运行的模式。"
            finishFeatureAttempt(.dsc)
            return
        }
        if target.selectionKey == current.selectionKey {
            retrainCurrentLink()
        } else {
            apply(target)
        }
    }

    func confirmPendingMode() {
        guard pendingModeConfirmation, displayRecoveryToken == nil, !capabilityTestStage.isRunning else { return }
        if pendingTimingChange != nil && !linkVerificationComplete {
            lastError = "系统尚未确认时序和完整连接状态，请等待验证或恢复。"; return
        }
        pendingTimingChange = nil
        manualPreparationToken = UUID()
        let targetDisplay = pendingTargetDisplayID.flatMap { displaySnapshot(for: $0) }
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        activeLinkTransaction = nil
        linkAttemptToken = UUID()
        modeAttemptToken = UUID()
        verifiedLinkOriginalHDR = nil
        previousMode = nil
        previousOutputMode = nil
        pendingModeConfirmation = false
        linkVerificationComplete = true
        confirmationSeconds = 0
        pendingVerificationText = "已确认"
        if var record = pendingCapabilityRecord, let display = targetDisplay {
            record.evidence = .userConfirmed
            record.lastChecked = Date()
            record.failureReason = nil
            Preferences.shared.recordLinkMode(
                record,
                for: display.hardwareKey,
                interfaceName: interfaceName(for: display)
            )
        }
        pendingCapabilityRecord = nil
        if verifiedLinkApplyStartedAt != nil {
            appendApplyDiagnostic("FINAL_RESULT", "result=user-confirmed")
            verifiedLinkApplyStartedAt = nil
        }
        if automaticCorrectionInProgress {
            automaticCorrectionInProgress = false
            autoCorrectionStage = .completed
            autoCorrectionDetail = "系统复读结果与目标一致，已保留新的颜色链路。"
        }
        refresh()
    }

    func restorePendingModeIfNeeded() {
        guard displayRecoveryToken == nil else { return }
        if let timing = pendingTimingChange { restoreTiming(timing); return }
        manualPreparationToken = UUID()
        let restoreContext = previousOutputContext
        let targetDisplay = pendingTargetDisplayID.flatMap { displaySnapshot(for: $0) }
        let originalHDR = verifiedLinkOriginalHDR
        let originalHDRDisplayID = previousOutputMode?.displayID
        let originalDescription = previousOutputMode?.description
        let originalModeID = previousOutputMode?.modeID
        let wasVerifiedApply = verifiedLinkApplyStartedAt != nil
        if wasVerifiedApply {
            appendApplyDiagnostic(
                "RESTORE_START",
                "displayID=\(originalHDRDisplayID.map(String.init) ?? "unavailable") targetHDR=\(linkTestHDRText(originalHDR)) targetLink=\(linkTestSemanticText(originalDescription))"
            )
        }
        linkAttemptToken = UUID()
        modeAttemptToken = UUID()
        verifiedLinkApplyToken = UUID()
        let restoreToken = linkAttemptToken
        displayRecoveryToken = restoreToken
        linkVerificationComplete = false
        verifiedLinkApplyStatus = ""
        verifiedLinkOriginalHDR = nil
        activeLinkTransaction = nil
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        var restoreAttempted = false
        var displayModeRestoreAccepted = true
        var linkRestoreAccepted = true
        var hdrRestoreAccepted = originalHDR == nil
        if let originalHDR, let originalHDRDisplayID, isCurrentLinkContext(restoreContext) {
            restoreAttempted = true
            hdrRestoreAccepted = CoreDisplayHDRController.shared.setEnabled(originalHDR, displayID: originalHDRDisplayID)
        }
        if let previousMode {
            restoreAttempted = true
            displayModeRestoreAccepted = CGDisplaySetDisplayMode(
                previousMode.displayID,
                previousMode.mode,
                nil
            ) == .success
        }
        if let previousOutputMode {
            restoreAttempted = true
            if isCurrentLinkContext(restoreContext),
               let description = previousOutputMode.description,
               let state = DisplayOutputController.shared.state(displayID: previousOutputMode.displayID, modeID: previousOutputMode.modeID),
               let index = state.descriptions.firstIndex(of: description) {
                linkRestoreAccepted = DisplayOutputController.shared.setOutputMode(
                    displayID: previousOutputMode.displayID, modeID: previousOutputMode.modeID,
                    index: UInt32(index)) == 0
            } else {
                linkRestoreAccepted = false
            }
        }
        let restoreCallsAccepted = restoreAttempted &&
            displayModeRestoreAccepted &&
            linkRestoreAccepted
        updateRestoreExplanation(restoreCallsAccepted && hdrRestoreAccepted
            ? "已请求恢复原配置。" : "无法确认原配置恢复状态。")
        previousMode = nil
        previousOutputMode = nil
        pendingModeConfirmation = false
        confirmationSeconds = 0
        pendingVerificationText = restoreCallsAccepted
            ? "恢复请求已返回成功，但系统状态尚未复读确认。"
            : "恢复请求未完全成功，当前显示状态未确认。"
        if var record = pendingCapabilityRecord, let display = targetDisplay {
            record.evidence = .failed
            record.lastChecked = Date()
            record.failureReason = restoreCallsAccepted
                ? "恢复调用已返回成功，但没有可靠的系统复读确认。"
                : "恢复调用未完全成功，当前状态未确认。"
            Preferences.shared.recordLinkMode(
                record,
                for: display.hardwareKey,
                interfaceName: interfaceName(for: display)
            )
        }
        pendingCapabilityRecord = nil
        if automaticCorrectionInProgress {
            automaticCorrectionInProgress = false
            autoCorrectionStage = .failed
            autoCorrectionDetail = restoreCallsAccepted
                ? "未在倒计时内确认；恢复调用已返回成功，但系统状态尚未复读确认。"
                : "未在倒计时内确认；恢复请求未完全成功，当前状态未确认。"
        }
        refresh()
        if wasVerifiedApply,
           let restoreDisplayID = originalHDRDisplayID,
           let restoreModeID = originalModeID {
            pollAuthoritativeSnapshotAfterRestore(
                displayID: restoreDisplayID,
                modeID: restoreModeID,
                expectedHDR: originalHDR,
                expectedLink: originalDescription,
                token: restoreToken,
                modeToken: modeAttemptToken,
                context: restoreContext,
                stableCount: 0,
                attempt: 0
            )
        }
        if !(wasVerifiedApply && originalHDRDisplayID != nil && originalModeID != nil) {
            completeDisplayRecovery(token: restoreToken)
        }
        lastError = AppLocalization.string(restoreExplanation)
    }

    private func pollAuthoritativeSnapshotAfterRestore(
        displayID: CGDirectDisplayID,
        modeID: Int32,
        expectedHDR: Bool?,
        expectedLink: DisplayLinkDescription?,
        token: UUID,
        modeToken: UUID,
        context: LinkOperationContext?,
        stableCount: Int,
        attempt: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            guard let self, self.displayRecoveryToken == token, self.linkAttemptToken == token,
                  self.modeAttemptToken == modeToken else { return }
            self.refresh()
            guard self.isCurrentLinkContext(context), self.activeLinkTransaction == nil,
                  !self.capabilityTestStage.isRunning else {
                self.updateRestoreExplanation("恢复上下文已改变，结果未确认；未继续显示写入。")
                self.verifiedLinkApplyStartedAt = nil
                self.completeDisplayRecovery(token: token)
                return
            }
            let systemHDR = CoreDisplayHDRController.shared.isEnabled(displayID: displayID)
            let actual = DisplayOutputController.shared.state(displayID: displayID, modeID: modeID)?.slsReportedDescription
            let matchesHDR = expectedHDR != nil && systemHDR == expectedHDR
            let matchesLink = expectedLink.map { expected in
                actual?.matches(expected) == true
            } ?? false
            let nextStable = matchesHDR && matchesLink ? stableCount + 1 : 0
            if nextStable >= 3 || attempt >= 8 {
                self.appendApplyDiagnostic(
                    "RESTORE_RESULT",
                    "confirmed=\(nextStable >= 3) CONTROL_VERIFICATION=\(nextStable >= 3 ? "PASS" : "UNCONFIRMED") systemHDR=\(self.linkTestHDRText(systemHDR)) SLS_REPORTED_CURRENT=\(self.linkTestSemanticText(actual))"
                )
                self.updateRestoreExplanation(nextStable >= 3 && expectedHDR != nil && expectedLink != nil
                    ? "系统回读确认原配置已恢复。" : "无法确认原配置恢复状态。")
                self.verifiedLinkApplyStartedAt = nil
                self.completeDisplayRecovery(token: token)
                self.refresh()
            } else {
                self.pollAuthoritativeSnapshotAfterRestore(
                    displayID: displayID,
                    modeID: modeID,
                    expectedHDR: expectedHDR,
                    expectedLink: expectedLink,
                    token: token,
                    modeToken: modeToken,
                    context: context,
                    stableCount: nextStable,
                    attempt: attempt + 1
                )
            }
        }
    }

    func startCapabilityTest() {
        guard !capabilityTestStage.isRunning else { return }
        guard canBeginDisplayOperation(), !pendingModeConfirmation else {
            if pendingModeConfirmation { lastError = "请先完成当前显示设置确认，再开始自动测试。" }
            return
        }
        resetLinkTestDiagnostics()
        capabilityTestStage = .preparing
        capabilityTestDetail = "正在读取当前 timing 下 macOS 枚举的链路组合。"
        guard let display = selectedDisplay else {
            capabilityTestStage = .failedSafely
            capabilityTestDetail = "无法开始：没有选中的显示器。"
            appendLinkTestDiagnostic("PRECHECK", "gate=selected-display edidPresent=false rawDescriptions=0 normalizedStates=0 executableProbes=0 observedStable=0 applyConfirmed=0 eligibility=UNAVAILABLE reason=no-selected-display")
            return
        }
        let eligibility = capabilityTestEligibility(for: display)
        guard let mode = CGDisplayCopyDisplayMode(display.id) else {
            capabilityTestStage = .failedSafely
            capabilityTestDetail = "无法开始：无法读取当前输出 timing。"
            appendLinkTestDiagnostic("PRECHECK", "displayID=\(display.id) gate=actual-timing \(eligibility.diagnosticSummary)")
            return
        }
        guard let state = DisplayOutputController.shared.state(
            displayID: display.id,
            modeID: mode.ioDisplayModeID
        ) else {
            capabilityTestStage = .failedSafely
            capabilityTestDetail = "无法开始：macOS 没有提供当前 timing 的链路描述。"
            appendLinkTestDiagnostic("PRECHECK", "displayID=\(display.id) modeID=\(mode.ioDisplayModeID) interface=\(interfaceName(for: display)) gate=raw-sls-state \(eligibility.diagnosticSummary)")
            return
        }
        guard let original = state.slsReportedDescription else {
            capabilityTestStage = .failedSafely
            capabilityTestDetail = "无法开始：未取得系统报告的测试前连接状态。"
            appendLinkTestDiagnostic("PRECHECK", "displayID=\(display.id) modeID=\(mode.ioDisplayModeID) interface=\(interfaceName(for: display)) gate=active-description activeIndex=\(state.activeIndex) \(eligibility.diagnosticSummary)")
            return
        }

        let allCapabilities = normalizedCapabilityProbes(from: state.descriptions)
        appendLinkTestDiagnostic(
            "PRECHECK",
            "displayID=\(display.id) timing=\(display.resolution)@\(display.refreshRate.text) interface=\(interfaceName(for: display)) modeID=\(mode.ioDisplayModeID) activeDescription=\(linkTestSemanticText(original)) \(eligibility.diagnosticSummary)"
        )
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        appendLinkTestDiagnostic(
            "TEST_SESSION_START",
            "displayID=\(display.id) hardwareKey=\(display.hardwareKey) modeID=\(mode.ioDisplayModeID) timing=\(display.resolution) refresh=\(display.refreshRate.text) initialSystemHDR=\(linkTestHDRText(CoreDisplayHDRController.shared.isEnabled(displayID: display.id))) initialActual=\(linkTestSemanticText(original)) slsMax=6 environmentMax=2 timeoutSeconds=120 noNewThreshold=3 appVersion=\(appVersion) build=\(appBuild)"
        )

        capabilityTestProgress = 0
        capabilityTestTotal = 100
        capabilityTestSuccessCount = 0
        capabilityTestReconfirmedCount = 0
        capabilityTestFailureCount = 0
        capabilityTestUnconfirmedCount = 0
        capabilityTestAttemptResults = []
        capabilityTestSessionStableModes = []
        capabilityTestSessionReplayProbes = [:]
        lastTestStableActual = nil
        testTransitionContext = nil
        testExecutedActions = []
        capabilityTestCurrent = ""
        capabilityTestEnvironment = original.isHDR ? "HDR" : "SDR"
        capabilityTestDisplayID = display.id
        Preferences.shared.clearAutomaticCapabilityResults(
            for: display.hardwareKey,
            interfaceName: interfaceName(for: display),
            engineGeneration: CapabilityTestTiming.engineGeneration
        )
        updateCapabilityTestReadback(
            hdr: CoreDisplayHDRController.shared.isEnabled(displayID: display.id),
            link: original
        )
        guard eligibility.isEnabled else {
            appendLinkTestStop("UNSUPPORTED")
            capabilityTestStage = .idle
            capabilityTestDetail = eligibility.reason
            capabilityTestEnvironment = "—"
            capabilityTestReadback = "HDR：—\n链路：—"
            capabilityTestDisplayID = nil
            return
        }
        capabilityRestoreContext = linkContext(for: display.id)
        capabilityTestSession = CapabilityTestSession(
            token: UUID(),
            displayID: display.id,
            hardwareKey: display.hardwareKey,
            interfaceName: interfaceName(for: display),
            modeID: mode.ioDisplayModeID,
            originalIndex: state.activeIndex,
            originalDescription: original,
            originalSystemHDR: CoreDisplayHDRController.shared.isEnabled(displayID: display.id),
            candidates: allCapabilities,
            nextIndex: 0,
            consecutiveWriteFailures: 0,
            completionStage: .completed,
            successfulSemanticStates: [],
            successCount: 0,
            reconfirmedCount: 0,
            failureCount: 0,
            unconfirmedCount: 0
        )
        beginCapabilityMatrixDiscovery()
    }

    private func beginCapabilityMatrixDiscovery() {
        guard let session = capabilityTestSession else { return }
        testBudget = LinkTestBudget(deadline: Date().addingTimeInterval(120))
        testProbeVisits = []
        testEnvironmentVisits = []
        testResultLoops = []
        testLoopDetected = false
        testBaselinePending = true
        testScheduledProbe = nil
        let candidate = capabilityTestCapability(from: session.originalDescription)
        var transaction = capabilityTestTransaction(candidate: candidate, session: session,
            active: session.originalDescription, didPerformHDRTransition: false)
        transaction.writeStartedAt = Date()
        activeLinkTransaction = transaction
        capabilityTestStage = .waitingForReadback
        capabilityTestDetail = "正在确认测试前的稳定链路…"
        linkVerificationComplete = false
        pollCapabilityTestTransaction(token: transaction.token)
    }

    private func augmentCapabilityTestMatrix(with descriptions: [DisplayLinkDescription]) {
        guard var session = capabilityTestSession else { return }
        let discovered = normalizedCapabilityProbes(from: descriptions)
        let existing = Set(session.candidates)
        session.candidates.append(contentsOf: Set(discovered).subtracting(existing).sorted(by: capabilityTestSort))
        capabilityTestSession = session
        updateTestProgress()
    }

    func stopCapabilityTest() {
        guard capabilityTestStage.isRunning, capabilityTestStage != .restoring else { return }
        appendLinkTestStop("CANCELLED")
        linkAttemptToken = UUID()
        activeLinkTransaction = nil
        beginCapabilityTestRestore(completion: .cancelled)
    }

    func restoreCapabilityTestForTerminationIfNeeded() {
        guard let session = capabilityTestSession,
              isCurrentLinkContext(capabilityRestoreContext),
              let display = displaySnapshot(for: session.displayID),
              display.hardwareKey == session.hardwareKey,
              let mode = CGDisplayCopyDisplayMode(session.displayID),
              mode.ioDisplayModeID == session.modeID,
              DisplayOutputController.shared.state(
            displayID: session.displayID,
            modeID: session.modeID
              ) != nil else {
            capabilityTestSession = nil
            return
        }
        if let originalHDR = session.originalSystemHDR,
           CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID) != originalHDR {
            _ = CoreDisplayHDRController.shared.setEnabled(originalHDR, displayID: session.displayID)
        }
        guard let freshState = DisplayOutputController.shared.state(displayID: session.displayID, modeID: session.modeID) else { return }
        if freshState.slsReportedDescription?.matches(session.originalDescription) != true {
            guard let index = freshState.descriptions.firstIndex(of: session.originalDescription).map(UInt32.init) else {
                capabilityTestSession = nil
                return
            }
            _ = DisplayOutputController.shared.setOutputMode(
                displayID: session.displayID,
                modeID: session.modeID,
                index: index
            )
        }
        capabilityTestSession = nil
    }

    private func runNextCapabilityTestCandidate() {
        guard var session = capabilityTestSession, capabilityTestStage != .restoring else { return }
        linkTestSchedulerIteration += 1
        guard isCurrentLinkContext(capabilityRestoreContext),
              let state = DisplayOutputController.shared.state(displayID: session.displayID, modeID: session.modeID),
              let actual = state.slsReportedDescription,
              let hdr = CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID),
              let context = transitionContext(displayID: session.displayID, actual: actual, hdr: hdr,
                stable: actual == lastTestStableActual) else {
            appendLinkTestStop("INVALID_CURRENT_SESSION")
            beginCapabilityTestRestore(completion: .failedSafely)
            return
        }
        guard testMayContinue(), let budget = testBudget else {
            var active: [String] = []
            if let budget = testBudget {
                if Date() >= budget.deadline { active.append("TIMEOUT") }
                if budget.noNewResults >= 3 { active.append("NO_NEW_3") }
                if budget.slsActions >= 6 { active.append("SLS_LIMIT") }
                if budget.environmentChanges >= 2 { active.append("ENV_LIMIT") }
            }
            if testLoopDetected { active.append("LOOP") }
            appendLinkTestBudgetState("stop-check")
            appendLinkTestStop(active.first ?? "INVALID_SESSION", active: active)
            beginCapabilityTestRestore(completion: .completed)
            return
        }
        let envelope = EDIDStore.shared.capabilityEnvelope.flatMap { $0.hardwareKey == session.hardwareKey ? $0 : nil }
        let declaredDepths = Set(envelope?.declaredBitDepths ?? [])
        let ranked = LinkTestProbeRanker.ranked(state.descriptions, context: context, history: transitionHistory,
            seen: budget.seen, declaredDepths: declaredDepths)
        appendLinkTestPoolDiagnostics(state: state, context: context, hdr: hdr, budget: budget,
            declaredDepths: declaredDepths, ranked: ranked)
        appendLinkTestBudgetState("before-decision", ranked: ranked)
        let sameEnvironment = ranked.first {
            $0.isHDR == hdr && !testProbeVisits.contains(TestProbeVisit(probe: $0, environment: hdr))
        }
        let selected: DisplayLinkDescription
        if budget.slsActions < 6, let probe = sameEnvironment {
            selected = probe
            testScheduledProbe = probe
        } else if budget.environmentChanges < 2, !testEnvironmentVisits.contains(!hdr),
                  let probe = ranked.first(where: { $0.isHDR != hdr }) {
            selected = probe
            testScheduledProbe = nil // This attempt executes only the environment action.
        } else {
            let reason = ranked.isEmpty ? "EMPTY_POOL" :
                (budget.slsActions >= 6 ? "SLS_LIMIT" :
                    (budget.environmentChanges >= 2 ? "ENV_LIMIT" : "COMPLETED"))
            appendLinkTestStop(reason)
            beginCapabilityTestRestore(completion: .completed)
            return
        }
        let candidate = capabilityTestCapability(from: selected)
        testTransitionContext = context
        testExecutedActions = []
        capabilityTestCurrent = "\(candidate.encodingText) · \(candidate.bitDepth)-bit · \(candidate.hdrEnabled ? "HDR" : "SDR")"
        capabilityTestStage = .testing
        capabilityTestDetail = "正在执行下一项有信息价值的链路尝试。"
        session.nextIndex += 1
        capabilityTestSession = session
        updateTestProgress()
        let actionType = testScheduledProbe == nil ? "ENVIRONMENT_ACTION" : "SLS_PROBE"
        let remainingSeconds = String(format: "%.1f", max(0, budget.deadline.timeIntervalSinceNow))
        appendLinkTestDiagnostic("PROBE_SELECTED", "iteration=\(linkTestSchedulerIteration) actionIndex=\(session.nextIndex) actionType=\(actionType) \(linkTestCandidateFields(selected)) currentHDR=\(hdr) targetHDR=\(selected.isHDR) environmentSwitchRequired=\(selected.isHDR != hdr) slsBefore=\(budget.slsActions) environmentBefore=\(budget.environmentChanges) noNewBefore=\(budget.noNewResults) remainingSeconds=\(remainingSeconds)")
        appendLinkTestDiagnostic("SCHEDULER_NEXT", "probe=\(selected) environmentChange=\(testScheduledProbe == nil)")
        prepareCapabilityTestCandidate(candidate, sessionToken: session.token)
    }

    private func prepareCapabilityTestCandidate(
        _ candidate: DisplayLinkCapability,
        sessionToken: UUID
    ) {
        guard let session = capabilityTestSession, session.token == sessionToken else { return }
        let currentHDR = CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID)
        guard let currentHDR else {
            finishCapabilityTestEnvironmentUnconfirmed(
                candidate,
                session: session,
                reason: "无法读取 macOS 当前 HDR 开关状态；未进入链路测试。"
            )
            return
        }
        guard testMayContinue() else {
            beginCapabilityTestRestore(completion: .completed)
            return
        }
        if currentHDR == candidate.hdrEnabled {
            // No-op environment request: do not write, count or record an HDR action.
            appendLinkTestDiagnostic("PROBE_SKIPPED", "iteration=\(linkTestSchedulerIteration) actionType=ENVIRONMENT_ACTION targetHDR=\(candidate.hdrEnabled) reason=environment-state-already-matches; continuing-to-SLS-probe")
            beginCapabilityTestEnvironmentObservation(candidate, session: session, didPerformHDRTransition: false)
            return
        }
        guard (testBudget?.environmentChanges ?? 2) < 2 else {
            beginCapabilityTestRestore(completion: .completed)
            return
        }
        testBudget?.environmentChanges += 1
        testEnvironmentVisits.insert(candidate.hdrEnabled)
        updateTestProgress()
        let didPerformHDRTransition = currentHDR != candidate.hdrEnabled
        appendLinkTestDiagnostic(
            "HDR_PREPARE",
            "requestedHDRState=\(candidate.hdrEnabled) didPerformHDRTransition=\(didPerformHDRTransition) currentHDR=\(currentHDR) action=explicit-system-hdr-request"
        )
        capabilityTestStage = .testing
        capabilityTestDetail = candidate.hdrEnabled
            ? "正在临时开启 HDR，并等待系统状态与链路枚举稳定。"
            : "正在临时关闭 HDR，并等待系统状态与链路枚举稳定。"
        let accepted = CoreDisplayHDRController.shared.setEnabled(candidate.hdrEnabled, displayID: session.displayID)
        testExecutedActions.append(LinkExecutedAction(action: .hdr(candidate.hdrEnabled), accepted: accepted))
        appendLinkTestDiagnostic("ACTION_EXECUTED", "action=HDR_\(candidate.hdrEnabled ? "ON" : "OFF") accepted=\(accepted)")
        guard accepted else {
            appendLinkTestDiagnostic("HDR_PREPARE", "transitionResult=rejected")
            finishCapabilityTestEnvironmentUnconfirmed(
                candidate,
                session: session,
                reason: "macOS 未接受 HDR 环境切换请求；未进入链路测试。"
            )
            return
        }
        appendLinkTestDiagnostic("HDR_PREPARE", "transitionResult=accepted")
        pollCapabilityTestHDR(
            candidate,
            sessionToken: sessionToken,
            didPerformHDRTransition: didPerformHDRTransition,
            attempt: 0
        )
    }

    private func pollCapabilityTestHDR(
        _ candidate: DisplayLinkCapability,
        sessionToken: UUID,
        didPerformHDRTransition: Bool,
        attempt: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            guard let self,
                  let session = self.capabilityTestSession,
                  session.token == sessionToken,
                  self.capabilityTestStage != .restoring else { return }
            guard self.testMayContinue(observing: true) else {
                self.beginCapabilityTestRestore(completion: self.isCurrentLinkContext(self.capabilityRestoreContext) ? .completed : .failedSafely)
                return
            }
            self.refresh()
            let hdrReadback = CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID)
            let activeLink = DisplayOutputController.shared.state(
                displayID: session.displayID,
                modeID: session.modeID
            )?.slsReportedDescription
            self.updateCapabilityTestReadback(hdr: hdrReadback, link: activeLink)
            if hdrReadback == candidate.hdrEnabled {
                let established = activeLink.map {
                    $0.pixelEncoding == candidate.rawPixelEncoding &&
                    $0.bitDepth == UInt32(candidate.bitDepth) &&
                    $0.isHDR == candidate.hdrEnabled &&
                    (!$0.isRGB || $0.isFullRange)
                } == true
                self.appendLinkTestDiagnostic(
                    "HDR_CONFIRMED",
                    "requestedHDRState=\(candidate.hdrEnabled) hdrReadback=\(self.linkTestHDRText(hdrReadback)) activeLink=\(self.linkTestSemanticText(activeLink)) diagnostic=\(established ? "TARGET_ESTABLISHED_BY_HDR_TRANSITION" : "none")"
                )
                self.beginCapabilityTestEnvironmentObservation(
                    candidate,
                    session: session,
                    didPerformHDRTransition: didPerformHDRTransition
                )
            } else if attempt < 4 {
                self.appendLinkTestDiagnostic(
                    "HDR_READBACK",
                    "attempt=\(attempt + 1) requestedHDRState=\(candidate.hdrEnabled) hdrReadback=\(self.linkTestHDRText(hdrReadback)) activeLink=\(self.linkTestSemanticText(activeLink)) result=pending"
                )
                self.pollCapabilityTestHDR(
                    candidate,
                    sessionToken: sessionToken,
                    didPerformHDRTransition: didPerformHDRTransition,
                    attempt: attempt + 1
                )
            } else {
                self.appendLinkTestDiagnostic(
                    "HDR_READBACK",
                    "attempt=\(attempt + 1) requestedHDRState=\(candidate.hdrEnabled) hdrReadback=\(self.linkTestHDRText(hdrReadback)) activeLink=\(self.linkTestSemanticText(activeLink)) result=failed"
                )
                self.capabilityTestDetail = "HDR 状态未能稳定切换；正在恢复测试开始前的完整配置。"
                self.finishCapabilityTestEnvironmentUnconfirmed(
                    candidate,
                    session: session,
                    reason: "HDR 环境切换未取得目标状态复读；未进入链路测试。"
                )
            }
        }
    }

    private func finishCapabilityTestEnvironmentUnconfirmed(
        _ candidate: DisplayLinkCapability,
        session: CapabilityTestSession,
        reason: String
    ) {
        guard let display = displaySnapshot(for: session.displayID),
              display.hardwareKey == session.hardwareKey else {
            beginCapabilityTestRestore(completion: .failedSafely)
            return
        }
        let resulting = DisplayOutputController.shared.state(
            displayID: session.displayID,
            modeID: session.modeID
        )?.slsReportedDescription
        appendLinkTestDiagnostic(
            "FINAL",
            "classification=environmentUnconfirmed finalHDRState=\(linkTestHDRText(CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID))) finalLink=\(linkTestSemanticText(resulting)) reason=\(reason)"
        )
        recordTransition(context: testTransitionContext, actions: testExecutedActions, actual: resulting,
            hdr: CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID), stable: false,
            desired: DesiredLinkState(rawPixelEncoding: candidate.rawPixelEncoding, bitDepth: candidate.bitDepth, hdrEnabled: candidate.hdrEnabled, rawRange: candidate.rawRange, rawEOTF: candidate.rawEOTF),
            source: "LINK_TEST")
        recordTestInformation(actual: resulting, stable: false)
        lastTestStableActual = nil
        recordCapabilityTestResult(
            candidate,
            evidence: .environmentUnconfirmed,
            reason: reason,
            display: display,
            interfaceName: session.interfaceName,
            resulting: resulting
        )
        capabilityTestAttemptResults.append(CapabilityTestAttemptResult(
            index: capabilityTestAttemptResults.count + 1,
            passed: false,
            actualLink: resulting.map(linkDescriptionSummary),
            diagnosticReason: reason
        ))
        updateTestProgress()
        if var current = capabilityTestSession, current.token == session.token {
            current.unconfirmedCount += 1
            capabilityTestSession = current
            capabilityTestUnconfirmedCount = current.unconfirmedCount
        }
        capabilityTestDetail = "当前候选项的 HDR/SDR 环境无法确认，未执行链路选择。准备下一项…"
        let completedSessionToken = session.token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.capabilityTestSession?.token == completedSessionToken,
                  self.capabilityTestStage != .restoring else { return }
            self.runNextCapabilityTestCandidate()
        }
    }

    private func beginCapabilityTestEnvironmentObservation(
        _ candidate: DisplayLinkCapability,
        session: CapabilityTestSession,
        didPerformHDRTransition: Bool
    ) {
        capabilityTestStage = .waitingForReadback
        capabilityTestDetail = "HDR/SDR 环境已确认；正在等待显示器重新握手并读取稳定链路。"
        appendLinkTestDiagnostic(
            "WAIT_FOR_RENEGOTIATION",
            "target=\(linkTestTargetText(candidate)) didPerformHDRTransition=\(didPerformHDRTransition)"
        )
        pollCapabilityTestEnvironment(
            candidate,
            sessionToken: session.token,
            didPerformHDRTransition: didPerformHDRTransition,
            startedAt: Date(),
            stableObservation: nil,
            stableStartedAt: nil
        )
    }

    private func pollCapabilityTestEnvironment(
        _ candidate: DisplayLinkCapability,
        sessionToken: UUID,
        didPerformHDRTransition: Bool,
        startedAt: Date,
        stableObservation: DisplayLinkDescription?,
        stableStartedAt: Date?
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + CapabilityTestTiming.readbackInterval) { [weak self] in
            guard let self,
                  let session = self.capabilityTestSession,
                  session.token == sessionToken,
                  self.capabilityTestStage != .restoring else { return }
            self.refresh()
            guard self.testMayContinue(observing: true) else {
                self.beginCapabilityTestRestore(completion: self.isCurrentLinkContext(self.capabilityRestoreContext) ? .completed : .failedSafely)
                return
            }
            let now = Date()
            let elapsed = now.timeIntervalSince(startedAt)
            let hdr = CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID)
            let active = DisplayOutputController.shared.state(
                displayID: session.displayID,
                modeID: session.modeID
            )?.slsReportedDescription
            self.updateCapabilityTestReadback(hdr: hdr, link: active)

            guard hdr == candidate.hdrEnabled else {
                self.finishCapabilityTestEnvironmentUnconfirmed(
                    candidate,
                    session: session,
                    reason: "HDR/SDR 环境在进入链路测试前偏离目标；未调用 SLS。"
                )
                return
            }

            if elapsed < CapabilityTestTiming.negotiationGracePeriod {
                self.pollCapabilityTestEnvironment(
                    candidate,
                    sessionToken: sessionToken,
                    didPerformHDRTransition: didPerformHDRTransition,
                    startedAt: startedAt,
                    stableObservation: active,
                    stableStartedAt: nil
                )
                return
            }

            if let active, active.isHDR != candidate.hdrEnabled {
                if elapsed >= CapabilityTestTiming.maximumCandidateTimeout {
                    self.finishCapabilityTestEnvironmentUnconfirmed(
                        candidate,
                        session: session,
                        reason: "系统 HDR 开关已到达目标，但实际链路仍处于不同 HDR/SDR 环境；未调用 SLS。"
                    )
                } else {
                    self.capabilityTestDetail = "系统开关已确认，正在等待实际链路进入对应 HDR/SDR 环境。"
                    self.pollCapabilityTestEnvironment(
                        candidate,
                        sessionToken: sessionToken,
                        didPerformHDRTransition: didPerformHDRTransition,
                        startedAt: startedAt,
                        stableObservation: nil,
                        stableStartedAt: nil
                    )
                }
                return
            }

            let nextStableObservation: DisplayLinkDescription?
            let nextStableStartedAt: Date?
            if let active {
                if active == stableObservation {
                    nextStableObservation = active
                    nextStableStartedAt = stableStartedAt ?? now
                } else {
                    nextStableObservation = active
                    nextStableStartedAt = now
                }
            } else {
                nextStableObservation = nil
                nextStableStartedAt = nil
            }
            let stableDuration = nextStableStartedAt.map { now.timeIntervalSince($0) } ?? 0
            if let active,
               stableDuration >= CapabilityTestTiming.minimumStableDuration {
                self.appendLinkTestDiagnostic(
                    "ENVIRONMENT_STABLE",
                    "hdr=\(self.linkTestHDRText(hdr)) activeLink=\(self.linkTestSemanticText(active))"
                )
                self.handleStableCapabilityTestEnvironment(
                    candidate,
                    session: session,
                    active: active,
                    didPerformHDRTransition: didPerformHDRTransition
                )
                return
            }

            if elapsed >= CapabilityTestTiming.maximumCandidateTimeout {
                self.finishCapabilityTestEnvironmentUnconfirmed(
                    candidate,
                    session: session,
                    reason: "HDR/SDR 环境已确认，但未取得稳定活动链路；未调用 SLS。"
                )
            } else {
                self.pollCapabilityTestEnvironment(
                    candidate,
                    sessionToken: sessionToken,
                    didPerformHDRTransition: didPerformHDRTransition,
                    startedAt: startedAt,
                    stableObservation: nextStableObservation,
                    stableStartedAt: nextStableStartedAt
                )
            }
        }
    }

    private func handleStableCapabilityTestEnvironment(
        _ candidate: DisplayLinkCapability,
        session: CapabilityTestSession,
        active: DisplayLinkDescription,
        didPerformHDRTransition: Bool
    ) {
        if let descriptions = DisplayOutputController.shared.state(
            displayID: session.displayID,
            modeID: session.modeID
        )?.descriptions {
            augmentCapabilityTestMatrix(with: descriptions)
        }
        updateCapabilityTestReadback(
            hdr: CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID),
            link: active
        )
        if didPerformHDRTransition {
            appendLinkTestDiagnostic(
                "TARGET_ESTABLISHED",
                "diagnostic=ACTUAL_LINK_ESTABLISHED_BY_HDR_TRANSITION internalAttempt=\(linkTestTargetText(candidate)) activeLink=\(linkTestSemanticText(active))"
            )
            capabilityTestDetail = "环境切换已产生稳定链路；正在完成观察窗口。"
            var transaction = capabilityTestTransaction(
                candidate: candidate,
                session: session,
                active: active,
                didPerformHDRTransition: true
            )
            transaction.writeStartedAt = Date()
            transaction.sawTarget = true
            activeLinkTransaction = transaction
            linkVerificationComplete = false
            pollCapabilityTestTransaction(token: transaction.token)
            return
        }

        beginCapabilityTestLinkControl(
            candidate,
            session: session,
            didPerformHDRTransition: didPerformHDRTransition
        )
    }

    private func hasStrongCapabilityEvidence(
        _ capability: DisplayLinkCapability,
        hardwareKey: String,
        interfaceName: String
    ) -> Bool {
        Preferences.shared.capabilityProfile(
            for: hardwareKey,
            interfaceName: interfaceName
        ).modes.contains {
            ($0.evidence == .userConfirmed ||
             ($0.evidence == .systemReadback &&
              $0.engineGeneration == CapabilityTestTiming.engineGeneration)) &&
            $0.rawPixelEncoding == capability.rawPixelEncoding &&
            $0.bitDepth == capability.bitDepth &&
            $0.hdr == capability.hdrEnabled
        }
    }

    private func capabilityTestTransaction(
        candidate: DisplayLinkCapability,
        session: CapabilityTestSession,
        active: DisplayLinkDescription,
        didPerformHDRTransition: Bool
    ) -> LinkControlTransaction {
        linkAttemptToken = UUID()
        return LinkControlTransaction(
            token: linkAttemptToken,
            displayID: session.displayID,
            modeID: session.modeID,
            intent: .capability(candidate),
            orderedCandidates: [active],
            attempted: [],
            expected: active,
            stableObservation: nil,
            stableReadCount: 0,
            pollCount: 0,
            summary: "自动测试 · \(capabilityTestCurrent)",
            joiningTransaction: false,
            purpose: .capabilityTest,
            writeAccepted: false,
            writeStartedAt: nil,
            stableStartedAt: nil,
            observationStartedAt: nil,
            sawTarget: false,
            didPerformHDREnvironmentTransition: didPerformHDRTransition,
            context: capabilityRestoreContext
        )
    }

    private func beginCapabilityTestLinkControl(
        _ candidate: DisplayLinkCapability,
        session: CapabilityTestSession,
        didPerformHDRTransition: Bool
    ) {
        let beforeSLSHDR = CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID)
        let beforeSLSLink = DisplayOutputController.shared.state(
            displayID: session.displayID,
            modeID: session.modeID
        )?.slsReportedDescription
        appendLinkTestDiagnostic(
            "PRE_SLS",
            "target=\(linkTestTargetText(candidate)) didPerformHDRTransition=\(didPerformHDRTransition) hdr=\(linkTestHDRText(beforeSLSHDR)) activeLink=\(linkTestSemanticText(beforeSLSLink))"
        )
        capabilityTestStage = .testing
        capabilityTestDetail = "HDR 前置状态已就绪；正在从最新系统枚举中选择目标链路组合。"
        beginLinkControl(
            .capability(candidate),
            targetDisplayID: session.displayID,
            summaryOverride: "自动测试 · \(capabilityTestCurrent)",
            allowEquivalentModeFallback: false,
            purpose: .capabilityTest,
            didPerformHDREnvironmentTransition: didPerformHDRTransition
        )
    }

    private func finishCapabilityTestCandidate(
        _ transaction: LinkControlTransaction,
        evidence: CapabilityEvidence,
        reason: String?
    ) {
        guard var session = capabilityTestSession,
              session.displayID == transaction.displayID,
              case .capability(let capability) = transaction.intent,
              let display = displaySnapshot(for: session.displayID),
              display.hardwareKey == session.hardwareKey else {
            beginCapabilityTestRestore(completion: .failedSafely)
            return
        }
        let resulting = DisplayOutputController.shared.state(
            displayID: session.displayID,
            modeID: session.modeID
        )?.slsReportedDescription
        let finalHDR = CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID)
        let effectiveReason = transaction.hdrStateChangedAfterSLS
            ? ["HDR_STATE_CHANGED_AFTER_SLS", reason].compactMap { $0 }.joined(separator: " · ")
            : reason
        appendLinkTestDiagnostic(
            "FINAL",
            "classification=\(evidence.rawValue) finalHDRState=\(linkTestHDRText(finalHDR)) finalLink=\(linkTestSemanticText(resulting)) reason=\(effectiveReason ?? "none")"
        )
        if testBaselinePending {
            testBaselinePending = false
            guard resulting == session.originalDescription, finalHDR == session.originalSystemHDR,
                  evidence == .systemReadback else {
                beginCapabilityTestRestore(completion: .failedSafely)
                return
            }
        }
        let transitionStable = evidence == .systemReadback && resulting != nil &&
            resulting == transaction.stableObservation && transaction.observationStartedAt != nil &&
            finalHDR == resulting?.isHDR
        recordTransition(context: testTransitionContext, actions: testExecutedActions, actual: resulting,
            hdr: finalHDR, stable: transitionStable,
            desired: DesiredLinkState(rawPixelEncoding: capability.rawPixelEncoding, bitDepth: capability.bitDepth, hdrEnabled: capability.hdrEnabled, rawRange: capability.rawRange, rawEOTF: capability.rawEOTF),
            source: "LINK_TEST")
        let seenBefore = testBudget?.seen.count ?? 0
        let wasNew = transitionStable && resulting.map { testBudget?.seen.contains($0) == false } == true
        recordTestInformation(actual: resulting, stable: transitionStable)
        let seenAfter = testBudget?.seen.count ?? seenBefore
        let targetMatchesActual = resulting.map {
            $0.pixelEncoding == capability.rawPixelEncoding &&
                $0.bitDepth == UInt32(capability.bitDepth) && $0.isHDR == capability.hdrEnabled
        } == true
        let actualFields = resulting.map(linkTestCandidateFields) ?? "actual=unavailable"
        let targetText = linkTestTargetText(capability).replacingOccurrences(of: " ", with: "_")
        let semanticKey = resulting.map(capabilityTestSemanticKey) ?? "unavailable"
        let targetComparison = targetMatchesActual ? "TARGET_EQUALS_ACTUAL" : "TARGET_NOT_EQUAL_ACTUAL"
        appendLinkTestDiagnostic(
            "STABLE_ACTUAL",
            "actionIndex=\(session.nextIndex) target=\(targetText) exists=\(resulting != nil) \(actualFields) evidence=\(evidence.rawValue) stableWindow=\(transaction.stableObservation != nil) observationWindow=\(transaction.observationStartedAt != nil) semanticKey=\(semanticKey) isNew=\(wasNew) seenBefore=\(seenBefore) seenAfter=\(seenAfter) targetComparison=\(targetComparison)"
        )
        appendLinkTestBudgetState("after-result")
        lastTestStableActual = transitionStable ? resulting : nil
        var finalEvidence = evidence
        if evidence == .systemReadback, let resulting {
            let key = capabilityTestSemanticKey(resulting)
            if session.successfulSemanticStates.insert(key).inserted {
                session.successCount += 1
                let record = recordCapabilityTestResult(
                    capabilityTestCapability(from: resulting),
                    evidence: .systemReadback,
                    reason: nil,
                    display: display,
                    interfaceName: session.interfaceName,
                    resulting: resulting
                )
                capabilityTestSessionStableModes.append(record)
                capabilityTestSessionReplayProbes[record.signature] = capability
            } else {
                finalEvidence = .observedStable
                session.reconfirmedCount += 1
                appendLinkTestDiagnostic(
                    "RECONFIRMED",
                    "actualLink=\(linkTestSemanticText(resulting)) result=deduplicated"
                )
            }
        } else {
            recordCapabilityTestResult(
                capability,
                evidence: evidence,
                reason: effectiveReason,
                display: display,
                interfaceName: session.interfaceName,
                resulting: resulting
            )
        }
        if finalEvidence == .failed { session.failureCount += 1 }
        if finalEvidence == .unconfirmed || finalEvidence == .environmentUnconfirmed {
            session.unconfirmedCount += 1
        }
        capabilityTestSuccessCount = session.successCount
        capabilityTestReconfirmedCount = session.reconfirmedCount
        capabilityTestFailureCount = session.failureCount
        capabilityTestUnconfirmedCount = session.unconfirmedCount
        capabilityTestAttemptResults.append(CapabilityTestAttemptResult(
            index: capabilityTestAttemptResults.count + 1,
            passed: evidence == .systemReadback,
            actualLink: resulting.map(linkDescriptionSummary),
            diagnosticReason: effectiveReason
        ))
        updateTestProgress()
        session.consecutiveWriteFailures = evidence == .failed ? session.consecutiveWriteFailures + 1 : 0
        capabilityTestSession = session
        activeLinkTransaction = nil
        linkVerificationComplete = true
        switch finalEvidence {
        case .systemReadback, .userConfirmed: capabilityTestDetail = "当前组合已通过稳定观察。准备下一项…"
        case .failed: capabilityTestDetail = "当前组合发生稳定回退。准备下一项…"
        case .unconfirmed: capabilityTestDetail = "当前组合未能确认。准备下一项…"
        case .environmentUnconfirmed: capabilityTestDetail = "当前组合的测试环境未确认。准备下一项…"
        case .observedStable, .systemEnumerated, .untestable: capabilityTestDetail = "准备下一项…"
        }
        let completedSessionToken = session.token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.capabilityTestSession?.token == completedSessionToken,
                  self.capabilityTestStage != .restoring else { return }
            self.runNextCapabilityTestCandidate()
        }
    }

    private func beginCapabilityTestRestore(completion: CapabilityTestStage) {
        guard var session = capabilityTestSession, capabilityTestStage != .restoring else { return }
        if !linkTestStopLogged {
            let reason: String
            switch completion {
            case .completed: reason = "COMPLETED"
            case .cancelled: reason = "CANCELLED"
            default: reason = "TARGET_DISAPPEARED"
            }
            appendLinkTestStop(reason)
        }
        session.completionStage = completion
        capabilityTestSession = session
        activeLinkTransaction = nil
        linkAttemptToken = UUID()
        capabilityTestStage = .restoring
        linkVerificationComplete = false
        capabilityTestCurrent = "测试开始前的链路配置"
        capabilityTestDetail = "正在恢复测试开始前的 HDR 状态与活动链路。"
        restoreCapabilityTestHDR(sessionToken: session.token)
    }

    private func restoreCapabilityTestHDR(sessionToken: UUID) {
        guard let session = capabilityTestSession, session.token == sessionToken else { return }
        guard isCurrentLinkContext(capabilityRestoreContext) else {
            finishCapabilityTestRestore(confirmed: false, detail: "恢复上下文已失效，未发送显示写入。")
            return
        }
        guard let originalHDR = session.originalSystemHDR,
              let currentHDR = CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID),
              currentHDR != originalHDR else {
            restoreCapabilityTestLink(sessionToken: sessionToken)
            return
        }
        guard CoreDisplayHDRController.shared.setEnabled(originalHDR, displayID: session.displayID) else {
            finishCapabilityTestRestore(confirmed: false, detail: "测试前 HDR 状态的恢复请求未被系统接受。")
            return
        }
        pollCapabilityTestHDRRestore(sessionToken: sessionToken, attempt: 0)
    }

    private func pollCapabilityTestHDRRestore(sessionToken: UUID, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            guard let self,
                  let session = self.capabilityTestSession,
                  session.token == sessionToken else { return }
            self.refresh()
            guard self.isCurrentLinkContext(self.capabilityRestoreContext),
                  let originalHDR = session.originalSystemHDR else {
                self.finishCapabilityTestRestore(confirmed: false, detail: "恢复上下文或原 HDR 状态不可用，结果未确认；未继续显示写入。")
                return
            }
            let hdr = CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID)
            let link = DisplayOutputController.shared.state(
                displayID: session.displayID,
                modeID: session.modeID
            )?.slsReportedDescription
            self.updateCapabilityTestReadback(hdr: hdr, link: link)
            if hdr == originalHDR {
                self.restoreCapabilityTestLink(sessionToken: sessionToken)
            } else if attempt < 4 {
                self.pollCapabilityTestHDRRestore(sessionToken: sessionToken, attempt: attempt + 1)
            } else {
                self.finishCapabilityTestRestore(confirmed: false, detail: "恢复结果未确认：测试前 HDR 状态没有取得稳定系统复读。")
            }
        }
    }

    private func restoreCapabilityTestLink(sessionToken: UUID) {
        guard let session = capabilityTestSession, session.token == sessionToken else { return }
        capabilityTestDetail = "HDR 状态已恢复；正在恢复并连续复读测试开始前的活动链路。"
        guard isCurrentLinkContext(capabilityRestoreContext), let display = displaySnapshot(for: session.displayID),
              display.hardwareKey == session.hardwareKey,
              let mode = CGDisplayCopyDisplayMode(session.displayID),
              mode.ioDisplayModeID == session.modeID,
              let state = DisplayOutputController.shared.state(displayID: session.displayID, modeID: session.modeID) else {
            finishCapabilityTestRestore(confirmed: false, detail: "目标显示器或原 timing 已不可用；未向其它显示器发送恢复请求。")
            return
        }
        if state.slsReportedDescription?.matches(session.originalDescription) == true {
            updateCapabilityTestReadback(
                hdr: CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID),
                link: state.slsReportedDescription
            )
            pollCapabilityTestRestore(stableCount: 1, attempt: 0)
            return
        }
        guard let index = state.descriptions.firstIndex(of: session.originalDescription).map(UInt32.init) else {
            finishCapabilityTestRestore(
                confirmed: false,
                detail: "恢复结果未确认：最新系统枚举中找不到测试前的语义链路，未使用旧 index 写入。"
            )
            return
        }
        guard DisplayOutputController.shared.setOutputMode(
            displayID: session.displayID,
            modeID: session.modeID,
            index: index
        ) == 0 else {
            finishCapabilityTestRestore(confirmed: false, detail: "恢复请求未被底层接口接受，当前显示状态未确认。")
            return
        }
        pollCapabilityTestRestore(stableCount: 0, attempt: 0)
    }

    private func pollCapabilityTestRestore(stableCount: Int, attempt: Int) {
        guard let session = capabilityTestSession else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, let current = self.capabilityTestSession, current.token == session.token else { return }
            self.refresh()
            guard self.isCurrentLinkContext(self.capabilityRestoreContext), let display = self.displaySnapshot(for: session.displayID),
                  display.hardwareKey == session.hardwareKey else {
                self.finishCapabilityTestRestore(confirmed: false, detail: "原目标显示器已不可用；未向其它显示器发送恢复请求。")
                return
            }
            let observed = DisplayOutputController.shared.state(
                displayID: session.displayID,
                modeID: session.modeID
            )?.slsReportedDescription
            self.updateCapabilityTestReadback(
                hdr: CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID),
                link: observed
            )
            let hdrMatches = session.originalSystemHDR.map {
                CoreDisplayHDRController.shared.isEnabled(displayID: session.displayID) == $0
            } ?? false
            let nextStable = observed?.matches(session.originalDescription) == true && hdrMatches ? stableCount + 1 : 0
            if nextStable >= 3 {
                self.finishCapabilityTestRestore(confirmed: true, detail: "系统连续复读确认已恢复测试开始前的链路配置。")
            } else if attempt < 6 {
                self.pollCapabilityTestRestore(stableCount: nextStable, attempt: attempt + 1)
            } else {
                self.finishCapabilityTestRestore(confirmed: false, detail: "恢复结果未确认：未取得足够稳定的系统复读。")
            }
        }
    }

    private func finishCapabilityTestRestore(confirmed: Bool, detail: String) {
        guard let session = capabilityTestSession else { return }
        let requestedCompletion = session.completionStage
        appendLinkTestDiagnostic("RESTORE_TERMINAL", "session=\(session.token) displayID=\(session.displayID) confirmed=\(confirmed) requestedCompletion=\(requestedCompletion) CONTROL_VERIFICATION=\(confirmed ? "PASS" : "UNCONFIRMED") PHYSICAL_VERIFICATION=UNAVAILABLE")
        linkAttemptToken = UUID()
        activeLinkTransaction = nil
        capabilityRestoreContext = nil
        linkVerificationComplete = true
        capabilityTestSession = nil
        capabilityTestStage = confirmed ? requestedCompletion : .failedSafely
        if confirmed && requestedCompletion == .completed {
            capabilityTestTotal = 100
            capabilityTestProgress = 100
        }
        capabilityTestDetail = confirmed && requestedCompletion == .completed
            ? AppLocalization.format("测试已完成，发现 %d 种稳定链路状态。原配置已恢复。", capabilityTestSessionStableModes.count)
            : detail
        capabilityTestCurrent = ""
        capabilityTestEnvironment = "—"
        capabilityTestReadback = "HDR：—\n链路：—"
        capabilityTestDisplayID = nil
        refresh()
    }

    @discardableResult
    private func recordCapabilityTestResult(
        _ capability: DisplayLinkCapability,
        evidence: CapabilityEvidence,
        reason: String?,
        display: DisplaySnapshot,
        interfaceName fixedInterfaceName: String? = nil,
        resulting: DisplayLinkDescription? = nil
    ) -> ValidatedLinkMode {
        var record = makeCapabilityRecord(
            display: display,
            color: capability.outputPreference,
            rawPixelEncoding: capability.rawPixelEncoding,
            rawRange: capability.rawRange,
            rawEOTF: capability.rawEOTF,
            bitDepth: capability.bitDepth,
            hdr: capability.hdrEnabled,
            resultingRawPixelEncoding: resulting?.pixelEncoding,
            resultingBitDepth: resulting.map { Int($0.bitDepth) },
            resultingHDR: resulting?.isHDR,
            resultingRange: resulting?.range,
            resultingEOTF: resulting?.eotf,
            engineGeneration: CapabilityTestTiming.engineGeneration,
            evidence: evidence
        )
        record.failureReason = reason
        Preferences.shared.recordLinkMode(
            record,
            for: display.hardwareKey,
            interfaceName: fixedInterfaceName ?? interfaceName(for: display)
        )
        return record
    }

    private func capabilityTestSort(_ lhs: DisplayLinkCapability, _ rhs: DisplayLinkCapability) -> Bool {
        if lhs.hdrEnabled != rhs.hdrEnabled { return !lhs.hdrEnabled && rhs.hdrEnabled }
        if lhs.rawPixelEncoding != rhs.rawPixelEncoding { return lhs.rawPixelEncoding < rhs.rawPixelEncoding }
        if lhs.bitDepth != rhs.bitDepth { return lhs.bitDepth < rhs.bitDepth }
        return false
    }

    func autoCorrectionPlan() -> AutoCorrectionPlan {
        if safeSessionActive || Preferences.shared.safeModeEnabled {
            autoCorrectionStage = .idle
            autoCorrectionDetail = "安全模式正在运行，只读取当前状态。"
            let plan = AutoCorrectionPlan(
                current: selectedDisplay?.signalLine ?? "无法读取",
                target: "安全模式不生成切换目标",
                explanation: autoCorrectionDetail,
                canApply: false
            )
            currentAutoCorrectionPlan = plan
            return plan
        }
        autoCorrectionStage = .inspecting
        guard let target = automaticCorrectionTarget() else {
            autoCorrectionStage = .failed
            autoCorrectionDetail = "当前系统没有提供可用于自动校正的颜色链路描述。"
            let plan = AutoCorrectionPlan(
                current: selectedDisplay?.pixelEncoding.text ?? "无法读取",
                target: "没有可用目标",
                explanation: autoCorrectionDetail,
                canApply: false
            )
            currentAutoCorrectionPlan = plan
            return plan
        }
        autoCorrectionStage = .idle
        let policy = selectedCapabilityProfile?.policy ?? .balanced
        autoCorrectionDetail = "规则：\(policy.title)。\(policy.explanation) 将保持分辨率、HiDPI、刷新率、VRR 与 HDR 状态不变。"
        let plan = AutoCorrectionPlan(
            current: "\(target.active.encodingText) · \(target.active.bitDepth) bit · \(target.active.isHDR ? "HDR" : "SDR")",
            target: "\(target.description.encodingText) · \(target.depth) bit · \(target.active.isHDR ? "HDR" : "SDR")",
            explanation: autoCorrectionDetail,
            canApply: true
        )
        currentAutoCorrectionPlan = plan
        return plan
    }

    func autoCorrect() {
        guard canBeginDisplayOperation() else { return }
        autoCorrectionStage = .inspecting
        guard let target = automaticCorrectionTarget() else {
            autoCorrectionStage = .failed
            autoCorrectionDetail = "当前系统没有提供可自动校正的颜色链路模式。"
            lastError = "当前系统没有提供可自动校正的颜色链路模式。"
            return
        }
        currentAutoCorrectionPlan = AutoCorrectionPlan(
            current: "\(target.active.encodingText) · \(target.active.bitDepth) bit · \(target.active.isHDR ? "HDR" : "SDR")",
            target: "\(target.description.encodingText) · \(target.depth) bit · \(target.active.isHDR ? "HDR" : "SDR")",
            explanation: "保持当前分辨率、HiDPI、刷新率、VRR 与 HDR 状态，仅重新协商像素格式与色深。",
            canApply: true
        )
        automaticCorrectionInProgress = true
        if let display = selectedDisplay {
            pendingCapabilityRecord = makeCapabilityRecord(
                display: display,
                color: target.color,
                rawPixelEncoding: target.description.pixelEncoding,
                rawRange: target.description.range,
                rawEOTF: target.description.eotf,
                bitDepth: target.depth,
                hdr: target.active.isHDR,
                evidence: .systemEnumerated
            )
        }
        autoCorrectionStage = .applying
        autoCorrectionDetail = "目标：\(target.description.encodingText) · \(target.depth) bit；正在请求 WindowServer 重新协商。"
        beginLinkControl(
            .automatic(preferred: target.description),
            summaryOverride: "自动校正 · \(target.description.encodingText) · \(target.depth) bit · \(target.active.isHDR ? "HDR" : "SDR")"
        )
    }

    private func automaticCorrectionTarget() -> (
        active: DisplayLinkDescription,
        description: DisplayLinkDescription,
        color: OutputPreference,
        depth: Int
    )? {
        guard let display = selectedDisplay,
              let mode = CGDisplayCopyDisplayMode(display.id),
              let state = DisplayOutputController.shared.state(
                  displayID: display.id,
                  modeID: mode.ioDisplayModeID
              ),
              let active = state.slsReportedDescription else { return nil }

        // Automatic correction never changes timing, HDR or VRR by itself.
        // It ranks only the link descriptions macOS exposes for the current
        // mode, then incorporates combinations previously verified here.
        let candidates = state.descriptions.filter {
            $0.isHDR == active.isHDR && (!$0.isRGB || $0.isFullRange)
        }
        guard !candidates.isEmpty else { return nil }
        let profile = Preferences.shared.capabilityProfile(
            for: display.hardwareKey,
            interfaceName: selectedInterfaceName
        )
        let description = candidates.max {
            automaticCandidateScore($0, active: active, display: display, profile: profile) <
            automaticCandidateScore($1, active: active, display: display, profile: profile)
        } ?? active
        return (
            active,
            description,
            description.isRGB ? .rgbFullRange : .yCbCr,
            Int(description.bitDepth)
        )
    }

    private func automaticCorrectionNeeded() -> Bool {
        guard let target = automaticCorrectionTarget() else { return false }
        return target.description != target.active
    }

    private func automaticCandidateScore(
        _ candidate: DisplayLinkDescription,
        active: DisplayLinkDescription,
        display: DisplaySnapshot,
        profile: DisplayCapabilityProfile
    ) -> Int {
        var score = linkPreferenceScore(candidate, preserving: active)
        switch profile.policy {
        case .balanced:
            score += candidate.isRGB ? 70 : 10
            score += candidate.bitDepth == 10 ? 45 : (candidate.bitDepth == 8 ? 20 : 15)
        case .desktop:
            score += candidate.isRGB ? 130 : 0
            score += candidate.bitDepth == 10 ? 35 : (candidate.bitDepth == 8 ? 25 : 10)
        case .cinema:
            score += candidate.bitDepth == 10 ? 100 : (candidate.bitDepth == 12 ? 80 : 0)
            score += candidate.isRGB ? 25 : 20
        case .gaming:
            score += candidate.pixelEncoding == active.pixelEncoding ? 70 : 0
            score += candidate.bitDepth == 10 ? 45 : (candidate.bitDepth == 8 ? 40 : 10)
        case .colorCritical:
            score += candidate.isRGB ? 150 : -80
            score += candidate.bitDepth == 10 ? 90 : (candidate.bitDepth == 8 ? 10 : 30)
        }

        let signature = capabilitySignature(
            display: display,
            color: candidate.isRGB ? .rgbFullRange : .yCbCr,
            rawPixelEncoding: candidate.pixelEncoding,
            rawRange: candidate.range,
            rawEOTF: candidate.eotf,
            bitDepth: Int(candidate.bitDepth),
            hdr: candidate.isHDR
        )
        if let observation = profile.modes.first(where: {
            $0.persistentIdentity != nil && ($0.signature == signature || (
                $0.timingIdentity == display.currentTimingIdentity &&
                $0.color == (candidate.isRGB ? .rgbFullRange : .yCbCr) &&
                $0.rawPixelEncoding == candidate.pixelEncoding &&
                $0.rawRange == candidate.range && $0.rawEOTF == candidate.eotf &&
                $0.bitDepth == Int(candidate.bitDepth) &&
                $0.hdr == candidate.isHDR &&
                $0.vrr == display.vrrEnabled &&
                ($0.dsc == nil || $0.dsc == display.dscEnabled)
            ))
        }) {
            switch observation.evidence {
            case .userConfirmed: score += 220
            case .systemReadback where observation.engineGeneration == CapabilityTestTiming.engineGeneration:
                score += 140
            case .systemReadback:
                break
            case .systemEnumerated: score += 30
            case .observedStable: score += 50
            case .failed: score -= 400
            case .unconfirmed: score -= 80
            case .environmentUnconfirmed: break
            case .untestable: break
            }
        }
        return score
    }

    func retrainCurrentLink() {
        guard canBeginDisplayOperation() else { return }
        guard let current = currentTiming(displayID: selectedDisplayID, modes: allModes(for: selectedDisplayID)) else {
            lastError = "无法读取当前完整时序身份。"; return
        }
        apply(current)
    }

    func softReplugSelectedDisplay() {
        guard canBeginDisplayOperation(), linkVerificationComplete,
              activeLinkTransaction == nil,
              let display = selectedDisplay,
              !display.isBuiltin else { return }
        guard let originalIdentity = display.deviceIdentity else {
            lastError = "当前连接实例身份不可用，未请求重探测。"; return
        }
        let displayID = display.id
        let hardwareKey = display.hardwareKey
        typealias DisplayIOServicePort = @convention(c) (CGDirectDisplayID) -> io_service_t
        guard let coreGraphics = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY | RTLD_LOCAL
        ), let symbol = dlsym(coreGraphics, "CGDisplayIOServicePort") else {
            lastError = "当前 macOS 不提供显示器重新探测入口。"
            return
        }
        let displayIOServicePort = unsafeBitCast(symbol, to: DisplayIOServicePort.self)
        let service = displayIOServicePort(displayID)
        guard service != 0 else {
            lastError = "无法取得当前显示器的 framebuffer 服务。"
            return
        }
        let probeToken = UUID()
        softReplugOperationToken = probeToken
        softReplugStatus = "正在请求 macOS 重新探测显示器…"
        let result = IOServiceRequestProbe(service, UInt32(kIOFBUserRequestProbe))
        appendApplyDiagnostic(
            "SOFT_REPLUG",
            "displayID=\(displayID) hardwareKey=\(hardwareKey) requestProbeResult=\(result)"
        )
        guard result == KERN_SUCCESS else {
            softReplugOperationToken = nil
            softReplugStatus = ""
            lastError = "macOS 未接受显示器软插拔请求（IOKit \(result)）。"
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.softReplugOperationToken == probeToken else { return }
            self.softReplugOperationToken = nil
            self.refresh()
            if let uniqueID = DisplayDeviceIdentity.uniqueReassociation(originalIdentity, among: self.displays.compactMap(\.deviceIdentity)),
               let reconnected = self.displaySnapshot(for: uniqueID) {
                self.selectedDisplayID = reconnected.id
                self.softReplugStatus = "显示器已重新探测；可用模式已刷新。"
            } else {
                self.softReplugStatus = "重新探测请求已完成，但原显示器尚未重新出现。"
            }
        }
    }

    private func applyLinkConfiguration(
        color: OutputPreference? = nil,
        bitDepth: Int? = nil,
        hdrEnabled: Bool? = nil,
        displayID: CGDirectDisplayID? = nil,
        joiningTransaction: Bool = false,
        summaryOverride: String? = nil,
        allowEquivalentModeFallback: Bool = true
    ) {
        let effectiveHDR: Bool?
        if let displayID {
            guard let display = displaySnapshot(for: displayID) else {
                finishLinkControlFailure(
                    "目标显示器已不可用，未继续应用显示设置。",
                    joiningTransaction: joiningTransaction
                )
                return
            }
            effectiveHDR = display.isBuiltin ? nil : hdrEnabled
        } else {
            effectiveHDR = selectedDisplay?.isBuiltin == true ? nil : hdrEnabled
        }
        let intent = LinkControlIntent.compound(
            color: color,
            bitDepth: bitDepth,
            hdr: effectiveHDR
        )
        beginLinkControl(
            intent,
            targetDisplayID: displayID,
            joiningTransaction: joiningTransaction,
            summaryOverride: summaryOverride,
            allowEquivalentModeFallback: allowEquivalentModeFallback
        )
    }

    /// All seven color controls enter here. Only the control the user touched
    /// is a hard constraint; the other link properties may move together when
    /// that is required by the sink (for example YCbCr 10 bit instead of RGB
    /// 12 bit). The UI is updated only from a stable WindowServer readback.
    private func beginLinkControl(
        _ intent: LinkControlIntent,
        targetDisplayID: CGDirectDisplayID? = nil,
        joiningTransaction: Bool = false,
        summaryOverride: String? = nil,
        allowEquivalentModeFallback: Bool = true,
        purpose: LinkControlPurpose = .userChange,
        didPerformHDREnvironmentTransition: Bool = false,
        finalExpectedCapability: DisplayLinkCapability? = nil,
        allowsPostSLSEnvironmentDrift: Bool = false
    ) {
        if purpose == .capabilityTest {
            linkAttemptToken = UUID()
            activeLinkTransaction = nil
        } else if !joiningTransaction {
            linkAttemptToken = UUID()
            activeLinkTransaction = nil
            if pendingModeConfirmation { confirmPendingMode() }
        }
        let display: DisplaySnapshot?
        if let targetDisplayID {
            display = displaySnapshot(for: targetDisplayID)
        } else {
            display = selectedDisplay
        }
        guard let display,
              let mode = CGDisplayCopyDisplayMode(display.id),
              let state = DisplayOutputController.shared.state(
                  displayID: display.id,
                  modeID: mode.ioDisplayModeID
              ),
              let active = state.slsReportedDescription else {
            if purpose == .capabilityTest {
                beginCapabilityTestRestore(completion: .failedSafely)
                return
            }
            finishLinkControlFailure("当前系统没有提供可切换的链路模式。", joiningTransaction: joiningTransaction)
            return
        }

        if purpose == .userChange, !joiningTransaction {
            appendApplyDiagnostic(
                "TRANSACTION_START",
                "source=MANUAL displayID=\(display.id) hardwareKey=\(display.hardwareKey) modeID=\(mode.ioDisplayModeID) desired=\(intent.summary) preActualLink=\(linkTestSemanticText(active))"
            )
        }

        requestedOutputPreference = intent.requestedColor
        requestedBitDepth = intent.requestedBitDepth

        let candidates = state.descriptions
            .filter {
                intent.accepts($0) &&
                    (!intent.protectsCurrentPixelEncoding || $0.pixelEncoding == active.pixelEncoding)
            }
            .sorted {
                linkControlScore($0, intent: intent, active: active) >
                linkControlScore($1, intent: intent, active: active)
            }

        guard !candidates.isEmpty else {
            if allowEquivalentModeFallback,
               let depth = intent.requestedBitDepth,
               applyEquivalentModeLinkConfiguration(
                   display: display,
                   currentMode: mode,
                   active: active,
                   color: intent.requestedColor,
                   bitDepth: depth,
                   hdrEnabled: intent.requestedHDR,
                   summaryOverride: summaryOverride
               ) {
                return
            }
            let message = unavailableLinkCombinationMessage(
                display: display,
                mode: mode,
                color: intent.requestedColor,
                bitDepth: intent.requestedBitDepth,
                hdrEnabled: intent.requestedHDR
            )
            if purpose == .capabilityTest {
                beginCapabilityTestRestore(completion: .failedSafely)
                return
            }
            finishLinkControlFailure(message, joiningTransaction: joiningTransaction)
            return
        }

        let automaticAlreadyOptimal: Bool = {
            if case .automatic(let preferred) = intent { return preferred == active }
            return false
        }()
        if (automaticAlreadyOptimal || (intent.isSatisfied(by: active) && !intent.forcesNegotiation)),
           !joiningTransaction,
           purpose != .capabilityTest {
            if purpose == .capabilityTest {
                appendLinkTestDiagnostic(
                    "SLS_REQUEST",
                    "targetLink=\(linkTestSemanticText(active)) hdrBeforeSLS=\(linkTestHDRText(CoreDisplayHDRController.shared.isEnabled(displayID: display.id))) didIssueSLSSelection=false returnStatus=not-invoked"
                )
                var transaction = LinkControlTransaction(
                    token: linkAttemptToken,
                    displayID: display.id,
                    modeID: mode.ioDisplayModeID,
                    intent: intent,
                    orderedCandidates: candidates,
                    attempted: [],
                    expected: active,
                    stableObservation: active,
                    stableReadCount: 3,
                    pollCount: 0,
                    summary: summaryOverride ?? intent.summary,
                    joiningTransaction: false,
                    purpose: purpose,
                    writeAccepted: false,
                    writeStartedAt: nil,
                    stableStartedAt: nil,
                    observationStartedAt: nil,
                    sawTarget: false,
                    didPerformHDREnvironmentTransition: didPerformHDREnvironmentTransition
                )
                if didPerformHDREnvironmentTransition {
                    transaction.writeStartedAt = Date()
                    transaction.sawTarget = true
                    activeLinkTransaction = transaction
                    linkVerificationComplete = false
                    capabilityTestDetail = "HDR 环境切换已建立目标链路；正在执行完整稳定性观察。"
                    pollCapabilityTestTransaction(token: transaction.token)
                    return
                }
                finishCapabilityTestCandidate(
                    transaction,
                    evidence: .unconfirmed,
                    reason: "目标组合已经处于活动状态，本轮没有发生可归因于测试的真实协商。"
                )
                return
            }
            completeLinkControl(
                displayID: display.id,
                intent: intent,
                observed: active,
                expected: active,
                changed: false,
                joiningTransaction: joiningTransaction
            )
            return
        }

        // The paired SkyLight read API returns an ordered description array and
        // its active index. SLSSetDisplayOutputMode selects that same array by
        // index; every requested result is still accepted only after stable
        // active-description readback.
        guard intent.allowsVerifiedLegacyNegotiation else {
            if purpose == .capabilityTest {
                beginCapabilityTestRestore(completion: .failedSafely)
                return
            }
            finishLinkControlFailure(
                intent.unavailableSelectionMessage,
                joiningTransaction: joiningTransaction
            )
            return
        }

        if purpose == .userChange, previousOutputMode == nil {
            previousOutputMode = (display.id, mode.ioDisplayModeID, state.activeIndex, state.slsReportedDescription)
        }
        var transaction = LinkControlTransaction(
            token: linkAttemptToken,
            displayID: display.id,
            modeID: mode.ioDisplayModeID,
            intent: intent,
            orderedCandidates: candidates,
            attempted: [],
            expected: nil,
            stableObservation: nil,
            stableReadCount: 0,
            pollCount: 0,
            summary: summaryOverride ?? intent.summary,
            joiningTransaction: joiningTransaction,
            purpose: purpose,
            writeAccepted: false,
            writeStartedAt: nil,
            stableStartedAt: nil,
            observationStartedAt: nil,
            sawTarget: false,
            didPerformHDREnvironmentTransition: didPerformHDREnvironmentTransition
        )
        if purpose == .userChange, intent.protectsCurrentHDREnvironment {
            transaction.protectedHDR = CoreDisplayHDRController.shared.isEnabled(displayID: display.id)
        }
        if purpose == .userChange, intent.protectsCurrentPixelEncoding {
            transaction.protectedPixelEncoding = active.pixelEncoding
            verifiedLinkOriginalHDR = CoreDisplayHDRController.shared.isEnabled(displayID: display.id)
        }
        transaction.context = linkContext(for: display.id)
        transaction.finalExpectedCapability = finalExpectedCapability
        transaction.allowsPostSLSEnvironmentDrift = allowsPostSLSEnvironmentDrift
        activeLinkTransaction = transaction
        lastError = nil
        if purpose == .userChange, !joiningTransaction {
            switch intent {
            case .encoding, .color, .bitDepth:
                pendingChangeSummary = intent.summary
                verifiedLinkApplyStatus = "正在发送链路请求…"
            default:
                break
            }
        }
        tryNextLinkCandidate(token: transaction.token)
    }

    private func tryNextLinkCandidate(token: UUID) {
        guard var transaction = activeLinkTransaction,
              transaction.token == token,
              linkAttemptToken == token else { return }
        if transaction.usesEvidencePlanner, let desired = plannerDesired(transaction),
           let capability = transaction.finalExpectedCapability {
            recordTransition(context: plannerPathContext, actions: plannerExecuted, actual: nil,
                hdr: nil, stable: false, desired: desired, source: plannerSource)
            failVerifiedLinkApply(capability, displayID: transaction.displayID, actual: nil,
                reason: "链路观察或总时间已超时。")
            return
        }
        guard isCurrentLinkContext(transaction.context),
              let state = DisplayOutputController.shared.state(
            displayID: transaction.displayID,
            modeID: transaction.modeID
        ) else {
            if transaction.purpose == .capabilityTest {
                beginCapabilityTestRestore(completion: .failedSafely)
                return
            }
            finishLinkControlFailure(
                "目标显示器已不可用，未继续链路操作。",
                joiningTransaction: transaction.joiningTransaction
            )
            return
        }

        let freshCandidates = state.descriptions
            .filter { candidate in
                (transaction.purpose != .capabilityTest || candidate == testScheduledProbe) &&
                transaction.intent.accepts(candidate) &&
                    transaction.protectedPixelEncoding.map { $0 == candidate.pixelEncoding } != false &&
                    !transaction.attempted.contains(candidate)
            }
            .sorted { lhs, rhs in
                let lhsOrder = transaction.orderedCandidates.firstIndex(of: lhs) ?? Int.max
                let rhsOrder = transaction.orderedCandidates.firstIndex(of: rhs) ?? Int.max
                return lhsOrder < rhsOrder
            }
        if transaction.purpose == .userChange,
           case .capability = transaction.intent {
            appendApplyDiagnostic(
                "ENUMERATION",
                "descriptionCount=\(state.descriptions.count) matchingCount=\(freshCandidates.count) activeLink=\(linkTestSemanticText(state.slsReportedDescription))"
            )
        }
        guard let candidate = freshCandidates.first,
              let index = state.descriptions.firstIndex(of: candidate) else {
            let actual = state.slsReportedDescription.map(linkDescriptionSummary) ?? "无法读取"
            if transaction.purpose == .capabilityTest {
                let attributable = transaction.didPerformHDREnvironmentTransition ||
                    transaction.didIssueSLSSelection
                finishCapabilityTestCandidate(
                    transaction,
                    evidence: attributable ? .failed : .unconfirmed,
                    reason: "macOS 没有稳定采用目标组合；当前实际输出：\(actual)。"
                )
                return
            }
            let message = "macOS 没有稳定采用所选设置。当前实际输出：\(actual)。"
            finishLinkControlFailure(message, joiningTransaction: transaction.joiningTransaction)
            return
        }

        transaction.attempted.insert(candidate)
        transaction.convergenceStepCount += 1
        if transaction.convergenceStepCount > 6 {
            if transaction.purpose == .capabilityTest {
                appendLinkTestDiagnostic("TIMEOUT", "reason=maximum-convergence-steps")
                finishCapabilityTestCandidate(transaction, evidence: .unconfirmed, reason: "超过最大有效调整次数。")
            } else {
                appendApplyDiagnostic("TIMEOUT", "reason=maximum-convergence-steps")
                finishLinkControlFailure("链路调整超过安全次数限制。", joiningTransaction: transaction.joiningTransaction)
            }
            return
        }
        transaction.expected = candidate
        transaction.stableObservation = nil
        transaction.stableReadCount = 0
        transaction.pollCount = 0
        activeLinkTransaction = transaction

        if transaction.purpose == .capabilityTest {
            appendLinkTestDiagnostic(
                "ACTION_PLAN",
                "step=\(transaction.convergenceStepCount) next=link-request selected=\(linkTestSemanticText(candidate)) reason=fresh-enumeration-probe"
            )
        } else if case .capability = transaction.intent {
            appendApplyDiagnostic(
                "ACTION_PLAN",
                "step=\(transaction.convergenceStepCount) next=link-request selected=\(linkTestSemanticText(candidate)) reason=remaining-desired-mismatch"
            )
        }

        if transaction.purpose == .capabilityTest {
            transaction.hdrBeforeSLS = CoreDisplayHDRController.shared.isEnabled(displayID: transaction.displayID)
            transaction.didIssueSLSSelection = true
            activeLinkTransaction = transaction
        }
        if transaction.purpose == .capabilityTest {
            guard testMayContinue(), (testBudget?.slsActions ?? 6) < 6,
                  let hdr = CoreDisplayHDRController.shared.isEnabled(displayID: transaction.displayID),
                  testProbeVisits.insert(TestProbeVisit(probe: candidate, environment: hdr)).inserted else {
                beginCapabilityTestRestore(completion: .completed)
                return
            }
            testBudget?.slsActions += 1
            updateTestProgress()
        }
        let result = DisplayOutputController.shared.setOutputMode(
            displayID: transaction.displayID,
            modeID: transaction.modeID,
            index: UInt32(index)
        )
        if transaction.purpose == .capabilityTest {
            testExecutedActions.append(LinkExecutedAction(action: .sls(candidate), accepted: result == 0))
            appendLinkTestDiagnostic("ACTION_EXECUTED", "action=SLS_PROBE probe=\(candidate) accepted=\(result == 0)")
        }
        if transaction.purpose == .capabilityTest {
            appendLinkTestDiagnostic(
                "SLS_REQUEST",
                "targetLink=\(linkTestSemanticText(candidate)) hdrBeforeSLS=\(linkTestHDRText(transaction.hdrBeforeSLS)) didIssueSLSSelection=true index=\(index) returnStatus=\(result)"
            )
        } else if case .capability = transaction.intent {
            appendApplyDiagnostic(
                "SLS_REQUEST",
                "selected=\(linkTestSemanticText(candidate)) index=\(index) returnStatus=\(result)"
            )
        }
        guard result == 0 else {
            tryNextLinkCandidate(token: token)
            return
        }

        transaction.writeAccepted = true
        transaction.writeStartedAt = Date()
        transaction.stableStartedAt = nil
        transaction.observationStartedAt = nil
        transaction.sawTarget = false
        activeLinkTransaction = transaction
        linkVerificationComplete = false
        if transaction.purpose == .capabilityTest {
            capabilityTestStage = .waitingForReadback
            capabilityTestDetail = "正在等待显示器重新连接与链路协商。"
            pollCapabilityTestTransaction(token: token)
            return
        }
        pendingVerificationText = "正在等待链路稳定并复读实际输出…"
        if case .capability = transaction.intent {
            verifiedLinkApplyStatus = "正在等待显示器重新协商…"
        }
        if automaticCorrectionInProgress {
            autoCorrectionStage = .verifying
            autoCorrectionDetail = "链路请求已经发送，正在连续读取活动像素格式、色深与 HDR 状态。"
        }
        pollLinkTransaction(token: token)
    }

    private func pollCapabilityTestTransaction(token: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + CapabilityTestTiming.readbackInterval) { [weak self] in
            guard let self,
                  var transaction = self.activeLinkTransaction,
                  transaction.token == token,
                  transaction.purpose == .capabilityTest,
                  self.linkAttemptToken == token,
                  let startedAt = transaction.writeStartedAt else { return }

            guard self.testMayContinue(observing: true) else {
                self.beginCapabilityTestRestore(completion: self.isCurrentLinkContext(self.capabilityRestoreContext) ? .completed : .failedSafely)
                return
            }
            let now = Date()
            let elapsed = now.timeIntervalSince(startedAt)
            guard let display = self.displaySnapshot(for: transaction.displayID),
                  self.capabilityTestSession?.hardwareKey == display.hardwareKey else {
                if elapsed < CapabilityTestTiming.maximumCandidateTimeout {
                    self.capabilityTestDetail = "显示信号暂时不可用，正在等待重新连接。"
                    self.pollCapabilityTestTransaction(token: token)
                } else {
                    self.beginCapabilityTestRestore(completion: .failedSafely)
                }
                return
            }

            let observed = DisplayOutputController.shared.state(
                displayID: transaction.displayID,
                modeID: transaction.modeID
            )?.slsReportedDescription
            let observedHDR = CoreDisplayHDRController.shared.isEnabled(displayID: transaction.displayID)
            self.updateCapabilityTestReadback(hdr: observedHDR, link: observed)
            if transaction.didIssueSLSSelection,
               !transaction.hdrStateChangedAfterSLS,
               let expectedHDR = transaction.intent.requestedHDR,
               transaction.hdrBeforeSLS == expectedHDR,
               let observedHDR,
               observedHDR != expectedHDR {
                transaction.hdrStateChangedAfterSLS = true
                self.appendLinkTestDiagnostic(
                    "HDR_STATE_CHANGE",
                    "diagnostic=HDR_STATE_CHANGED_AFTER_SLS expectedHDR=\(expectedHDR) observedHDR=\(observedHDR) activeLink=\(self.linkTestSemanticText(observed))"
                )
            }
            if transaction.didIssueSLSSelection && !transaction.didLogPostSLSReadback {
                let expectedHDR = transaction.intent.requestedHDR
                let diagnostic: String
                if let expectedHDR,
                   transaction.hdrBeforeSLS == expectedHDR,
                   let observedHDR,
                   observedHDR != expectedHDR {
                    diagnostic = "HDR_STATE_CHANGED_AFTER_SLS"
                    transaction.hdrStateChangedAfterSLS = true
                } else {
                    diagnostic = "none"
                }
                self.appendLinkTestDiagnostic(
                    "POST_SLS",
                    "hdr=\(self.linkTestHDRText(observedHDR)) activeLink=\(self.linkTestSemanticText(observed)) diagnostic=\(diagnostic)"
                )
                transaction.didLogPostSLSReadback = true
            }

            if elapsed < CapabilityTestTiming.negotiationGracePeriod {
                transaction.stableObservation = observed
                transaction.stableStartedAt = nil
                transaction.observationStartedAt = nil
                self.activeLinkTransaction = transaction
                self.capabilityTestDetail = "正在重新协商；暂时读不到或不一致不会判定失败。"
                self.pollCapabilityTestTransaction(token: token)
                return
            }

            if let observed {
                if transaction.stableObservation == observed {
                    if transaction.stableStartedAt == nil { transaction.stableStartedAt = now }
                } else {
                    transaction.stableObservation = observed
                    transaction.stableStartedAt = now
                    transaction.observationStartedAt = nil
                }
                transaction.sawTarget = true
            } else {
                transaction.stableObservation = nil
                transaction.stableStartedAt = nil
                transaction.observationStartedAt = nil
            }

            let stableDuration = transaction.stableStartedAt.map { now.timeIntervalSince($0) } ?? 0
            if let observed,
               stableDuration >= CapabilityTestTiming.minimumStableDuration,
               !transaction.didLogStableCompletion {
                self.appendLinkTestDiagnostic(
                    "STABLE_END",
                    "hdr=\(self.linkTestHDRText(observedHDR)) activeLink=\(self.linkTestSemanticText(observed))"
                )
                transaction.didLogStableCompletion = true
            }
            if let observed, stableDuration >= CapabilityTestTiming.minimumStableDuration {
                if transaction.observationStartedAt == nil {
                    transaction.observationStartedAt = now
                }
                let observationDuration = now.timeIntervalSince(transaction.observationStartedAt ?? now)
                self.capabilityTestDetail = "已读取稳定链路，正在完成观察窗口。"
                self.activeLinkTransaction = transaction
                if observationDuration >= CapabilityTestTiming.observationWindow {
                    self.appendLinkTestDiagnostic(
                        "OBSERVATION_END",
                        "hdr=\(self.linkTestHDRText(observedHDR)) activeLink=\(self.linkTestSemanticText(observed))"
                    )
                    self.completeLinkControl(
                        displayID: transaction.displayID,
                        intent: transaction.intent,
                        observed: observed,
                        expected: transaction.expected ?? observed,
                        changed: true,
                        joiningTransaction: transaction.joiningTransaction
                    )
                } else {
                    self.pollCapabilityTestTransaction(token: token)
                }
                return
            }

            self.activeLinkTransaction = transaction
            if elapsed >= CapabilityTestTiming.maximumCandidateTimeout {
                if observedHDR == nil {
                    self.finishCapabilityTestCandidate(
                        transaction,
                        evidence: .unconfirmed,
                        reason: "SLS 调用后无法可靠读取 macOS HDR 状态，结果未确认。"
                    )
                } else if let observed, stableDuration >= CapabilityTestTiming.minimumStableDuration {
                    self.finishCapabilityTestCandidate(
                        transaction,
                        evidence: .unconfirmed,
                        reason: "本轮取得稳定实际链路，但未完成完整观察窗口。"
                    )
                } else {
                    self.finishCapabilityTestCandidate(
                        transaction,
                        evidence: .unconfirmed,
                        reason: "候选测试超时：未取得持续稳定的活动链路复读。"
                    )
                }
            } else {
                self.capabilityTestDetail = observed == nil ? "正在等待信号重新出现。" : "正在确认链路稳定性。"
                self.pollCapabilityTestTransaction(token: token)
            }
        }
    }

    private func pollLinkTransaction(token: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self,
                  var transaction = self.activeLinkTransaction,
                  transaction.token == token,
                  self.linkAttemptToken == token else { return }

            guard self.isCurrentLinkContext(transaction.context) else {
                if transaction.purpose == .capabilityTest {
                    self.beginCapabilityTestRestore(completion: .failedSafely)
                    return
                }
                self.finishLinkControlFailure(
                    "目标显示器已断开，链路结果未写入其它显示器。",
                    joiningTransaction: transaction.joiningTransaction
                )
                return
            }
            if transaction.usesEvidencePlanner,
               self.plannerDeadline.map({ Date() >= $0 }) != false {
                self.tryNextLinkCandidate(token: token)
                return
            }
            transaction.pollCount += 1
            let now = Date()
            var elapsed = transaction.writeStartedAt.map { now.timeIntervalSince($0) } ?? 0
            let observed = DisplayOutputController.shared.state(
                displayID: transaction.displayID,
                modeID: transaction.modeID
            )?.slsReportedDescription
            let observedHDR = CoreDisplayHDRController.shared.isEnabled(displayID: transaction.displayID)

            let protectedEncodingSatisfied = transaction.protectedPixelEncoding.map { protected in
                observed.map { protected == $0.pixelEncoding } ?? false
            } ?? true
            if transaction.purpose == .userChange,
               let observed,
               transaction.intent.isSatisfied(by: observed),
               protectedEncodingSatisfied,
               !transaction.sawTarget {
                transaction.sawTarget = true
                transaction.writeStartedAt = now
                elapsed = 0
                self.activeLinkTransaction = transaction
                self.appendApplyDiagnostic(
                    "TARGET_SEEN",
                    "actual=\(self.linkTestSemanticText(observed)) action=grant-full-stability-window"
                )
            }

            if !transaction.usesEvidencePlanner, case .capability(let capability) = transaction.intent {
                let stateKey = "\(linkTestHDRText(observedHDR))|\(linkTestSemanticText(observed))"
                if transaction.lastDiagnosticStateKey != stateKey {
                    transaction.lastDiagnosticStateKey = stateKey
                    let priorOccurrences = transaction.convergenceHistory.filter { $0 == stateKey }.count
                    transaction.convergenceHistory.append(stateKey)
                    self.appendApplyDiagnostic(
                        "STATE_CHANGED",
                        "step=\(transaction.convergenceStepCount) systemHDR=\(self.linkTestHDRText(observedHDR)) actual=\(self.linkTestSemanticText(observed))"
                    )
                    if priorOccurrences >= 2 {
                        self.activeLinkTransaction = transaction
                        self.appendApplyDiagnostic(
                            "LOOP_DETECTED",
                            "desired=\(self.linkTestTargetText(capability)) repeatedState=\(stateKey)"
                        )
                        self.failVerifiedLinkApply(
                            capability,
                            displayID: transaction.displayID,
                            actual: observed,
                            reason: "检测到链路状态循环。"
                        )
                        return
                    }
                }
            }

            if case .capability = transaction.intent,
               !transaction.didLogPostSLSReadback {
                self.appendApplyDiagnostic(
                    "POST_SLS_READBACK",
                    "systemHDR=\(self.linkTestHDRText(observedHDR)) actualLink=\(self.linkTestSemanticText(observed))"
                )
                transaction.didLogPostSLSReadback = true
            }

            if let protectedHDR = transaction.protectedHDR,
               elapsed >= CapabilityTestTiming.negotiationGracePeriod,
               observedHDR != protectedHDR,
               !transaction.didPerformPostSLSEnvironmentCorrection {
                transaction.didPerformPostSLSEnvironmentCorrection = true
                transaction.writeStartedAt = now
                transaction.stableObservation = nil
                transaction.stableStartedAt = nil
                transaction.observationStartedAt = nil
                self.activeLinkTransaction = transaction
                self.pendingVerificationText = protectedHDR
                    ? "链路切换改变了 HDR，正在恢复 HDR 环境…"
                    : "链路切换改变了 HDR，正在恢复 SDR 环境…"
                self.appendApplyDiagnostic(
                    "ENV_CORRECTION",
                    "source=MANUAL reason=protect-user-environment request=\(protectedHDR) actual=\(self.linkTestSemanticText(observed))"
                )
                guard CoreDisplayHDRController.shared.setEnabled(protectedHDR, displayID: transaction.displayID) else {
                    self.finishLinkControlFailure(
                        "无法恢复操作前的 HDR/SDR 环境。",
                        joiningTransaction: transaction.joiningTransaction
                    )
                    return
                }
                self.pollLinkTransaction(token: token)
                return
            }

            if let protectedHDR = transaction.protectedHDR,
               transaction.didPerformPostSLSEnvironmentCorrection,
               !transaction.didPerformFinalSLSConvergence,
               elapsed >= CapabilityTestTiming.negotiationGracePeriod,
               observedHDR == protectedHDR,
               let observed,
               !transaction.intent.isSatisfied(by: observed) {
                transaction.didPerformFinalSLSConvergence = true
                transaction.attempted.removeAll()
                transaction.writeStartedAt = now
                transaction.stableObservation = nil
                transaction.stableStartedAt = nil
                transaction.observationStartedAt = nil
                self.activeLinkTransaction = transaction
                self.appendApplyDiagnostic(
                    "ACTION_PLAN",
                    "source=MANUAL next=final-link-request protectedHDR=\(protectedHDR) actual=\(self.linkTestSemanticText(observed))"
                )
                self.tryNextLinkCandidate(token: token)
                return
            }

            if !transaction.usesEvidencePlanner, case .capability(let capability) = transaction.intent,
               elapsed >= CapabilityTestTiming.negotiationGracePeriod,
               observedHDR != capability.hdrEnabled,
               !transaction.allowsPostSLSEnvironmentDrift,
               !transaction.didPerformPostSLSEnvironmentCorrection {
                let before = observedHDR
                transaction.didPerformPostSLSEnvironmentCorrection = true
                transaction.writeStartedAt = now
                transaction.stableObservation = nil
                transaction.stableStartedAt = nil
                transaction.observationStartedAt = nil
                self.activeLinkTransaction = transaction
                self.verifiedLinkApplyStatus = capability.hdrEnabled
                    ? "正在重新确认 HDR 环境…"
                    : "正在重新确认 SDR 环境…"
                self.appendApplyDiagnostic(
                    "ENV_CORRECTION",
                    "reason=post-sls-environment-drift before=\(self.linkTestHDRText(before)) request=\(capability.hdrEnabled) actualLink=\(self.linkTestSemanticText(observed))"
                )
                guard CoreDisplayHDRController.shared.setEnabled(capability.hdrEnabled, displayID: transaction.displayID) else {
                    self.failVerifiedLinkApply(
                        capability,
                        displayID: transaction.displayID,
                        actual: observed,
                        reason: "SLS 后 HDR/SDR 环境修正请求未被系统接受。"
                    )
                    return
                }
                self.pollLinkTransaction(token: token)
                return
            }

            if !transaction.usesEvidencePlanner, case .capability(let capability) = transaction.intent,
               transaction.didPerformPostSLSEnvironmentCorrection,
               !transaction.didPerformFinalSLSConvergence,
               elapsed >= CapabilityTestTiming.negotiationGracePeriod,
               observedHDR == capability.hdrEnabled,
               let observed,
               !transaction.intent.isSatisfied(by: observed) {
                transaction.didPerformFinalSLSConvergence = true
                transaction.attempted.removeAll()
                transaction.writeStartedAt = now
                transaction.stableObservation = nil
                transaction.stableStartedAt = nil
                transaction.observationStartedAt = nil
                self.activeLinkTransaction = transaction
                self.verifiedLinkApplyStatus = "正在选择显示链路…"
                self.appendApplyDiagnostic(
                    "ENV_CORRECTION",
                    "result=environment-restored afterSystemHDR=\(self.linkTestHDRText(observedHDR)) afterActualLink=\(self.linkTestSemanticText(observed)) action=one-final-sls-convergence"
                )
                self.tryNextLinkCandidate(token: token)
                return
            }

            if let observed,
               observedHDR == observed.isHDR {
                if transaction.stableObservation == observed {
                    transaction.stableReadCount += 1
                    if transaction.stableStartedAt == nil { transaction.stableStartedAt = now }
                } else {
                    transaction.stableObservation = observed
                    transaction.stableReadCount = 1
                    transaction.stableStartedAt = now
                    transaction.observationStartedAt = nil
                }
            } else {
                transaction.stableObservation = nil
                transaction.stableReadCount = 0
                transaction.stableStartedAt = nil
                transaction.observationStartedAt = nil
            }
            self.activeLinkTransaction = transaction

            if elapsed < CapabilityTestTiming.negotiationGracePeriod {
                self.pendingVerificationText = "正在等待显示器重新连接…"
                self.pollLinkTransaction(token: token)
                return
            }

            let stableDuration = transaction.stableStartedAt.map { now.timeIntervalSince($0) } ?? 0
            if let observed, stableDuration >= CapabilityTestTiming.minimumStableDuration {
                if case .capability = transaction.intent, !transaction.didLogStableCompletion {
                    self.appendApplyDiagnostic(
                        "STABLE_POLL",
                        "checkpoint=stable systemHDR=\(self.linkTestHDRText(observedHDR)) actualLink=\(self.linkTestSemanticText(observed))"
                    )
                    transaction.didLogStableCompletion = true
                    self.activeLinkTransaction = transaction
                }
                if transaction.observationStartedAt == nil {
                    transaction.observationStartedAt = now
                    self.activeLinkTransaction = transaction
                }
                self.pendingVerificationText = AppLocalization.format(
                    "正在确认实际输出：%@",
                    self.linkDescriptionSummary(observed)
                )
                if transaction.purpose == .userChange,
                   case .capability = transaction.intent {
                    self.verifiedLinkApplyStatus = "正在确认稳定输出…"
                }
                let observationDuration = now.timeIntervalSince(transaction.observationStartedAt ?? now)
                if observationDuration >= CapabilityTestTiming.observationWindow {
                    self.completeLinkControl(
                        displayID: transaction.displayID,
                        intent: transaction.intent,
                        observed: observed,
                        expected: transaction.expected ?? observed,
                        changed: true,
                        joiningTransaction: transaction.joiningTransaction
                    )
                    return
                }
            } else {
                self.pendingVerificationText = observed == nil
                    ? "正在等待显示信号重新出现…"
                    : "正在确认当前链路稳定…"
            }
            if elapsed < CapabilityTestTiming.maximumCandidateTimeout {
                self.pollLinkTransaction(token: token)
            } else {
                self.tryNextLinkCandidate(token: token)
            }
        }
    }

    private func completeLinkControl(
        displayID: CGDirectDisplayID,
        intent: LinkControlIntent,
        observed: DisplayLinkDescription,
        expected: DisplayLinkDescription,
        changed: Bool,
        joiningTransaction: Bool
    ) {
        let transaction = activeLinkTransaction
        if transaction?.purpose == .capabilityTest {
            guard let transaction,
                  displaySnapshot(for: displayID) != nil else {
                beginCapabilityTestRestore(completion: .failedSafely)
                return
            }
            finishCapabilityTestCandidate(transaction, evidence: .systemReadback, reason: nil)
            return
        }
        guard let display = displaySnapshot(for: displayID) else {
            finishLinkControlFailure(
                "目标显示器已断开，链路结果未写入其它显示器。",
                joiningTransaction: joiningTransaction
            )
            return
        }
        if let transaction, transaction.usesEvidencePlanner {
            let hdr = CoreDisplayHDRController.shared.isEnabled(displayID: displayID)
            guard finishPlannerObservation(transaction, actual: observed, hdr: hdr) else { return }
            if plannerSLSCount == 0 && plannerHDRCount == 0 {
                activeLinkTransaction = nil
                linkVerificationComplete = true
                verifiedLinkApplyStatus = ""
                verifiedLinkApplyStartedAt = nil
                previousOutputMode = nil
                verifiedLinkOriginalHDR = nil
                pendingVerificationText = "系统报告已满足完整目标，未发送显示写入。"
                appendApplyDiagnostic("FINAL_RESULT", "result=no-write-exact-success CONTROL_VERIFICATION=PASS")
                return
            }
        }
        let protectedEncodingSatisfied = transaction?.protectedPixelEncoding.map {
            $0 == observed.pixelEncoding
        } ?? true
        if transaction?.purpose == .userChange,
           transaction?.finalExpectedCapability == nil,
           (!intent.isSatisfied(by: observed) || !protectedEncodingSatisfied),
           let token = transaction?.token {
            appendApplyDiagnostic(
                "STABLE_RESULT",
                "match=false target=\(intent.summary) actual=\(linkTestSemanticText(observed)) action=try-next-candidate"
            )
            tryNextLinkCandidate(token: token)
            return
        }
        if case .capability(let capability) = intent {
            let systemHDR = CoreDisplayHDRController.shared.isEnabled(displayID: displayID)
            let finalCapability = transaction?.finalExpectedCapability ?? capability
            let desired = DesiredLinkState(rawPixelEncoding: finalCapability.rawPixelEncoding,
                bitDepth: finalCapability.bitDepth, hdrEnabled: finalCapability.hdrEnabled, rawRange: finalCapability.rawRange, rawEOTF: finalCapability.rawEOTF)
            let verification = ConnectionVerification(target: desired, slsReported: observed, systemHDR: systemHDR)
            let matched = !verification.requiresControlRecovery
            appendApplyDiagnostic(
                "STABLE_RESULT",
                "CONTROL_VERIFICATION=\(verification.control.rawValue) PHYSICAL_VERIFICATION=\(verification.physical.rawValue) match=\(matched) target=\(linkTestTargetText(finalCapability)) probe=\(linkTestTargetText(capability)) systemHDR=\(linkTestHDRText(systemHDR)) SLS_REPORTED_CURRENT=\(linkTestSemanticText(observed))"
            )
            guard matched else {
                failVerifiedLinkApply(
                    finalCapability,
                    displayID: displayID,
                    actual: observed,
                    reason: "稳定读回与目标链路不一致。"
                )
                return
            }
        }
        if let preference = intent.preferenceToPersist {
            Preferences.shared.setOutputPreference(preference, for: display.hardwareKey)
        }
        requestedOutputPreference = nil
        requestedBitDepth = nil
        if intent.requestedHDR != nil { applyingFeature = nil }
        lastError = nil
        activeLinkTransaction = nil
        linkVerificationComplete = true
        verifiedLinkApplyToken = UUID()
        verifiedLinkApplyStatus = ""
        let summary = linkDescriptionSummary(observed)
        if transaction?.purpose == .userChange {
            appendApplyDiagnostic(
                "UI_ACTUAL_SYNC",
                "actual=\(linkTestSemanticText(observed)) writesTriggered=false"
            )
        }
        pendingVerificationText = observed.matches(expected)
            ? "系统回读确认：\(summary)"
            : "操作已生效；系统联动调整为 \(summary)"
        var record = makeCapabilityRecord(
            display: display,
            color: observed.isRGB ? .rgbFullRange : .yCbCr,
            rawPixelEncoding: observed.pixelEncoding,
            rawRange: observed.range,
            rawEOTF: observed.eotf,
            bitDepth: Int(observed.bitDepth),
            hdr: observed.isHDR,
            evidence: .systemReadback
        )
        record.failureReason = nil
        pendingCapabilityRecord = changed ? record : nil
        Preferences.shared.recordLinkMode(
            record,
            for: display.hardwareKey,
            interfaceName: interfaceName(for: display)
        )
        if changed && !pendingModeConfirmation {
            if case .capability = intent {
                appendApplyDiagnostic(
                    "FINAL_RESULT",
                    "result=stable-awaiting-user-confirmation actual=\(linkTestSemanticText(observed))"
                )
            }
            beginConfirmationCountdown(summary: transaction?.summary ?? intent.summary)
            pendingVerificationText = "系统回读确认：\(summary)"
        }
        if automaticCorrectionInProgress {
            automaticCorrectionInProgress = false
            autoCorrectionStage = .completed
            autoCorrectionDetail = "复读结果：\(summary)。"
        }
        refresh()
    }

    private func finishLinkControlFailure(_ message: String, joiningTransaction: Bool) {
        let wasVerifiedLinkApply = !verifiedLinkApplyStatus.isEmpty
        let desired = wasVerifiedLinkApply ? failureDesiredCapability : nil
        let failureOutput = previousOutputMode.flatMap {
            DisplayOutputController.shared.state(displayID: $0.displayID, modeID: $0.modeID)?.slsReportedDescription
        }
        let failureHDR = previousOutputMode.flatMap {
            CoreDisplayHDRController.shared.isEnabled(displayID: $0.displayID)
        }
        activeLinkTransaction = nil
        linkVerificationComplete = true
        verifiedLinkApplyStatus = ""
        requestedOutputPreference = nil
        requestedBitDepth = nil
        applyingFeature = nil
        pendingCapabilityRecord = nil
        if joiningTransaction {
            restorePendingModeIfNeeded()
        } else if pendingModeConfirmation {
            // A successful low-level call may already have changed the link.
            // Keep the existing confirmation window and fallback available;
            // timeout or an explicit user choice will finish the pending state.
            pendingVerificationText = "系统复读未确认；原设置仍保留为可恢复状态。"
        } else {
            confirmationTimer?.invalidate()
            confirmationTimer = nil
            previousMode = nil
            previousOutputMode = nil
            pendingModeConfirmation = false
            confirmationSeconds = 0
        }
        if automaticCorrectionInProgress {
            automaticCorrectionInProgress = false
            autoCorrectionStage = .failed
            autoCorrectionDetail = message
        }
        refresh()
        if let desired {
            showLinkFailure(desired: desired, actual: failureOutput, systemHDR: failureHDR, reason: message)
        } else if !joiningTransaction {
            lastError = message
        } else if wasVerifiedLinkApply {
            lastError = message + "\n" + AppLocalization.string(restoreExplanation)
        }
    }

    private func linkDescriptionSummary(_ item: DisplayLinkDescription) -> String {
        "\(item.encodingText) · \(item.bitDepth) bit · \(item.isHDR ? "HDR" : "SDR")"
    }

    private func linkControlScore(
        _ candidate: DisplayLinkDescription,
        intent: LinkControlIntent,
        active: DisplayLinkDescription
    ) -> Int {
        var score = linkPreferenceScore(candidate, preserving: active)
        switch intent {
        case .automatic(let preferred):
            if candidate == preferred { score += 500 }
        case .encoding:
            if candidate.isHDR == active.isHDR { score += 120 }
            if candidate.bitDepth == active.bitDepth { score += 80 }
        case .color(let color):
            if candidate.isHDR == active.isHDR { score += 120 }
            if candidate.bitDepth == active.bitDepth { score += 80 }
            if color == .yCbCr && candidate.bitDepth == 10 { score += 100 }
        case .bitDepth:
            if candidate.pixelEncoding == active.pixelEncoding { score += 140 }
            if candidate.isHDR == active.isHDR { score += 120 }
        case .hdr(let enabled):
            if candidate.pixelEncoding == active.pixelEncoding { score += 120 }
            if candidate.bitDepth == active.bitDepth { score += 80 }
            if !enabled && candidate.bitDepth == 10 { score += 60 }
        case .capability:
            score += 400
        case .compound:
            score += 200
        }
        return score
    }

    /// Some Apple-Silicon display drivers expose visually identical desktop
    /// modes under separate CoreGraphics mode IDs, with a different set of
    /// low-level color descriptions attached to each ID. Search those aliases
    /// before declaring a requested bit depth unavailable.
    private func applyEquivalentModeLinkConfiguration(
        display: DisplaySnapshot,
        currentMode: CGDisplayMode,
        active: DisplayLinkDescription,
        color: OutputPreference?,
        bitDepth: Int,
        hdrEnabled: Bool?,
        summaryOverride: String?
    ) -> Bool {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(display.id, options) as? [CGDisplayMode] else {
            return false
        }

        let currentVRR = DisplayOutputController.shared.isVRR(
            displayID: display.id,
            modeID: currentMode.ioDisplayModeID
        )
        let equivalentModes = modes.filter { candidate in
            candidate.ioDisplayModeID != currentMode.ioDisplayModeID &&
            candidate.isUsableForDesktopGUI() &&
            candidate.width == currentMode.width && candidate.height == currentMode.height &&
            candidate.pixelWidth == currentMode.pixelWidth && candidate.pixelHeight == currentMode.pixelHeight &&
            (candidate.refreshRate == 0 || currentMode.refreshRate == 0 ||
             abs(candidate.refreshRate - currentMode.refreshRate) < 0.01) &&
            DisplayOutputController.shared.isVRR(
                displayID: display.id,
                modeID: candidate.ioDisplayModeID
            ) == currentVRR
        }

        let match = equivalentModes.compactMap { candidate -> (CGDisplayMode, DisplayLinkDescription)? in
            guard let state = DisplayOutputController.shared.state(
                displayID: display.id,
                modeID: candidate.ioDisplayModeID
            ) else { return nil }
            let descriptions = state.descriptions.filter {
                $0.satisfies(color: color, bitDepth: bitDepth, hdrEnabled: hdrEnabled)
            }
            guard let description = descriptions.max(by: {
                linkPreferenceScore($0, preserving: active) < linkPreferenceScore($1, preserving: active)
            }) else { return nil }
            return (candidate, description)
        }.max {
            linkPreferenceScore($0.1, preserving: active) < linkPreferenceScore($1.1, preserving: active)
        }

        guard let (targetMode, targetDescription) = match else { return false }
        if previousMode == nil { previousMode = (display.id, currentMode) }
        if previousOutputMode == nil,
           let currentState = DisplayOutputController.shared.state(
               displayID: display.id,
               modeID: currentMode.ioDisplayModeID
           ) {
            previousOutputMode = (display.id, currentMode.ioDisplayModeID, currentState.activeIndex, currentState.slsReportedDescription)
        }
        guard CGDisplaySetDisplayMode(display.id, targetMode, nil) == .success else {
            previousMode = nil
            previousOutputMode = nil
            return false
        }

        let summary = summaryOverride ?? "\(targetDescription.encodingText) · \(bitDepth) bit"
        let transactionToken = linkAttemptToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.linkAttemptToken == transactionToken else { return }
            self.applyLinkConfiguration(
                color: color,
                bitDepth: bitDepth,
                hdrEnabled: hdrEnabled,
                displayID: display.id,
                joiningTransaction: true,
                summaryOverride: summary,
                allowEquivalentModeFallback: false
            )
        }
        return true
    }

    private func unavailableLinkCombinationMessage(
        display: DisplaySnapshot,
        mode: CGDisplayMode,
        color: OutputPreference?,
        bitDepth: Int?,
        hdrEnabled: Bool?
    ) -> String {
        let timing = display.modes.first {
            $0.matches(mode)
        }
        let resolution = timing?.outputResolutionText ?? "当前分辨率"
        let refresh = RefreshRateText.fixed(mode.refreshRate)
        let requested = [
            color?.title,
            bitDepth.map { "\($0) bit" },
            hdrEnabled.map { $0 ? "HDR" : "SDR" }
        ].compactMap { $0 }.joined(separator: "、")
        let requestText = requested.isEmpty ? "所选组合" : requested

        return AppLocalization.format("当前枚举没有可执行的同名探测项：%@ @ %@，%@。这不代表设备不支持该状态。", resolution, refresh, requestText)
    }

    private func verifyDisplayMode(_ option: DisplayModeOption, displayID: CGDirectDisplayID,
                                   token: UUID, attempt: Int, stable: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.pendingModeConfirmation, self.modeAttemptToken == token,
                  let change = self.pendingTimingChange else { return }
            let modes = self.allModes(for: displayID)
            let timing = self.currentTiming(displayID: displayID, modes: modes)
            let state = timing.flatMap { DisplayOutputController.shared.state(displayID: displayID, modeID: $0.id) }
            let hdr = CoreDisplayHDRController.shared.isEnabled(displayID: displayID)
            let isBuiltin = self.displaySnapshot(for: displayID)?.isBuiltin == true
            let contextOK = CGDisplayIsOnline(displayID) != 0 && self.linkContextGeneration == change.generation &&
                self.displaySnapshot(for: displayID)?.hardwareKey == change.original.hardwareKey
            let matched = contextOK && timing?.timingIdentity == option.timingIdentity &&
                (isBuiltin || (change.protection.matches(state?.slsReportedDescription?.identity, systemHDR: hdr) &&
                    state.map { change.protection.targetExists(in: $0.descriptions) } == true))
            self.appendApplyDiagnostic("TIMING_READBACK", "attempt=\(attempt) matched=\(matched) timing=\(timing?.selectionKey ?? "UNAVAILABLE") SLS_REPORTED=\(state?.slsReportedDescription?.identity.detail ?? "UNAVAILABLE") systemHDR=\(self.linkTestHDRText(hdr)) PHYSICAL_VERIFICATION=UNAVAILABLE")
            let nextStable = matched ? stable + 1 : 0
            if nextStable >= 2 {
                self.linkVerificationComplete = true
                self.pendingVerificationText = "系统回读确认时序与完整连接状态一致"
                self.applyingFeature = nil; self.refresh(); return
            }
            if attempt < 3 && contextOK {
                self.verifyDisplayMode(option, displayID: displayID, token: token, attempt: attempt + 1, stable: nextStable); return
            }
            self.restorePendingModeIfNeeded()
            self.applyingFeature = nil
            self.lastError = "系统未确认目标时序或完整颜色／HDR 状态发生变化；已进入恢复流程。"
        }
    }

    private func restoreTiming(_ change: TimingChange) {
        confirmationTimer?.invalidate(); confirmationTimer = nil
        modeAttemptToken = UUID()
        let token = modeAttemptToken
        displayRecoveryToken = token
        pendingTimingChange = nil; previousMode = nil
        pendingModeConfirmation = false; confirmationSeconds = 0
        linkVerificationComplete = false
        let id = change.original.displayID
        guard CGDisplayIsOnline(id) != 0, linkContextGeneration == change.generation,
              displaySnapshot(for: id)?.hardwareKey == change.original.hardwareKey,
              let original = allModes(for: id).first(where: { $0.timingIdentity == change.original.timingIdentity }) else {
            completeDisplayRecovery(token: token)
            pendingVerificationText = "目标上下文改变，无法确认恢复；未向其他显示器写入。"
            lastError = pendingVerificationText; return
        }
        let accepted = setTiming(original) == .success
        pendingVerificationText = "已请求恢复原时序；完整连接状态尚未确认。"
        // Restoration is confined to this timing transaction and the same
        // context. Phase C recovery/budgets are untouched.
        finishTimingRestore(change, token: token, timingAccepted: accepted, attempt: 0, stable: 0)
    }

    private func finishTimingRestore(_ change: TimingChange, token: UUID, timingAccepted: Bool,
                                     attempt: Int, stable: Int, restoreActionAttempted: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            guard let self, self.displayRecoveryToken == token, self.modeAttemptToken == token else { return }
            self.refresh()
            let id = change.original.displayID
            guard CGDisplayIsOnline(id) != 0, self.linkContextGeneration == change.generation,
                  self.displaySnapshot(for: id)?.hardwareKey == change.original.hardwareKey else {
                self.completeDisplayRecovery(token: token)
                self.pendingVerificationText = "恢复上下文已改变，结果未确认。"; return
            }
            let timing = self.currentTiming(displayID: id, modes: self.allModes(for: id))
            let state = timing.flatMap { DisplayOutputController.shared.state(displayID: id, modeID: $0.id) }
            let hdr = CoreDisplayHDRController.shared.isEnabled(displayID: id)
            let builtin = self.displaySnapshot(for: id)?.isBuiltin == true
            let correctTiming = timing?.timingIdentity == change.original.timingIdentity
            var didAttemptRestore = restoreActionAttempted
            if !didAttemptRestore, timingAccepted, correctTiming, !builtin,
               let expected = change.protection.original, let state,
               state.descriptions.contains(where: { $0.identity == expected && $0.identity.isKnown }) {
                didAttemptRestore = true
                if hdr != change.protection.systemHDR, let hdr = change.protection.systemHDR {
                    _ = CoreDisplayHDRController.shared.setEnabled(hdr, displayID: id)
                }
                if state.slsReportedDescription?.identity != expected,
                   let fresh = DisplayOutputController.shared.state(displayID: id, modeID: change.original.id),
                   let freshIndex = fresh.descriptions.firstIndex(where: { $0.identity == expected && $0.identity.isKnown }) {
                    _ = DisplayOutputController.shared.setOutputMode(displayID: id, modeID: change.original.id, index: UInt32(freshIndex))
                }
            }
            let matches = timingAccepted && correctTiming && (builtin ||
                change.protection.matches(state?.slsReportedDescription?.identity, systemHDR: hdr))
            let nextStable = matches ? stable + 1 : 0
            if nextStable >= 3 || attempt >= 8 {
                self.completeDisplayRecovery(token: token)
                self.pendingVerificationText = nextStable >= 3 ? "系统回读确认原时序与连接状态已恢复" : "原时序／连接状态恢复未确认"
                self.appendApplyDiagnostic("TIMING_RESTORE_RESULT", "CONTROL_VERIFICATION=\(nextStable >= 3 ? "PASS" : "UNCONFIRMED") PHYSICAL_VERIFICATION=UNAVAILABLE")
                self.refresh()
            } else {
                self.finishTimingRestore(change, token: token, timingAccepted: timingAccepted, attempt: attempt + 1, stable: nextStable, restoreActionAttempted: didAttemptRestore)
            }
        }
    }

    private func linkPreferenceScore(
        _ candidate: DisplayLinkDescription,
        preserving active: DisplayLinkDescription,
        requestedColor: OutputPreference? = nil,
        requestedHDR: Bool? = nil
    ) -> Int {
        var score = 0
        if candidate.bitDepth == active.bitDepth { score += 20 }
        score += Int(candidate.bitDepth)
        if candidate.pixelEncoding == active.pixelEncoding { score += 10 }
        if candidate.range == active.range { score += 5 }
        if candidate.eotf == active.eotf { score += 40 }
        // 10 bit is the most widely interoperable deep-color format for
        // YCbCr and for SDR after HDR is disabled. Prefer it when bit depth is
        // not itself the requested target, while still allowing the sink to
        // report another working combination.
        if requestedColor == .yCbCr && candidate.bitDepth == 10 { score += 45 }
        if requestedHDR == false && candidate.bitDepth == 10 { score += 30 }
        return score
    }

    private func makeCapabilityRecord(
        display: DisplaySnapshot,
        color: OutputPreference,
        rawPixelEncoding: UInt32? = nil,
        rawRange: UInt32? = nil,
        rawEOTF: UInt32? = nil,
        bitDepth: Int,
        hdr: Bool,
        resultingRawPixelEncoding: UInt32? = nil,
        resultingBitDepth: Int? = nil,
        resultingHDR: Bool? = nil,
        resultingRange: UInt32? = nil,
        resultingEOTF: UInt32? = nil,
        engineGeneration: Int? = nil,
        evidence: CapabilityEvidence
    ) -> ValidatedLinkMode {
        ValidatedLinkMode(
            signature: capabilitySignature(
                display: display,
                color: color,
                rawPixelEncoding: rawPixelEncoding,
                rawRange: rawRange,
                rawEOTF: rawEOTF,
                bitDepth: bitDepth,
                hdr: hdr
            ),
            timingIdentity: display.currentTimingIdentity,
            resolution: display.resolution,
            refreshRate: display.refreshRate.text,
            color: color,
            rawPixelEncoding: rawPixelEncoding,
            rawRange: rawRange,
            rawEOTF: rawEOTF,
            bitDepth: bitDepth,
            hdr: hdr,
            resultingRawPixelEncoding: resultingRawPixelEncoding,
            resultingBitDepth: resultingBitDepth,
            resultingHDR: resultingHDR,
            resultingRange: resultingRange,
            resultingEOTF: resultingEOTF,
            engineGeneration: engineGeneration,
            vrr: display.vrrEnabled,
            dsc: display.dscEnabled,
            evidence: evidence,
            lastChecked: Date(),
            failureReason: nil
        )
    }

    private func capabilitySignature(
        display: DisplaySnapshot,
        color: OutputPreference,
        rawPixelEncoding: UInt32? = nil,
        rawRange: UInt32? = nil,
        rawEOTF: UInt32? = nil,
        bitDepth: Int,
        hdr: Bool
    ) -> String {
        guard let timing = display.currentTimingIdentity,
              let rawPixelEncoding, let rawRange, let rawEOTF,
              let depth = UInt32(exactly: bitDepth) else { return "incomplete|\(UUID())" }
        let connection = ConnectionIdentity(pixelEncoding: rawPixelEncoding, depth: depth, range: rawRange, eotf: rawEOTF)
        guard connection.isKnown, connection.hdrEnabled == hdr else { return "incomplete|\(UUID())" }
        return "v2|\(timing.key)|\(connection.persistenceKey)"
    }

    private func canModifyDisplay() -> Bool {
        guard applyingFeature != .hdr else { return false }
        guard !Preferences.shared.displayOutputControlsLocked else {
            lastError = "配置保护已开启；解锁后才能修改显示设置。"
            return false
        }
        guard !safeSessionActive, !Preferences.shared.safeModeEnabled else {
            lastError = "安全模式正在运行；关闭安全模式后才能修改显示设置。"
            return false
        }
        return true
    }

    private func beginFeatureAttempt(_ feature: DisplayFeatureChange) {
        let token = UUID()
        featureAttemptToken = token
        applyingFeature = feature
        lastError = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            guard let self, self.featureAttemptToken == token else { return }
            self.refresh()
            self.applyingFeature = nil
        }
    }

    private func finishFeatureAttempt(_ feature: DisplayFeatureChange) {
        guard applyingFeature == feature else { return }
        refresh()
        applyingFeature = nil
    }

    private func beginConfirmationCountdown(summary: String) {
        pendingModeConfirmation = true
        pendingChangeSummary = summary
        pendingVerificationText = "正在复读系统状态…"
        confirmationSeconds = 15
        confirmationTimer?.invalidate()
        let confirmationModeToken = modeAttemptToken
        let confirmationLinkToken = linkAttemptToken
        confirmationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, self.pendingModeConfirmation,
                      self.modeAttemptToken == confirmationModeToken,
                      self.linkAttemptToken == confirmationLinkToken else { return }
                self.confirmationSeconds -= 1
                if self.confirmationSeconds <= 0 {
                    timer.invalidate()
                    self.restorePendingModeIfNeeded()
                }
            }
        }
    }

    private func makeSnapshot(_ id: CGDirectDisplayID, reuseObservationInventory: Bool = false) -> DisplaySnapshot? {
        guard let current = CGDisplayCopyDisplayMode(id) else { return nil }
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        let systemName = screen?.localizedName ?? "显示器 \(id)"
        guard let deviceIdentity = displayIdentityRegistry.identity(for: id) else { return nil }
        let hardwareKey = deviceIdentity.storageKey
        let correction = Preferences.shared.correction(for: hardwareKey)
        let name = correction?.alias.isEmpty == false ? correction!.alias : systemName
        let millimeters = CGDisplayScreenSize(id)
        let diagonalMM = hypot(millimeters.width, millimeters.height)
        let reportedDiagonal = diagonalMM > 0 ? Double(diagonalMM / 25.4) : nil
        let rate = current.refreshRate
        // Active readback remains fresh on every observation. Cached inventory
        // is never fed to control prechecks, write verification or recovery.
        let outputState = DisplayOutputController.shared.state(displayID: id, modeID: current.ioDisplayModeID)
        let activeIndex = DisplayTimingController.shared.currentIndex(displayID: id)
        let activeTiming = activeIndex.flatMap { DisplayTimingController.shared.read(displayID: id, index: $0) }
        let activeKey = activeTiming.map {
            "\($0.index)|\($0.ioModeID)|\($0.width)x\($0.height)|\($0.pixelWidth)x\($0.pixelHeight)|\($0.refreshRate.bitPattern)|\($0.ioFlags)|\($0.vrr.map(String.init) ?? "unknown")|\($0.range.minimum.map { String($0.bitPattern) } ?? "unknown")|\($0.range.maximum.map { String($0.bitPattern) } ?? "unknown")"
        } ?? "CGS_ACTIVE_UNAVAILABLE"
        let linkKey = outputState.map { state in
            "\(state.activeIndex)|" + state.descriptions.map { "\($0.pixelEncoding),\($0.bitDepth),\($0.range),\($0.eotf)" }.joined(separator: ";")
        } ?? "SLS_ACTIVE_UNAVAILABLE"
        let inventoryKey = "\(hardwareKey)|\(DisplayModeOption.selectionKey(for: current))|\(current.ioFlags)|\(activeKey)|\(linkKey)"
        let inventory = observationInventory.value(for: id, key: inventoryKey,
            now: ProcessInfo.processInfo.systemUptime, forceFresh: !reuseObservationInventory) {
                DisplayPresentationInventory(modes: allModes(for: id),
                    compatibleLinks: equivalentLinkDescriptions(displayID: id, currentMode: current))
            }
        let modeOptions = inventory.modes
        let signalResolution = outputTimingResolution(
            from: modeOptions,
            currentRefreshRate: current.refreshRate
        )
        let encoding = pixelEncoding(for: current)
        let compatibleLinkDescriptions = inventory.compatibleLinks
        let activeLink = outputState?.slsReportedDescription
        // Missing fresh active evidence must not expose a previous VRR/range as current.
        let currentModeOption = reuseObservationInventory && activeTiming == nil
            ? nil : currentTiming(displayID: id, modes: modeOptions)
        let currentModeKey = currentModeOption?.selectionKey ?? DisplayModeOption.selectionKey(for: current)
        let edrAvailable = (screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) > 1
        let edrActive = (screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1) > 1
        let isBuiltin = CGDisplayIsBuiltin(id) != 0
        let systemHDRSupported = !isBuiltin ? CoreDisplayHDRController.shared.isSupported(displayID: id) : nil
        let systemHDREnabled = !isBuiltin ? CoreDisplayHDRController.shared.isEnabled(displayID: id) : nil
        let currentOutputWidth = currentModeOption?.outputWidth ?? current.pixelWidth
        let currentOutputHeight = currentModeOption?.outputHeight ?? current.pixelHeight
        let applePanel = isBuiltin
            ? DisplayResolutionCatalog.appleBuiltinSpec(width: currentOutputWidth, height: currentOutputHeight)
            : nil

        let dscState = dscStatus(
            displayID: id,
            mode: currentModeOption,
            modes: modeOptions,
            activeLink: activeLink
        )
        let currentVRRState = currentModeOption?.vrrState
        // SLS-reported active is not a physical-current authority. The system
        // HDR switch is a separate configuration signal, not sink evidence.
        let externalHDRState = activeLink?.isHDR ?? systemHDREnabled
        let hdrSignal: SignalValue
        if isBuiltin {
            hdrSignal = SignalValue(
                text: edrAvailable ? (edrActive ? "HDR / EDR 活跃" : "HDR / EDR 自动") : "SDR",
                verification: .verified,
                source: "NSScreen EDR 状态",
                detail: edrAvailable
                    ? "该内建屏幕支持扩展动态范围；macOS 会按当前内容、供电和参考模式动态管理 EDR，不提供外接显示器式 HDR 总开关。"
                    : "该内建屏幕当前未报告扩展动态范围能力。"
            )
        } else if let externalHDRState {
            hdrSignal = SignalValue(
                text: activeLink.map { $0.identity.eotfText == "Unknown" ? "HDR 状态未知" : $0.identity.eotfText }
                    ?? (externalHDRState ? "HDR10" : "SDR"),
                verification: activeLink.map { [UInt32(0), 2, 3].contains($0.eotf) ? .slsReported : .unavailable } ?? .inferred,
                source: activeLink == nil ? "macOS 高动态范围设置" : "SkyLight 活动链路描述",
                detail: activeLink == nil
                    ? "未取得活动链路 EOTF，因此暂以 macOS HDR 开关状态表示。"
                    : "系统报告的输出状态；最终接收端状态可能不同。系统 HDR 开关另用于环境确认。"
            )
        } else {
            hdrSignal = SignalValue(
                text: "HDR 状态未知",
                verification: .unavailable,
                source: "HDR 状态来源不可用",
                detail: "未取得 macOS HDR 开关或活动链路 EOTF，不能据此断言当前为 SDR。"
            )
        }

        return DisplaySnapshot(
            id: id,
            hardwareKey: hardwareKey,
            deviceIdentity: deviceIdentity,
            name: name,
            systemName: systemName,
            isBuiltin: isBuiltin,
            isMain: CGDisplayIsMain(id) != 0,
            reportedDiagonalInches: reportedDiagonal,
            correctedDiagonalInches: correction?.diagonalInches,
            resolution: signalResolution,
            logicalResolution: "\(current.width) × \(current.height)",
            renderResolution: "\(current.pixelWidth) × \(current.pixelHeight)",
            refreshRate: SignalValue(
                text: currentModeOption?.refreshText ?? RefreshRateText.fixed(rate),
                verification: rate > 0 ? .verified : .inferred,
                source: "Core Graphics 当前输出模式",
                detail: "\(currentModeOption?.refreshRange.source ?? "Core Graphics")；timing=\(currentModeOption?.selectionKey ?? "UNAVAILABLE")；系统报告，不是物理接收端验证。"
            ),
            pixelEncoding: activeLink?.encodingSignal(activeIndex: outputState?.activeIndex)
                ?? (isBuiltin ? builtinPixelEncoding(from: encoding)
                    : SignalValue(text: "颜色格式未知", verification: .unavailable,
                        source: "SLS 报告值不可用")),
            colorGamut: colorGamut(for: screen, applePanel: applePanel),
            bitDepth: isBuiltin ? builtinBitDepth(for: current, applePanel: applePanel)
                : activeLink?.depthSignal
                    ?? SignalValue(text: "色深未知", verification: .unavailable,
                        source: "SLS 报告值不可用"),
            hdr: hdrSignal,
            vrr: SignalValue(
                text: currentVRRState.map { $0 ? "VRR 已开启" : "VRR 已关闭" } ?? "VRR 状态未知",
                verification: currentVRRState == nil ? .unavailable : .inferred,
                source: currentVRRState == nil ? "SkyLight VRR 接口不可用" : "SkyLight 显示模式标记",
                detail: currentVRRState == nil
                    ? "当前系统没有提供可用的 VRR 模式标记，不能将未知状态当作开启或关闭。"
                    : "读取当前模式的 VRR 标记；macOS 未公开最终 HDMI Forum VRR 数据包。"
            ),
            dsc: dscState.signal,
            dscEnabled: dscState.enabled,
            dscSupported: dscState.linkAvailable,
            activeOutputPreference: activeLink.flatMap { $0.encoding == nil ? nil : ($0.isRGB ? .rgbFullRange : .yCbCr) },
            activeRawPixelEncoding: activeLink?.pixelEncoding,
            activeBitDepth: activeLink.map { Int($0.bitDepth) },
            supportedBitDepths: Array(Set(compatibleLinkDescriptions.map { Int($0.bitDepth) })).sorted(),
            linkCapabilities: Array(Set(outputState?.descriptions ?? [])).sorted {
                ($0.pixelEncoding, $0.bitDepth, $0.range, $0.eotf) < ($1.pixelEncoding, $1.bitDepth, $1.range, $1.eotf)
            }.map { item in
                return DisplayLinkCapability(
                    outputPreference: item.isRGB ? .rgbFullRange : .yCbCr,
                    encodingText: item.encodingText,
                    rawPixelEncoding: item.pixelEncoding,
                    bitDepth: Int(item.bitDepth),
                    hdrEnabled: item.isHDR, rawRange: item.range, rawEOTF: item.eotf
                )
            },
            hdrEnabled: isBuiltin ? nil : systemHDREnabled,
            hdrSupported: isBuiltin ? edrAvailable : (systemHDRSupported ?? outputState?.descriptions.contains(where: \.isHDR) == true),
            vrrEnabled: currentVRRState == true,
            vrrSupported: modeOptions.contains(where: \.isVRR),
            vrrStateKnown: currentVRRState != nil,
            modes: modeOptions,
            currentModeID: current.ioDisplayModeID,
            currentModeKey: currentModeKey,
            currentConnectionIdentity: activeLink?.identity
        )
    }

    private func allModes(for id: CGDirectDisplayID) -> [DisplayModeOption] {
#if DEBUG
        if displayObservationValidationTraceEnabled {
            fputs("DISPLAY_FULL_MODE_ENUMERATION machTicks=\(mach_absolute_time()) uptime=\(ProcessInfo.processInfo.systemUptime) display=\(id)\n", stderr)
        }
#endif
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        var modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        if let current = CGDisplayCopyDisplayMode(id), !modes.contains(where: {
            DisplayModeOption.selectionKey(for: $0) == DisplayModeOption.selectionKey(for: current)
        }) { modes.append(current) }
        let usable = modes.filter { $0.isUsableForDesktopGUI() }
        let records = DisplayTimingController.shared.enumerate(displayID: id)
        guard let hardware = displayIdentityRegistry.identity(for: id)?.storageKey else { return [] }
        // Per-refresh index only: all candidates remain fresh and the original
        // full matching predicate still decides the association. No mode cache.
        let recordsByModeID = Dictionary(grouping: records, by: \.ioModeID)
        var represented = Set<UInt32>()
        var result = usable.map { mode in
            let matches = (recordsByModeID[mode.ioDisplayModeID] ?? []).filter { $0.matches(mode) }
            let record = matches.count == 1 ? matches[0] : nil
            if let record { represented.insert(record.index) }
            let output = physicalOutputTiming(for: mode, among: usable)
            return DisplayModeOption(id: mode.ioDisplayModeID, width: mode.width, height: mode.height,
                pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                outputWidth: output.width, outputHeight: output.height,
                refreshRate: mode.refreshRate, isHiDPI: mode.pixelWidth > mode.width,
                vrrState: record?.vrr, ioFlags: mode.ioFlags, mode: mode,
                displayID: id, hardwareKey: hardware, cgsIndex: record?.index,
                refreshRange: record?.range ?? ModeRefreshRange(minimum: nil, maximum: nil, source: "CGS association UNAVAILABLE"))
        }
        for record in records where !represented.contains(record.index) && record.ioFlags & 3 == 3 {
            // A real CGS mode remains a CGS mode, never a fabricated CGDisplayMode.
            // Output dimensions remain an inference unless a native flag exists.
            let native = record.ioFlags & 0x02000000 != 0
            let sameTiming = result.filter { $0.ioFlags & 0x02000000 != 0 &&
                $0.refreshRate == record.refreshRate && $0.vrrState == record.vrr }
            let output = sameTiming.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
            result.append(DisplayModeOption(id: record.ioModeID, width: record.width, height: record.height,
                pixelWidth: record.pixelWidth, pixelHeight: record.pixelHeight,
                outputWidth: native ? record.pixelWidth : (output?.pixelWidth ?? record.pixelWidth),
                outputHeight: native ? record.pixelHeight : (output?.pixelHeight ?? record.pixelHeight),
                refreshRate: record.refreshRate, isHiDPI: record.pixelWidth > record.width,
                vrrState: record.vrr, ioFlags: record.ioFlags, mode: nil,
                displayID: id, hardwareKey: hardware, cgsIndex: record.index, refreshRange: record.range))
        }
        return Array(Set(result)).sorted {
            if $0.outputWidth != $1.outputWidth { return $0.outputWidth > $1.outputWidth }
            if $0.outputHeight != $1.outputHeight { return $0.outputHeight > $1.outputHeight }
            if $0.width != $1.width { return $0.width > $1.width }
            if $0.height != $1.height { return $0.height > $1.height }
            if $0.refreshRate != $1.refreshRate { return $0.refreshRate > $1.refreshRate }
            if $0.vrrState != $1.vrrState { return $0.vrrState == false }
            return $0.selectionKey < $1.selectionKey
        }
    }

    private func currentTiming(displayID: UInt32, modes: [DisplayModeOption]) -> DisplayModeOption? {
        if let index = DisplayTimingController.shared.currentIndex(displayID: displayID) {
            let found = modes.filter { $0.cgsIndex == index }
            if found.count == 1 { return found[0] }
        }
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
        let found = modes.filter { $0.matches(mode) }
        return found.count == 1 ? found[0] : nil
    }

    private func equivalentLinkDescriptions(
        displayID: CGDirectDisplayID,
        currentMode: CGDisplayMode
    ) -> [DisplayLinkDescription] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
        let currentVRR = DisplayOutputController.shared.isVRR(
            displayID: displayID,
            modeID: currentMode.ioDisplayModeID
        )
        let modeIDs = Set(modes.filter { candidate in
            candidate.isUsableForDesktopGUI() &&
            candidate.width == currentMode.width && candidate.height == currentMode.height &&
            candidate.pixelWidth == currentMode.pixelWidth && candidate.pixelHeight == currentMode.pixelHeight &&
            (candidate.refreshRate == 0 || currentMode.refreshRate == 0 ||
             abs(candidate.refreshRate - currentMode.refreshRate) < 0.01) &&
            DisplayOutputController.shared.isVRR(
                displayID: displayID,
                modeID: candidate.ioDisplayModeID
            ) == currentVRR
        }.map(\.ioDisplayModeID)).union([currentMode.ioDisplayModeID])

        var seen = Set<DisplayLinkDescription>()
        return modeIDs.flatMap { modeID in
            DisplayOutputController.shared.state(displayID: displayID, modeID: modeID)?.descriptions ?? []
        }.filter { seen.insert($0).inserted }
    }

    private func physicalOutputTiming(
        for mode: CGDisplayMode,
        among modes: [CGDisplayMode]
    ) -> (width: Int, height: Int) {
        // kDisplayModeNativeFlag marks modes tied to the panel's native output
        // timing. Scaled HiDPI modes can use a larger offscreen framebuffer, so
        // pixelWidth/pixelHeight must not be presented as the link resolution.
        let nativeFlag: UInt32 = 0x02000000
        if (mode.ioFlags & nativeFlag) != 0 {
            return (mode.pixelWidth, mode.pixelHeight)
        }

        let sameRateNativeModes = modes.filter { candidate in
            (candidate.ioFlags & nativeFlag) != 0 &&
            (mode.refreshRate == 0 || candidate.refreshRate == 0 ||
             abs(candidate.refreshRate - mode.refreshRate) < 1)
        }
        if let timing = sameRateNativeModes.max(by: {
            ($0.pixelWidth * $0.pixelHeight) < ($1.pixelWidth * $1.pixelHeight)
        }) {
            return (timing.pixelWidth, timing.pixelHeight)
        }

        return (mode.pixelWidth, mode.pixelHeight)
    }

    private func pixelEncoding(for mode: CGDisplayMode) -> SignalValue {
        // This describes the framebuffer mode. macOS does not expose a public,
        // authoritative API for the final HDMI transport encoding.
        guard let raw = runtimePixelEncoding(for: mode) else {
            return SignalValue(text: "格式未知", verification: .unavailable, source: "Core Graphics 帧缓冲格式")
        }
        if raw.localizedCaseInsensitiveContains("RGB") {
            return SignalValue(text: "RGB", verification: .inferred, source: "Core Graphics 帧缓冲格式", detail: "这不是接收端 HDMI 信息帧的直接回报。")
        }
        if raw.localizedCaseInsensitiveContains("YCbCr") || raw.localizedCaseInsensitiveContains("YUV") {
            return SignalValue(text: "YCbCr", verification: .inferred, source: "Core Graphics 帧缓冲格式", detail: "这不是接收端 HDMI 信息帧的直接回报。")
        }
        return SignalValue(text: "格式未验证", verification: .unavailable, source: "Core Graphics 帧缓冲格式")
    }

    private func builtinPixelEncoding(from framebuffer: SignalValue) -> SignalValue {
        guard framebuffer.verification != .unavailable else { return framebuffer }
        return SignalValue(
            text: framebuffer.text == "RGB" ? "RGB（帧缓冲）" : framebuffer.text,
            verification: .inferred,
            source: "Core Graphics 内建屏幕帧缓冲",
            detail: "内建面板不存在可由 Mac 读取的 HDMI/DP 接收端色彩格式；此项描述 macOS 合成帧缓冲。"
        )
    }

    private func colorGamut(
        for screen: NSScreen?,
        applePanel: AppleBuiltinPanelSpec?
    ) -> SignalValue {
        let localizedName = screen?.colorSpace?.localizedName ?? ""
        let coreGraphicsName = screen?.colorSpace?.cgColorSpace?.name.map { $0 as String } ?? ""
        let combined = "\(localizedName) \(coreGraphicsName)".lowercased()

        if combined.contains("display p3") || combined.contains("displayp3") {
            return SignalValue(
                text: "Display P3",
                verification: .verified,
                source: "ColorSync 当前显示颜色空间",
                detail: "由 NSScreen 当前 ColorSync 颜色空间读取；自定义校色文件可能改变实际覆盖范围。"
            )
        }
        if combined.contains("srgb") {
            return SignalValue(
                text: "sRGB",
                verification: .verified,
                source: "ColorSync 当前显示颜色空间",
                detail: "由 NSScreen 当前 ColorSync 颜色空间读取。"
            )
        }
        if let applePanel {
            return SignalValue(
                text: applePanel.colorGamut,
                verification: .inferred,
                source: "Apple 内建面板规格匹配",
                detail: "按 \(applePanel.family) 原生分辨率匹配；这是面板标称色域，不是校色后的覆盖率实测。"
            )
        }
        return SignalValue(
            text: localizedName.isEmpty ? "色域未验证" : localizedName,
            verification: .unavailable,
            source: "ColorSync 当前显示颜色空间",
            detail: "当前颜色空间名称不足以确定色域覆盖率。"
        )
    }

    private func builtinBitDepth(
        for mode: CGDisplayMode,
        applePanel: AppleBuiltinPanelSpec?
    ) -> SignalValue {
        if let applePanel {
            return SignalValue(
                text: "最高 \(applePanel.maximumBitDepth) bit",
                verification: .inferred,
                source: "Apple 内建面板规格匹配",
                detail: "按 \(applePanel.family) 的十亿色能力标示面板上限；macOS 没有公开当前内屏扫描输出位深。"
            )
        }

        let raw = runtimePixelEncoding(for: mode)?.lowercased() ?? ""
        if raw.contains("30bit") {
            return SignalValue(
                text: "10 bit（帧缓冲）",
                verification: .inferred,
                source: "Core Graphics 内建屏幕帧缓冲",
                detail: "30-bit RGB 帧缓冲对应每个颜色通道 10 bit；不等同于面板链路实测。"
            )
        }
        if raw.contains("32bit") {
            return SignalValue(
                text: "8 bit（帧缓冲）",
                verification: .inferred,
                source: "Core Graphics 内建屏幕帧缓冲",
                detail: "32-bit ARGB 帧缓冲通常对应每个颜色通道 8 bit；不等同于面板能力上限。"
            )
        }
        return SignalValue(
            text: "色深未验证",
            verification: .unavailable,
            source: "macOS 未公开内建面板当前扫描位深"
        )
    }

    private func runtimePixelEncoding(for mode: CGDisplayMode) -> String? {
        // The Swift overlay deprecated `pixelEncoding`, but older and current
        // systems still export its C accessor. Resolve it dynamically so this
        // optional diagnostic does not create a deprecated-API build warning.
        typealias CopyEncoding = @convention(c) (CGDisplayMode) -> Unmanaged<CFString>?
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY
        ) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "CGDisplayModeCopyPixelEncoding") else { return nil }
        let copyEncoding = unsafeBitCast(symbol, to: CopyEncoding.self)
        return copyEncoding(mode)?.takeRetainedValue() as String?
    }

    private func outputTimingResolution(
        from modes: [DisplayModeOption],
        currentRefreshRate: Double
    ) -> String {
        // kDisplayModeNativeFlag from IOKit/graphics/IOGraphicsTypes.h.
        // A scaled HiDPI framebuffer does not carry this flag, while modes that
        // map to the display's native output timing do.
        let nativeFlag: UInt32 = 0x02000000
        var candidates = modes.filter { option in
            (option.ioFlags & nativeFlag) != 0 &&
            (currentRefreshRate == 0 || option.refreshRate == 0 || abs(option.refreshRate - currentRefreshRate) < 1)
        }
        if candidates.isEmpty {
            candidates = modes.filter { ($0.ioFlags & nativeFlag) != 0 }
        }
        guard let timing = candidates.max(by: {
            ($0.pixelWidth * $0.pixelHeight) < ($1.pixelWidth * $1.pixelHeight)
        }) else {
            return "输出时序未验证"
        }
        return "\(timing.pixelWidth) × \(timing.pixelHeight)"
    }

    private func bitDepth(from encoding: SignalValue) -> SignalValue {
        // Do not claim transport bit depth from the framebuffer encoding alone.
        SignalValue(text: "色深未验证", verification: .unavailable, source: "macOS 未公开活动链路色深")
    }

    private func dscStatus(
        displayID: CGDirectDisplayID,
        mode: DisplayModeOption?,
        modes: [DisplayModeOption],
        activeLink: DisplayLinkDescription?
    ) -> (signal: SignalValue, enabled: Bool?, linkAvailable: Bool) {
        guard let mode, let activeLink else {
            return (SignalValue(text: "DSC 状态未知", verification: .unavailable, source: "显示链路信息不足"), nil, false)
        }
        let refresh = mode.refreshRate > 0
            ? mode.refreshRate
            : modes.filter {
                $0.outputWidth == mode.outputWidth && $0.outputHeight == mode.outputHeight
            }.map(\.refreshRate).max() ?? 0
        guard refresh > 0,
              let link = displayPortLink(for: displayID) else {
            return (SignalValue(text: "DSC 状态未知", verification: .unavailable, source: "IOKit 链路信息不足"), nil, false)
        }

        // RGB and YCbCr 4:4:4 both carry three full-resolution components.
        // Active-pixel bandwidth deliberately excludes blanking, making this a
        // conservative proof: if even this minimum exceeds link payload, DSC
        // must be active for the observed signal to exist.
        guard let componentMultiplier = activeLink.bandwidthComponentMultiplier else {
            return (SignalValue(text: "DSC 状态未知", verification: .unavailable, source: "像素采样格式未知", detail: "当前像素编码无法映射为可靠的未压缩带宽，不能判断 DSC。"), nil, true)
        }
        if modeRequiresDSC(mode, bitDepth: Int(activeLink.bitDepth), link: link, refreshOverride: refresh, componentMultiplier: componentMultiplier) {
            return (SignalValue(text: "DSC 已启用", verification: .inferred, source: "IOKit DP/HDMI 链路带宽推断", detail: "按当前 \(activeLink.encodingText)、\(activeLink.bitDepth) bit 与活动像素最低带宽计算，未压缩需求超过链路有效载荷，因此推断 DSC 必须启用；这不是接收端直接回报。"), true, true)
        }
        return (SignalValue(text: "DSC 未确认启用", verification: .inferred, source: "IOKit DP/HDMI 链路带宽推断", detail: "按当前 \(activeLink.encodingText) 计算可在未压缩有效载荷内传输；带宽不足以证明 DSC 已关闭。"), nil, true)
    }

    private func modeRequiresDSC(
        _ mode: DisplayModeOption,
        bitDepth: Int,
        link: (laneRate: Double, laneCount: Int),
        refreshOverride: Double? = nil,
        componentMultiplier: Double
    ) -> Bool {
        let refresh = refreshOverride ?? mode.refreshRate
        guard refresh > 0 else { return true }
        let required = Double(mode.outputWidth * mode.outputHeight) * refresh * Double(bitDepth) * componentMultiplier
        let efficiency = link.laneRate >= 10_000_000_000 ? (128.0 / 132.0) : 0.8
        let payload = link.laneRate * Double(link.laneCount) * efficiency
        return required > payload
    }

    private func displayPortLink(for displayID: CGDirectDisplayID) -> (laneRate: Double, laneCount: Int)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOPortTransportStateDisplayPort"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let model = CGDisplayModelNumber(displayID)
        var productMatchCount = 0
        var matchedLink: (laneRate: Double, laneCount: Int)?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any],
                  (properties["ProductID"] as? NSNumber)?.uint32Value == model else { continue }
            productMatchCount += 1
            guard let lanes = (properties["LaneCount"] as? NSNumber)?.intValue,
                  let frequency = linkFrequency(properties["NominalSignalingFrequenciesHz"]) else { continue }
            if matchedLink != nil { return nil }
            matchedLink = (laneRate: frequency, laneCount: lanes)
        }
        return productMatchCount == 1 ? matchedLink : nil
    }

    private func linkFrequency(_ value: Any?) -> Double? {
        if let values = value as? [NSNumber] { return values.first?.doubleValue }
        if let values = value as? NSSet { return (values.anyObject() as? NSNumber)?.doubleValue }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
