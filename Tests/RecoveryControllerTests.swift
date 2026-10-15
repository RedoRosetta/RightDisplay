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
final class Backend: AudioBridgeBackend {
 var starts=0, active=false, present=true, deviceID:UInt32=10, failure="NONE", cleanup=true, uid="synthetic"
 func devices() throws->[AudioBridgeDevice] {present ? [.init(uid:uid,deviceID:deviceID,name:"fixture",transport:0,rate:48000,channels:2,buffer:512,maxBlock:512,latency:0,safety:0,eligibility:"USABLE_DIRECT_PATH",physicalBits:32,physicalFloat:true,streamLatency:0)] : []}
 func start(uid:String,fixture:String,gain:Float,muted:Bool)throws {starts+=1;active=true;failure="NONE"}
 func poll()throws->AudioBridgeTelemetry? {guard active else {return nil};return .init(failureDetail:failure == "TARGET_UNAVAILABLE" ? "TARGET_REMOVAL_CONFIRMED=1" : "",epoch:UInt64(starts),callbacks:10,frames:5120,fill:0,minFill:0,maxFill:0,capacity:32768,targetFill:4096,underrun:0,overrun:0,ringMS:85,bufferMS:10,residenceMS:nil,failure:failure)}
 func configure(gain:Float,muted:Bool){}
 func stop()->Bool {active=false;return cleanup}
}
@main struct Tests {
 @MainActor static func main() async {
 var n=0
 func check(_ value:Bool){n+=1;precondition(value,"recovery assertion \(n)")}
 func wait(_ predicate:()->Bool) async {for _ in 0..<400 {if predicate(){return};try? await Task.sleep(nanoseconds:5_000_000)};preconditionFailure("recovery timeout")}
 let suite="RightDisplay.RecoveryFixture.\(UUID())",defaults=UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
 defaults.set("synthetic",forKey:"virtualVolumeAudioUID")
 let backend=Backend(),virtual=VirtualAudioDeviceStore.shared
 virtual.status = .init(matches:1,loaded:true,defaultKnown:true,isDefault:true,rate:48000)
 let controller=VirtualVolumeController(defaults:defaults,engine:AudioBridgeEngine(backend:backend,evidence:{_ in}))
 controller.startMonitoring();await wait {backend.starts==1 && controller.model.hasSession};controller.refresh();await wait {controller.model.state == .running};check(backend.starts==1)
 backend.present=false;backend.failure="TARGET_UNAVAILABLE"
 try? await Task.sleep(nanoseconds:600_000_000);controller.refresh();await wait {!controller.model.hasSession};check(!controller.needsRestart)
 backend.deviceID=99;backend.present=true;controller.refresh();await wait {backend.starts==2 && controller.model.hasSession};controller.refresh();await wait {controller.model.state == .running};check(controller.selectedDevice?.deviceID==99)
 // Manual stop cancels pending target-return recovery and survives later refresh.
 backend.present=false;backend.failure="TARGET_UNAVAILABLE";try? await Task.sleep(nanoseconds:600_000_000);controller.refresh();await wait {!controller.model.hasSession}
 controller.stop();await wait {!controller.busy};backend.present=true;controller.refresh();try? await Task.sleep(nanoseconds:100_000_000);check(backend.starts==2)
 // Explicit manual start still works; overrun must never restart automatically.
 controller.startRoute();await wait {backend.starts==3 && controller.model.hasSession};controller.refresh();await wait {controller.model.state == .running}
 backend.failure="OVERRUN";try? await Task.sleep(nanoseconds:600_000_000);controller.refresh();await wait {!controller.model.hasSession};controller.refresh();try? await Task.sleep(nanoseconds:100_000_000);check(backend.starts==3)
 controller.stop();await wait {!controller.busy};controller.refresh();await wait {controller.canStart};controller.startRoute();await wait {backend.starts==4 && controller.model.hasSession};controller.refresh();await wait {controller.model.state == .running}
 // Real cleanup failure still latches restart-required and blocks return.
 backend.cleanup=false;backend.present=false;backend.failure="TARGET_UNAVAILABLE";try? await Task.sleep(nanoseconds:600_000_000);controller.refresh();await wait {controller.needsRestart};backend.present=true;controller.refresh();try? await Task.sleep(nanoseconds:100_000_000);check(backend.starts==4)
 controller.shutdown()
 var policy=VirtualAudioTargetReturnPolicy()
 policy.arm(uid:"A",wasRunning:true,systemRoute:true,failure:"TARGET_UNAVAILABLE",cleanupOK:true,removalConfirmed:true)
 check(!policy.consume(uid:"A",eligible:false,virtualSelected:true,manuallyDisabled:false))
 check(!policy.consume(uid:"B",eligible:true,virtualSelected:true,manuallyDisabled:false));check(policy.pendingUID==nil)
 for reason in ["OVERRUN","CONTEXT_CHANGED","FORMAT_CHANGED","STOPPED"] {
  policy.arm(uid:"A",wasRunning:true,systemRoute:true,failure:reason,cleanupOK:true,removalConfirmed:true);check(policy.pendingUID==nil)
 }
 policy.arm(uid:"A",wasRunning:true,systemRoute:true,failure:"TARGET_UNAVAILABLE",cleanupOK:true,removalConfirmed:true)
 check(policy.consume(uid:"A",eligible:true,virtualSelected:true,manuallyDisabled:false));check(!policy.consume(uid:"A",eligible:true,virtualSelected:true,manuallyDisabled:false))
 policy.arm(uid:"A",wasRunning:true,systemRoute:true,failure:"TARGET_UNAVAILABLE",cleanupOK:true,removalConfirmed:false);check(policy.pendingUID==nil)
 print("Target-return controller: \(n) assertions PASS; same UID/new ID, single attempt, manual stop, other failures, cleanup guard; fake backend only")
 }
}
