// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import Combine
import Foundation
import Darwin
import CoreAudio

@MainActor
final class VirtualVolumeController: ObservableObject {
    static let shared = VirtualVolumeController()
    static let systemAudioRouting = "REQUIRES_INSTALLED_LOADED_VIRTUAL_DEVICE; AUTO_START_ON_VIRTUAL_OUTPUT_UNLESS_USER_STOPPED; OUTPUT_ONLY_SHARED_PCM; EXPLICIT_RATE_SRC; CLOCK_DRIFT_SRC"
    @Published private(set) var model: VirtualVolumeStateModel
    @Published private(set) var devices: [AudioBridgeDevice] = []
    @Published private(set) var telemetry: AudioBridgeTelemetry?
    @Published private(set) var lastFailure: String?
    @Published private(set) var needsRestart = false
    @Published private(set) var isSystemRoute = false
    @Published var gain: Double = 0.02 { didSet { configure() } }
    @Published var muted = false { didSet { configure() } }
    private let preference: AudioTargetPreference
    private let engine: AudioBridgeEngine
    private var timer: Timer?
    private static let manualStopKey = "virtualAudioManualStop"
    private let defaults: UserDefaults
    private var autoStartPolicy: VirtualAudioAutoStartPolicy
    private var targetReturnPolicy = VirtualAudioTargetReturnPolicy()
    private var routeSubscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var refreshing = false
    private var monitoring = false
    private var topologyListener: AudioObjectPropertyListenerBlock?
    private var topologyAddress = AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
    private var aliases = AudioDiagnosticAnonymizer()
    var selectedDevice: AudioBridgeDevice? {
        let matches = devices.filter { $0.uid == model.uid };return matches.count == 1 ? matches[0] : nil
    }
    var forwardingEnabled: Bool { isSystemRoute && model.hasSession && lastFailure == nil && model.state != .stopping }
    var busy: Bool { model.hasSession || model.starting || model.state == .stopping }
    var canStart: Bool { model.state == .ready && !busy && !model.suspended && !needsRestart }
    init(defaults: UserDefaults = .standard, engine: AudioBridgeEngine = AudioBridgeEngine()) {
        self.defaults = defaults
        autoStartPolicy = VirtualAudioAutoStartPolicy(manuallyDisabled:defaults.bool(forKey:Self.manualStopKey))
        preference = AudioTargetPreference(defaults:defaults);self.engine = engine
        model = VirtualVolumeStateModel(uid:preference.uid)
    }
    func startMonitoring() {
        guard !monitoring else { return };monitoring = true
        let virtual = VirtualAudioDeviceStore.shared
        virtual.appear()
        virtual.$status.combineLatest(virtual.$installed)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.considerAutomaticRoute() }
            }.store(in:&routeSubscriptions)
        // React after @Published assignments, including startup device discovery.
        let audio = AudioOutputStore.shared
        audio.$selectedControlTargetID.combineLatest(audio.$outputs, audio.$current)
            .sink { [weak self] _, _, _ in
                Task { @MainActor [weak self] in self?.considerAutomaticRoute() }
            }.store(in: &routeSubscriptions)
        virtual.$updateAvailable.combineLatest(virtual.$identityUnconfirmed)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.considerAutomaticRoute() }
            }.store(in: &routeSubscriptions)
        refresh()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            let timestamp = mach_absolute_time()
            Task { @MainActor in
                self?.record("AUDIO_DEVICE_LIST_NOTIFICATION",result:"notificationMach=\(timestamp); observation only")
                self?.refresh()
            }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&topologyAddress,DispatchQueue.main,listener) == noErr { topologyListener = listener }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return };self.engine.recordBoundary("SLEEP", generation:self.model.generation);self.stop(suspend:true)
            }
        })
        observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in guard let self else { return };self.engine.recordBoundary("WAKE", generation:self.model.generation);self.autoStartPolicy.targetSelected();self.model.wake();self.engine.invalidate(self.model.generation);self.refresh() }
        })
    }
    func select(_ uid: String?) {
        targetReturnPolicy.cancel()
        let token = model.requestStop();engine.invalidate(token)
        engine.stop(generation:token) { [weak self] clean in
            guard let self else { return };if !clean { self.needsRestart = true;self.lastFailure = "HAL_TEARDOWN_UNCONFIRMED" }
        }
        autoStartPolicy.targetSelected()
        model.select(uid);preference.save(model.uid);engine.invalidate(model.generation)
        telemetry = nil;lastFailure = nil
        record("AUDIO_TARGET_SELECTED", result:"explicit UID selection; no playback")
        refresh()
    }
    func refresh() {
        guard !refreshing else { return };refreshing = true
        let token = model.generation
        engine.refresh(generation:token) { [weak self] update in
            guard let self else { return };self.refreshing = false
            guard update.generation == self.model.generation else { return }
            var reconciled = self.model
            reconciled.reconcile(update.devices, generation:token)
            let unchangedIdle = reconciled.state == self.model.state && !self.busy && self.devices == update.devices && update.telemetry == nil && update.error == nil && update.cleanupOK && !self.needsRestart
            if unchangedIdle { self.considerAutomaticRoute(); return }
            if self.devices != update.devices { self.devices = update.devices }
            let previous = self.model.state
            if let value = update.telemetry {
                if value.failure != "NONE" {
                    self.targetReturnPolicy.arm(uid:self.model.uid, wasRunning:self.model.state == .running,
                        systemRoute:self.isSystemRoute, failure:value.failure, cleanupOK:update.cleanupOK,
                        removalConfirmed:value.failureDetail?.contains("TARGET_REMOVAL_CONFIRMED=1") == true)
                }
                self.telemetry = value;self.model.observed(value,generation:token)
                if self.model.state == .running && value.failure == "NONE" { self.lastFailure = nil }
                if value.failure != "NONE" {
                    self.lastFailure = value.failure
                    let action = value.failure == "TARGET_UNAVAILABLE" ? "AUDIO_TARGET_LOST" : ["FORMAT_CHANGED","CONTEXT_CHANGED"].contains(value.failure) ? "AUDIO_FORMAT_CHANGED" : value.failure == "UNDERRUN" ? "AUDIO_UNDERRUN" : value.failure == "OVERRUN" ? "AUDIO_OVERRUN" : value.failure == "STOPPED" ? "AUDIO_BRIDGE_STOP" : "AUDIO_BRIDGE_FAILED"
                    self.record(action,result:"\(value.failure); origin=\(value.failureDetail ?? "UNAVAILABLE"); inputCallbacks=\(value.inputCallbacks ?? 0); callbacks=\(value.callbacks); frames=\(value.frames)")
                }
            } else if let error = update.error {
                self.targetReturnPolicy.cancel();self.lastFailure = error;self.model.fail(generation:token);self.record("AUDIO_BRIDGE_FAILED",result:error)
            } else if !self.needsRestart { self.model.reconcile(update.devices,generation:token) }
            if !update.cleanupOK { self.targetReturnPolicy.cancel();self.needsRestart = true;self.lastFailure = "HAL_TEARDOWN_UNCONFIRMED";self.model.fail(generation:token) }
            if previous != self.model.state, self.model.state == .ready { self.record("AUDIO_BRIDGE_READY",result:"format eligible; playback not started") }
            self.considerAutomaticRoute()
        }
    }
    private func considerAutomaticRoute() {
        guard monitoring else { return }
        let virtual = VirtualAudioDeviceStore.shared
        let eligible = canStart && virtual.installed && !virtual.updateAvailable && !virtual.identityUnconfirmed
            && virtual.status.loaded && virtual.status.matches == 1 && virtual.status.rate == 48000
            && selectedDevice.map { [44100.0,48000,88200,96000,176400,192000].contains($0.rate) } == true
        let selectedVirtual = VirtualAudioAutoStartPolicy.virtualSelected(
            systemDefault:virtual.status.defaultKnown && virtual.status.isDefault,
            controlUID:AudioOutputStore.shared.selectedAudioDevice?.id)
        if targetReturnPolicy.consume(uid:model.uid, eligible:eligible, virtualSelected:selectedVirtual,
                                      manuallyDisabled:autoStartPolicy.manuallyDisabled) {
            engine.recordBoundary("REBUILD_TARGET_RETURN_REQUESTED", generation:model.generation)
            record("AUDIO_ROUTE_TARGET_RETURN",result:"same physical UID returned; one fresh session; old endpoint retired")
            startRoute(automatic:true);return
        }
        guard !model.unexpectedStop else { return }
        guard autoStartPolicy.shouldStart(virtualSelected:selectedVirtual, eligible:eligible) else { return }
        record("AUDIO_ROUTE_AUTO_START",result:"system or app virtual output selected; saved physical UID only; no fallback")
        startRoute(automatic:true)
    }
    func startRoute(automatic: Bool = false) {
        let virtual = VirtualAudioDeviceStore.shared
        guard canStart, virtual.installed, virtual.status.loaded, virtual.status.matches == 1, virtual.status.rate == 48000,
              selectedDevice.map({ [44100.0,48000,88200,96000,176400,192000].contains($0.rate) }) == true else { return }
        if !automatic {
            autoStartPolicy.userStarted()
            defaults.set(false,forKey:Self.manualStopKey)
        }
        engine.recordBoundary(automatic ? "SESSION_PREPARE_AUTOMATIC_REQUESTED" : "SESSION_PREPARE_MANUAL_REQUESTED", generation:model.generation)
        startTest(fixture:"system")
    }
    func startTest(fixture: String) {
        guard canStart, let uid = model.uid, let token = model.requestStart() else { return }
        isSystemRoute = fixture == "system"
        if !model.unexpectedStop { lastFailure = nil;telemetry = nil };engine.invalidate(token)
        record("AUDIO_BRIDGE_START",result:isSystemRoute ? "system route; direct output PCM; explicit target-rate and clock-drift SRC; no default change" : "user test request; fixture=\(fixture); native rate; max 30s")
        startNative(uid:uid,fixture:fixture,token:token)
    }
    private func startNative(uid: String, fixture: String, token: UInt64) {
        guard token == model.generation,model.starting,!model.suspended else { return }
        engine.start(uid:uid,fixture:fixture,gain:fixture == "system" ? 1 : Float(gain),muted:muted,generation:token) { [weak self] error in
            guard let self,token == self.model.generation else { return }
            self.model.started(generation:token,error:error)
            if let error { self.lastFailure = error;if error.contains("RESTART_REQUIRED") || error.contains("TEARDOWN_UNCONFIRMED") { self.needsRestart = true };self.record("AUDIO_BRIDGE_FAILED",result:error) }
            self.updateTelemetryTimer();self.refresh()
        }
    }
    private func configure() {
        guard gain.isFinite,(0...1).contains(gain),model.hasSession else { return }
        engine.configure(gain:isSystemRoute ? 1 : Float(gain),muted:muted,generation:model.generation)
    }
    func stop(suspend: Bool = false) {
        targetReturnPolicy.cancel()
        if !suspend { autoStartPolicy.userStopped(); defaults.set(true,forKey:Self.manualStopKey) }
        let token = model.requestStop(suspend:suspend)
        engine.stop(generation:token) { [weak self] clean in
            guard let self,token == self.model.generation else { return }
            self.model.stopped(generation:token,clean:clean)
            if !clean { self.needsRestart = true;self.lastFailure = "HAL_TEARDOWN_UNCONFIRMED" }
            self.record("AUDIO_BRIDGE_STOP",result:clean ? (suspend ? "sleep; stopped; automatic route rechecked on wake" : "user stop") : "cleanup unconfirmed")
            self.updateTelemetryTimer()
            if !suspend { self.refresh() }
        }
    }
    private func updateTelemetryTimer() {
        if !busy { timer?.invalidate();timer = nil;return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            Task { @MainActor in guard let self else { return };if self.busy { self.refresh() } else { self.updateTelemetryTimer() } }
        }
    }
    func shutdown() {
        targetReturnPolicy.cancel()
        timer?.invalidate();timer = nil
        if let listener = topologyListener { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&topologyAddress,DispatchQueue.main,listener);topologyListener = nil }
        monitoring = false
        routeSubscriptions.removeAll()
        VirtualAudioDeviceStore.shared.disappear()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) };observers.removeAll()
        _ = model.requestStop(suspend:true)
        let clean = engine.shutdown()
        record("AUDIO_BRIDGE_STOP",result:clean ? "app termination; HAL deregistered" : "app termination; cleanup unconfirmed")
    }
    private func record(_ action: String, result: String) {
        // Never emit raw UID into exported semantic events.
        DiagnosticEvents.record("audio",action,target:aliases.alias(model.uid),result:"routeGeneration=\(model.generation); \(result)")
    }
    func redactDiagnostics(_ report: String, uids: [String]) -> String { aliases.redact(report,uids:uids) }
    var diagnosticSummary: String {
        let target = aliases.alias(model.uid)
        let device = selectedDevice
        var result = "target=\(target) state=\(model.state.rawValue) generation=\(model.generation) SYSTEM_AUDIO_ROUTING=\(Self.systemAudioRouting)\nrate=\(device?.rate ?? 0) channels=\(device?.channels ?? 0) processing=Float32 physicalBits=\(device?.physicalBits.map(String.init) ?? "UNAVAILABLE") \(isSystemRoute ? (model.hasSession ? "SYSTEM_ROUTE CLOCK_DRIFT_SRC_CONFIGURED" : "SYSTEM_ROUTE_STOPPED") : "DIRECT_PATH BRIDGE_SRC_INACTIVE")\nbuffer=\(device?.buffer.description ?? "UNAVAILABLE") deviceLatency=\(device?.latency?.description ?? "UNAVAILABLE") safety=\(device?.safety?.description ?? "UNAVAILABLE") streamLatency=\(device?.streamLatency?.description ?? "UNAVAILABLE")"
        if let t = telemetry { if let details=t.bufferDetails { result += "\nbufferPlan=\(details)" };result += "\nfailure=\(t.failure) origin=\(t.failureDetail ?? "UNAVAILABLE") transportUnderrun=\(t.transportUnderrun.map(String.init) ?? "UNAVAILABLE") transportOverrun=\(t.transportOverrun.map(String.init) ?? "UNAVAILABLE")\nepoch=\(t.epoch) callbacks=\(t.callbacks) frames=\(t.frames) fill=\(t.fill) min=\(t.minFill) max=\(t.maxFill) capacity=\(t.capacity) targetFill=\(t.targetFill) underrun=\(t.underrun) overrun=\(t.overrun) ESTIMATED_SOFTWARE_ADDED_LATENCY ringMS=\(t.ringMS) bufferMS=\(t.bufferMS) (separate components; acoustic latency UNKNOWN) ringResidenceStartupInclusiveMS=\(t.residenceMS?.description ?? "UNAVAILABLE")" }
        return result
    }
}
