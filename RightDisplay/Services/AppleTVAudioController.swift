// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Combine
import Foundation
import AppKit
import Network

struct AppleTVAudioDevice: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let address: String
    let model: String
    let kind: String
    let paired: Bool
    let isReachable: Bool?

    init(
        id: String,
        name: String,
        address: String,
        model: String,
        kind: String = "appletv",
        paired: Bool = false,
        isReachable: Bool? = true
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.model = model
        self.kind = kind
        self.paired = paired
        self.isReachable = isReachable
    }

    var isHomePod: Bool { kind == "homepod" || model.localizedCaseInsensitiveContains("HomePod") }
    var isOnline: Bool { isReachable == true }
    var displayName: String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModel.isEmpty,
              cleanModel != "Apple 音频设备",
              cleanModel != "正在读取设备信息" else { return cleanName }
        if cleanModel.localizedCaseInsensitiveContains(cleanName) { return cleanModel }
        if cleanName.caseInsensitiveCompare(cleanModel) == .orderedSame { return cleanModel }
        return "\(cleanName) · \(cleanModel)"
    }
}

enum HelperExitOutcome: Equatable {
    case exited, timedOut, superseded
}

@MainActor
final class AppleTVAudioController: ObservableObject {
    static let shared = AppleTVAudioController()

