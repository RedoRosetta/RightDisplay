// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import Combine
import Darwin
import Foundation

// Export-only mapping; raw identities remain intact in the internal models/logs.
struct DiagnosticPrivacyRedactor {
    private var aliases: [String: String] = [:]
    private var serials = Set<String>()
    init(hardwareKeys: [String]) {
        for key in hardwareKeys { _ = alias(for: key) }
    }
    private mutating func alias(for key: String) -> String {
        let normalized = key.uppercased()
        if let existing = aliases[normalized] { return existing }
        var number = aliases.count + 1
        var letters = ""
        while number > 0 {
            number -= 1
            letters = String(UnicodeScalar(65 + number % 26)!) + letters
            number /= 26
        }
        let result = "Display-" + letters
        aliases[normalized] = result
        let base = key.components(separatedBy: "|")[0]
        if let part = base.split(separator: "-").last,
           let serial = UInt32(part, radix: 16), serial > 0 {
            serials.formUnion([String(serial), String(serial, radix: 16), String(format: "%08X", serial),
                              "0x" + String(serial, radix: 16)])
        }
        return result
    }
    mutating func redact(_ source: String) -> String {
        var text = source
        for key in aliases.keys.sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: key, with: aliases[key]!, options: .caseInsensitive)
        }
        // Historical log identities can belong to devices no longer connected.
        let regex = try! NSRegularExpression(pattern: #"(?i)\b[0-9a-f]{8}-[0-9a-f]{8}-[0-9a-f]{8}\b"#)
        let range = NSRange(text.startIndex..., in: text)
        let keys = regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        for key in keys {
            let replacement = alias(for: key)
            text = text.replacingOccurrences(of: key, with: replacement, options: .caseInsensitive)
        }
        // Short numeric serials can have hex forms such as A/B. Preserve the
        // anonymous labels while redacting every representation of the serial.
        let audioLabelRegex = try! NSRegularExpression(pattern: #"\bAudio-[0-9]+\b"#)
        let audioLabels = audioLabelRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        let labels = (Array(aliases.values) + Array(Set(audioLabels))).sorted(by: { $0.count > $1.count })
        let protected = labels.enumerated().map { (String(UnicodeScalar(0xF0000 + $0.offset)!), $0.element) }
        for (token, label) in protected { text = text.replacingOccurrences(of: label, with: token) }
        for serial in serials.sorted(by: { $0.count > $1.count }) {
            let pattern = "(?i)(?<![0-9a-z])" + NSRegularExpression.escapedPattern(for: serial) + "(?![0-9a-z])"
            text = text.replacingOccurrences(of: pattern, with: "[serial redacted]", options: .regularExpression)
        }
        for (token, label) in protected { text = text.replacingOccurrences(of: token, with: label) }
        return text
    }
}

struct DiagnosticEvent: Identifiable {
    let id = UUID()
    let monotonicTicks = mach_absolute_time()
    let observedAt: Date
    let subsystem: String
    let action: String
    let target: String?
    let requested: String?
    let observed: String?
    let method: String?
    let result: String?
    let error: String?
}

@MainActor
final class DiagnosticEvents: ObservableObject {
    static let shared = DiagnosticEvents()
    @Published private(set) var recent: [DiagnosticEvent] = []
    private init() {}

    static func record(
        _ subsystem: String, _ action: String, target: String? = nil,
        requested: String? = nil, observed: String? = nil,
        method: String? = nil, result: String? = nil, error: String? = nil
    ) {
        let store = shared
        let now = Date()
        store.recent.removeAll { now.timeIntervalSince($0.observedAt) > 300 }
        store.recent.append(DiagnosticEvent(observedAt: now, subsystem: subsystem,
            action: action, target: target, requested: requested, observed: observed,
            method: method, result: result, error: error))
        if store.recent.count > 180 { store.recent.removeFirst(store.recent.count - 180) }
    }

    var snapshot: [DiagnosticEvent] {
        recent.filter { Date().timeIntervalSince($0.observedAt) <= 300 }
    }
}

