// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation

// Read-only entry gate. Continuations use their existing operation/session tokens.
struct DisplayOperationAvailability {
    var verificationPending = false
    var confirmationPending = false
    var linkTransactionActive = false
    var linkPreparationActive = false
    var capabilityTestActive = false
    var timingChangeActive = false
    var recoveryActive = false
    var probeActive = false
    var automaticCorrectionActive = false

    var canStart: Bool {
        !verificationPending && !confirmationPending && !linkTransactionActive &&
        !linkPreparationActive && !capabilityTestActive && !timingChangeActive &&
        !recoveryActive && !probeActive && !automaticCorrectionActive
    }
}

enum AutoCorrectionPolicy: String, Codable, CaseIterable, Identifiable {
    case balanced
    case desktop
    case cinema
    case gaming
    case colorCritical

    var id: String { rawValue }
    var title: String {
        switch self {
        case .balanced: "均衡"
        case .desktop: "桌面清晰度"
        case .cinema: "HDR 影音"
        case .gaming: "高刷新游戏"
        case .colorCritical: "专业色彩"
        }
    }
    var explanation: String {
        switch self {
        case .balanced: "优先 RGB 与 10 bit，同时保持当前 HDR、VRR 和刷新率。"
        case .desktop: "优先 RGB 和完整色度，适合文字与桌面使用。"
        case .cinema: "优先 10 bit 与 HDR，链路不足时允许 YCbCr。"
        case .gaming: "优先当前高刷新率与 VRR，再选择可用的最佳颜色组合。"
        case .colorCritical: "优先 RGB、10 bit 和固定刷新率，避免未经确认的链路组合。"
        }
    }
}

enum CapabilityEvidence: String, Codable {
    case systemEnumerated
    case observedStable
    case systemReadback
    case userConfirmed
    case failed
    case unconfirmed
    case environmentUnconfirmed
    case untestable

    var title: String {
        switch self {
        case .systemEnumerated: "macOS 可选"
        case .observedStable: "环境切换后稳定观察"
        case .systemReadback: "系统复读确认"
        case .userConfirmed: "用户保留确认"
        case .failed: "验证失败"
        case .unconfirmed: "结果未确认"
        case .environmentUnconfirmed: "测试环境未确认"
        case .untestable: "系统枚举 · 无可靠主动测试路径"
        }
    }
}

enum CapabilityTestStage: Equatable {
    case idle, preparing, testing, waitingForReadback, restoring, completed, cancelled, failedSafely

    var isRunning: Bool {
        switch self {
        case .preparing, .testing, .waitingForReadback, .restoring: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .idle: "尚未开始"
        case .preparing: "正在准备测试"
        case .testing: "正在切换显示链路"
        case .waitingForReadback: "正在确认当前链路稳定"
        case .restoring: "正在恢复测试前设置"
        case .completed: "测试完成，原设置已恢复"
        case .cancelled: "测试已停止，原设置已恢复"
        case .failedSafely: "测试已安全停止"
        }
    }
}

struct CapabilityTestAttemptResult: Identifiable, Equatable {
    let id = UUID()
    let index: Int
    let passed: Bool
    let actualLink: String?
    let diagnosticReason: String?
}

struct ValidatedLinkMode: Codable, Hashable, Identifiable {
    var connectionIdentity: ConnectionIdentity? {
        guard let rawPixelEncoding, let rawRange, let rawEOTF,
              let depth = UInt32(exactly: bitDepth) else { return nil }
        return ConnectionIdentity(pixelEncoding: rawPixelEncoding, depth: depth, range: rawRange, eotf: rawEOTF)
    }
    var persistentIdentity: String? {
        guard let timingIdentity, let connectionIdentity, connectionIdentity.isKnown,
              connectionIdentity.hdrEnabled == hdr else { return nil }
        return "v2|\(timingIdentity.key)|\(connectionIdentity.persistenceKey)"
    }
    var deduplicationKey: String {
        guard let persistentIdentity else { return "incomplete-legacy|\(signature)|\(evidence.rawValue)" }
        return "\(persistentIdentity)|\(evidence == .userConfirmed ? "user" : "automatic")"
    }
    var id: String { "\(signature)|\(evidence == .userConfirmed ? "user" : "automatic")" }
    let signature: String
    var timingIdentity: PersistentTimingIdentity? = nil
    let resolution: String
    let refreshRate: String
    let color: OutputPreference
    let rawPixelEncoding: UInt32?
    var rawRange: UInt32? = nil
    var rawEOTF: UInt32? = nil
    let bitDepth: Int
    let hdr: Bool
    let resultingRawPixelEncoding: UInt32?
    let resultingBitDepth: Int?
    let resultingHDR: Bool?
    var resultingRange: UInt32? = nil
    var resultingEOTF: UInt32? = nil
    let engineGeneration: Int?
    let vrr: Bool
    let dsc: Bool?
    var evidence: CapabilityEvidence
    var lastChecked: Date
    var failureReason: String?
}

