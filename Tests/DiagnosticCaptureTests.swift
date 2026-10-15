// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation
final class EvidenceBackend: AudioBridgeBackend {
    private let lock = NSLock()
    private var active = false
    private var count: UInt64 = 0
    var failed = false
    var badEnumeration = false
    var uncleanStop = false
    func devices() throws -> [AudioBridgeDevice] {
        lock.lock();defer { lock.unlock() }
        if badEnumeration { throw AudioBridgeError.message("SYNTHETIC_ENUMERATION_FAILURE") }
        return []
    }
    func start(uid:String,fixture:String,gain:Float,muted:Bool) throws { lock.lock();active = true;failed = false;count = 0;lock.unlock() }
    func poll() throws -> AudioBridgeTelemetry? {
        lock.lock();defer { lock.unlock() };guard active else { return nil };count += 1
        return .init(failureDetail:failed ? "DIFF_FIELDS=lease" : nil,epoch:9,callbacks:count,frames:count*512,fill:4096,minFill:4000,maxFill:4200,capacity:32768,targetFill:4096,underrun:0,overrun:0,ringMS:85.33,bufferMS:2.67,residenceMS:nil,failure:failed ? "CONTEXT_CHANGED" : "NONE")
    }
    func configure(gain:Float,muted:Bool) {}
    func stop()->Bool { lock.lock();active = false;count = 0;let clean = !uncleanStop;lock.unlock();return clean }
    func fail() { lock.lock();failed = true;lock.unlock() }
    func enumerationFail() { lock.lock();badEnumeration = true;uncleanStop = true;lock.unlock() }
}
final class Capture {
    let lock = NSLock();var rows:[AudioBridgeDiagnosticRecord] = []
    func append(_ row: AudioBridgeDiagnosticRecord) { lock.lock();rows.append(row);lock.unlock() }
    func snapshot()->[AudioBridgeDiagnosticRecord] { lock.lock();defer { lock.unlock() };return rows }
}
@main struct DiagnosticCaptureTests {
    @MainActor static func main() async {
        let backend = EvidenceBackend(), capture = Capture()
        let engine = AudioBridgeEngine(backend:backend,evidence:capture.append)
        func start(_ generation:UInt64) async {
            engine.invalidate(generation)
            await withCheckedContinuation { (c:CheckedContinuation<Void,Never>) in
                engine.start(uid:"fixture-stable-UID",fixture:"system",gain:1,muted:false,generation:generation) { error in precondition(error == nil);c.resume() }
            }
        }
        await start(2)
        try? await Task.sleep(nanoseconds:700_000_000)
        backend.fail();try? await Task.sleep(nanoseconds:650_000_000)
        let failures = capture.snapshot().filter { $0.phase == "FIRST_FAILURE" }
        precondition(failures.count == 1)
        let f = failures[0]
        precondition(f.targetUID == "fixture-stable-UID" && f.generation == 2)
        precondition(f.lastHealthy?.failure == "NONE" && f.lastHealthy!.callbacks > 0)
        precondition(f.failure?.failure == "CONTEXT_CHANGED" && f.failure!.callbacks > 0)
        precondition(f.failure?.failureDetail == "DIFF_FIELDS=lease")
        precondition(try! JSONDecoder().decode(AudioBridgeDiagnosticRecord.self,from:JSONEncoder().encode(f)).failure == f.failure)
        engine.recordBoundary("SLEEP",generation:2)
        await withCheckedContinuation { (c:CheckedContinuation<Void,Never>) in engine.stop(generation:3) { clean in precondition(clean);c.resume() } }
        engine.recordBoundary("WAKE",generation:3)
        await start(4)
        try? await Task.sleep(nanoseconds:700_000_000)
        backend.enumerationFail()
        await withCheckedContinuation { (c:CheckedContinuation<Void,Never>) in engine.refresh(generation:4) { update in precondition(update.error != nil);c.resume() } }
        let e = capture.snapshot().first { $0.phase == "DEVICE_OBSERVATION_ERROR" }!
        precondition(e.lastHealthy?.failure == "NONE" && e.error!.contains("SYNTHETIC_ENUMERATION_FAILURE"))
        let phases = capture.snapshot().map { $0.phase };precondition(phases.contains("SLEEP") && phases.contains("WAKE") && phases.contains("EXPLICIT_STOP") && phases.contains("TEARDOWN_UNCONFIRMED"))
        _ = engine.shutdown()
        print("Diagnostic capture PASS: first failure before teardown, last healthy/counters/context, stable UID/generation, codec, observation error and lifecycle boundaries; fake backend only")
    }
}
