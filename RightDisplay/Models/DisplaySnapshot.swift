// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import CoreGraphics

enum Verification: String, Codable, Sendable {
    case verified
    case slsReported
    case inferred
    case unavailable
}

struct SignalValue: Equatable, Sendable {
    let text: String
    let verification: Verification
    let source: String
    let detail: String

    init(
        text: String,
        verification: Verification,
        source: String = "macOS 系统读取",
        detail: String = ""
    ) {
        self.text = text
        self.verification = verification
        self.source = source
        self.detail = detail
    }

    var verificationText: String {
        switch verification {
        case .verified: "已验证"
        case .slsReported: "系统报告"
        case .inferred: "推断"
        case .unavailable: "不可验证"
        }
    }
}

// Formatting is presentation only. Never use labels or rounded Hz for mode identity.
enum RefreshRateText {
    static func number(_ rate: Double) -> String {
        guard rate.isFinite, rate > 0 else { return "未知" }
        if abs(rate - rate.rounded()) < 0.00001 { return String(format: "%.0f", rate) }
        return String(format: "%.2f", rate)
    }
    static func fixed(_ rate: Double) -> String { "\(number(rate)) Hz" }
}

// A serial-less device is only identifiable within its observed attachment.
struct DisplayDeviceDescriptor: Equatable {
    let displayID: UInt32
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32?
    var hardwareKey: String { String(format: "%08X-%08X-%08X", vendor, model, serial ?? 0) }
    var persistentKey: String? { (serial ?? 0) > 0 ? hardwareKey : nil }
}

struct DisplayDeviceIdentity: Equatable {
    let descriptor: DisplayDeviceDescriptor
    let persistentKey: String?
    let session: UUID
    let attachment: UUID
    var connectionInstanceKey: String { "\(session)|\(descriptor.displayID)|\(attachment)" }
    var storageKey: String {
        persistentKey ?? "\(descriptor.hardwareKey)|session=\(session)|instance=\(attachment)"
    }
    static func uniqueReassociation(_ original: Self, among candidates: [Self]) -> UInt32? {
        let matches = candidates.filter {
            if let key = original.persistentKey { return $0.persistentKey == key }
            return $0.connectionInstanceKey == original.connectionInstanceKey
        }
        return matches.count == 1 ? matches[0].descriptor.displayID : nil
    }
}

struct DisplayIdentityRegistry {
    private let session = UUID()
    private var entries: [UInt32: DisplayDeviceIdentity] = [:]
    mutating func update(_ online: [DisplayDeviceDescriptor]) {
        let ids = Set(online.map(\.displayID))
        entries = entries.filter { ids.contains($0.key) }
        for descriptor in online {
            let duplicate = descriptor.persistentKey.map { key in online.filter { $0.persistentKey == key }.count > 1 } ?? true
            let persistent = duplicate ? nil : descriptor.persistentKey
            let old = entries[descriptor.displayID]
            let attachment = old?.descriptor == descriptor ? old!.attachment : UUID()
            entries[descriptor.displayID] = DisplayDeviceIdentity(descriptor: descriptor,
                persistentKey: persistent, session: session, attachment: attachment)
        }
    }
    mutating func invalidate(_ displayID: UInt32) { entries.removeValue(forKey: displayID) }
    func identity(for displayID: UInt32) -> DisplayDeviceIdentity? { entries[displayID] }
}

struct TimingIdentity: Hashable, Codable {
    let displayID: UInt32
    let hardwareKey: String
    let cgsIndex: UInt32?
    let ioModeID: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let rawRefreshRate: Double
    let vrr: Bool?
    let ioFlags: UInt32
    var key: String {
        "\(displayID)|\(hardwareKey)|\(cgsIndex.map(String.init) ?? "unknown")|\(ioModeID)|\(width)x\(height)|\(pixelWidth)x\(pixelHeight)|\(rawRefreshRate.bitPattern)|\(vrr.map { $0 ? "vrr" : "fixed" } ?? "unknown")|\(ioFlags)"
    }
}