@MainActor
enum DiagnosticReportExporter {
    static func export(
        display: DisplaySnapshot,
        brightness: DisplayBrightnessStore,
        audio: AudioOutputStore,
        qmsAssessment: String
    ) -> String? {
        let panel = NSSavePanel()
        panel.title = AppLocalization.string("导出 Right Display 诊断报告")
        panel.nameFieldStringValue = AppLocalization.format("Right Display 诊断报告-%@.txt", safeFileName(display.name))
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let report = makeReport(
            display: display,
            brightness: brightness,
            audio: audio,
            qmsAssessment: qmsAssessment
        )
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return AppLocalization.format("无法写入诊断报告：%@", error.localizedDescription)
        }
    }

    private static func makeReport(
        display: DisplaySnapshot,
        brightness: DisplayBrightnessStore,
        audio: AudioOutputStore,
        qmsAssessment: String
    ) -> String {
        let hardwareParts = display.hardwareKey.split(separator: "-")
        let nonIdentifyingHardware = hardwareParts.prefix(2).joined(separator: "-")
        let currentMode = display.modes.first { $0.selectionKey == display.currentModeKey }
        let formatter = ISO8601DateFormatter()
        let appleTV = AppleTVAudioController.shared
        let store = DisplayStore.shared
        var privacy = DiagnosticPrivacyRedactor(hardwareKeys: [display.hardwareKey] + store.displays.map(\.hardwareKey))
        let displaySummaries = store.displays.map { item in
            let publicHardware = item.hardwareKey.split(separator: "-").prefix(2).joined(separator: "-")
            return "- \(item.name) | hardware=\(publicHardware) | \(item.resolution) | \(item.refreshRate.text) | encoding=\(item.pixelEncoding.text) [\(item.pixelEncoding.verificationText)] | HDR=\(item.hdr.text) [\(item.hdr.verificationText)]"
        }.joined(separator: "\n")
        let recentEvents = DiagnosticEvents.shared.snapshot.map { event in
            "- \(formatter.string(from: event.observedAt)) [\(event.subsystem)] machTicks=\(event.monotonicTicks) \(event.action) target=\(event.target ?? "—") requested=\(event.requested ?? "—") observed=\(event.observed ?? "—") method=\(event.method ?? "—") result=\(event.result ?? "—") error=\(event.error ?? "—")"
        }.joined(separator: "\n")

        func signal(_ name: String, _ value: SignalValue) -> String {
            "\(name): \(value.text) [\(value.verificationText)]\n  来源: \(value.source)\n  说明: \(value.detail.isEmpty ? "—" : value.detail)"
        }

        let availableModes = display.modes.map {
            "- \($0.outputResolutionText) | HiDPI \($0.resolutionText) | \($0.refreshText) | VRR \($0.isVRR ? "是" : "否")"
        }.joined(separator: "\n")
        let linkCapabilities = display.linkCapabilities.isEmpty
            ? "- macOS 未提供链路描述"
            : display.linkCapabilities.map {
                "- \($0.encodingText) | \($0.bitDepth) bit | \($0.hdrEnabled ? "HDR" : "SDR") | \($0.identity?.detail ?? "incomplete identity / legacy unknown")"
            }.joined(separator: "\n")
        let slsState = DisplayOutputController.shared.state(displayID: display.id, modeID: display.currentModeID)
        let slsEvidence = slsState.map { state in
            "source=SLSGetDisplayOutputModeLinkDescriptions; displayID=\(display.id); modeID=\(display.currentModeID); activeIndex=\(state.activeIndex)\nSLS-reported active: \(state.activeDescription?.identity.detail ?? "UNAVAILABLE")\n" +
            state.descriptions.enumerated().map { "candidate[\($0.offset)]: \($0.element.identity.detail)" }.joined(separator: "\n")
        } ?? "SLS descriptions UNAVAILABLE"
        let interfaceName = DisplayStore.shared.selectedInterfaceName
        let profile = Preferences.shared.capabilityProfile(
            for: display.hardwareKey,
            interfaceName: interfaceName
        )
        let validationHistory = profile.modes.isEmpty
            ? "- 尚无实际切换验证记录"
            : profile.modes.map {
                "- \($0.resolution) | \($0.refreshRate) | \($0.color.title) | \($0.bitDepth) bit | \($0.hdr ? "HDR" : "SDR") | \($0.evidence.title)"
            }.joined(separator: "\n")

        let timingEvidence = display.modes.map {
            "identity=\($0.selectionKey) rawHz=\($0.refreshRate) type=\($0.vrrState.map { $0 ? "VRR" : "FIXED" } ?? "UNKNOWN") min=\($0.refreshRange.minimum.map(String.init(describing:)) ?? "UNAVAILABLE") max=\($0.refreshRange.maximum.map(String.init(describing:)) ?? "UNAVAILABLE") source=\($0.refreshRange.source)"
        }.joined(separator: "\n")
        let capabilityEvidence = EDIDStore.shared.capabilityHardwareKey == display.hardwareKey
            ? (EDIDStore.shared.sinkCapabilityFields + EDIDStore.shared.macOSCapabilityFields)
                .map { "\($0.title): \($0.value) | \($0.detail)" }.joined(separator: "\n")
            : "UNAVAILABLE: capability snapshot belongs to a different display"

        let report = """
        Right Display 隐私诊断报告
        =========================
        生成时间: \(formatter.string(from: Date()))
        Right Display: \(RightDisplayReleaseHistory.currentVersion)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Mac 型号: \(hardwareModel())

        显示器
        ------
        匿名标识: \(display.hardwareKey)
        名称: \(display.name)
        系统名称: \(display.systemName)
        Vendor/Product: \(nonIdentifyingHardware)
        主显示器: \(display.isMain ? "是" : "否")
        内建显示器: \(display.isBuiltin ? "是" : "否")
        尺寸: \(display.sizeText)
        推定输出时序: \(display.resolution)
        HiDPI 界面: \(display.logicalResolution)
        当前模式 ID: \(currentMode?.id.description ?? "未知")

        Timing enumeration（系统模式；不是物理链路验证）
        ------------------------------------------------
        \(DisplayTimingController.shared.diagnostics[display.id] ?? "UNAVAILABLE")
        \(timingEvidence)

        EDID / macOS Capability（不是 current state）
        -------------------------------------------
        \(capabilityEvidence)

        当前信号与证据
        --------------
        \(signal("刷新率", display.refreshRate))
        \(signal("颜色格式", display.pixelEncoding))
        \(signal("色域", display.colorGamut))
        \(signal("色深", display.bitDepth))
        \(signal("HDR", display.hdr))
        \(signal("VRR", display.vrr))
        \(signal("DSC", display.dsc))
        QMS 评估: \(qmsAssessment)

        当前时序可用的颜色链路
        ----------------------
        candidate source: SLSGetDisplayOutputModeLinkDescriptions（不是 physical active）
        SLS_REPORTED_CURRENT: \(slsState?.slsReportedDescription?.identity.detail ?? "UNAVAILABLE")
        AUTHORITATIVE_PHYSICAL_CURRENT: UNAVAILABLE
        CONTROL_VERIFICATION: 操作后的 fresh SLS 完整 exact-match，见操作日志
        PHYSICAL_VERIFICATION: UNAVAILABLE（未由 App 直接读取）
        SLS 报告可能与人工 sink/其他工具读数不同；候选存在不证明 physical current。
        \(slsEvidence)
        \(linkCapabilities)

        显示器能力档案
        --------------
        当前接口: \(interfaceName)
        自动校正规则: \(profile.policy.title)
        \(validationHistory)

        亮度与音频路径
        --------------
        系统亮度: \(brightness.isAvailable ? "\(Int((brightness.value * 100).rounded()))%" : "不可用")
        亮度来源: \(brightness.statusText)
        音频输出: \(audio.current.name)
        音频传输: \(audio.current.transport)
        声道: \(audio.current.channels)
        采样率: \(Int(audio.current.sampleRate)) Hz
        格式: \(audio.current.format)
        CoreAudio 音量可写: \(audio.current.systemVolumeWritable ? "是" : "否")

        软件音量（独立测试路径；系统路由尚未启用）
        -----------------------------------------
        \(VirtualVolumeController.shared.diagnosticSummary)

        当前状态快照
        ------------
        Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知")
        Build: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知")
        Architecture: \(architectureName)
        当前显示器数: \(store.displays.count)
        当前显示器: \(display.name)
        当前显示器列表与证据:
        \(displaySummaries)
        显示链路确认状态: \(store.linkVerificationComplete ? "已完成当前复读" : "正在验证")
        配置保护: \(Preferences.shared.displayOutputControlsLocked ? "锁定" : "解锁")
        安全模式: \(store.safeSessionActive ? "是" : "否")
        显示事务: \(store.pendingModeConfirmation ? "待用户确认" : "无待确认事务")
        链路测试: \(store.capabilityTestStage)
        最近显示错误: \(store.lastError ?? "无")
        当前音频控制目标: \(audio.selectedControlTargetID)
        Apple TV: \(appleTV.isConnected ? "远程连接已建立" : "未连接")
        Apple TV helper: \(appleTV.helperRunning ? "进程运行中" : "未运行")
        Apple TV 音量就绪: \(appleTV.hasVolumeControl ? "可读取和调节" : "尚未就绪")
        Apple TV 音量回读: \(appleTV.volume.map { "\(Int($0.rounded()))%" } ?? "不可用")
        Apple TV 状态: \(appleTV.statusText)

        最近五分钟语义事件（最多 180 项）
        -----------------------------
        \(recentEvents.isEmpty ? "- 暂无本次运行的事件" : recentEvents)

        Apple TV 近期诊断摘录（敏感字段已排除）
        -----------------------------------
        \(recentAppleTVEvents())

        显示链路近期诊断摘录（显示器硬件标识已排除）
        -----------------------------------------
        \(recentDisplayEvents())

        可用显示模式（\(display.modes.count)）
        ----------------
        \(availableModes)

        隐私说明
        --------
        显示器标识仅使用本报告内的匿名代号；本报告不包含显示器序列号、Apple TV 配对凭据、PIN、token 或文件路径；音频 UID 使用匿名代号，不导出原值；设备名称可能由用户自定义，分享前请检查。
        """
        let audioUIDs = audio.outputs.map(\.id) + [VirtualVolumeController.shared.model.uid].compactMap { $0 }
            + (audio.selectedControlTargetID.hasPrefix("coreaudio:") ? [String(audio.selectedControlTargetID.dropFirst("coreaudio:".count))] : [])
        return privacy.redact(VirtualVolumeController.shared.redactDiagnostics(report, uids: audioUIDs))
    }

    private static func recentAppleTVEvents() -> String {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Right Display/ATV-Diagnostics.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "- 无可读取的 Apple TV 诊断摘录"
        }
        defer { try? handle.close() }
        let length = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: length > 256_000 ? length - 256_000 : 0)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        let allowed = Set(["volume.status.success", "volume.status.error", "volume.set.request",
            "volume.set.success", "volume.set.error", "volume.control_gate",
            "connection.recovery.attempt", "connection.recovery.connected",
            "connection.recovery.exhausted", "helper.terminated"])
        let lines = text.split(separator: "\n").suffix(300).compactMap { line -> String? in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let event = object["event"] as? String, allowed.contains(event) else { return nil }
            let timestamp = object["timestamp"] as? String ?? "—"
            let volume = (object["value"] as? NSNumber)?.stringValue ?? "—"
            let available = (object["can_set_volume"] as? Bool).map { $0 ? "true" : "false" } ?? "—"
            let remote = object["remote_protocol"] as? String ?? "—"
            let error = sanitizedError(object["error"] as? String)
            return "- \(timestamp) \(event) volume=\(volume) canSet=\(available) protocol=\(remote) error=\(error)"
        }
        return lines.suffix(60).joined(separator: "\n")
    }

    private static func recentDisplayEvents() -> String {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RightDisplay/LinkTest-Diagnostics.log")
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "- 无可读取的显示链路诊断摘录"
        }
        defer { try? handle.close() }
        let length = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: length > 192_000 ? length - 192_000 : 0)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        let selected = text.split(separator: "\n").suffix(250).filter { line in
            ["[UI_USER_INTENT]", "[FINAL_RESULT]", "[RESTORE_START]", "[RESTORE_RESULT]",
             "[SCHEDULER_STOP]", "[STABLE_ACTUAL]", "[SESSION_START]",
             "[TIMING_PRECHECK]", "[TIMING_READBACK]", "[TIMING_RESTORE_RESULT]"].contains { line.contains($0) }
        }
        return selected.suffix(60).map(String.init).joined(separator: "\n")
    }

    private static var architectureName: String {
        #if arch(arm64)
        "arm64"
        #else
        "other"
        #endif
    }

    private static func sanitizedError(_ source: String?) -> String {
        guard let source else { return "—" }
        let lower = source.lowercased()
        guard !["credential", "token", "secret", "pin", "password", "/users/"].contains(where: lower.contains) else {
            return "[redacted]"
        }
        let compact = String(source.prefix(160))
        return compact.replacingOccurrences(
            of: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,
            with: "[network address]", options: .regularExpression
        )
    }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "未知" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "未知" }
        return String(cString: bytes)
    }

    private static func safeFileName(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}
