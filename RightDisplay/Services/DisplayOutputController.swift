// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import CoreGraphics
import Darwin

#if DEBUG
private let displayTimingValidationTraceEnabled = ProcessInfo.processInfo.environment["RIGHTDISPLAY_PERF_TRACE"] == "1"
#endif

func displayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    Task { @MainActor in
        if flags.contains(.removeFlag) || flags.contains(.addFlag) {
            DisplayStore.shared.displayConnectionChanged(display)
        }
        DisplayStore.shared.refresh()
    }
}

struct DisplayLinkDescription: Hashable, Codable {
    var bitDepth: UInt32 = 0
    var range: UInt32 = 0
    var eotf: UInt32 = 0
    var pixelEncoding: UInt32 = 0

    var identity: ConnectionIdentity {
        ConnectionIdentity(pixelEncoding: pixelEncoding, depth: bitDepth, range: range, eotf: eotf)
    }

    var encoding: LinkPixelEncoding? { LinkPixelEncoding(rawValue: pixelEncoding) }
    var isRGB: Bool { encoding == .rgb }
    var isFullRange: Bool { range == 1 }
    var isHDR: Bool { eotf != 0 }

    var bandwidthComponentMultiplier: Double? {
        encoding?.bandwidthComponentMultiplier
    }

    var encodingText: String {
        LinkPixelEncoding.title(for: pixelEncoding)
    }

    func matches(_ other: DisplayLinkDescription) -> Bool {
        bitDepth == other.bitDepth &&
        range == other.range &&
        eotf == other.eotf &&
        pixelEncoding == other.pixelEncoding
    }

    func satisfies(
        color: OutputPreference?,
        bitDepth requestedBitDepth: Int?,
        hdrEnabled requestedHDR: Bool?
    ) -> Bool {
        guard encoding != nil else { return false }
        if let color {
            switch color {
            case .automatic:
                break
            case .rgbFullRange:
                guard isRGB else { return false }
            case .yCbCr:
                guard !isRGB else { return false }
            }
        }
        if let requestedBitDepth, bitDepth != UInt32(requestedBitDepth) {
            return false
        }
        if let requestedHDR, isHDR != requestedHDR {
            return false
        }
        return true
    }

    var depthSignal: SignalValue {
        SignalValue(text: [8, 10, 12].contains(bitDepth) ? "\(bitDepth) bit" : "色深未知",
            verification: [8, 10, 12].contains(bitDepth) ? .slsReported : .unavailable,
            source: "SLSGetDisplayOutputModeLinkDescriptions",
            detail: "系统报告的输出状态；最终接收端状态可能不同。\(identity.detail)")
    }

    func encodingSignal(activeIndex: UInt32?) -> SignalValue {
        SignalValue(
            text: isRGB ? "RGB（\(identity.rangeText)）" : encodingText,
            verification: encoding != nil ? .slsReported : .unavailable,
            source: "SLSGetDisplayOutputModeLinkDescriptions",
            detail: "SLS-reported active description; \(identity.detail); mapped=\(encodingText); activeIndex=\(activeIndex.map(String.init) ?? "unknown")。不是 authoritative current，也不是物理 HDMI 输出验证。"
        )
    }
}

enum LinkControlIntent: Equatable {
    case automatic(preferred: DisplayLinkDescription)
    case encoding(UInt32)
    case color(OutputPreference)
    case bitDepth(Int)
    case hdr(Bool)
    case capability(DisplayLinkCapability)
    case compound(color: OutputPreference?, bitDepth: Int?, hdr: Bool?)

    var requestedColor: OutputPreference? {
        switch self {
        case .color(let color): color
        case .capability(let capability): capability.outputPreference
        case .compound(let color, _, _): color
        case .automatic, .encoding, .bitDepth, .hdr: nil
        }
    }

    var requestedBitDepth: Int? {
        switch self {
        case .bitDepth(let depth): depth
        case .capability(let capability): capability.bitDepth
        case .compound(_, let depth, _): depth
        case .automatic, .encoding, .color, .hdr: nil
        }
    }

    var requestedHDR: Bool? {
        switch self {
        case .hdr(let enabled): enabled
        case .capability(let capability): capability.hdrEnabled
        case .compound(_, _, let enabled): enabled
        case .automatic, .encoding, .color, .bitDepth: nil
        }
    }