// Persistence omits the connection's ephemeral displayID, never its concrete timing.
struct PersistentTimingIdentity: Hashable, Codable {
    let cgsIndex: UInt32?
    let ioModeID: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let rawRefreshRate: Double
    let vrr: Bool?
    let ioFlags: UInt32
    var key: String {
        "\(cgsIndex.map(String.init) ?? "unknown")|\(ioModeID)|\(width)x\(height)|\(pixelWidth)x\(pixelHeight)|\(rawRefreshRate.bitPattern)|\(vrr.map { $0 ? "vrr" : "fixed" } ?? "unknown")|\(ioFlags)"
    }
    init(_ timing: TimingIdentity) {
        cgsIndex = timing.cgsIndex; ioModeID = timing.ioModeID
        width = timing.width; height = timing.height
        pixelWidth = timing.pixelWidth; pixelHeight = timing.pixelHeight
        rawRefreshRate = timing.rawRefreshRate; vrr = timing.vrr; ioFlags = timing.ioFlags
    }
}

struct ModeRefreshRange: Equatable {
    let minimum: Double?
    let maximum: Double?
    let source: String
    var isComplete: Bool {
        guard let minimum, let maximum else { return false }
        return minimum.isFinite && maximum.isFinite && minimum > 0 && maximum >= minimum
    }
    var text: String {
        guard isComplete, let minimum, let maximum else { return "可变刷新率 · 范围未知" }
        return "\(RefreshRateText.number(minimum))–\(RefreshRateText.number(maximum)) Hz（VRR）"
    }
}

struct DisplayModeOption: Identifiable, Hashable {
    let id: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let outputWidth: Int
    let outputHeight: Int
    let refreshRate: Double
    let isHiDPI: Bool
    let vrrState: Bool?
    let ioFlags: UInt32
    let mode: CGDisplayMode?
    var displayID: UInt32 = 0
    var hardwareKey: String = ""
    var cgsIndex: UInt32? = nil
    var refreshRange = ModeRefreshRange(minimum: nil, maximum: nil, source: "UNAVAILABLE")

    var isVRR: Bool { vrrState == true }
    var timingIdentity: TimingIdentity {
        TimingIdentity(displayID: displayID, hardwareKey: hardwareKey, cgsIndex: cgsIndex,
            ioModeID: id, width: width, height: height, pixelWidth: pixelWidth,
            pixelHeight: pixelHeight, rawRefreshRate: refreshRate, vrr: vrrState, ioFlags: ioFlags)
    }
    static func == (lhs: DisplayModeOption, rhs: DisplayModeOption) -> Bool { lhs.timingIdentity == rhs.timingIdentity }
    func hash(into hasher: inout Hasher) { hasher.combine(timingIdentity) }
    var resolutionText: String { "\(width) × \(height)" }
    var selectionKey: String { timingIdentity.key }
    static func selectionKey(for mode: CGDisplayMode) -> String {
        "\(mode.ioDisplayModeID)-\(mode.width)x\(mode.height)-\(mode.pixelWidth)x\(mode.pixelHeight)-\(mode.refreshRate)"
    }
    func matches(_ mode: CGDisplayMode) -> Bool {
        id == mode.ioDisplayModeID && width == mode.width && height == mode.height &&
        pixelWidth == mode.pixelWidth && pixelHeight == mode.pixelHeight && refreshRate == mode.refreshRate
    }
    var outputResolutionText: String { "\(outputWidth) × \(outputHeight)" }
    var refreshText: String {
        if isVRR { return refreshRange.text }
        if vrrState == nil { return "\(RefreshRateText.fixed(refreshRate)) · 类型未知" }
        return RefreshRateText.fixed(refreshRate)
    }
    var menuText: String {
        "输出 \(outputResolutionText) · 界面 \(resolutionText)\(isHiDPI ? " HiDPI" : "") · \(refreshText)"
    }
}

