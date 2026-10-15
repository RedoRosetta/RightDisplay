// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AudioToolbox
import Combine
import CoreAudio
import Foundation

struct AudioOutputSnapshot: Identifiable, Equatable {
    let id: String
    let deviceID: AudioDeviceID
    let name: String
    let transport: String
    let channels: Int
    let sampleRate: Double
    let format: String
    let dolby: SignalValue
    let systemVolumeWritable: Bool
    let volume: Double?
    let isMuted: Bool?
    let isDefault: Bool

    // Presentation only: the concrete CoreAudio UID and system name stay intact.
    var controlDisplayName: String {
        id == "RightDisplay.VirtualVolume"
            ? (AppLocalization.isEnglish ? "Right Display Virtual Audio" : "Right Display 虚拟音频") : name
    }
    var controlDisplayTitle: String {
        id == "RightDisplay.VirtualVolume" ? controlDisplayName
            : "\(name) · \(AppLocalization.string(transport))"
    }

    static let unavailable = AudioOutputSnapshot(
        id: "unavailable",
        deviceID: 0,
        name: "没有音频输出",
        transport: "—",
        channels: 0,
        sampleRate: 0,
        format: "—",
        dolby: SignalValue(text: "不可用", verification: .unavailable),
        systemVolumeWritable: false,
        volume: nil,
        isMuted: nil,
        isDefault: false
    )
}

@MainActor
final class AudioOutputStore: ObservableObject {
    static let shared = AudioOutputStore()
    static let followsSystemTargetID = "system-default"
    static let appleTVTargetID = "apple-tv-homepod"

    @Published private(set) var current = AudioOutputSnapshot.unavailable
    @Published private(set) var outputs: [AudioOutputSnapshot] = []
    @Published var selectedControlTargetID: String {
        didSet { defaults.set(selectedControlTargetID, forKey: Keys.selectedControlTargetID) }
    }
    @Published private(set) var virtualKeyboardFailure:String?
    private var timer: Timer?
    private struct PropertyListener {
        let device: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var topologyListeners: [PropertyListener] = []
    private var levelListeners: [PropertyListener] = []
    private var observedDeviceIDs: Set<AudioDeviceID> = []
    private var listenerGeneration: UInt64 = 0
    private var pendingLevelDevices: Set<AudioDeviceID> = []
    private var levelUpdateTask: Task<Void, Never>?
    private var topologyRefreshPending = false
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let selectedControlTargetID = "selectedVolumeControlTargetID"
    }