struct DisplayCapabilityProfile: Codable, Equatable {
    let hardwareKey: String
    let interfaceName: String
    var policy: AutoCorrectionPolicy
    var modes: [ValidatedLinkMode]
    var lastSeen: Date
}

struct PreferenceMigrationSummary: Equatable {
    let fromVersion: Int
    let toVersion: Int
    let notes: [String]
}

// Gate B: bounded transition history. These value types never perform display I/O.
struct LinkTransitionContext: Codable, Hashable {
    let hardwareKey: String
    let interfaceEvidence: String
    let timing: String
    var timingIdentity: PersistentTimingIdentity? = nil
    let startingActual: DisplayLinkDescription?
    let systemHDR: Bool?
    let startingStable: Bool
    let engineVersion: Int
    let systemVersion: String
}

enum LinkTransitionAction: Codable, Hashable {
    case hdr(Bool)
    case sls(DisplayLinkDescription)
}

struct LinkExecutedAction: Codable, Hashable {
    let action: LinkTransitionAction
    let accepted: Bool
}

struct LinkTransitionEvidence: Codable {
    let context: LinkTransitionContext
    let actions: [LinkExecutedAction]
    let actual: DisplayLinkDescription?
    let systemHDR: Bool?
    let desired: DesiredLinkState?
    let stable: Bool
    let exactMatch: Bool
    let source: String
    let session: UUID
    let timestamp: Date
}

struct LinkRankedPath {
    let actions: [LinkTransitionAction]
    let relevance: String
    let successes: Int
    let failures: Int
    let score: Int
}

enum LinkEvidencePlanner {
    static let engineVersion = 1

    static func exact(_ desired: DesiredLinkState, actual: DisplayLinkDescription?, hdr: Bool?) -> Bool {
        // System control confirmation is separate from physical sink proof.
        !ConnectionVerification(target: desired, slsReported: actual, systemHDR: hdr).requiresControlRecovery
    }

    static func rankedPaths(desired: DesiredLinkState, context: LinkTransitionContext,
                            descriptions: [DisplayLinkDescription], history: [LinkTransitionEvidence],
                            session: UUID) -> [LinkRankedPath] {
        let compatible = history.filter {
            $0.context.hardwareKey == context.hardwareKey && $0.context.timing == context.timing
        }
        let paths = Set(compatible.filter {
            $0.stable && exact(desired, actual: $0.actual, hdr: $0.systemHDR) &&
                !$0.actions.isEmpty && $0.actions.allSatisfy(\.accepted)
        }.map { $0.actions.map(\.action) })
        return paths.compactMap { actions in
            guard actions.count <= 5, actions.allSatisfy({ action in
                if case .sls(let probe) = action { return descriptions.contains(probe) }
                return true
            }) else { return nil }
            let observations = compatible.filter { $0.actions.map(\.action) == actions }
            let successes = observations.filter {
                $0.stable && $0.actions.allSatisfy(\.accepted) && exact(desired, actual: $0.actual, hdr: $0.systemHDR)
            }
            guard let latestSuccess = successes.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            let failures = observations.count - successes.count
            let high = latestSuccess.session == session && latestSuccess.context.startingStable &&
                latestSuccess.context.interfaceEvidence == context.interfaceEvidence &&
                latestSuccess.context.startingActual == context.startingActual &&
                latestSuccess.context.systemHDR == context.systemHDR &&
                latestSuccess.context.engineVersion == context.engineVersion &&
                latestSuccess.context.systemVersion == context.systemVersion
            let medium = latestSuccess.session == session &&
                latestSuccess.context.interfaceEvidence == context.interfaceEvidence
            let recentFailure = observations.max(by: { $0.timestamp < $1.timestamp }).map {
                !$0.stable || !exact(desired, actual: $0.actual, hdr: $0.systemHDR)
            } ?? false
            return LinkRankedPath(actions: actions, relevance: high ? "HIGH" : (medium ? "MEDIUM" : "LOW"),
                successes: successes.count, failures: failures,
                score: (high ? 100 : (medium ? 50 : 10)) + min(successes.count, 10) * 4 - failures * 8 - (recentFailure ? 25 : 0))
        }.sorted { $0.score > $1.score }
    }
}

// Phase C final: recommendations and scheduling remain pure, read-only decisions.
enum LinkEditedField {
    case encoding, bitDepth, hdr

    func preservesEdit(_ candidate: DesiredLinkState, primary: DesiredLinkState) -> Bool {
        switch self {
        case .encoding: return candidate.rawPixelEncoding == primary.rawPixelEncoding
        case .bitDepth: return candidate.bitDepth == primary.bitDepth
        case .hdr: return candidate.hdrEnabled == primary.hdrEnabled
        }
    }
}