    var preferenceToPersist: OutputPreference? {
        switch self {
        case .automatic: .automatic
        case .color(let color): color
        case .capability(let capability): capability.outputPreference
        case .compound(let color, _, _): color
        case .encoding(let raw): raw == 0 ? .rgbFullRange : .yCbCr
        case .bitDepth, .hdr: nil
        }
    }

    var forcesNegotiation: Bool {
        if case .automatic = self { return true }
        return false
    }

    var protectsCurrentHDREnvironment: Bool {
        switch self {
        case .encoding, .color: true
        default: false
        }
    }

    var protectsCurrentPixelEncoding: Bool {
        if case .bitDepth = self { return true }
        return false
    }

    var allowsVerifiedLegacyNegotiation: Bool {
        switch self {
        case .encoding(let raw):
            return raw == 0 || raw == 1 || raw == 2
        case .color(.rgbFullRange), .color(.yCbCr):
            return true
        case .bitDepth(let depth):
            return depth == 8 || depth == 10 || depth == 12
        case .capability:
            return true
        case .compound(let color, let depth, _):
            return color != .automatic && depth.map { $0 == 8 || $0 == 10 || $0 == 12 } != false
        case .automatic, .color(.automatic), .hdr:
            return false
        }
    }

    var unavailableSelectionMessage: String {
        if requestedColor == .yCbCr {
            return "这个 YCbCr 组合目前只能由 macOS 自动协商；Right Display 暂时不能可靠地强制选择它。当前输出没有改变。"
        }
        if let depth = requestedBitDepth {
            return "macOS 当前没有为 \(depth) bit 提供可验证的独立切换路径；没有发送可能改变颜色格式的请求。"
        }
        return "macOS 没有为这个组合提供可验证的切换路径，当前输出没有改变。"
    }

    var summary: String {
        switch self {
        case .automatic: return "自动协商颜色输出"
        case .encoding(let raw):
            return "切换为 \(LinkPixelEncoding.title(for: raw))"
        case .color(let color): return color == .rgbFullRange ? "切换为 RGB" : "切换为 YCbCr"
        case .bitDepth(let depth): return "切换为 \(depth) bit"
        case .hdr(let enabled): return enabled ? "开启 HDR" : "关闭 HDR"
        case .capability(let capability):
            return "\(capability.encodingText) · \(capability.bitDepth) bit · \(capability.hdrEnabled ? "HDR" : "SDR")"
        case .compound(let color, let depth, let hdr):
            return [
                color?.title,
                depth.map { "\($0) bit" },
                hdr.map { $0 ? "HDR" : "SDR" }
            ].compactMap { $0 }.joined(separator: " · ")
        }
    }

    func accepts(_ item: DisplayLinkDescription) -> Bool {
        switch self {
        case .capability(let capability):
            return capability.identity == item.identity && item.identity.isKnown &&
                item.isHDR == capability.hdrEnabled
        case .automatic:
            return true
        case .encoding(let raw):
            return item.pixelEncoding == raw && (!item.isRGB || item.isFullRange)
        case .color(let color):
            return color == .rgbFullRange ? item.isRGB : !item.isRGB
        case .bitDepth(let depth):
            return item.bitDepth == UInt32(depth)
        case .hdr(let enabled):
            return item.isHDR == enabled
        case .compound(let color, let depth, let hdr):
            return item.satisfies(color: color, bitDepth: depth, hdrEnabled: hdr)
        }
    }

    func isSatisfied(by item: DisplayLinkDescription) -> Bool {
        // Automatic mode succeeds only after the selected candidate remains
        // stable; it intentionally has no persistent color/depth constraint.
        accepts(item)
    }
}

enum LinkControlPurpose {
    case userChange
    case capabilityTest
}

struct LinkOperationContext: Equatable {
    let displayID: CGDirectDisplayID
    let hardwareKey: String
    let modeID: Int32
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let generation: UUID
}

