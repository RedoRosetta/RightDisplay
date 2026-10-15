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
 var starts=0,stops=0,active=false;var rate=48000.0;var lastGain:Float = -1;var configuredGain:Float = -1
 func devices() throws->[AudioBridgeDevice] {[.init(uid:"synthetic",deviceID:10,name:"fixture",transport:0,rate:rate,channels:2,buffer:512,maxBlock:512,latency:0,safety:0,eligibility:"USABLE_DIRECT_PATH",physicalBits:32,physicalFloat:true,streamLatency:0)]}
 func start(uid:String,fixture:String,gain:Float,muted:Bool)throws {starts+=1;active=true;lastGain=gain}
 func poll()throws->AudioBridgeTelemetry? {nil}
 func configure(gain:Float,muted:Bool){configuredGain=gain}
 func stop()->Bool {stops+=1;active=false;return true}
}
@main struct Tests {
 @MainActor static func main() async {
  var assertions=0
  func check(_ v:Bool){assertions+=1;precondition(v,"controller test \(assertions)")}
  func wait(_ predicate:()->Bool) async {for _ in 0..<200 {if predicate(){return};try? await Task.sleep(nanoseconds:5_000_000)};preconditionFailure("timeout")}
  let name="RightDisplay.ControllerFixture.\(UUID())",defaults=UserDefaults(suiteName:name)!;defer{defaults.removePersistentDomain(forName:name)}
  defaults.set("synthetic",forKey:"virtualVolumeAudioUID")
  let backend=Backend();let engine=AudioBridgeEngine(backend:backend)
  let controller=VirtualVolumeController(defaults:defaults,engine:engine)
  controller.refresh();await wait {controller.canStart};check(backend.starts==0)
  controller.startRoute();await wait {backend.active && controller.model.hasSession};check(backend.starts==1);check(backend.lastGain==1)
  controller.gain=0.4;await wait {backend.configuredGain==1};check(backend.configuredGain==1)
  controller.stop();await wait {!controller.busy};check(!backend.active)
  controller.refresh();await wait {controller.canStart};controller.startTest(fixture:"silence");await wait {backend.active && controller.model.hasSession};check(backend.starts==2);check(abs(backend.lastGain-0.4)<0.00001)
  controller.stop();await wait {!controller.busy};check(!backend.active)
  for rate in [44100.0,48000,88200,96000,176400,192000] {
   backend.rate=rate;controller.refresh();await wait {controller.selectedDevice?.rate==rate && controller.canStart}
   controller.startRoute();await wait {backend.active && controller.model.hasSession};check(backend.active)
   controller.stop();await wait {!controller.busy};check(!backend.active)
  }
  controller.refresh();await wait {controller.canStart}
  let virtual = VirtualAudioDeviceStore.shared
  let startsBeforeInvalidDriver = backend.starts
  virtual.installed = false;controller.startRoute();check(backend.starts == startsBeforeInvalidDriver && !backend.active)
  virtual.installed = true
  for invalid in [
   VirtualAudioDeviceStatus(matches:0,loaded:false,defaultKnown:true,isDefault:false,rate:48000),
   VirtualAudioDeviceStatus(matches:2,loaded:true,defaultKnown:true,isDefault:false,rate:48000),
   VirtualAudioDeviceStatus(matches:1,loaded:true,defaultKnown:true,isDefault:false,rate:44100)
  ] {
   virtual.status = invalid;controller.startRoute();check(backend.starts == startsBeforeInvalidDriver && !backend.active)
  }
  virtual.status = VirtualAudioDeviceStatus(matches:1,loaded:true,defaultKnown:true,isDefault:false,rate:48000)
  controller.startRoute();controller.stop();await wait {!controller.busy};check(!backend.active)
  check(defaults.bool(forKey:"virtualAudioManualStop")) // explicit stop persists; never auto-falls back
  controller.shutdown();check(!backend.active)
  check(virtual.disappearances == 1)
  print("Production VirtualVolumeController: \(assertions) assertions PASS; direct output / all native rates / cancellation / no permission dependency; fake backend, no HAL or permission request")
 }
}