// Overview presentation only; uses the current enumerated mode, never capability.
struct OverviewRefreshText {
    let value: String
    let status: String
    init(mode: DisplayModeOption?, fallbackText: String, reportedVRR: Bool?) {
        let vrr = mode?.vrrState ?? reportedVRR
        status = vrr.map { $0 ? "VRR 已启用" : "VRR 未启用" } ?? "VRR 状态未知"
        if vrr == true {
            if let range = mode?.refreshRange, range.isComplete,
               let minimum = range.minimum, let maximum = range.maximum {
                value = "\(RefreshRateText.number(minimum))–\(RefreshRateText.number(maximum)) Hz"
            } else {
                value = "范围未知"
            }
        } else {
            value = mode.map { RefreshRateText.fixed($0.refreshRate) } ?? fallbackText
        }
    }
}

// Complete connection identity. Unknown values remain raw, never normalized to
// a known encoding/range/EOTF. Display and timing IDs belong to the I/O context.
struct ConnectionIdentity: Hashable, Codable {
    let pixelEncoding: UInt32
    let depth: UInt32
    let range: UInt32
    let eotf: UInt32

    var isKnown: Bool {
        LinkPixelEncoding.isKnown(pixelEncoding) && [8, 10, 12].contains(depth) &&
            [0, 1].contains(range) && [0, 2, 3].contains(eotf)
    }
    var persistenceKey: String { "\(pixelEncoding)|\(depth)|\(range)|\(eotf)" }
    var hdrEnabled: Bool { eotf != 0 }
    var rangeText: String {
        switch range { case 0: "Limited"; case 1: "Full"; default: "Unknown" }
    }
    var eotfText: String {
        switch eotf { case 0: "SDR"; case 2: "HDR10"; case 3: "HLG"; default: "Unknown" }
    }
    var detail: String {
        "PixelEncoding=\(pixelEncoding); Depth=\(depth); Range=\(range); EOTF=\(eotf)"
    }
}

struct DisplayLinkCapability: Hashable {
    let outputPreference: OutputPreference
    let encodingText: String
    let rawPixelEncoding: UInt32
    let bitDepth: Int
    let hdrEnabled: Bool
    var rawRange: UInt32? = nil
    var rawEOTF: UInt32? = nil

    var identity: ConnectionIdentity? { desiredState.identity }

    var desiredState: DesiredLinkState {
        DesiredLinkState(
            rawPixelEncoding: rawPixelEncoding,
            bitDepth: bitDepth,
            hdrEnabled: hdrEnabled, rawRange: rawRange, rawEOTF: rawEOTF
        )
    }
}

struct DesiredLinkState: Hashable, Codable {
    let rawPixelEncoding: UInt32
    let bitDepth: Int
    let hdrEnabled: Bool
    var rawRange: UInt32? = nil
    var rawEOTF: UInt32? = nil

    var identity: ConnectionIdentity? {
        guard let rawRange, let rawEOTF, bitDepth >= 0,
              let depth = UInt32(exactly: bitDepth) else { return nil }
        return ConnectionIdentity(pixelEncoding: rawPixelEncoding, depth: depth,
                                  range: rawRange, eotf: rawEOTF)
    }

    init(rawPixelEncoding: UInt32, bitDepth: Int, hdrEnabled: Bool,
         rawRange: UInt32? = nil, rawEOTF: UInt32? = nil) {
        self.rawPixelEncoding = rawPixelEncoding
        self.bitDepth = bitDepth
        self.hdrEnabled = hdrEnabled
        self.rawRange = rawRange
        self.rawEOTF = rawEOTF
    }

    init(description: DisplayLinkDescription) {
        self.init(rawPixelEncoding: description.pixelEncoding,
                  bitDepth: Int(description.bitDepth), hdrEnabled: description.isHDR,
                  rawRange: description.range, rawEOTF: description.eotf)
    }