struct LinkControlTransaction {
    let token: UUID
    let displayID: CGDirectDisplayID
    let modeID: Int32
    let intent: LinkControlIntent
    let orderedCandidates: [DisplayLinkDescription]
    var attempted: Set<DisplayLinkDescription>
    var expected: DisplayLinkDescription?
    var stableObservation: DisplayLinkDescription?
    var stableReadCount: Int
    var pollCount: Int
    let summary: String
    let joiningTransaction: Bool
    let purpose: LinkControlPurpose
    var writeAccepted: Bool
    var writeStartedAt: Date?
    var stableStartedAt: Date?
    var observationStartedAt: Date?
    var sawTarget: Bool
    var protectedHDR: Bool? = nil
    var protectedPixelEncoding: UInt32? = nil
    var finalExpectedCapability: DisplayLinkCapability? = nil
    var allowsPostSLSEnvironmentDrift = false
    var didPerformHDREnvironmentTransition = false
    var didIssueSLSSelection = false
    var hdrStateChangedAfterSLS = false
    var hdrBeforeSLS: Bool? = nil
    var didLogPostSLSReadback = false
    var didLogStableCompletion = false
    var didPerformPostSLSEnvironmentCorrection = false
    var didPerformFinalSLSConvergence = false
    var convergenceStepCount = 0
    var convergenceHistory: [String] = []
    var lastDiagnosticStateKey: String?
    var context: LinkOperationContext? = nil
    var usesEvidencePlanner = false
}

struct DisplayOutputState {
    let descriptions: [DisplayLinkDescription]
    let activeIndex: UInt32

    // SLS current is usable system evidence, distinct from physical sink proof.
    var slsReportedDescription: DisplayLinkDescription? { activeDescription }
    var authoritativeDescription: DisplayLinkDescription? { nil }
    var currentReadbackSource: String { "SLS_REPORTED: SLSGetDisplayOutputModeLinkDescriptions; PHYSICAL_CURRENT=UNAVAILABLE" }
    static let currentUnavailableMessage = "未取得完整的系统报告连接状态，未发送显示写入。"

    var activeDescription: DisplayLinkDescription? {
        guard descriptions.indices.contains(Int(activeIndex)) else { return nil }
        return descriptions[Int(activeIndex)]
    }
}

final class CoreDisplayHDRController {
    static let shared = CoreDisplayHDRController()

    private typealias SupportsHDRMode = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias IsHDRModeEnabled = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias SetHDRModeEnabled = @convention(c) (CGDirectDisplayID, Bool) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let supportsHDRMode: SupportsHDRMode?
    private let isHDRModeEnabled: IsHDRModeEnabled?
    private let setHDRModeEnabled: SetHDRModeEnabled?

    private init() {
        let framework = dlopen(
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            RTLD_LAZY | RTLD_LOCAL
        )
        handle = framework
        supportsHDRMode = Self.load("CoreDisplay_Display_SupportsHDRMode", from: framework)
        isHDRModeEnabled = Self.load("CoreDisplay_Display_IsHDRModeEnabled", from: framework)
        setHDRModeEnabled = Self.load("CoreDisplay_Display_SetHDRModeEnabled", from: framework)
    }

    func isSupported(displayID: CGDirectDisplayID) -> Bool? {
        supportsHDRMode?(displayID)
    }

    func isEnabled(displayID: CGDirectDisplayID) -> Bool? {
        isHDRModeEnabled?(displayID)
    }