    private init() {
        selectedControlTargetID = defaults.string(forKey: Keys.selectedControlTargetID)
            ?? Self.followsSystemTargetID
        installTopologyListeners()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode:.common) }
    }

    func refresh() {
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            &size,
            &device
        ) == noErr, device != 0 else {
            if current != .unavailable { current = .unavailable }
            if !outputs.isEmpty { outputs = [] }
            synchronizeLevelListeners()
            return
        }
        let nextOutputs = allOutputDeviceIDs()
            .map { snapshot(for: $0, defaultDeviceID: device) }
            .sorted {
                if $0.isDefault != $1.isDefault { return $0.isDefault }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        let nextCurrent = nextOutputs.first(where: { $0.deviceID == device })
            ?? snapshot(for: device, defaultDeviceID: device)
        if outputs != nextOutputs { outputs = nextOutputs }
        if current != nextCurrent { current = nextCurrent }
        synchronizeLevelListeners()
    }

    deinit {
        timer?.invalidate()
        levelUpdateTask?.cancel()
        for listener in topologyListeners + levelListeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.device, &address, .main, listener.block)
        }
    }

    private func installTopologyListeners() {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector:selector, mScope:kAudioObjectPropertyScopeGlobal, mElement:kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.enqueueTopologyRefresh() }
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
                topologyListeners.append(.init(device:AudioObjectID(kAudioObjectSystemObject), address:address, block:block))
            }
        }
    }
    private func enqueueTopologyRefresh() {
        guard !topologyRefreshPending else { return }
        topologyRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.topologyRefreshPending = false
            self.refresh()
        }
    }
    private func synchronizeLevelListeners() {
        var devices = Set(outputs.map(\.deviceID))
        if current.deviceID != 0 { devices.insert(current.deviceID) }
        guard devices != observedDeviceIDs else { return }
        listenerGeneration &+= 1
        levelUpdateTask?.cancel(); levelUpdateTask = nil
        pendingLevelDevices.removeAll()
        for listener in levelListeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.device, &address, .main, listener.block)
        }
        levelListeners.removeAll()
        observedDeviceIDs = devices
        let generation = listenerGeneration
        for device in devices {
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                for element in 0...8 {
                    var address = AudioObjectPropertyAddress(mSelector:selector, mScope:kAudioDevicePropertyScopeOutput, mElement:AudioObjectPropertyElement(element))
                    guard AudioObjectHasProperty(device, &address) else { continue }
                    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                        Task { @MainActor [weak self] in self?.enqueueLevelRead(device:device, generation:generation) }
                    }
                    if AudioObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr {
                        levelListeners.append(.init(device:device, address:address, block:block))
                    }
                }
            }
        }
    }
    private func enqueueLevelRead(device: AudioDeviceID, generation: UInt64) {
        guard generation == listenerGeneration, observedDeviceIDs.contains(device) else { return }
        pendingLevelDevices.insert(device)
        guard levelUpdateTask == nil else { return }
        levelUpdateTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            guard let self, !Task.isCancelled, generation == self.listenerGeneration else { return }
            self.levelUpdateTask = nil
            let devices = self.pendingLevelDevices
            self.pendingLevelDevices.removeAll()
            for device in devices { self.readChangedLevels(device:device) }
        }
    }
    private func readChangedLevels(device: AudioDeviceID) {
        // Validate UID before using a queued device ID; never select a fallback.
        guard let uid = stringProperty(device, selector:kAudioDevicePropertyDeviceUID, scope:kAudioObjectPropertyScopeGlobal) else { return }
        let volume = volumeScalar(device).map(Double.init)
        let muted = muteValue(device)
        var updated = outputs
        var changed = false
        for index in updated.indices where updated[index].deviceID == device && updated[index].id == uid {
            if updated[index].volume != volume || updated[index].isMuted != muted {
                updated[index] = replacingLevels(updated[index], volume:volume, muted:muted)
                changed = true
            }
        }
        if changed { outputs = updated }
        if current.deviceID == device, current.id == uid, current.volume != volume || current.isMuted != muted {
            current = replacingLevels(current, volume:volume, muted:muted)
        }
    }
    private func replacingLevels(_ old: AudioOutputSnapshot, volume: Double?, muted: Bool?) -> AudioOutputSnapshot {
        AudioOutputSnapshot(id:old.id, deviceID:old.deviceID, name:old.name, transport:old.transport,
            channels:old.channels, sampleRate:old.sampleRate, format:old.format, dolby:old.dolby,
            systemVolumeWritable:old.systemVolumeWritable, volume:volume, isMuted:muted, isDefault:old.isDefault)
    }

    var selectedAudioDevice: AudioOutputSnapshot? {
        switch selectedControlTargetID {
        case Self.appleTVTargetID:
            return nil
        case Self.followsSystemTargetID:
            return current.deviceID == 0 ? nil : current
        default:
            guard selectedControlTargetID.hasPrefix("coreaudio:") else { return nil }
            let uid = String(selectedControlTargetID.dropFirst("coreaudio:".count))
            return outputs.first { $0.id == uid }
        }
    }

    func targetID(for output: AudioOutputSnapshot) -> String {
        "coreaudio:\(output.id)"
    }

    func setVolume(_ newValue: Double) {
        guard let device = selectedAudioDevice?.deviceID, device != 0 else { return }
        writeVolume(newValue, device:device)
    }

    var virtualOutput: AudioOutputSnapshot? {
        let matches = outputs.filter { $0.id == "RightDisplay.VirtualVolume" }
        return matches.count == 1 ? matches[0] : nil
    }
    func setVirtualVolume(_ newValue: Double) {
        // Fresh unique virtual UID resolution, independent of physical/Apple TV selection.
        refresh()
        guard let output = virtualOutput, output.systemVolumeWritable else { return }
        writeVolume(newValue, device:output.deviceID)
    }
    private func writeVolume(_ newValue: Double, device: AudioDeviceID) {
        guard newValue.isFinite else { return }
        let value = Float32(min(1, max(0, newValue)))
        var wrote = false
        for element in writableVolumeElements(device) {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var mutableValue = value
            let size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectSetPropertyData(
                device, &address, 0, nil, size, &mutableValue
            ) == noErr { wrote = true }
        }
        if wrote { refresh() }
    }

    func setMuted(_ muted: Bool) {
        guard let device = selectedAudioDevice?.deviceID, device != 0 else { return }
        var value: UInt32 = muted ? 1 : 0
        for element in 0...8 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(element)
            )
            var writable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &writable) == noErr,
                  writable.boolValue else { continue }
            _ = AudioObjectSetPropertyData(
                device, &address, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), &value
            )
        }
        refresh()
    }

    func useVirtualSystemOutput() {
        virtualKeyboardFailure = nil
        refresh()
        guard let output = virtualOutput, output.systemVolumeWritable else {
            virtualKeyboardFailure = "虚拟设备不可用"; return
        }
        var address = AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var device = output.deviceID
        let result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
        refresh()
        guard result == noErr, virtualOutput?.deviceID == device, virtualOutput?.isDefault == true else {
            virtualKeyboardFailure = "系统输出切换未确认"; return
        }
    }

    private func snapshot(for device: AudioDeviceID, defaultDeviceID: AudioDeviceID) -> AudioOutputSnapshot {
        let name = stringProperty(
            device,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? "音频设备 \(device)"
        let uid = stringProperty(
            device,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? "device-\(device)"
        let transportID = uint32Property(
            device,
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? 0
        let stream = streamFormat(device)
        let formatCode = stream.map { fourCC($0.mFormatID) } ?? "—"
        let formatName: String
        let dolby: SignalValue
        switch formatCode {
        case "lpcm":
            formatName = "Linear PCM"
            dolby = SignalValue(text: "未启用（PCM）", verification: .verified)
        case "ac-3", "cac3", "IAC3":
            formatName = "Dolby Digital (AC-3)"
            dolby = SignalValue(text: "Dolby Digital", verification: .verified)
        case "ec-3":
            formatName = "Dolby Digital Plus (E-AC-3)"
            dolby = SignalValue(text: "Dolby Digital Plus", verification: .verified)
        default:
            formatName = formatCode
            dolby = SignalValue(text: "下游状态不可见", verification: .unavailable)
        }

        return AudioOutputSnapshot(
            id: uid,
            deviceID: device,
            name: name,
            transport: transportName(transportID),
            channels: Int(stream?.mChannelsPerFrame ?? 0),
            sampleRate: stream?.mSampleRate ?? 0,
            format: formatName,
            dolby: dolby,
            systemVolumeWritable: volumeIsWritable(device),
            volume: volumeScalar(device).map(Double.init),
            isMuted: muteValue(device),
            isDefault: device == defaultDeviceID
        )
    }

    private func allOutputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteCount
        ) == noErr, byteCount > 0 else { return [] }
        var devices = [AudioDeviceID](
            repeating: 0,
            count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteCount, &devices
        ) == noErr else { return [] }
        return devices.filter(hasOutputStreams)
    }

    private func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr
            && size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private func streamFormat(_ device: AudioDeviceID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private func stringProperty(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value?.takeUnretainedValue() as String?
    }

    private func uint32Property(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private func volumeIsWritable(_ device: AudioDeviceID) -> Bool {
        !writableVolumeElements(device).isEmpty
    }

    private func writableVolumeElements(_ device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        (0...8).compactMap { element in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(element)
            )
            var writable: DarwinBoolean = false
            if AudioObjectHasProperty(device, &address),
               AudioObjectIsPropertySettable(device, &address, &writable) == noErr,
               writable.boolValue {
                return AudioObjectPropertyElement(element)
            }
            return nil
        }
    }

    private func volumeScalar(_ device: AudioDeviceID) -> Float32? {
        for element in 0...8 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(element)
            )
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(device, &address),
               AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                return value
            }
        }
        return nil
    }

    private func muteValue(_ device: AudioDeviceID) -> Bool? {
        for element in 0...8 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(element)
            )
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectHasProperty(device, &address),
               AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                return value != 0
            }
        }
        return nil
    }

    private func transportName(_ value: UInt32) -> String {
        switch value {
        case kAudioDeviceTransportTypeHDMI: "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: "DisplayPort"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeBuiltIn: "内建"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "蓝牙"
        default: fourCC(value)
        }
    }

    private func fourCC(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? String(format: "0x%08X", value)
    }
}