    func exactlyMatches(rawPixelEncoding: UInt32?, bitDepth: Int?, hdr: Bool?, systemHDR: Bool?,
                        rawRange: UInt32? = nil, rawEOTF: UInt32? = nil) -> Bool {
        guard let identity, identity.isKnown else { return false }
        return rawRange == identity.range && rawEOTF == identity.eotf &&
            rawPixelEncoding == self.rawPixelEncoding && bitDepth == self.bitDepth &&
            identity.hdrEnabled == hdrEnabled &&
            hdr == hdrEnabled && systemHDR == hdrEnabled
    }

    var encodingText: String {
        LinkPixelEncoding.title(for: rawPixelEncoding)
    }

    var capability: DisplayLinkCapability {
        DisplayLinkCapability(
            outputPreference: rawPixelEncoding == 0 ? .rgbFullRange : .yCbCr,
            encodingText: encodingText,
            rawPixelEncoding: rawPixelEncoding,
            bitDepth: bitDepth,
            hdrEnabled: hdrEnabled, rawRange: rawRange, rawEOTF: rawEOTF
        )
    }
}

enum ConnectionTargetResolver {
    // SLS-reported working state is a baseline, not physical current. Every
    // result must be a real fresh candidate; ambiguity needs explicit selection.
    static func singleField(current: ConnectionIdentity?, candidates: [DisplayLinkDescription],
                            encoding: UInt32? = nil, depth: Int? = nil) -> DesiredLinkState? {
        guard let current, current.isKnown else { return nil }
        let targetDepth: UInt32
        if let depth {
            guard let rawDepth = UInt32(exactly: depth) else { return nil }
            targetDepth = rawDepth
        } else { targetDepth = current.depth }
        var matches = Array(Set(candidates.filter {
            $0.identity.isKnown && $0.eotf == current.eotf &&
            (encoding == nil || $0.pixelEncoding == encoding) &&
            (depth == nil || $0.bitDepth == targetDepth)
        }))
        let preserved = matches.filter {
            (encoding != nil || $0.pixelEncoding == current.pixelEncoding) &&
            (depth != nil || $0.bitDepth == current.depth)
        }
        if !preserved.isEmpty { matches = preserved }
        let sameRange = matches.filter { $0.range == current.range }
        if !sameRange.isEmpty { matches = sameRange }
        guard matches.count == 1, let candidate = matches.first else { return nil }
        return DesiredLinkState(description: candidate)
    }
}

struct ConnectionVerification {
    enum Result: String { case pass = "PASS", fail = "FAIL", unavailable = "UNAVAILABLE" }
    let control: Result
    let physical: Result = .unavailable
    var requiresControlRecovery: Bool { control != .pass }

    init(target: DesiredLinkState, slsReported: DisplayLinkDescription?, systemHDR: Bool?) {
        guard let slsReported, let systemHDR else { control = .unavailable; return }
        control = target.exactlyMatches(rawPixelEncoding: slsReported.pixelEncoding,
            bitDepth: Int(slsReported.bitDepth), hdr: slsReported.isHDR, systemHDR: systemHDR,
            rawRange: slsReported.range, rawEOTF: slsReported.eotf) ? .pass : .fail
    }
}

struct TimingConnectionProtection {
    let original: ConnectionIdentity?
    let systemHDR: Bool?
    var canVerify: Bool { original?.isKnown == true && systemHDR != nil }
    func matches(_ observed: ConnectionIdentity?, systemHDR observedHDR: Bool?) -> Bool {
        canVerify && observed?.isKnown == true && original == observed && systemHDR == observedHDR
    }
    func targetExists(in candidates: [DisplayLinkDescription]) -> Bool {
        canVerify && candidates.contains { $0.identity.isKnown && $0.identity == original }
    }
}

enum AutoCorrectionStage: Equatable {
    case idle
    case inspecting
    case applying
    case verifying
    case completed
    case failed

    var title: String {
        switch self {
        case .idle: "尚未执行"
        case .inspecting: "正在检查可用链路"
        case .applying: "正在应用目标模式"
        case .verifying: "正在复读系统状态"
        case .completed: "自动校正完成"
        case .failed: "自动校正未完成"
        }
    }
}

