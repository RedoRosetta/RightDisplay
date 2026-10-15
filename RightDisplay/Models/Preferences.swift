// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import Combine

enum HUDCorner: String, CaseIterable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeading: "左上"
        case .topTrailing: "右上"
        case .bottomLeading: "左下"
        case .bottomTrailing: "右下"
        }
    }
}

struct DisplayCorrection: Codable, Equatable {
    var alias: String
    var diagonalInches: Double?
    var role: DisplayRole? = nil
    var outputPreference: OutputPreference? = nil
}

enum DisplayRole: String, Codable, CaseIterable, Identifiable {
    case automatic, desktopMonitor, television

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "自动判断"
        case .desktopMonitor: "桌面显示器"
        case .television: "电视"
        }
    }
}

enum OutputPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case automatic, rgbFullRange, yCbCr

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "由 macOS 自动选择"
        case .rgbFullRange: "RGB"
        case .yCbCr: "YCbCr（自动采样）"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage) }
    }
    @Published var hudEnabled: Bool {
        didSet { defaults.set(hudEnabled, forKey: Keys.hudEnabled) }
    }
    @Published var clickThrough: Bool {
        didSet { defaults.set(clickThrough, forKey: Keys.clickThrough) }
    }
    @Published var hudCorner: HUDCorner {
        didSet { defaults.set(hudCorner.rawValue, forKey: Keys.hudCorner) }
    }
    @Published var hudScale: Double {
        didSet { defaults.set(hudScale, forKey: Keys.hudScale) }
    }
    @Published var hudOpacity: Double {
        didSet { defaults.set(hudOpacity, forKey: Keys.hudOpacity) }
    }
    @Published var hudDuration: Double {
        didSet { defaults.set(hudDuration, forKey: Keys.hudDuration) }
    }
    @Published var selectedDisplayID: UInt32 {
        didSet { defaults.set(Int(selectedDisplayID), forKey: Keys.selectedDisplayID) }
    }
    private(set) var automaticAuthorizationGeneration = UUID()
    @Published var autoCorrectColorOnLoginLaunch: Bool {
        didSet { automaticAuthorizationGeneration = UUID(); defaults.set(autoCorrectColorOnLoginLaunch, forKey: Keys.autoCorrectColorOnLoginLaunch) }
    }
    @Published var showPanelOnLoginLaunch: Bool {
        didSet { defaults.set(showPanelOnLoginLaunch, forKey: Keys.showPanelOnLoginLaunch) }
    }
    @Published var autoCorrectColorOnDisplayConnect: Bool {
        didSet { automaticAuthorizationGeneration = UUID(); defaults.set(autoCorrectColorOnDisplayConnect, forKey: Keys.autoCorrectColorOnDisplayConnect) }
    }
    @Published var autoCorrectColorOnWake: Bool {
        didSet { automaticAuthorizationGeneration = UUID(); defaults.set(autoCorrectColorOnWake, forKey: Keys.autoCorrectColorOnWake) }
    }
    @Published var safeModeEnabled: Bool {
        didSet { automaticAuthorizationGeneration = UUID(); defaults.set(safeModeEnabled, forKey: Keys.safeModeEnabled) }
    }
    @Published var displayOutputControlsLocked: Bool {
        didSet {
            automaticAuthorizationGeneration = UUID()
            defaults.set(displayOutputControlsLocked, forKey: Keys.displayOutputControlsLocked)
            DiagnosticEvents.record("display", "protection", result: displayOutputControlsLocked ? "locked" : "unlocked")
        }
    }
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }
    @Published var onboardingStep: Int {
        didSet { defaults.set(onboardingStep, forKey: Keys.onboardingStep) }
    }
    @Published var quickPanelShowsDisplayInfo: Bool {
        didSet { defaults.set(quickPanelShowsDisplayInfo, forKey: Keys.quickPanelShowsDisplayInfo) }
    }
    @Published var quickPanelShowsBrightness: Bool {
        didSet { defaults.set(quickPanelShowsBrightness, forKey: Keys.quickPanelShowsBrightness) }
    }
    @Published var quickPanelShowsVolume: Bool {
        didSet { defaults.set(quickPanelShowsVolume, forKey: Keys.quickPanelShowsVolume) }
    }
    @Published var quickPanelShowsColorFormat: Bool {
        didSet { defaults.set(quickPanelShowsColorFormat, forKey: Keys.quickPanelShowsColorFormat) }
    }
    @Published var quickPanelShowsBitDepth: Bool {
        didSet { defaults.set(quickPanelShowsBitDepth, forKey: Keys.quickPanelShowsBitDepth) }
    }
    @Published var quickPanelShowsHDR: Bool {
        didSet { defaults.set(quickPanelShowsHDR, forKey: Keys.quickPanelShowsHDR) }
    }
    @Published var quickPanelShowsVRR: Bool {
        didSet { defaults.set(quickPanelShowsVRR, forKey: Keys.quickPanelShowsVRR) }
    }
    @Published private(set) var migrationSummary: PreferenceMigrationSummary?
    @Published private(set) var displayCorrections: [String: DisplayCorrection] {
        didSet {
            if let data = try? JSONEncoder().encode(displayCorrections) {
                defaults.set(data, forKey: Keys.displayCorrections)
            }
        }
    }
    @Published private(set) var capabilityProfiles: [String: DisplayCapabilityProfile] {
        didSet {
            if let data = try? JSONEncoder().encode(capabilityProfiles) {
                defaults.set(data, forKey: Keys.capabilityProfiles)
            }
        }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let appLanguage = AppLocalization.preferenceKey
        static let hudEnabled = "hudEnabled"
        static let clickThrough = "clickThrough"
        static let hudCorner = "hudCorner"
        static let hudScale = "hudScale"
        static let hudOpacity = "hudOpacity"
        static let hudDuration = "hudDuration"
        static let selectedDisplayID = "selectedDisplayID"
        static let autoCorrectColorOnLoginLaunch = "autoCorrectColorOnLoginLaunch"
        static let showPanelOnLoginLaunch = "showPanelOnLoginLaunch"
        static let autoCorrectColorOnDisplayConnect = "autoCorrectColorOnDisplayConnect"
        static let autoCorrectColorOnWake = "autoCorrectColorOnWake"
        static let safeModeEnabled = "safeModeEnabled"
        static let displayOutputControlsLocked = "displayOutputControlsLocked"
        static let onboardingCompleted = "onboardingCompleted"
        static let onboardingStep = "onboardingStep"
        static let quickPanelShowsDisplayInfo = "quickPanelShowsDisplayInfo"
        static let quickPanelShowsBrightness = "quickPanelShowsBrightness"
        static let quickPanelShowsVolume = "quickPanelShowsVolume"
        static let quickPanelShowsColorFormat = "quickPanelShowsColorFormat"
        static let quickPanelShowsBitDepth = "quickPanelShowsBitDepth"
        static let quickPanelShowsHDR = "quickPanelShowsHDR"
        static let quickPanelShowsVRR = "quickPanelShowsVRR"
        static let lastAutoCorrectBootEpoch = "lastAutoCorrectBootEpoch"
        static let displayCorrections = "displayCorrections"
        static let capabilityProfiles = "capabilityProfiles"
        static let schemaVersion = "preferenceSchemaVersion"
    }

    private static let currentSchemaVersion = 4

    private init() {
        defaults.register(defaults: [
            Keys.appLanguage: AppLanguage.system.rawValue,
            Keys.hudEnabled: true,
            Keys.clickThrough: true,
            Keys.hudCorner: HUDCorner.topTrailing.rawValue,
            Keys.hudScale: 1.0,
            Keys.hudOpacity: 0.92,
            Keys.hudDuration: 5.0,
            Keys.autoCorrectColorOnLoginLaunch: false,
            Keys.showPanelOnLoginLaunch: false,
            Keys.autoCorrectColorOnDisplayConnect: false,
            Keys.autoCorrectColorOnWake: false,
            Keys.safeModeEnabled: false,
            Keys.displayOutputControlsLocked: false,
            Keys.onboardingCompleted: false,
            Keys.onboardingStep: 0,
            Keys.quickPanelShowsDisplayInfo: true,
            Keys.quickPanelShowsBrightness: true,
            Keys.quickPanelShowsVolume: true,
            Keys.quickPanelShowsColorFormat: true,
            Keys.quickPanelShowsBitDepth: true,
            Keys.quickPanelShowsHDR: true,
            Keys.quickPanelShowsVRR: true
        ])
        appLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.appLanguage) ?? "") ?? .system
        hudEnabled = defaults.bool(forKey: Keys.hudEnabled)
        clickThrough = defaults.bool(forKey: Keys.clickThrough)
        hudCorner = HUDCorner(rawValue: defaults.string(forKey: Keys.hudCorner) ?? "") ?? .topTrailing
        hudScale = defaults.double(forKey: Keys.hudScale)
        hudOpacity = defaults.double(forKey: Keys.hudOpacity)
        hudDuration = defaults.double(forKey: Keys.hudDuration)
        selectedDisplayID = UInt32(defaults.integer(forKey: Keys.selectedDisplayID))
        autoCorrectColorOnLoginLaunch = defaults.bool(forKey: Keys.autoCorrectColorOnLoginLaunch)
        showPanelOnLoginLaunch = defaults.bool(forKey: Keys.showPanelOnLoginLaunch)
        autoCorrectColorOnDisplayConnect = defaults.bool(forKey: Keys.autoCorrectColorOnDisplayConnect)
        autoCorrectColorOnWake = defaults.bool(forKey: Keys.autoCorrectColorOnWake)
        safeModeEnabled = defaults.bool(forKey: Keys.safeModeEnabled)
        displayOutputControlsLocked = defaults.bool(forKey: Keys.displayOutputControlsLocked)
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        onboardingStep = defaults.integer(forKey: Keys.onboardingStep)
        quickPanelShowsDisplayInfo = defaults.bool(forKey: Keys.quickPanelShowsDisplayInfo)
        quickPanelShowsBrightness = defaults.bool(forKey: Keys.quickPanelShowsBrightness)
        quickPanelShowsVolume = defaults.bool(forKey: Keys.quickPanelShowsVolume)
        quickPanelShowsColorFormat = defaults.bool(forKey: Keys.quickPanelShowsColorFormat)
        quickPanelShowsBitDepth = defaults.bool(forKey: Keys.quickPanelShowsBitDepth)
        quickPanelShowsHDR = defaults.bool(forKey: Keys.quickPanelShowsHDR)
        quickPanelShowsVRR = defaults.bool(forKey: Keys.quickPanelShowsVRR)
        migrationSummary = nil
        if let data = defaults.data(forKey: Keys.displayCorrections),
           let saved = try? JSONDecoder().decode([String: DisplayCorrection].self, from: data) {
            displayCorrections = saved
        } else {
            displayCorrections = [:]
        }
        if let data = defaults.data(forKey: Keys.capabilityProfiles),
           let saved = try? JSONDecoder().decode([String: DisplayCapabilityProfile].self, from: data) {
            capabilityProfiles = saved
        } else {
            capabilityProfiles = [:]
        }
        migrateIfNeeded()
    }

    func correction(for hardwareKey: String) -> DisplayCorrection? {
        displayCorrections[hardwareKey]
    }

    func setCorrection(_ correction: DisplayCorrection, for hardwareKey: String) {
        displayCorrections[hardwareKey] = correction
    }

    func removeCorrection(for hardwareKey: String) {
        displayCorrections.removeValue(forKey: hardwareKey)
    }

    func setOutputPreference(_ preference: OutputPreference, for hardwareKey: String) {
        var correction = displayCorrections[hardwareKey] ?? DisplayCorrection(
            alias: "",
            diagonalInches: nil,
            role: .automatic,
            outputPreference: .automatic
        )
        correction.outputPreference = preference
        displayCorrections[hardwareKey] = correction
    }

    func capabilityProfile(for hardwareKey: String, interfaceName: String) -> DisplayCapabilityProfile {
        let key = capabilityProfileKey(hardwareKey, interfaceName)
        var profile = capabilityProfiles[key] ?? DisplayCapabilityProfile(
            hardwareKey: hardwareKey,
            interfaceName: interfaceName,
            policy: .balanced,
            modes: [],
            lastSeen: Date()
        )
        var latest: [String: ValidatedLinkMode] = [:]
        for mode in profile.modes.sorted(by: { $0.lastChecked > $1.lastChecked }) {
            let identity = capabilityModeIdentity(mode)
            if latest[identity] == nil { latest[identity] = mode }
        }
        profile.modes = latest.values.sorted { $0.lastChecked > $1.lastChecked }
        return profile
    }

    func setCorrectionPolicy(_ policy: AutoCorrectionPolicy, for hardwareKey: String, interfaceName: String) {
        let key = capabilityProfileKey(hardwareKey, interfaceName)
        var profile = capabilityProfile(for: hardwareKey, interfaceName: interfaceName)
        profile.policy = policy
        profile.lastSeen = Date()
        capabilityProfiles[key] = profile
    }

    func recordLinkMode(_ mode: ValidatedLinkMode, for hardwareKey: String, interfaceName: String) {
        let key = capabilityProfileKey(hardwareKey, interfaceName)
        var profile = capabilityProfile(for: hardwareKey, interfaceName: interfaceName)
        let identity = capabilityModeIdentity(mode)
        profile.modes.removeAll { capabilityModeIdentity($0) == identity && $0.signature != mode.signature }
        if let index = profile.modes.firstIndex(where: { capabilityModeIdentity($0) == identity }) {
            let existing = profile.modes[index]
            let existingIsCurrentVerified = existing.evidence == .systemReadback &&
                existing.engineGeneration == CapabilityTestTiming.engineGeneration
            let incomingIsCurrentVerified = mode.evidence == .systemReadback &&
                mode.engineGeneration == CapabilityTestTiming.engineGeneration
            if incomingIsCurrentVerified || !existingIsCurrentVerified {
                profile.modes[index] = mode
            }
        } else {
            profile.modes.append(mode)
        }
        profile.modes.sort { $0.lastChecked > $1.lastChecked }
        if profile.modes.count > 80 { profile.modes.removeLast(profile.modes.count - 80) }
        profile.lastSeen = Date()
        capabilityProfiles[key] = profile
    }

    func clearCapabilityHistory(for hardwareKey: String, interfaceName: String) {
        capabilityProfiles.removeValue(forKey: capabilityProfileKey(hardwareKey, interfaceName))
    }

    func clearAutomaticCapabilityResults(
        for hardwareKey: String,
        interfaceName: String,
        engineGeneration: Int
    ) {
        let key = capabilityProfileKey(hardwareKey, interfaceName)
        guard var profile = capabilityProfiles[key] else { return }
        profile.modes.removeAll {
            $0.evidence != .userConfirmed && $0.engineGeneration == engineGeneration
        }
        profile.lastSeen = Date()
        capabilityProfiles[key] = profile
    }

    /// Returns true at most once per Mac boot. This prevents a manual relaunch
    /// later in the same login session from renegotiating the display again.
    func claimLoginLaunchAutoCorrection() -> Bool {
        guard autoCorrectColorOnLoginLaunch, !safeModeEnabled else { return false }
        let bootEpoch = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        let previous = defaults.double(forKey: Keys.lastAutoCorrectBootEpoch)
        guard previous == 0 || abs(previous - bootEpoch) > 30 else { return false }
        defaults.set(bootEpoch, forKey: Keys.lastAutoCorrectBootEpoch)
        return true
    }

    private func capabilityProfileKey(_ hardwareKey: String, _ interfaceName: String) -> String {
        "\(hardwareKey)|\(interfaceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func capabilityModeIdentity(_ mode: ValidatedLinkMode) -> String {
        mode.deduplicationKey
    }

    private func migrateIfNeeded() {
        let oldVersion = defaults.integer(forKey: Keys.schemaVersion)
        guard oldVersion < Self.currentSchemaVersion else { return }
        let hadExistingConfiguration = defaults.object(forKey: Keys.displayCorrections) != nil ||
            defaults.object(forKey: Keys.selectedDisplayID) != nil
        var notes: [String] = []
        if oldVersion < 1 {
            notes.append("保留显示器名称、尺寸修正和原有输出偏好。")
        }
        if oldVersion < 2 {
            notes.append("为每台显示器建立独立的能力与验证记录。")
        }
        if oldVersion < 3 {
            notes.append("自动修复连接与唤醒触发项保持关闭，避免升级后擅自切换显示设置。")
            autoCorrectColorOnDisplayConnect = false
            autoCorrectColorOnWake = false
        }
        if oldVersion < 4 {
            if oldVersion > 0 {
                onboardingCompleted = true
            }
            notes.append("新增首次使用引导与快捷控制显示管理；升级用户保留现有快捷面板内容。")
        }
        defaults.set(Self.currentSchemaVersion, forKey: Keys.schemaVersion)
        if hadExistingConfiguration {
            migrationSummary = PreferenceMigrationSummary(
                fromVersion: oldVersion,
                toVersion: Self.currentSchemaVersion,
                notes: notes
            )
        }
    }
}
