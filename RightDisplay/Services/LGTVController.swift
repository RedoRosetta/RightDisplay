// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Combine
import Darwin
import Foundation

enum LGTVConnectionMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }
    var title: String { self == .automatic ? "自动发现" : "手动 IP" }
}

struct LGTVDevice: Identifiable, Hashable {
    let host: String
    var name: String
    var model: String?

    var id: String { host }
    var displayName: String {
        let title = name.isEmpty ? "LG webOS TV" : name
        return model.map { "\(title) · \($0)" } ?? title
    }
}

@MainActor
final class LGTVController: ObservableObject {
    static let shared = LGTVController()

    @Published var host: String {
        didSet { defaults.set(host, forKey: Keys.host) }
    }
    @Published var connectionMode: LGTVConnectionMode {
        didSet { defaults.set(connectionMode.rawValue, forKey: Keys.connectionMode) }
    }
    @Published var selectedHost = ""
    @Published private(set) var discoveredDevices: [LGTVDevice] = []
    @Published private(set) var isDiscovering = false
    @Published private(set) var isConnected = false
    @Published private(set) var isPairing = false
    @Published private(set) var connectedHost: String?
    @Published private(set) var volume: Double = 0
    @Published private(set) var isMuted = false
    @Published private(set) var soundOutput = "unknown"
    @Published private(set) var statusText = "尚未连接 LG 电视"

    private let defaults: UserDefaults
    private var clientKeys: [String: String]
    private var session: URLSession?
    private var sessionDelegate: LGTVSessionDelegate?
    private var socket: URLSessionWebSocketTask?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var discoveryTimeoutTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var discoverySource: DispatchSourceRead?
    private let discoveryQueue = DispatchQueue(label: "com.rightdisplay.lgtv.ssdp")
    private var activeHost: String?
    private var connectionToken = UUID()
    private var isUsingSecureSocket = false
    private var retriedWithoutStoredKey = false
    private var connectAfterDiscovery = false
    private var reportedVolume: Double?
    private var requestSerial = 0

    var usesExternalARC: Bool {
        let value = soundOutput.lowercased()
        return value == "external_arc" || value.contains("earc")
    }

    var soundOutputText: String {
        switch soundOutput.lowercased() {
        case "external_arc": "ARC/eARC 外接音频"
        case "tv_speaker": "电视扬声器"
        case "external_optical": "光纤外接音频"
        case "external_speaker": "外接扬声器"
        case "bt_soundbar", "bluetooth": "蓝牙音频"
        case "lineout": "线路输出"
        case "headphone": "耳机"
        case "unknown", "": "声音输出待检测"
        default: soundOutput
        }
    }

    private enum Keys {
        static let host = "lgTVHost"
        static let legacyClientKey = "lgTVClientKey"
        static let clientKeys = "lgTVClientKeysByHost"
        static let connectionMode = "lgTVConnectionMode"
    }

    private init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        host = defaults.string(forKey: Keys.host) ?? ""
        connectionMode = LGTVConnectionMode(
            rawValue: defaults.string(forKey: Keys.connectionMode) ?? "automatic"
        ) ?? .automatic
        clientKeys = defaults.dictionary(forKey: Keys.clientKeys) as? [String: String] ?? [:]