struct AutoCorrectionPlan: Equatable {
    let current: String
    let target: String
    let explanation: String
    let canApply: Bool
}

struct AppleBuiltinPanelSpec: Sendable {
    let aspectRatioText: String
    let colorGamut: String
    let maximumBitDepth: Int
    let family: String
}

enum DisplayResolutionCatalog {
    // Recent Apple notebook panels include extra vertical pixels around the
    // camera/menu-bar area. Their usable desktop canvas retains the familiar
    // 16:10 geometry, so presenting the raw fraction (for example 756:491) is
    // technically reducible but not useful to a person.
    private static let appleBuiltinPanels: [String: AppleBuiltinPanelSpec] = [
        "3024x1964": .init(aspectRatioText: "16:10（含顶部扩展区）", colorGamut: "Display P3", maximumBitDepth: 10, family: "14 英寸 Liquid Retina XDR"),
        "3456x2234": .init(aspectRatioText: "16:10（含顶部扩展区）", colorGamut: "Display P3", maximumBitDepth: 10, family: "16 英寸 Liquid Retina XDR"),
        "2560x1664": .init(aspectRatioText: "16:10（含顶部扩展区）", colorGamut: "Display P3", maximumBitDepth: 10, family: "13 英寸 Liquid Retina"),
        "2880x1864": .init(aspectRatioText: "16:10（含顶部扩展区）", colorGamut: "Display P3", maximumBitDepth: 10, family: "15 英寸 Liquid Retina")
    ]

    // Native resolutions used by Apple notebooks, iMacs and Apple displays.
    // The table avoids exposing large reduced fractions for well-known panels.
    private static let appleAspectRatios: [String: String] = [
        "1280x800": "16:10", "1440x900": "16:10", "1680x1050": "16:10",
        "1920x1200": "16:10", "2304x1440": "16:10", "2560x1600": "16:10",
        "2880x1800": "16:10", "3072x1920": "16:10",
        "1920x1080": "16:9", "2048x1152": "16:9", "2560x1440": "16:9",
        "3840x2160": "16:9", "4096x2304": "16:9", "4480x2520": "16:9",
        "5120x2880": "16:9", "6016x3384": "16:9"
    ]

    static func appleBuiltinSpec(width: Int, height: Int) -> AppleBuiltinPanelSpec? {
        appleBuiltinPanels[key(width, height)]
    }

    static func aspectRatio(width: Int, height: Int, isBuiltin: Bool) -> String {
        guard width > 0, height > 0 else { return "未知" }
        if isBuiltin, let panel = appleBuiltinSpec(width: width, height: height) {
            return panel.aspectRatioText
        }
        if let known = appleAspectRatios[key(width, height)] { return known }

        let value = Double(width) / Double(height)
        let standards: [(String, Double)] = [
            ("1:1", 1), ("4:3", 4.0 / 3), ("3:2", 3.0 / 2),
            ("16:10", 16.0 / 10), ("16:9", 16.0 / 9),
            ("21:9", 21.0 / 9), ("32:9", 32.0 / 9)
        ]
        if let nearest = standards.min(by: { abs($0.1 - value) < abs($1.1 - value) }),
           abs(nearest.1 - value) / nearest.1 < 0.012 {
            return nearest.0
        }

        let divisor = greatestCommonDivisor(width, height)
        let numerator = width / divisor
        let denominator = height / divisor
        if numerator <= 32, denominator <= 20 {
            return "\(numerator):\(denominator)"
        }
        return String(format: "%.2f:1", value)
    }

    private static func key(_ width: Int, _ height: Int) -> String {
        "\(width)x\(height)"
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}

struct DisplaySnapshot: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let hardwareKey: String
    var deviceIdentity: DisplayDeviceIdentity? = nil
    var currentTimingIdentity: PersistentTimingIdentity? {
        let candidates = modes.filter { $0.selectionKey == currentModeKey }
        return candidates.count == 1 ? PersistentTimingIdentity(candidates[0].timingIdentity) : nil
    }

