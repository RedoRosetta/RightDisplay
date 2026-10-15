// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation

// Sparse control-plane evidence. Never called by the native realtime callback.
struct AudioBridgeDiagnosticRecord: Codable {
    let observedAt: Date
    let uptime: Double
    let runtime: String
    let phase: String
    let generation: UInt64
    let targetUID: String?
    let target: AudioBridgeDevice?
    let targetEnumerated: Bool
    let lastHealthy: AudioBridgeTelemetry?
    let failure: AudioBridgeTelemetry?
    let error: String?
}
enum AudioBridgeFailureJournal {
    static let runtime = UUID().uuidString
    private static let queue = DispatchQueue(label: "RightDisplay.AudioBridge.Evidence", qos: .utility)
    // Local diagnostic identities are deliberately raw; do not share without review.
    static func append(_ record: AudioBridgeDiagnosticRecord) {
        queue.async {
            do {
                let encoder = JSONEncoder();encoder.dateEncodingStrategy = .iso8601
                var bytes = try encoder.encode(record);bytes.append(10)
                let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Logs/Right Display", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let url = directory.appendingPathComponent("VirtualAudio-Evidence.jsonl")
                if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
                   size.intValue + bytes.count > 524288 {
                    let previous = directory.appendingPathComponent("VirtualAudio-Evidence.previous.jsonl")
                    if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
                    try FileManager.default.moveItem(at: url, to: previous)
                }
                if !FileManager.default.fileExists(atPath: url.path) {
                    guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                         attributes: [.posixPermissions: 0o600]) else { return }
                }
                let file = try FileHandle(forWritingTo: url);defer { try? file.close() }
                try file.seekToEnd();try file.write(contentsOf: bytes)
            } catch { /* Diagnostic IO never changes playback or retries a session. */ }
        }
    }
}