enum LinkAlternativeSelector {
    static func best(primary: DesiredLinkState, field: LinkEditedField, context: LinkTransitionContext,
                     descriptions: [DisplayLinkDescription], history: [LinkTransitionEvidence],
                     session: UUID, confirmed: Set<DesiredLinkState>) -> DesiredLinkState? {
        let states = Set(history.compactMap { evidence -> DesiredLinkState? in
            guard evidence.stable, evidence.actions.allSatisfy(\.accepted),
                  evidence.context.hardwareKey == context.hardwareKey,
                  evidence.context.timing == context.timing,
                  evidence.context.interfaceEvidence == context.interfaceEvidence,
                  let actual = evidence.actual, evidence.systemHDR == actual.isHDR,
                  LinkPixelEncoding.isKnown(actual.pixelEncoding), [UInt32(8), 10, 12].contains(actual.bitDepth) else { return nil }
            let state = DesiredLinkState(description: actual)
            return state != primary && field.preservesEdit(state, primary: primary) ? state : nil
        })
        return states.compactMap { state -> (DesiredLinkState, Int)? in
            guard let path = LinkEvidencePlanner.rankedPaths(desired: state, context: context,
                descriptions: descriptions, history: history, session: session).first else { return nil }
            let changes = (state.rawPixelEncoding == primary.rawPixelEncoding ? 0 : 1) +
                (state.bitDepth == primary.bitDepth ? 0 : 1) + (state.hdrEnabled == primary.hdrEnabled ? 0 : 1)
            let score = (state.rawPixelEncoding == primary.rawPixelEncoding ? 10000 : 0) - changes * 1000 +
                (confirmed.contains(state) ? 200 : 0) + min(path.successes, 10) * 10 + path.score
            return (state, score)
        }.sorted { $0.1 > $1.1 }.first?.0
    }
}

struct LinkTestBudget {
    var slsActions = 0
    var environmentChanges = 0
    var noNewResults = 0
    var seen: Set<DisplayLinkDescription> = []
    let deadline: Date

    var exhausted: Bool { slsActions >= 6 && environmentChanges >= 2 }
    func shouldStop(now: Date) -> Bool { now >= deadline || noNewResults >= 3 || exhausted }
    mutating func observe(_ actual: DisplayLinkDescription?, actionCount: Int) {
        let newState = actual.map { seen.insert($0).inserted } ?? false
        if newState { noNewResults = 0 }
        else if actionCount > 0 { noNewResults += actionCount }
    }
    var progress: Int { min(95, 5 + (slsActions + environmentChanges) * 11) }
}

enum LinkTestProbeRanker {
    static func ranked(_ descriptions: [DisplayLinkDescription], context: LinkTransitionContext,
                       history: [LinkTransitionEvidence], seen: Set<DisplayLinkDescription>,
                       declaredDepths: Set<Int>) -> [DisplayLinkDescription] {
        let candidates = Set(descriptions.filter {
            LinkPixelEncoding.isKnown($0.pixelEncoding) && [UInt32(8), 10, 12].contains($0.bitDepth) &&
                ($0.pixelEncoding != 0 || $0.range == 1)
        })
        func score(_ probe: DisplayLinkDescription) -> Int {
            let evidence = history.filter { $0.context.hardwareKey == context.hardwareKey &&
                $0.context.timing == context.timing && $0.actions.contains { $0.action == .sls(probe) } }
            let novel = evidence.filter { $0.stable && $0.actual.map { !seen.contains($0) } == true }
            let relevant = novel.contains { $0.context.interfaceEvidence == context.interfaceEvidence &&
                $0.context.startingActual == context.startingActual && $0.context.systemHDR == context.systemHDR }
            return (relevant ? 120 : (novel.isEmpty ? 0 : 70)) +
                (seen.contains { $0.pixelEncoding == probe.pixelEncoding } ? 0 : 30) +
                (seen.contains { $0.bitDepth == probe.bitDepth } ? 0 : 20) +
                (declaredDepths.contains(Int(probe.bitDepth)) ? 3 : 0) + 10 -
                min(30, evidence.filter { !$0.stable }.count * 5) -
                min(20, evidence.filter { $0.actual.map { seen.contains($0) } == true }.count * 2)
        }
        return candidates.filter { score($0) > 0 }.sorted {
            if score($0) != score($1) { return score($0) > score($1) }
            return [$0.pixelEncoding, $0.bitDepth, $0.eotf, $0.range].lexicographicallyPrecedes([$1.pixelEncoding, $1.bitDepth, $1.eotf, $1.range])
        }
    }
}