    let name: String
    let systemName: String
    let isBuiltin: Bool
    let isMain: Bool
    let reportedDiagonalInches: Double?
    let correctedDiagonalInches: Double?
    let resolution: String
    let logicalResolution: String
    let renderResolution: String
    let refreshRate: SignalValue
    let pixelEncoding: SignalValue
    let colorGamut: SignalValue
    let bitDepth: SignalValue
    let hdr: SignalValue
    let vrr: SignalValue
    let dsc: SignalValue
    let dscEnabled: Bool?
    let dscSupported: Bool
    let activeOutputPreference: OutputPreference?
    let activeRawPixelEncoding: UInt32?
    let activeBitDepth: Int?
    let supportedBitDepths: [Int]
    let linkCapabilities: [DisplayLinkCapability]
    let hdrEnabled: Bool?
    let hdrSupported: Bool
    let vrrEnabled: Bool
    let vrrSupported: Bool
    let vrrStateKnown: Bool
    let modes: [DisplayModeOption]
    let currentModeID: Int32
    let currentModeKey: String
    var currentConnectionIdentity: ConnectionIdentity? = nil

    // Identity equality of a mode deliberately excludes presentation metadata.
    // Include range/output dimensions before suppressing an unchanged UI publish.
    func hasSamePresentation(as other: DisplaySnapshot) -> Bool {
        self == other && zip(modes, other.modes).allSatisfy {
            $0.outputWidth == $1.outputWidth && $0.outputHeight == $1.outputHeight &&
                $0.isHiDPI == $1.isHiDPI && $0.refreshRange == $1.refreshRange
        }
    }

    /// Built-in HDR-capable panels are managed dynamically by macOS through
    /// EDR/reference modes; they do not expose the external-display HDR switch.
    var hdrIsSystemManaged: Bool { isBuiltin && hdrSupported }
    var hdrCanBeToggled: Bool { !isBuiltin && hdrSupported }
    var pixelFormatSignal: SignalValue {
        SignalValue(text: activeRawPixelEncoding.flatMap(LinkPixelEncoding.init(rawValue:))?.title
            ?? pixelEncoding.text, verification: pixelEncoding.verification,
            source: pixelEncoding.source, detail: pixelEncoding.detail)
    }
    var pixelFormatIndicator: DisplayStatusIndicator {
        DisplayStatusIndicator.pixelEncoding(raw: activeRawPixelEncoding,
            known: pixelEncoding.verification != .unavailable)
    }
    var hdrIndicator: DisplayStatusIndicator {
        DisplayStatusIndicator.hdr(systemManaged: hdrIsSystemManaged, supported: hdrSupported,
            enabled: hdrEnabled, known: hdr.verification != .unavailable)
    }
    var vrrIndicator: DisplayStatusIndicator {
        DisplayStatusIndicator.vrr(enabled: vrrEnabled, known: vrrStateKnown)
    }

    var headline: String {
        "\(resolution) · \(refreshRate.text)"
    }

    var sizeText: String {
        guard let size = correctedDiagonalInches ?? reportedDiagonalInches else { return "尺寸未知" }
        return String(format: "%.0f 英寸", size)
    }

    var hasIdentityCorrection: Bool {
        name != systemName || correctedDiagonalInches != nil
    }

    var signalLine: String {
        [pixelEncoding.text, colorGamut.text, bitDepth.text, hdr.text, vrr.text]
            .filter { $0 != "—" }
            .joined(separator: " · ")
    }

    var overallVerification: Verification {
        let values = [refreshRate, pixelEncoding, colorGamut, bitDepth, hdr, vrr, dsc]
        if values.contains(where: { $0.verification == .unavailable }) { return .unavailable }
        if values.contains(where: { $0.verification == .inferred }) { return .inferred }
        if values.contains(where: { $0.verification == .slsReported }) { return .slsReported }
        return .verified
    }
}
