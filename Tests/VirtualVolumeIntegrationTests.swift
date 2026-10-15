// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation

private final class FakeBackend: AudioBridgeBackend {
    var list: [AudioBridgeDevice] = []
    var target: String?
    var stops = 0
    var configures = 0
    var stopConfirmed = true
    var telemetry: AudioBridgeTelemetry?
    func devices() throws -> [AudioBridgeDevice] { list }
    func start(uid: String, fixture: String, gain: Float, muted: Bool) throws {
        guard list.filter({ $0.uid == uid }).count == 1 else { throw AudioBridgeError.message("TARGET_UNAVAILABLE") }
        target = uid
    }
    func poll() throws -> AudioBridgeTelemetry? { telemetry }
    func configure(gain: Float, muted: Bool) { configures += 1 }
    func stop() -> Bool { target = nil;stops += 1;return stopConfirmed }
}
@main struct AudioIntegrationTests {
    static func device(_ uid: String="HDMI-A", _ id: UInt32=10, _ rate: Double=192000, _ eligible: String="USABLE_DIRECT_PATH") -> AudioBridgeDevice {
        .init(uid:uid,deviceID:id,name:"Same name",transport:0,rate:rate,channels:2,buffer:512,maxBlock:512,latency:88,safety:512,eligibility:eligible,physicalBits:24,physicalFloat:false,streamLatency:0)
    }
    static func reading(_ callbacks: UInt64=0, failure: String="NONE") -> AudioBridgeTelemetry {
        .init(epoch:1,callbacks:callbacks,frames:callbacks*512,fill:512,minFill:0,maxFill:512,capacity:4096,targetFill:512,underrun:failure == "UNDERRUN" ? 1 : 0,overrun:0,ringMS:2.6667,bufferMS:2.6667,residenceMS:nil,failure:failure)
    }
    static func main() async {
        var count = 0
        func check(_ value: Bool, _ message: String) { count += 1;precondition(value,message) }
        let suite="RightDisplay.Build12.Tests.\(UUID().uuidString)", defaults=UserDefaults(suiteName:"RightDisplay.Build12.Tests.\(UUID().uuidString)")!
        defer { defaults.removeObject(forKey:AudioTargetPreference.key) }
        _ = suite
        let preference=AudioTargetPreference(defaults:defaults)
        check(preference.uid == nil,"default must not pick speakers")
        preference.save("HDMI-A");check(preference.uid == "HDMI-A","UID persistence")
        check(defaults.dictionaryRepresentation().keys.filter({ $0.localizedCaseInsensitiveContains("deviceID") }).isEmpty,"ephemeral deviceID persisted")
        var model=VirtualVolumeStateModel(uid:preference.uid)
        model.reconcile([device("HDMI-A",99)],generation:model.generation)
        check(model.state == .ready && !model.hasSession,"device exists != running")
        model.reconcile([],generation:model.generation);check(model.state == .targetUnavailable,"missing target")
        model.reconcile([device("Speakers",100)],generation:model.generation);check(model.uid == "HDMI-A"&&model.state == .targetUnavailable,"no fallback")
        model.reconcile([device("HDMI-A",101)],generation:model.generation);check(model.state == .ready && !model.hasSession,"reappear without autoplay")
        let token=model.requestStart()!;model.started(generation:token,error:nil)
        model.observed(reading(),generation:token);check(model.state == .ready&&model.starting,"API success is not running")
        model.observed(reading(1),generation:token);check(model.state == .running,"real frames required")
        let old=token;let stop=model.requestStop();model.observed(reading(99),generation:old);check(model.state == .stopping && !model.hasSession,"stale callback")
        model.stopped(generation:stop,clean:true);model.reconcile([device()],generation:model.generation)
        check(model.state == .ready,"stop terminal")
        for failure in ["FORMAT_CHANGED","TARGET_UNAVAILABLE","HAL_FAILURE","UNDERRUN"] {
            let t=model.requestStart()!;model.started(generation:t,error:nil);model.observed(reading(1,failure:failure),generation:t)
            check(!model.hasSession && !model.starting&&model.state != .running,"safe terminal for \(failure)")
            model.reconcile([device()],generation:model.generation)
        }
        model.reconcile([device("HDMI-A",1,32000,"UNSUPPORTED_RATE")],generation:model.generation)
        check(model.state == .unsupportedFormat&&model.requestStart() == nil,"unsupported rate no start")
        for rate in [44100.0,48000,96000,192000] {
            check(abs(VirtualVolumeStateModel.latency(frames:512,rate:rate)!-512000/rate)<1e-9,"native latency \(rate)")
        }
        check(VirtualVolumeStateModel.latency(frames:512,rate:0) == nil,"unknown rate no calculation")
        model.reconcile([device()],generation:model.generation)
        let failedToken=model.requestStart()!;model.started(generation:failedToken,error:nil);model.observed(reading(2),generation:failedToken)
        model.observed(reading(3,failure:"CONTEXT_CHANGED"),generation:failedToken)
        check(model.unexpectedStop,"running context failure visible")
        for _ in 0..<3 { model.reconcile([device()],generation:model.generation);check(model.unexpectedStop,"ordinary refresh preserves abnormal stop") }
        let retry=model.requestStart()!;model.started(generation:retry,error:nil)
        check(model.unexpectedStop,"start acceptance alone must not acknowledge failure")
        model.observed(reading(4),generation:retry);check(!model.unexpectedStop,"successful running callback acknowledges failure")
        let manual=model.requestStop();model.stopped(generation:manual,clean:true)
        check(!model.unexpectedStop,"manual stop never abnormal")
        model.reconcile([device()],generation:model.generation)
        let target=model.uid;var unrelatedDisplay="Display-A";unrelatedDisplay="Display-B"
        check(model.uid == target&&unrelatedDisplay == "Display-B","display selection does not retarget audio")
        let appleTVTarget="apple-tv-homepod";model.select("HDMI-B")
        check(appleTVTarget == "apple-tv-homepod"&&model.uid == "HDMI-B","independent device-control path")
        model.reconcile([device("HDMI-B"),device("HDMI-B",42)],generation:model.generation)
        check(model.state == .targetUnavailable,"ambiguous UID rejected")
        let sleep=model.requestStop(suspend:true);model.stopped(generation:sleep,clean:true);model.reconcile([device("HDMI-B")],generation:model.generation)
        check(model.state == .disabled,"sleep no Ready")
        model.wake();model.reconcile([device("HDMI-B")],generation:model.generation);check(model.state == .ready && !model.hasSession,"wake no autoplay")
        var privacy=AudioDiagnosticAnonymizer();let secret="HDMI:uid-123456789"
        let redacted=privacy.redact("target=coreaudio:\(secret) nested={uid:\(secret)}",uids:[secret])
        check(!redacted.contains(secret)&&redacted.components(separatedBy:"Audio-1").count == 3,"privacy and correlation")
        check(device(secret).uid == secret,"internal identity unmodified")
        var displayPrivacy=DiagnosticPrivacyRedactor(hardwareKeys:["00000001-00000002-00000001"])
        let combined=displayPrivacy.redact(privacy.redact("UID=\(secret) Audio-1 hardware=00000001-00000002-00000001",uids:[secret]))
        check(!combined.contains(secret)&&combined.contains("Audio-1")&&combined.contains("Display-A"),"combined privacy preserves anonymous audio correlation")
        let installed = VirtualAudioDeviceStatus(matches:1,loaded:true,defaultKnown:true,isDefault:false,rate:48000)
        check(installed.safeToRemove,"unique non-default permits removal preflight")
        check(!VirtualAudioDeviceStatus(matches:1,loaded:true,defaultKnown:true,isDefault:true,rate:48000).safeToRemove,"default virtual output blocks removal")
        check(!VirtualAudioDeviceStatus(matches:2,loaded:true,defaultKnown:true,isDefault:false,rate:48000).safeToRemove,"ambiguous virtual identity blocks removal")
        check(!VirtualAudioDeviceStatus().safeToRemove,"unknown default blocks removal")
        // Actual async control facade with an injected backend; no native HAL call.
        let fake=FakeBackend();fake.list=[device()];let engine=AudioBridgeEngine(backend:fake);engine.invalidate(20)
        let first=await withCheckedContinuation { c in engine.refresh(generation:20) { c.resume(returning:$0) } }
        check(first.devices[0].deviceID == 10,"fresh ID")
        fake.list=[device("HDMI-A",45)]
        let second=await withCheckedContinuation { c in engine.refresh(generation:20) { c.resume(returning:$0) } }
        check(second.devices[0].deviceID == 45,"refreshed ID rather than persistence")
        let result: String?=await withCheckedContinuation { c in engine.start(uid:"HDMI-A",fixture:"silence",gain:0.02,muted:true,generation:20) { c.resume(returning:$0) } }
        check(result == nil&&fake.target == "HDMI-A","explicit target start")
        for _ in 0..<3 {
            fake.list=[device("HDMI-A",45)];fake.telemetry=reading(2)
            let stable=await withCheckedContinuation { c in engine.refresh(generation:20) { c.resume(returning:$0) } }
            check(stable.generation == 20 && fake.target == "HDMI-A" && fake.stops == 0,"equivalent observation/telemetry reconstruction preserves route")
        }
        fake.telemetry=reading(1,failure:"FORMAT_CHANGED")
        let changed=await withCheckedContinuation { c in engine.refresh(generation:20) { c.resume(returning:$0) } }
        check(changed.telemetry?.failure == "FORMAT_CHANGED"&&fake.target == nil&&fake.stops == 1,"poll failure tears down backend")
        engine.invalidate(21)
        let cancelled: String?=await withCheckedContinuation { c in engine.start(uid:"Speakers",fixture:"sine",gain:0.02,muted:false,generation:20) { c.resume(returning:$0) } }
        check(cancelled == "CANCELLED"&&fake.target == nil,"stale start ignored")
        check(engine.shutdown()&&fake.stops == 2,"app termination teardown")
        let bad=FakeBackend();bad.list=[device()];let badEngine=AudioBridgeEngine(backend:bad);badEngine.invalidate(40)
        let _: String?=await withCheckedContinuation { c in badEngine.start(uid:"HDMI-A",fixture:"silence",gain:0.02,muted:true,generation:40) { c.resume(returning:$0) } }
        bad.stopConfirmed=false
        let clean=await withCheckedContinuation { c in badEngine.stop(generation:41) { c.resume(returning:$0) } }
        check(!clean,"uncertain teardown is not success")
        let failed=await withCheckedContinuation { c in badEngine.refresh(generation:41) { c.resume(returning:$0) } }
        check(!failed.cleanupOK,"uncertain teardown remains sticky")
        let refused: String?=await withCheckedContinuation { c in badEngine.start(uid:"HDMI-A",fixture:"silence",gain:0.02,muted:true,generation:41) { c.resume(returning:$0) } }
        check(refused?.contains("RESTART_REQUIRED") == true&&bad.target == nil,"restart required before another start")
        print("Virtual Volume integration: \(count) assertions PASS; fake backend, no hardware playback")
    }
}