    @Published private(set) var devices: [AppleTVAudioDevice] = []
    @Published var selectedIdentifier: String {
        didSet {
            defaults.set(selectedIdentifier, forKey: Keys.selectedIdentifier)
            guard selectedIdentifier != oldValue else { return }
            cancelPairing()
            reconnectGeneration += 1
            reconnectTask?.cancel()
            reconnectTask = nil
            volumeTask?.cancel()
            pendingVolume = nil
            volumeWriteInFlight = false
            refreshInFlight = false
            isReconnecting = false
            isConnected = false
            canSetVolume = false
            volume = nil
            statusText = "请选择连接或配对"
            guard usageEnabled, selectedDevice?.paired == true else { return }
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    @Published private(set) var volume: Double? {
        didSet {
            if let volume { defaults.set(volume, forKey: Keys.lastObservedVolume) }
            else {
                defaults.removeObject(forKey: Keys.lastObservedVolume)
                requestedVolume = nil
            }
        }
    }
    @Published private(set) var outputDescription = "Apple TV 默认音频输出"
    @Published private(set) var requestedVolume: Double?
    @Published private(set) var isScanning = false
    @Published private(set) var isReconnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var canSetVolume = false
    var helperRunning: Bool { serviceProcess?.isRunning == true }
    var isBusy: Bool { isScanning || isReconnecting || isPairing || refreshInFlight }
    // Live capability, independent of discovery's cached pairing flag or temporary busy state.
    var hasVolumeControl: Bool { isConnected && canSetVolume && volume != nil }
    var volumeControlAvailable: Bool {
        let available = usageEnabled && hasVolumeControl && !isBusy
        let signature = "\(available)|\(usageEnabled)|\(isConnected)|\(canSetVolume)|\(volume != nil)|\(isScanning)|\(isReconnecting)|\(isPairing)|\(refreshInFlight)|\(statusText)"
        if signature != lastVolumeControlGateSignature {
            lastVolumeControlGateSignature = signature
            log("volume.control_gate", [
                "available": available,
                "usage_enabled": usageEnabled,
                "connected": isConnected,
                "can_set_volume": canSetVolume,
                "volume_available": volume != nil,
                "scanning": isScanning,
                "reconnecting": isReconnecting,
                "pairing": isPairing,
                "refresh_in_flight": refreshInFlight,
                "status": statusText,
            ])
        }
        return available
    }
    @Published private(set) var isPairing = false
    @Published private(set) var awaitsPIN = false
    @Published private(set) var statusText = "尚未连接 Apple TV" {
        didSet { defaults.set(statusText, forKey: Keys.lastStatusText) }
    }
    @Published var bindsKeyboardVolumeKeys: Bool {
        didSet {
            defaults.set(bindsKeyboardVolumeKeys, forKey: Keys.bindsKeyboardVolumeKeys)
            updateMediaKeyMonitors()
        }
    }

    private let defaults = UserDefaults.standard
    private var volumeTask: Task<Void, Never>?
    private var volumeWriteInFlight = false
    private var lastVolumeControlGateSignature: String?
    private var pendingVolume: Double?
    private var globalMediaKeyMonitor: Any?
    private var localMediaKeyMonitor: Any?
    private var pairingToken: String?
    private var pairingProtocol = "airplay"
    private var preferredProtocol: String {
        defaults.dictionary(forKey: Keys.pairingProtocols)?[selectedIdentifier] as? String ?? "auto"
    }
    private var pairingGeneration = 0
    private var serviceProcess: Process?
    private var serviceInput: Pipe?
    private var serviceOutput: Pipe?
    private var serviceBuffer = Data()
    private var serviceRequestSerial = 0
    private var serviceCompletions: [String: (HelperResult) -> Void] = [:]
    private var hasStarted = false
    @Published private(set) var refreshInFlight = false
    private var reconnectTask: Task<Void, Never>?
    private var recoveryToken: UUID?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "RightDisplay.ATVDiagnostics.Network")
    private var lastNetworkSummary: String?
    private var scanAfterRefresh = false
    @Published private var usageEnabled = false
    private let appRuntimeID = UUID().uuidString
    private var helperRuntimeID: String?
    private var helperPID: Int32?
    private var reconnectGeneration = 0

    private enum Keys {
        static let selectedIdentifier = "appleTVAudioIdentifier"
        static let pairingProtocols = "appleTVAudioPairingProtocols"
        static let bindsKeyboardVolumeKeys = "appleTVAudioBindsKeyboardVolumeKeys"
        static let cachedDevices = "appleTVAudioCachedDevices"
        static let lastObservedVolume = "appleTVAudioLastObservedVolume"
        static let lastStatusText = "appleTVAudioLastStatusText"
    }

    private init() {
        selectedIdentifier = defaults.string(forKey: Keys.selectedIdentifier) ?? ""
        bindsKeyboardVolumeKeys = defaults.bool(forKey: Keys.bindsKeyboardVolumeKeys)
        if defaults.object(forKey: Keys.lastObservedVolume) != nil {
            volume = defaults.double(forKey: Keys.lastObservedVolume)
        }
        if let data = defaults.data(forKey: Keys.cachedDevices),
           let cached = try? JSONDecoder().decode([AppleTVAudioDevice].self, from: data) {
            devices = cached.filter { !$0.isHomePod }.map {
                AppleTVAudioDevice(
                    id: $0.id,
                    name: $0.name,
                    address: $0.address,
                    model: $0.model,
                    kind: $0.kind,
                    paired: $0.paired,
                    isReachable: false
                )
            }
        } else if !selectedIdentifier.isEmpty {
            devices = [AppleTVAudioDevice(
                id: selectedIdentifier,
                name: "已配对的 Apple TV",
                address: "上次连接",
                model: "正在读取设备信息",
                paired: true
            )]
        }
        updateMediaKeyMonitors()
        log("app.controller.initialized", ["process_pid": ProcessInfo.processInfo.processIdentifier])
    }

    func start(active: Bool = true) {
        guard !hasStarted else {
            setUsageEnabled(active)
            return
        }
        hasStarted = true
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.log("mac.wake")
                self?.resume()
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.log("mac.sleep") }
        }
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.log("mac.screen_locked") }
        }
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.log("mac.screen_unlocked") }
        }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let interfaces = path.availableInterfaces
                .filter { path.usesInterfaceType($0.type) }
                .map { "\($0.type)" }
                .sorted()
                .joined(separator: ",")
            let summary = "status=\(path.status) expensive=\(path.isExpensive) constrained=\(path.isConstrained) interfaces=\(interfaces)"
            Task { @MainActor [weak self] in
                guard let self, summary != self.lastNetworkSummary else { return }
                self.lastNetworkSummary = summary
                self.log("network.path_changed", ["summary": summary])
            }
        }
        networkMonitor.start(queue: networkQueue)
        log("app.controller.started", ["usage_enabled": active])
        setUsageEnabled(active)
    }

    func setUsageEnabled(_ enabled: Bool) {
        if usageEnabled != enabled { log("usage.changed", ["enabled": enabled]) }
        usageEnabled = enabled
        if enabled {
            resume()
        } else {
            cancelPairing()
            volumeTask?.cancel()
            pendingVolume = nil
            reconnectTask?.cancel()
            reconnectTask = nil
            scanAfterRefresh = false
            if !isConnected { statusText = "未选择 Apple TV 作为音量控制目标" }
        }
    }

    func resume() {
        log("resume.requested", [
            "selected": !selectedIdentifier.isEmpty,
            "pairing": isPairing,
            "scanning": isScanning,
        ])
        guard usageEnabled, !isPairing else { return }
        // The single helper resolves this exact saved identity using its live discovery context.
        if !selectedIdentifier.isEmpty {
            scanAfterRefresh = true
            refresh()
        } else if !isScanning {
            scan()
        }
    }

    /// Drops the current pyatv connection while retaining the helper's
    /// persistent discovery context and saved pairing credentials.
    func reconnect() {
        guard !isBusy else { return }
        log("reconnect.begin", [
            "operation": "cancel pending work; close pyatv connection; retain helper discovery context; restore selected device; refresh status and volume; then scan"
        ])
        usageEnabled = true
        reconnectGeneration += 1
        let generation = reconnectGeneration
        isReconnecting = true
        reconnectTask?.cancel()
        reconnectTask = nil
        refreshInFlight = false
        volumeTask?.cancel()
        volumeTask = nil
        pendingVolume = nil
        volumeWriteInFlight = false
        scanAfterRefresh = false
        isConnected = false
        volume = nil
        guard !selectedIdentifier.isEmpty else {
            isReconnecting = false
            scan()
            return
        }
        statusText = "正在重新连接…"
        sendCommand(["action": "reconnect"]) { [weak self] result in
            guard let self, self.reconnectGeneration == generation else { return }
            self.log(result.ok ? "reconnect.connection_reset" : "reconnect.connection_reset_failed", [
                "generation": generation,
                "helper_runtime": self.helperRuntimeID ?? "unavailable",
                "error": result.error ?? "",
            ])
            guard result.ok else {
                self.isReconnecting = false
                self.statusText = result.error ?? "Apple TV 音频连接已中断"
                return
            }
            self.refresh()
        }
    }

    func scan() {
        guard !isBusy else { return }
        log("scan.requested", [
            "operation": "reuse current helper/runtime; issue scan; does not teardown pyatv connection"
        ])
        usageEnabled = true
        if refreshInFlight {
            scanAfterRefresh = true
            return
        }
        isScanning = true
        if selectedIdentifier.isEmpty {
            statusText = "正在搜索同一局域网内的 Apple TV…"
        }
        let generation = reconnectGeneration
        let cachedDevices = devices
        log("discovery.ipc.begin")
        sendCommand(["action": "scan"]) { [weak self] result in
            guard let self else { return }
            self.isScanning = false
            guard generation == self.reconnectGeneration else { return }
            self.log(result.ok ? "discovery.ipc.end" : "discovery.ipc.error", [
                "error": result.error ?? ""
            ])
            guard result.ok else {
                if !self.isConnected {
                    self.statusText = result.error ?? "Apple TV 搜索失败"
                }
                return
            }
            let discovered: [AppleTVAudioDevice] = (result.object?["devices"] as? [[String: Any]] ?? []).compactMap { item -> AppleTVAudioDevice? in
                guard let id = item["id"] as? String,
                      let name = item["name"] as? String,
                      let address = item["address"] as? String else { return nil }
                let device = AppleTVAudioDevice(
                    id: id,
                    name: name,
                    address: address,
                    model: item["model"] as? String ?? "Apple 音频设备",
                    kind: item["kind"] as? String ?? "appletv",
                    paired: item["paired"] as? Bool ?? false,
                    isReachable: true
                )
                return device.isHomePod ? nil : device
            }
            var merged = discovered
            for cached in cachedDevices where !cached.isHomePod && !merged.contains(where: { $0.id == cached.id }) {
                merged.append(AppleTVAudioDevice(
                    id: cached.id,
                    name: cached.name,
                    address: cached.address,
                    model: cached.model,
                    kind: cached.kind,
                    paired: cached.paired,
                    isReachable: false
                ))
            }
            self.devices = merged.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            self.saveDeviceCache()
            if !self.isConnected {
                self.statusText = self.devices.isEmpty
                    ? "没有发现 Apple TV，请确认设备已开机并连接同一网络。"
                    : "已找到 \(discovered.count) 台在线设备，保留 \(self.devices.count) 台已知设备"
            }
        }
    }

    func pairSelected(protocolName: String = "airplay") {
        guard !selectedIdentifier.isEmpty, !isBusy, !hasVolumeControl else { return }
        usageEnabled = true
        reconnectGeneration += 1
        pairingGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        let generation = pairingGeneration
        let identifier = selectedIdentifier
        volumeTask?.cancel()
        pairingProtocol = protocolName
        pendingVolume = nil
        // Pairing is an auxiliary task: don't erase an already working remote
        // audio session merely because the user opened pairing options. The
        // helper keeps that session alive until pairing is explicitly saved.
        isPairing = true
        awaitsPIN = false
        statusText = "正在请求 Apple TV 显示验证码…"
        sendCommand(["action": "pair_begin", "identifier": identifier, "protocol": protocolName]) { [weak self] result in
            guard let self, self.pairingGeneration == generation,
                  self.selectedIdentifier == identifier else { return }
            guard result.ok, let token = result.object?["token"] as? String else {
                self.isPairing = false
                self.statusText = result.error ?? "Apple TV 配对失败"
                return
            }
            self.pairingToken = token
            self.awaitsPIN = true
            self.statusText = "请输入电视上的四位验证码（60 秒内）"
        }
    }

    func cancelPairing() {
        guard isPairing else { return }
        pairingGeneration += 1
        pairingToken = nil
        awaitsPIN = false
        isPairing = false
        statusText = "配对已取消"
        // Serialized behind any pending begin; no credential deletion or identity migration.
        if serviceProcess?.isRunning == true {
            sendCommand(["action": "pair_cancel"]) { [weak self] _ in
                guard let self, !self.selectedIdentifier.isEmpty, self.isConnected else { return }
                self.refresh()
            }
        }
    }

    func submitPIN(_ pin: String) {
        let pin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard awaitsPIN, let token = pairingToken,
              pin.count == 4, pin.allSatisfy({ $0.isASCII && $0.isNumber }) else { return }
        let generation = pairingGeneration
        let identifier = selectedIdentifier
        awaitsPIN = false
        statusText = "正在完成 Apple TV 配对…"
        sendCommand(["action": "pair_pin", "identifier": identifier, "token": token, "pin": pin]) { [weak self] result in
            guard let self, self.pairingGeneration == generation,
                  self.selectedIdentifier == identifier else { return }
            self.isPairing = false
            self.pairingToken = nil
            if result.ok {
                var protocols = self.defaults.dictionary(forKey: Keys.pairingProtocols) ?? [:]
                protocols[identifier] = self.pairingProtocol
                self.defaults.set(protocols, forKey: Keys.pairingProtocols)
                self.devices = self.devices.map { device in
                    guard device.id == identifier else { return device }
                    return AppleTVAudioDevice(id: device.id, name: device.name, address: device.address,
                                              model: device.model, kind: device.kind, paired: true, isReachable: true)
                }
                self.saveDeviceCache()
                self.refresh()
            } else {
                self.statusText = result.error ?? "Apple TV 配对失败"
            }
        }
    }

    func refresh() {

        guard usageEnabled, !selectedIdentifier.isEmpty, !isPairing, !refreshInFlight, !isScanning else { return }
        let identifier = selectedIdentifier
        let generation = reconnectGeneration
        refreshInFlight = true
        statusText = "正在读取 Apple TV 默认音频输出…"
        sendCommand(["action": "status", "identifier": identifier, "protocol": preferredProtocol]) { [weak self] result in
            guard let self, identifier == self.selectedIdentifier,
                  generation == self.reconnectGeneration else { return }
            self.refreshInFlight = false
            self.isReconnecting = false
            guard result.ok, let object = result.object else {
                self.isConnected = false
                self.canSetVolume = false
                self.volume = nil
                self.statusText = result.error ?? "Apple TV 音频连接已中断"
                self.log("volume.status.error", ["error": result.error ?? "invalid response"])
                self.runDeferredScanIfNeeded()
                return
            }
            let remoteProtocol = object["remote_protocol"] as? String ?? "unavailable"
            self.volume = (object["volume"] as? NSNumber)?.doubleValue
            self.canSetVolume = object["can_set_volume"] as? Bool == true
            self.isConnected = remoteProtocol != "unavailable"
            if let selected = self.selectedDevice {
                self.outputDescription = "\(selected.displayName) 默认音频输出"
            }
            self.statusText = !self.isConnected
                ? "未建立 Apple TV 远程控制配对，请先完成配对"
                : self.canSetVolume && self.volume != nil
                    ? "已连接" : "当前协议未提供真实音量读数或调节"
            self.log("volume.status.success", ["can_set_volume": self.canSetVolume,
                                               "volume_available": self.volume != nil,
                                               "remote_protocol": remoteProtocol])
            self.runDeferredScanIfNeeded()
        }
    }

    private func runDeferredScanIfNeeded() {
        guard scanAfterRefresh, !isScanning else { return }
        scanAfterRefresh = false
        scan()
    }

    /// Recover an unexpectedly closed transport using the same saved identity and
    /// protocol. Each status request lets the helper replace only a closed connection.
    private func scheduleConnectionRecovery() {
        guard usageEnabled, !selectedIdentifier.isEmpty, !isPairing,
              reconnectTask == nil else { return }
        let identifier = selectedIdentifier
        let generation = reconnectGeneration
        let protocolName = preferredProtocol
        let token = UUID()
        recoveryToken = token
        reconnectTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.recoveryToken == token {
                    self.reconnectTask = nil
                    self.recoveryToken = nil
                }
            }
            for (attempt, delay) in [1, 3, 8].enumerated() {
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard let self, !Task.isCancelled, self.usageEnabled,
                      self.selectedIdentifier == identifier,
                      self.reconnectGeneration == generation,
                      self.preferredProtocol == protocolName, !self.isPairing else { return }
                // Let an existing request finish before issuing another. Do not
                // replay an unconfirmed volume write during recovery.
                let deadline = Date().addingTimeInterval(40)
                while self.isBusy || self.volumeWriteInFlight {
                    do { try await Task.sleep(for: .milliseconds(200)) }
                    catch { return }
                    guard !Task.isCancelled, self.usageEnabled,
                          self.reconnectGeneration == generation, !self.isPairing,
                          Date() < deadline else { return }
                }
                if self.isConnected { return }
                self.log("connection.recovery.attempt", ["attempt": attempt + 1,
                                                          "protocol": protocolName])
                self.refresh()
                while self.refreshInFlight {
                    do { try await Task.sleep(for: .milliseconds(200)) }
                    catch { return }
                    guard !Task.isCancelled, self.usageEnabled,
                          self.reconnectGeneration == generation,
                          Date() < deadline else { return }
                }
                if self.isConnected {
                    self.log("connection.recovery.connected", ["attempt": attempt + 1,
                        "can_set_volume": self.canSetVolume, "volume_available": self.volume != nil])
                    return
                }
            }
            self?.log("connection.recovery.exhausted", ["attempts": 3])
        }
    }

    func setVolume(_ newValue: Double) {
        guard volumeControlAvailable else { return }
        let clamped = min(100, max(0, newValue))
        requestedVolume = clamped
        pendingVolume = clamped
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(110)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.flushPendingVolume()
        }
    }

    private func flushPendingVolume() {
        guard volumeControlAvailable, !volumeWriteInFlight, let target = pendingVolume else { return }
        let generation = reconnectGeneration
        let identifier = selectedIdentifier
        pendingVolume = nil
        volumeWriteInFlight = true
        log("volume.set.request", ["value": target])
        sendCommand([
                "action": "set_volume",
                "identifier": identifier,
                "protocol": preferredProtocol,
                "value": target
        ]) { [weak self] result in
            guard let self else { return }
            guard generation == self.reconnectGeneration, identifier == self.selectedIdentifier else { return }
            self.volumeWriteInFlight = false
            if result.ok {
                self.log("volume.set.success", ["value": target])
                if self.pendingVolume == nil {
                    self.volume = (result.object?["volume"] as? NSNumber)?.doubleValue
                    self.requestedVolume = nil
                }
                self.statusText = "已连接"
                self.flushPendingVolume()
            } else {
                self.log("volume.set.error", ["error": result.error ?? "unknown"])
                self.pendingVolume = nil
                self.requestedVolume = nil
                self.statusText = result.error ?? "无法设置 Apple TV 音量"
            }
        }
    }

    func volumeUp() { adjust(command: "volume-up") }
    func volumeDown() { adjust(command: "volume-down") }

    private func adjust(command: String) {
        guard volumeControlAvailable, let volume else { return }
        setVolume(volume + (command == "volume-up" ? 4 : -4))
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    private func updateMediaKeyMonitors() {
        if let monitor = globalMediaKeyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMediaKeyMonitor { NSEvent.removeMonitor(monitor) }
        globalMediaKeyMonitor = nil
        localMediaKeyMonitor = nil
        guard bindsKeyboardVolumeKeys else { return }

        globalMediaKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleMediaKey(event) }
        }
        localMediaKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleMediaKey(event) }
            return event
        }
    }

    private func handleMediaKey(_ event: NSEvent) {
        guard event.subtype.rawValue == 8, volumeControlAvailable else { return }
        let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
        let keyState = Int((event.data1 & 0x0000FF00) >> 8)
        guard keyState == 0xA else { return }
        switch keyCode {
        case Int(NX_KEYTYPE_SOUND_UP):
            setVolume((volume ?? 0) + 4)
            NSSound(named: NSSound.Name("Tink"))?.play()
        case Int(NX_KEYTYPE_SOUND_DOWN):
            setVolume((volume ?? 0) - 4)
            NSSound(named: NSSound.Name("Tink"))?.play()
        case Int(NX_KEYTYPE_MUTE):
            setVolume(0)
            NSSound(named: NSSound.Name("Tink"))?.play()
        default:
            break
        }
    }

    private struct HelperResult {
        let ok: Bool
        let object: [String: Any]?
        let error: String?
    }

    private func sendCommand(
        _ command: [String: Any],
        completion: @escaping (HelperResult) -> Void
    ) {

        guard ensureService(), let input = serviceInput else {
            log("ipc.helper_unavailable", ["action": command["action"] ?? "unknown"])
            completion(.init(ok: false, object: nil, error: "无法启动 Apple TV 音频辅助组件"))
            return
        }
        serviceRequestSerial += 1
        let requestID = "swift-\(serviceRequestSerial)"
        var request = command
        request["request"] = requestID
        log("ipc.request", [
            "request": requestID,
            "action": command["action"] ?? "unknown",
            "helper_pid": helperPID ?? -1,
            "helper_runtime": helperRuntimeID ?? "pending",
        ])
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              var line = String(data: data, encoding: .utf8)?.data(using: .utf8) else {
            completion(.init(ok: false, object: nil, error: "无法编码 Apple TV 控制命令"))
            return
        }
        line.append(0x0A)
        serviceCompletions[requestID] = completion
        do {
            try input.fileHandleForWriting.write(contentsOf: line)
            DispatchQueue.main.asyncAfter(deadline: .now() + 35) { [weak self] in
                guard let self,
                      self.serviceCompletions.removeValue(forKey: requestID) != nil else { return }
                self.log("ipc.timeout", ["request": requestID, "action": command["action"] ?? "unknown"])
                self.stopService(error: "Apple 音频设备连接超时")
                completion(.init(ok: false, object: nil,
                                 error: "Apple 音频设备没有响应，请确认本地网络权限和设备网络状态。"))
            }
        } catch {
            log("ipc.write_error", [
                "request": requestID,
                "action": command["action"] ?? "unknown",
                "error": error.localizedDescription,
            ])
            serviceCompletions.removeValue(forKey: requestID)
            completion(.init(ok: false, object: nil, error: error.localizedDescription))
            stopService()
        }
    }

    private func ensureService() -> Bool {
        if serviceProcess?.isRunning == true { return true }
        guard let helperURL else {
            log("helper.missing")
            return false
        }
        ensureStorageDirectory()
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = helperURL
        process.arguments = baseArguments + ["serve"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        serviceProcess = process
        serviceInput = input
        serviceOutput = output
        serviceBuffer = Data()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.serviceProcess === process else { return }
                self.consumeServiceData(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self, self.serviceProcess === process else { return }
                self.log("helper.terminated", [
                    "pid": process.processIdentifier,
                    "status": process.terminationStatus,
                    "reason": process.terminationReason.rawValue,
                ])
                self.stopService(error: "Apple TV 音频连接已中断")
            }
        }
        do {
            try process.run()
            helperPID = process.processIdentifier
            log("helper.launched", ["pid": process.processIdentifier, "executable": helperURL.lastPathComponent])
            return true
        } catch {
            log("helper.launch_error", ["error": error.localizedDescription])
            stopService(error: error.localizedDescription)
            return false
        }
    }

    private func consumeServiceData(_ data: Data) {
        serviceBuffer.append(data)
        while let newline = serviceBuffer.firstIndex(of: 0x0A) {
            let line = serviceBuffer.prefix(upTo: newline)
            serviceBuffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                log("ipc.unparseable_output", ["bytes": line.count])
                continue
            }
            if object["diagnostic"] as? Bool == true {
                if let runtime = object["runtime"] as? String { helperRuntimeID = runtime }
                log("helper.event", object)
                if let event = object["event"] as? String,
                   ["pyatv.connection_lost", "pyatv.connection_closed"].contains(event),
                   object["identifier"] as? String == selectedIdentifier,
                   object["expected_close"] as? Bool != true {
                    isConnected = false
                    canSetVolume = false
                    volume = nil
                    pendingVolume = nil
                    requestedVolume = nil
                    volumeTask?.cancel()
                    statusText = "Apple TV 音频连接已中断"
                    scheduleConnectionRecovery()
                }
                continue
            }
            if object["event"] as? String == "pair_expired" {
                if let token = object["token"] as? String, token == pairingToken {
                    pairingToken = nil
                    isPairing = false
                    awaitsPIN = false
                    statusText = "验证码已过期，请重新配对"
                }
                continue
            }
            if object["event"] as? String == "volume_update" {
                if object["identifier"] as? String == selectedIdentifier, isConnected, !isPairing {
                    let remoteProtocol = object["remote_protocol"] as? String ?? "unavailable"
                    isConnected = remoteProtocol != "unavailable"
                    canSetVolume = isConnected && object["can_set_volume"] as? Bool == true
                    volume = (object["volume"] as? NSNumber)?.doubleValue
                    if !volumeWriteInFlight, pendingVolume == nil, !isBusy {
                        statusText = canSetVolume && volume != nil
                            ? "已连接" : "设备当前未提供音量读取或调节"
                    }
                }
                continue
            }
            guard
                  let requestID = object["request"] as? String,
                  let completion = serviceCompletions.removeValue(forKey: requestID) else {
                log("ipc.orphan_response", ["request": object["request"] ?? "none"])
                continue
            }
            let ok = object["ok"] as? Bool == true
            log(ok ? "ipc.response" : "ipc.response_error", [
                "request": requestID,
                "error": object["error"] ?? "",
            ])
            completion(.init(
                ok: ok,
                object: object,
                error: object["error"] as? String ?? (ok ? nil : "Apple TV 控制失败")
            ))
        }
    }

    private func stopService(error: String? = nil, terminateProcess: Bool = true) {
        serviceOutput?.fileHandleForReading.readabilityHandler = nil
        let process = serviceProcess
        log("helper.stop", [
            "pid": process?.processIdentifier ?? helperPID ?? -1,
            "running": process?.isRunning == true,
            "reason": error ?? "requested teardown",
            "pending_requests": serviceCompletions.count,
        ])
        serviceProcess = nil
        if terminateProcess, process?.isRunning == true { process?.terminate() }
        serviceInput = nil
        serviceOutput = nil
        serviceBuffer = Data()
        helperPID = nil
        helperRuntimeID = nil
        isConnected = false
        canSetVolume = false
        volume = nil
        let pending = Array(serviceCompletions.values)
        serviceCompletions.removeAll()
        if isPairing {
            pairingGeneration += 1
            pairingToken = nil
            isPairing = false
            awaitsPIN = false
            statusText = error ?? "Apple TV 音频连接已中断"
        }
        for completion in pending {
            completion(.init(ok: false, object: nil, error: error ?? "Apple TV 音频连接已中断"))
        }
    }

    /// Asks the helper to close pyatv cleanly so its sessions, sockets and
    /// asyncio runtime are released before a replacement process is launched.
    /// A bounded forced termination remains as the fallback for a wedged helper.
    private func shutdownService(completion: @escaping (HelperExitOutcome) -> Void) {
        guard serviceProcess?.isRunning == true else {
            stopService()
            completion(.exited)
            return
        }
        let process = serviceProcess
        let pid = process?.processIdentifier ?? -1
        let generation = reconnectGeneration
        sendCommand(["action": "shutdown"]) { [weak self, weak process] _ in
            guard let self else { completion(.superseded); return }
            self.waitForServiceExit(process, pid: pid, generation: generation, completion: completion)
        }
    }

    private func waitForServiceExit(
        _ process: Process?,
        pid: Int32,
        deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 3,
        forcedDeadline: TimeInterval? = nil,
        generation: Int,
        completion: @escaping (HelperExitOutcome) -> Void
    ) {
        guard reconnectGeneration == generation, serviceProcess === process,
              process?.processIdentifier == pid else {
            log("helper.shutdown.superseded", ["pid": pid])
            completion(.superseded)
            return
        }
        guard process?.isRunning == true else {
            log("helper.shutdown.finished", ["pid": pid, "forced": forcedDeadline != nil])
            stopService()
            completion(.exited)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        var finalDeadline = forcedDeadline
        if let finalDeadline, now >= finalDeadline {
            log("helper.shutdown.timeout", ["pid": pid])
            stopService(error: "Apple TV helper 未在终止期限内退出", terminateProcess: false)
            completion(.timedOut)
            return
        }
        if finalDeadline == nil, now >= deadline {
            log("helper.shutdown.force_terminate", ["pid": pid])
            process?.terminate()
            finalDeadline = now + 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { completion(.superseded); return }
            self.waitForServiceExit(process, pid: pid, deadline: deadline,
                forcedDeadline: finalDeadline, generation: generation, completion: completion)
        }
    }

    private var helperURL: URL? {
        Bundle.main.url(
            forResource: "RightDisplayAppleTVHelper",
            withExtension: nil,
            subdirectory: "AppleTVAudioHelper"
        ) ?? Bundle(for: BundleMarker.self).url(
            forResource: "RightDisplayAppleTVHelper",
            withExtension: nil,
            subdirectory: "AppleTVAudioHelper"
        )
    }

    private var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Right Display", isDirectory: true)
            .appendingPathComponent("AppleTVAudio.json")
    }

    private var baseArguments: [String] {
        ["--storage", storageURL.path, "--timeout", "8"]
    }

    private func ensureStorageDirectory() {
        try? FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    var selectedDevice: AppleTVAudioDevice? {
        devices.first(where: { $0.id == selectedIdentifier })
    }

    private func saveDeviceCache() {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: Keys.cachedDevices)
        }
    }

    private var diagnosticLogURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Right Display", isDirectory: true)
            .appendingPathComponent("ATV-Diagnostics.jsonl")
    }

    private func log(_ event: String, _ details: [String: Any] = [:]) {
        if ["volume.status.success", "volume.status.error", "volume.set.request",
            "volume.set.success", "volume.set.error", "connection.recovery.attempt",
            "connection.recovery.connected", "connection.recovery.exhausted",
            "helper.terminated"].contains(event) {
            DiagnosticEvents.record("apple-tv", event, target: "selected Apple TV",
                requested: (details["value"] as? NSNumber)?.stringValue,
                observed: event == "volume.status.success" ? (volume.map { String(Int($0.rounded())) }) : nil,
                method: "helper/pyatv", result: event.hasSuffix("error") ? "failure" : "observed")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var payload: [String: Any] = [
            "timestamp": formatter.string(from: Date()),
            "source": "RightDisplay",
            "event": event,
            "app_runtime": appRuntimeID,
            "app_pid": ProcessInfo.processInfo.processIdentifier,
        ]
        for (key, value) in details {
            payload[key] = value
        }
        guard JSONSerialization.isValidJSONObject(payload),
              var data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        let url = diagnosticLogURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
            } else {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            }
        } catch {
            NSLog("Right Display ATV diagnostics write failed: %@", error.localizedDescription)
        }
    }
}

private final class BundleMarker {}
