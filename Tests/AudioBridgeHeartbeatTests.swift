// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation
import Combine
// Only the controller's diagnostics/localization/device-status dependencies are
// stubs. The production controller, state reducer and async engine are compiled.
enum AppLocalization { static let isEnglish = false }
enum DiagnosticEvents { static func record(_ category:String,_ action:String,target:String?=nil,result:String?=nil) {} }
// Offline output-selection dependency used by the Build40+ controller.
@MainActor final class AudioOutputStore {
 struct Output { let id:String }
 static let shared = AudioOutputStore()
 @Published var selectedControlTargetID = "physical-fixture"
 @Published var outputs:[Output] = []
 @Published var current:Output? = nil
 var selectedAudioDevice:Output? { nil }
}
@MainActor final class VirtualAudioDeviceStore {
 static let shared = VirtualAudioDeviceStore()
 @Published var installed = true
 @Published var status = VirtualAudioDeviceStatus(matches:1,loaded:true,defaultKnown:true,isDefault:false,rate:48000)
 @Published var updateAvailable = false
 @Published var identityUnconfirmed = false
 private(set) var appearances = 0
 private(set) var disappearances = 0
 func appear() { appearances += 1 }
 func disappear() { disappearances += 1 }
}
import Foundation
final class HeartbeatBackend: AudioBridgeBackend {
    let lock=NSLock();private var active=false;private var count=0;private var failure="NONE"
    func devices() throws -> [AudioBridgeDevice] { [] }
    func start(uid:String,fixture:String,gain:Float,muted:Bool) throws { lock.lock();active=true;lock.unlock() }
    func poll() throws -> AudioBridgeTelemetry? {
        lock.lock();defer{lock.unlock()};guard active else{return nil};count+=1
        return .init(epoch:1,callbacks:UInt64(count),frames:UInt64(count*512),fill:4096,minFill:4096,maxFill:4608,capacity:32768,targetFill:4096,underrun:0,overrun:0,ringMS:85.33,bufferMS:2.67,residenceMS:nil,failure:failure)
    }
    func configure(gain:Float,muted:Bool) {}
    func stop()->Bool { lock.lock();active=false;lock.unlock();return true }
    func polls()->Int { lock.lock();defer{lock.unlock()};return count }
    func isActive()->Bool { lock.lock();defer{lock.unlock()};return active }
    func fail() { lock.lock();failure="HAL_CALLBACK_STALLED";lock.unlock() }
}
@main struct HeartbeatTests {
    static func blockUI() { Thread.sleep(forTimeInterval:3.6) }
    @MainActor static func main() async {
        var assertions=0
        func check(_ value:Bool){assertions+=1;precondition(value,"heartbeat assertion \(assertions)")}
        let backend=HeartbeatBackend(),engine=AudioBridgeEngine(backend:HeartbeatBackend())
        _=engine // No test of the HAL; each backend is synthetic.
        let route=AudioBridgeEngine(backend:backend)
        await withCheckedContinuation { (continuation:CheckedContinuation<Void,Never>) in
            route.start(uid:"synthetic",fixture:"system",gain:0.02,muted:false,generation:1) { error in check(error==nil);continuation.resume() }
        }
        // Main thread cannot run timers or receive completions for > native lease.
        blockUI();check(backend.polls()>=6 && backend.isActive())
        backend.fail();try? await Task.sleep(nanoseconds:700_000_000);check(!backend.isActive())
        await withCheckedContinuation { (continuation:CheckedContinuation<Void,Never>) in
            route.refresh(generation:1) { update in check(update.telemetry?.failure=="HAL_CALLBACK_STALLED");continuation.resume() }
        }
        let stopped=backend.polls();try? await Task.sleep(nanoseconds:700_000_000);check(backend.polls()==stopped)
        await withCheckedContinuation { (continuation:CheckedContinuation<Void,Never>) in
            route.start(uid:"synthetic",fixture:"system",gain:0.02,muted:false,generation:1) { error in check(error==nil);continuation.resume() }
        }
        route.invalidate(2);try? await Task.sleep(nanoseconds:700_000_000);check(!backend.isActive())
        check(route.shutdown())
        // Default authorization path is preparation only: no AVFoundation request.
        check(route.shutdown()) // teardown remains idempotent without permission preparation
        print("Independent audio heartbeat: \(assertions) assertions PASS; blocked main thread, real dispatch timer, failure and stale generation; no HAL")
    }
}