    func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) -> Bool {
        guard isSupported(displayID: displayID) == true, let setHDRModeEnabled else { return false }
        setHDRModeEnabled(displayID, enabled)
        return true
    }

    private static func load<T>(_ symbol: String, from handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let pointer = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

final class DisplayOutputController {
    static let shared = DisplayOutputController()

    private typealias GetModeCount = @convention(c) (
        UInt32, Int32, UnsafeMutablePointer<UInt32>
    ) -> Int32
    private typealias GetLinkDescriptions = @convention(c) (
        UInt32, Int32, UnsafeMutableRawPointer?,
        UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>?
    ) -> Int32
    private typealias SetOutputMode = @convention(c) (UInt32, Int32, UInt32) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let getModeCount: GetModeCount?
    private let getLinkDescriptions: GetLinkDescriptions?
    private let setOutputModeFunction: SetOutputMode?

    private init() {
        let framework = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL
        )
        handle = framework
        getModeCount = Self.load("SLSGetDisplayOutputModeCount", from: framework)
        getLinkDescriptions = Self.load("SLSGetDisplayOutputModeLinkDescriptions", from: framework)
        setOutputModeFunction = Self.load("SLSSetDisplayOutputMode", from: framework)
    }

    func state(displayID: CGDirectDisplayID, modeID: Int32) -> DisplayOutputState? {
        guard let getModeCount, let getLinkDescriptions else { return nil }
        var count: UInt32 = 0
        guard getModeCount(displayID, modeID, &count) == 0, count > 0, count < 128 else {
            return nil
        }
        var descriptions = [DisplayLinkDescription](
            repeating: DisplayLinkDescription(),
            count: Int(count)
        )
        var capacity = count
        var activeIndex = UInt32.max
        let result = descriptions.withUnsafeMutableBufferPointer { buffer in
            getLinkDescriptions(
                displayID,
                modeID,
                buffer.baseAddress,
                &capacity,
                &activeIndex
            )
        }
        guard result == 0 else { return nil }
        return DisplayOutputState(
            descriptions: Array(descriptions.prefix(Int(capacity))),
            activeIndex: activeIndex
        )
    }

    func setOutputMode(displayID: CGDirectDisplayID, modeID: Int32, index: UInt32) -> Int32 {
        guard let setOutputModeFunction else { return -1 }
        return setOutputModeFunction(displayID, modeID, index)
    }

    func vrrState(displayID: CGDirectDisplayID, modeID: Int32) -> Bool? {
        DisplayTimingController.shared.vrrState(displayID: displayID, ioModeID: modeID)
    }

    func isVRR(displayID: CGDirectDisplayID, modeID: Int32) -> Bool {
        vrrState(displayID: displayID, modeID: modeID) == true
    }

    private static func load<T>(_ symbol: String, from handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let pointer = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

// CGS index and IOKit mode ID are separate namespaces. Read their association
// from each successful 212-byte description, never infer index from mode ID.
struct CGSTimingDescription {
    let index: UInt32
    let ioModeID: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let ioFlags: UInt32
    let vrr: Bool?
    let range: ModeRefreshRange
    func matches(_ mode: CGDisplayMode) -> Bool {
        ioModeID == mode.ioDisplayModeID && width == mode.width && height == mode.height &&
        pixelWidth == mode.pixelWidth && pixelHeight == mode.pixelHeight &&
        abs(refreshRate - mode.refreshRate) <= 1.0 / 65536.0
    }
}

final class DisplayTimingController {
    static let shared = DisplayTimingController()
    private typealias Count = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias Description = @convention(c) (UInt32, Int32, UnsafeMutableRawPointer, Int32) -> Int32
    private typealias Current = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias VRR = @convention(c) (UInt32, UInt32) -> Bool
    private typealias Minimum = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<Float>) -> UInt32
    private typealias Configure = @convention(c) (CGDisplayConfigRef, UInt32, UInt32) -> Int32
    private let handle: UnsafeMutableRawPointer?
    private let count: Count?
    private let description: Description?
    private let current: Current?
    private let vrr: VRR?
    private let minimum: Minimum?
    private let configure: Configure?
    private(set) var diagnostics: [UInt32: String] = [:]
    private var indexHints: [UInt32: [Int32: UInt32]] = [:]
    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
        self.handle = handle
        func load<T>(_ name: String, _ type: T.Type) -> T? {
            guard let handle, let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        count = load("CGSGetNumberOfDisplayModes", Count.self)
        description = load("CGSGetDisplayModeDescriptionOfLength", Description.self)
        current = load("CGSGetCurrentDisplayMode", Current.self)
        vrr = load("SLSIsDisplayModeVRR", VRR.self)
        minimum = load("SLSGetDisplayModeMinRefreshRate", Minimum.self)
        configure = load("CGSConfigureDisplayMode", Configure.self)
    }
    func currentIndex(displayID: UInt32) -> UInt32? {
        var index = UInt32.max
        guard current?(displayID, &index) == 0, index != .max else { return nil }
        return index
    }
    func read(displayID: UInt32, index: UInt32) -> CGSTimingDescription? {
        guard let description, index < 4096 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 512)
        let status = bytes.withUnsafeMutableBytes { description(displayID, Int32(index), $0.baseAddress!, 212) }
        guard status == 0 else { return nil }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        // Public AllRez ABI + read-only validation on this host. Reject another
        // layout/version rather than reinterpreting or truncating it.
        guard u32(0) == index, u32(184) == 212 else { return nil }
        let width = Int(u32(8)), height = Int(u32(12))
        let pixelWidth = Int(u32(200)), pixelHeight = Int(u32(204))
        let refresh = Double(u32(188)) / 65536.0
        guard width > 0, height > 0, pixelWidth >= width, pixelHeight >= height,
              pixelWidth < 65536, pixelHeight < 65536, refresh > 0, refresh < 1000 else { return nil }
#if DEBUG
        if vrr != nil && displayTimingValidationTraceEnabled { fputs("SLS_VRR_QUERY machTicks=\(mach_absolute_time()) display=\(displayID) index=\(index)\n", stderr) }
#endif
        let isVRR = vrr?(displayID, index)
        var low: Float = 0
        let statusMin = minimum?(displayID, index, &low)
        let minRate = statusMin == 0 && low.isFinite && low > 0 ? Double(low) : nil
        let range = ModeRefreshRange(minimum: isVRR == true ? minRate : nil,
            maximum: isVRR == true ? refresh : nil,
            source: "CGS index=\(index); min=SLSGetDisplayModeMinRefreshRate status=\(statusMin.map(String.init) ?? "UNAVAILABLE"); max=CGS description refreshRate 16.16")
        return CGSTimingDescription(index: index, ioModeID: Int32(bitPattern: u32(196)),
            width: width, height: height, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            refreshRate: refresh, ioFlags: u32(192), vrr: isVRR, range: range)
    }
    func enumerate(displayID: UInt32) -> [CGSTimingDescription] {
#if DEBUG
        let trace = displayTimingValidationTraceEnabled
        if trace { fputs("CGS_ENUM_START machTicks=\(mach_absolute_time()) display=\(displayID)\n", stderr) }
        defer { if trace { fputs("CGS_ENUM_END machTicks=\(mach_absolute_time()) display=\(displayID)\n", stderr) } }
#endif
        var total: UInt32 = 0
        guard count?(displayID, &total) == 0, total > 0, total < 4096 else {
            diagnostics[displayID] = "CGS enumeration UNAVAILABLE; hidden fractional timings not synthesized"
            return []
        }
        let descriptions = (0..<total).compactMap { read(displayID: displayID, index: $0) }
        let grouped = Dictionary(grouping: descriptions, by: \.ioModeID)
        indexHints[displayID] = grouped.compactMapValues { $0.count == 1 ? $0[0].index : nil }
        let fractional = descriptions.filter { $0.vrr == false && abs($0.refreshRate - $0.refreshRate.rounded()) > 0.00001 }
        diagnostics[displayID] = "CGS count=\(total) decoded=\(descriptions.count); fractional=\(fractional.count); hidden NTSC=\(fractional.isEmpty ? "UNAVAILABLE in this enumeration" : "use only enumerated identities"); no synthesized targets; VRR physical protocol=UNAVAILABLE"
        return descriptions
    }
    func vrrState(displayID: UInt32, ioModeID: Int32) -> Bool? {
        // Hints cache only an association. Every use re-reads the descriptor
        // and its VRR state; cached readback/ranges are never returned.
        if let index = indexHints[displayID]?[ioModeID],
           let fresh = read(displayID: displayID, index: index), fresh.ioModeID == ioModeID { return fresh.vrr }
        let matches = enumerate(displayID: displayID).filter { $0.ioModeID == ioModeID }
        guard matches.count == 1 else { return nil }
        return matches[0].vrr
    }
    // Only called in response to a user timing selection. The read-only probe
    // never calls this method or opens a display configuration transaction.
    func applyCGS(_ option: DisplayModeOption) -> CGError {
        guard let index = option.cgsIndex, let configure,
              let fresh = read(displayID: option.displayID, index: index),
              fresh.ioModeID == option.id, fresh.width == option.width, fresh.height == option.height,
              fresh.pixelWidth == option.pixelWidth, fresh.pixelHeight == option.pixelHeight,
              fresh.refreshRate == option.refreshRate, fresh.vrr == option.vrrState,
              fresh.ioFlags == option.ioFlags else { return .illegalArgument }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { return begin }
        let result = configure(config, option.displayID, index)
        guard result == 0 else {
            CGCancelDisplayConfiguration(config)
            return CGError(rawValue: result) ?? .failure
        }
        return CGCompleteDisplayConfiguration(config, .forSession)
    }
}