protocol AudioBridgeBackend: AnyObject {
    func devices() throws -> [AudioBridgeDevice]
    func start(uid: String, fixture: String, gain: Float, muted: Bool) throws
    func poll() throws -> AudioBridgeTelemetry?
    func configure(gain: Float, muted: Bool)
    func stop() -> Bool
}
final class NativeAudioBridgeBackend: AudioBridgeBackend {
    private var session: OpaquePointer?
    private let provider = AudioDeviceProvider()
    deinit { _ = stop() }
    func devices() throws -> [AudioBridgeDevice] { try provider.devices() }
    func start(uid: String, fixture: String, gain: Float, muted: Bool) throws {
        guard session == nil else { throw AudioBridgeError.message("ALREADY_OWNED") }
        var error: UnsafeMutablePointer<CChar>?
        session = ABStartTest(uid, fixture, gain, muted ? 1 : 0, &error)
        if let error { defer { ABFreeString(error) };throw AudioBridgeError.message(String(cString: error)) }
        guard session != nil else { throw AudioBridgeError.message("START_FAILED") }
    }
    func poll() throws -> AudioBridgeTelemetry? {
        guard let session else { return nil };return try AudioBridgeJSON.decode(ABPollJSON(session))
    }
    func configure(gain: Float, muted: Bool) { if let session { ABSetGain(session, gain, muted ? 1 : 0) } }
    func stop() -> Bool { guard let old = session else { return true };session = nil;return ABStop(old) == 0 }
}
struct AudioBridgeUpdate {
    let generation: UInt64
    let devices: [AudioBridgeDevice]
    let telemetry: AudioBridgeTelemetry?
    let error: String?
    let cleanupOK: Bool
}
// One non-realtime queue owns every HAL call and the opaque session lifetime.
// No Swift closure or object is accessed from the C++ audio callback.
final class AudioBridgeEngine {
    private let queue = DispatchQueue(label: "RightDisplay.AudioBridge.Control", qos: .userInitiated)
    private let backend: AudioBridgeBackend
    private let gate = NSLock()
    private var generation: UInt64 = 1
    private var teardownConfirmed = true
    private var heartbeat: DispatchSourceTimer?
    private var latestTelemetry: AudioBridgeTelemetry?
    private var heartbeatError: String?
    private let evidence: (AudioBridgeDiagnosticRecord) -> Void
    private var targetUID: String?
    private var targetObservation: AudioBridgeDevice?
    private var targetEnumerated = false
    private var lastHealthy: AudioBridgeTelemetry?
    private func record(_ phase: String, token: UInt64, failure: AudioBridgeTelemetry? = nil, error: String? = nil) {
        evidence(.init(observedAt: Date(), uptime: ProcessInfo.processInfo.systemUptime,
                       runtime: AudioBridgeFailureJournal.runtime, phase: phase, generation: token,
                       targetUID: targetUID, target: targetObservation, targetEnumerated: targetEnumerated,
                       lastHealthy: lastHealthy, failure: failure, error: error))
    }
    func recordBoundary(_ phase: String, generation: UInt64) {
        queue.async { [self] in record(phase, token: generation) }
    }
    private func startHeartbeat(generation token: UInt64) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.accepts(token) else { self.record("STALE_GENERATION_STOP", token: token);_ = self.stopBackend();return }
            do {
                let value = try self.backend.poll()
                if let value, value.failure != "NONE" {
                    self.record("FIRST_FAILURE", token: token, failure: value)
                    _ = self.stopBackend()
                    self.latestTelemetry = value
                } else { self.latestTelemetry = value;if let value { self.lastHealthy = value } }
            } catch {
                self.record("POLL_ERROR", token: token, error: String(describing:error))
                _ = self.stopBackend()
                self.heartbeatError = String(describing:error)
            }
        }
        heartbeat = timer;timer.resume()
    }
    private func stopBackend() -> Bool {
        heartbeat?.cancel();heartbeat = nil;latestTelemetry = nil;heartbeatError = nil
        let previouslyConfirmed = teardownConfirmed
        teardownConfirmed = backend.stop() && teardownConfirmed
        if previouslyConfirmed && !teardownConfirmed { record("TEARDOWN_UNCONFIRMED", token: 0, error: "cleanup failed; generation unspecified; existing restart latch retained") }
        return teardownConfirmed
    }
    init(backend: AudioBridgeBackend = NativeAudioBridgeBackend(), evidence: @escaping (AudioBridgeDiagnosticRecord) -> Void = AudioBridgeFailureJournal.append) { self.backend = backend;self.evidence = evidence }
    func invalidate(_ generation: UInt64) { gate.lock();self.generation = generation;gate.unlock() }
    private func accepts(_ value: UInt64) -> Bool { gate.lock();defer { gate.unlock() };return generation == value }
    private func deliver(_ update: AudioBridgeUpdate, _ completion: @escaping (AudioBridgeUpdate) -> Void) {
        DispatchQueue.main.async { completion(update) }
    }
    func refresh(generation: UInt64, completion: @escaping (AudioBridgeUpdate) -> Void) {
        queue.async { [self] in
            guard accepts(generation) else { return deliver(.init(generation:generation,devices:[],telemetry:nil,error:nil,cleanupOK:true),completion) }
            do {
                let devices = try backend.devices()
                targetObservation = devices.first { $0.uid == targetUID };targetEnumerated = true
                let telemetry: AudioBridgeTelemetry?
                if let value = latestTelemetry { telemetry = value }
                else if heartbeat == nil && heartbeatError == nil { telemetry = try backend.poll() }
                else { telemetry = nil }
                let error = heartbeatError
                if let telemetry, telemetry.failure != "NONE", heartbeat != nil { record("FIRST_FAILURE", token: generation, failure: telemetry) }
                let clean = telemetry.map { $0.failure != "NONE" } == true || error != nil ? stopBackend() : teardownConfirmed
                deliver(.init(generation:generation,devices:devices,telemetry:telemetry,error:error,cleanupOK:clean),completion)
            } catch {
                record("DEVICE_OBSERVATION_ERROR", token: generation, error: String(describing:error))
                let clean = stopBackend()
                deliver(.init(generation:generation,devices:[],telemetry:nil,error:String(describing:error),cleanupOK:clean),completion)
            }
        }
    }
    func start(uid: String, fixture: String, gain: Float, muted: Bool, generation: UInt64, completion: @escaping (String?) -> Void) {
        queue.async { [self] in
            guard accepts(generation) else { DispatchQueue.main.async { completion("CANCELLED") };return }
            var failure: String?
            do {
                // Final UID resolution occurs again inside the native start.
                guard teardownConfirmed else { throw AudioBridgeError.message("HAL_TEARDOWN_UNCONFIRMED_RESTART_REQUIRED") }
                latestTelemetry = nil;heartbeatError = nil;lastHealthy = nil;targetUID = uid;targetObservation = nil;targetEnumerated = false
                try backend.start(uid:uid,fixture:fixture,gain:gain,muted:muted)
                record("SESSION_START", token: generation)
                if fixture == "system" { startHeartbeat(generation:generation) }
                if !accepts(generation) { failure = stopBackend() ? "CANCELLED" : "CANCELLED; HAL_TEARDOWN_UNCONFIRMED" }
            } catch { record("START_ERROR", token: generation, error: String(describing:error));failure = String(describing:error) + (stopBackend() ? "" : "; HAL_TEARDOWN_UNCONFIRMED") }
            let result = failure;DispatchQueue.main.async { completion(result) }
        }
    }
    func configure(gain: Float, muted: Bool, generation: UInt64) {
        queue.async { [self] in if accepts(generation) { backend.configure(gain:gain,muted:muted) } }
    }
    func stop(generation: UInt64, completion: @escaping (Bool) -> Void) {
        invalidate(generation);queue.async { [self] in record("EXPLICIT_STOP", token: generation);let clean = stopBackend();DispatchQueue.main.async { completion(clean) } }
    }
    func shutdown() -> Bool { invalidate(UInt64.max);return queue.sync { record("APP_SHUTDOWN", token: UInt64.max);return stopBackend() } }
}