        // Migrate the old single-TV key without losing an existing pairing.
        if !host.isEmpty,
           clientKeys[host] == nil,
           let legacyKey = defaults.string(forKey: Keys.legacyClientKey) {
            clientKeys[host] = legacyKey
            defaults.set(clientKeys, forKey: Keys.clientKeys)
        }
    }

    func resumeAutomaticConnection() {
        guard connectionMode == .automatic, !isConnected, !isPairing, !isDiscovering else { return }
        startDiscovery(connectAutomatically: true)
    }

    func startDiscovery(connectAutomatically: Bool = false) {
        stopDiscovery()
        discoveredDevices = []
        selectedHost = ""
        connectAfterDiscovery = connectAutomatically
        isDiscovering = true
        statusText = "正在局域网中搜索 LG webOS 电视…"

        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else {
            isDiscovering = false
            statusText = "无法启动局域网搜索。"
            return
        }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: discoveryQueue)
        source.setEventHandler { [weak self] in
            let messages = Self.receiveSSDPResponses(from: descriptor)
            guard !messages.isEmpty else { return }
            Task { @MainActor [weak self] in
                for message in messages { self?.handleSSDPResponse(message) }
            }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        discoverySource = source
        source.resume()

        Self.sendSSDPSearch(from: descriptor)
        discoveryQueue.asyncAfter(deadline: .now() + 1.2) {
            Self.sendSSDPSearch(from: descriptor)
        }

        discoveryTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.finishDiscovery()
        }
    }

    func stopDiscovery() {
        discoveryTimeoutTask?.cancel()
        discoveryTimeoutTask = nil
        discoverySource?.cancel()
        discoverySource = nil
        isDiscovering = false
        connectAfterDiscovery = false
    }

    func connectSelectedDevice() {
        guard !selectedHost.isEmpty else {
            statusText = "请先选择一台搜索到的电视。"
            return
        }
        connect(to: selectedHost)
    }

    func connectManualHost() {
        connectionMode = .manual
        guard let normalized = Self.normalizedHost(host) else {
            statusText = "请输入有效的电视 IP 地址。"
            return
        }
        connect(to: normalized)
    }

    // Kept for the standalone prototype view; the preference-pane UI uses the
    // explicit automatic/manual connection actions above.
    func connect() {
        connectManualHost()
    }

    func disconnect() {
        stopDiscovery()
        closeTransport()
        isConnected = false
        isPairing = false
        connectedHost = nil
        activeHost = nil
        soundOutput = "unknown"
        reportedVolume = nil
        statusText = "已断开 LG 电视"
    }

    func forgetPairingAndReconnect() {
        guard let target = activeHost ?? connectedHost ?? Self.normalizedHost(host) else {
            statusText = "请先选择电视或输入 IP 地址。"
            return
        }
        clientKeys.removeValue(forKey: target)
        defaults.set(clientKeys, forKey: Keys.clientKeys)
        retriedWithoutStoredKey = true
        connect(to: target, forcePairing: true)
    }

    func setVolume(_ newValue: Double) {
        let baseline = reportedVolume ?? volume
        let clamped = min(100, max(0, newValue.rounded()))
        volume = clamped
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(140)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            defer { self.volumeTask = nil }

            if self.usesExternalARC {
                // ARC/eARC receivers generally expose volume as relative CEC
                // key presses. Sending setVolume changes LG's internal value but
                // may never reach the downstream Apple TV/HomePod audio system.
                let current = Int((self.reportedVolume ?? baseline).rounded())
                let target = Int(clamped)
                let delta = max(-60, min(60, target - current))
                guard delta != 0 else { return }
                let uri = delta > 0 ? "ssap://audio/volumeUp" : "ssap://audio/volumeDown"
                for _ in 0..<abs(delta) {
                    guard !Task.isCancelled else { return }
                    self.sendRequest(id: self.nextRequestID("volume-step"), uri: uri)
                    do { try await Task.sleep(for: .milliseconds(95)) }
                    catch { return }
                }
                self.requestCurrentVolume()
            } else {
                self.sendRequest(
                    id: self.nextRequestID("set-volume"),
                    uri: "ssap://audio/setVolume",
                    payload: ["volume": Int(clamped)]
                )
            }
        }
    }

    func volumeUp() {
        volumeTask?.cancel()
        sendRequest(id: nextRequestID("volume-up"), uri: "ssap://audio/volumeUp")
    }

    func volumeDown() {
        volumeTask?.cancel()
        sendRequest(id: nextRequestID("volume-down"), uri: "ssap://audio/volumeDown")
    }

    func adjustVolume(by steps: Int) {
        let limitedSteps = max(-20, min(20, steps))
        guard limitedSteps != 0 else { return }
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            guard let self else { return }
            defer { self.volumeTask = nil }
            let uri = limitedSteps > 0 ? "ssap://audio/volumeUp" : "ssap://audio/volumeDown"
            for _ in 0..<abs(limitedSteps) {
                guard !Task.isCancelled else { return }
                self.sendRequest(id: self.nextRequestID("volume-step"), uri: uri)
                do { try await Task.sleep(for: .milliseconds(95)) }
                catch { return }
            }
            self.requestCurrentVolume()
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        sendRequest(id: "set-mute", uri: "ssap://audio/setMute", payload: ["mute": muted])
    }

    private func connect(to target: String, forcePairing: Bool = false) {
        guard let normalized = Self.normalizedHost(target) else {
            statusText = "电视地址无效。"
            return
        }
        stopDiscovery()
        closeTransport()
        host = normalized
        activeHost = normalized
        connectedHost = nil
        isConnected = false
        isPairing = true
        isUsingSecureSocket = false
        if !forcePairing { retriedWithoutStoredKey = false }
        openSocket(host: normalized, secure: false, forcePairing: forcePairing)
    }

    private func openSocket(host: String, secure: Bool, forcePairing: Bool) {
        closeTransport()
        let scheme = secure ? "wss" : "ws"
        let port = secure ? 3001 : 3000
        guard let url = URL(string: "\(scheme)://\(host):\(port)") else {
            handleFinalConnectionFailure("电视地址无效。")
            return
        }

        isUsingSecureSocket = secure
        let token = UUID()
        connectionToken = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        let delegate = LGTVSessionDelegate(allowedHost: host)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("null", forHTTPHeaderField: "Origin")
        let socket = session.webSocketTask(with: request)
        self.sessionDelegate = delegate
        self.session = session
        self.socket = socket
        statusText = secure ? "正在通过安全连接访问电视…" : "正在连接电视…"
        socket.resume()
        sendRegistration(on: socket, host: host, forcePairing: forcePairing)
        receiveNextMessage(from: socket, token: token)

        connectionTimeoutTask = Task { [weak self, weak socket] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, let socket, self.socket === socket,
                  self.isPairing, !self.isConnected else { return }
            self.trySecureFallbackOrFail(forcePairing: forcePairing)
        }
    }

    private func closeTransport() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        volumeTask?.cancel()
        volumeTask = nil
        let oldSocket = socket
        socket = nil
        oldSocket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        session = nil
        sessionDelegate = nil
        connectionToken = UUID()
    }

    private func trySecureFallbackOrFail(forcePairing: Bool) {
        guard let target = activeHost else { return }
        if !isUsingSecureSocket {
            openSocket(host: target, secure: true, forcePairing: forcePairing)
        } else {
            handleFinalConnectionFailure(
                "未收到电视响应。请确认电视已开机，并在 LG 设置中启用“LG Connect Apps”或“通过 Wi‑Fi 开机”。"
            )
        }
    }

    private func handleFinalConnectionFailure(_ text: String) {
        closeTransport()
        isConnected = false
        isPairing = false
        connectedHost = nil
        statusText = text
    }

    private func sendRegistration(
        on socket: URLSessionWebSocketTask,
        host: String,
        forcePairing: Bool
    ) {
        // The former custom `signed` block had no matching signature and is
        // ignored by some webOS versions. Use the current unsigned manifest
        // shape and request only the two permissions this feature needs.
        var payload: [String: Any] = [
            "forcePairing": forcePairing,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "0.2",
                "permissions": ["CONTROL_AUDIO", "READ_SETTINGS"]
            ]
        ]
        if !forcePairing, let key = clientKeys[host] { payload["client-key"] = key }
        sendJSONObject(
            ["id": "register_0", "type": "register", "payload": payload],
            on: socket
        )
    }

    private func subscribeToVolume() {
        sendJSONObject([
            "id": "volume-subscription",
            "type": "subscribe",
            "uri": "ssap://audio/getVolume",
            "payload": [:]
        ])
    }

    private func subscribeToSoundOutput() {
        sendJSONObject([
            "id": "sound-output-subscription",
            "type": "subscribe",
            "uri": "ssap://com.webos.service.apiadapter/audio/getSoundOutput",
            "payload": [:]
        ])
    }

    private func requestCurrentVolume() {
        sendRequest(id: nextRequestID("get-volume"), uri: "ssap://audio/getVolume")
    }

    private func nextRequestID(_ prefix: String) -> String {
        requestSerial += 1
        return "\(prefix)-\(requestSerial)"
    }

    private func sendRequest(id: String, uri: String, payload: [String: Any] = [:]) {
        guard isConnected else { return }
        sendJSONObject(["id": id, "type": "request", "uri": uri, "payload": payload])
    }

    private func sendJSONObject(
        _ object: [String: Any],
        on explicitSocket: URLSessionWebSocketTask? = nil
    ) {
        guard let target = explicitSocket ?? socket,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        Task { [weak self, weak target] in
            do {
                try await target?.send(.string(text))
            } catch {
                guard let self, let target, self.socket === target else { return }
                self.handleSocketError(error)
            }
        }
    }

    private func receiveNextMessage(from target: URLSessionWebSocketTask, token: UUID) {
        Task { [weak self, weak target] in
            guard let target else { return }
            do {
                let message = try await target.receive()
                guard let self, self.socket === target, self.connectionToken == token else { return }
                self.handle(message)
                self.receiveNextMessage(from: target, token: token)
            } catch {
                guard let self, self.socket === target, self.connectionToken == token else { return }
                self.handleSocketError(error)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let value): data = value
        @unknown default: return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = object["type"] as? String
        let payload = object["payload"] as? [String: Any] ?? [:]

        if type == "response", payload["pairingType"] as? String == "PROMPT" {
            statusText = "请在 LG 电视屏幕上选择“允许”"
        }

        if type == "registered", let target = activeHost {
            if let key = payload["client-key"] as? String {
                clientKeys[target] = key
                defaults.set(clientKeys, forKey: Keys.clientKeys)
            }
            connectionTimeoutTask?.cancel()
            isConnected = true
            isPairing = false
            connectedHost = target
            statusText = "LG 电视已连接 · \(target)"
            subscribeToSoundOutput()
        }

        let volumePayload = payload["volumeStatus"] as? [String: Any] ?? payload
        if let value = volumePayload["volume"] as? NSNumber {
            reportedVolume = value.doubleValue
            if volumeTask == nil || volumeTask?.isCancelled == true {
                volume = value.doubleValue
            } else {
                // A completed step sequence is allowed to converge to the TV's
                // reported value; live slider movement keeps its local target.
                let difference = abs(volume - value.doubleValue)
                if difference < 1 { volume = value.doubleValue }
            }
        }
        if let muted = (volumePayload["muted"] ?? volumePayload["mute"]) as? Bool {
            isMuted = muted
        }
        if let output = payload["soundOutput"] as? String {
            soundOutput = output
        }

        if type == "error" {
            let message = object["error"] as? String
                ?? payload["errorText"] as? String
                ?? "电视拒绝了连接请求"
            let messageID = object["id"] as? String ?? ""
            if isPairing || messageID == "register_0" {
                handleRegistrationError(message)
            } else if messageID == "sound-output-subscription" {
                soundOutput = "unknown"
            } else {
                statusText = "LG 电视已连接，但控制请求失败：\(message)"
            }
        }
    }

    private func handleRegistrationError(_ message: String) {
        guard let target = activeHost else {
            handleFinalConnectionFailure(message)
            return
        }
        if isPairing, clientKeys[target] != nil, !retriedWithoutStoredKey {
            clientKeys.removeValue(forKey: target)
            defaults.set(clientKeys, forKey: Keys.clientKeys)
            retriedWithoutStoredKey = true
            statusText = "旧配对已失效，正在请求电视重新确认…"
            openSocket(host: target, secure: isUsingSecureSocket, forcePairing: true)
        } else {
            handleFinalConnectionFailure("电视拒绝连接：\(message)")
        }
    }

    private func handleSocketError(_ error: Error) {
        guard isPairing else {
            handleFinalConnectionFailure("电视连接已中断：\(error.localizedDescription)")
            return
        }
        trySecureFallbackOrFail(forcePairing: retriedWithoutStoredKey)
    }

    private func finishDiscovery() {
        let shouldConnect = connectAfterDiscovery
        discoveryTimeoutTask = nil
        discoverySource?.cancel()
        discoverySource = nil
        isDiscovering = false
        connectAfterDiscovery = false

        guard !discoveredDevices.isEmpty else {
            statusText = "没有发现 LG 电视；可切换到“手动 IP”，并检查电视的 LG Connect Apps 设置。"
            return
        }
        if selectedHost.isEmpty { selectedHost = discoveredDevices[0].host }
        statusText = "已发现 \(discoveredDevices.count) 台 LG 电视"
        if shouldConnect { connectSelectedDevice() }
    }

    private func handleSSDPResponse(_ response: String) {
        let headers = Self.headers(in: response)
        guard let location = headers["location"],
              let url = URL(string: location),
              let responseHost = url.host else { return }
        let signature = [headers["st"], headers["usn"], headers["server"]]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        if signature.contains("webos") || signature.contains("lge") {
            upsertDevice(host: responseHost, name: "LG webOS TV", model: nil)
        } else {
            fetchDescription(at: url, fallbackHost: responseHost)
        }
    }

    private func fetchDescription(at url: URL, fallbackHost: String) {
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let xml = String(data: data, encoding: .utf8) else { return }
            let manufacturer = Self.xmlValue("manufacturer", in: xml) ?? ""
            guard manufacturer.localizedCaseInsensitiveContains("LG") else { return }
            let name = Self.xmlValue("friendlyName", in: xml) ?? "LG webOS TV"
            let model = Self.xmlValue("modelName", in: xml)
            self?.upsertDevice(host: fallbackHost, name: name, model: model)
        }
    }

    private func upsertDevice(host: String, name: String, model: String?) {
        if let index = discoveredDevices.firstIndex(where: { $0.host == host }) {
            if discoveredDevices[index].name == "LG webOS TV", name != "LG webOS TV" {
                discoveredDevices[index].name = name
                discoveredDevices[index].model = model
            }
        } else {
            discoveredDevices.append(LGTVDevice(host: host, name: name, model: model))
            discoveredDevices.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
        if selectedHost.isEmpty || host == self.host { selectedHost = host }
        if connectAfterDiscovery, host == self.host, clientKeys[host] != nil {
            connectAfterDiscovery = false
            connect(to: host)
        }
    }

    private nonisolated static func normalizedHost(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "ws://\(trimmed)"
        guard let url = URL(string: candidate), let host = url.host, !host.isEmpty else { return nil }
        return host
    }

    private nonisolated static func sendSSDPSearch(from descriptor: Int32) {
        let targets = [
            "urn:lge-com:service:webos-second-screen:1",
            "urn:schemas-upnp-org:device:MediaRenderer:1"
        ]
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(1900).bigEndian
        destination.sin_addr = in_addr(s_addr: inet_addr("239.255.255.250"))

        for target in targets {
            let request = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(target)\r\n\r\n"
            let data = Data(request.utf8)
            data.withUnsafeBytes { bytes in
                withUnsafePointer(to: &destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                        _ = Darwin.sendto(descriptor, bytes.baseAddress, bytes.count, 0, address, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    private nonisolated static func receiveSSDPResponses(from descriptor: Int32) -> [String] {
        var messages: [String] = []
        while true {
            var buffer = [UInt8](repeating: 0, count: 16_384)
            var sender = sockaddr_storage()
            var senderLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = withUnsafeMutablePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    Darwin.recvfrom(descriptor, &buffer, buffer.count, 0, address, &senderLength)
                }
            }
            guard count > 0 else { break }
            if let value = String(bytes: buffer.prefix(count), encoding: .utf8) { messages.append(value) }
        }
        return messages
    }

    private nonisolated static func headers(in response: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in response.components(separatedBy: "\r\n") {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }

    private nonisolated static func xmlValue(_ tag: String, in xml: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        let pattern = "<\\s*\(escaped)[^>]*>(.*?)<\\s*/\\s*\(escaped)\\s*>"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = expression.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class LGTVSessionDelegate: NSObject, URLSessionDelegate {
    private let allowedHost: String

    init(allowedHost: String) {
        self.allowedHost = allowedHost
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == allowedHost,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // webOS port 3001 uses a device-local self-signed certificate. Trust is
        // scoped to the exact host selected by the user or discovered by SSDP.
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
