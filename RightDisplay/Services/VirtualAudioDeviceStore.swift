// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import Foundation
import Security
import CoreAudio

// Installation is delegated to the standard macOS Installer UI. No privileged
// shell from the app, audio-service restart, or automatic default-device change.
@MainActor
final class VirtualAudioDeviceStore: ObservableObject {
    static let shared = VirtualAudioDeviceStore()
    @Published private(set) var status = VirtualAudioDeviceStatus()
    @Published private(set) var installed = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var identityUnconfirmed = false
    @Published private(set) var failure: String?
    private let queue = DispatchQueue(label:"RightDisplay.VirtualAudio.Status",qos:.utility)
    private var reading = false
    private var generation: UInt64 = 0
    private var listener: AudioObjectPropertyListenerBlock?
    private var addresses = [kAudioHardwarePropertyDevices,kAudioHardwarePropertyDefaultOutputDevice,kAudioHardwarePropertyDefaultSystemOutputDevice].map { AudioObjectPropertyAddress(mSelector:$0,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain) }
    private var registered: [AudioObjectPropertyAddress] = []
    static let driverPath = "/Library/Audio/Plug-Ins/HAL/RightDisplayVirtualVolume.driver"
    func appear() {
        refresh()
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _,_ in Task { @MainActor in self?.refresh() } }
        listener = block
        for var address in addresses {
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,DispatchQueue.main,block) == noErr { registered.append(address) }
        }
    }
    func disappear() {
        if let block = listener { for var address in registered { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,DispatchQueue.main,block) } }
        listener = nil;registered.removeAll();generation &+= 1
    }
    func refresh() {
        guard !reading else { return };reading = true;let token = generation
        let path = Self.driverPath
        queue.async { [weak self] in
            let value: VirtualAudioDeviceStatus? = try? AudioBridgeJSON.decode(RVCopyStatusJSON())
            let exists = FileManager.default.fileExists(atPath:path)
            var code: SecStaticCode?
            var requirement: SecRequirement?
            let condition = String(cString: RDDriverRequirement())
            let valid = exists && SecStaticCodeCreateWithPath(URL(fileURLWithPath:path) as CFURL,[],&code) == errSecSuccess
                && SecRequirementCreateWithString(condition as CFString,[],&requirement) == errSecSuccess
                && code != nil && requirement != nil
                && SecStaticCodeCheckValidity(code!,SecCSFlags(rawValue:kSecCSStrictValidate),requirement) == errSecSuccess
            let installedVersion = (NSDictionary(contentsOfFile:path + "/Contents/Info.plist")?["CFBundleVersion"] as? String).flatMap(Int.init)
            let update = valid && (installedVersion ?? 0) < 21
            DispatchQueue.main.async {
                guard let self else { return };self.reading = false
                guard token == self.generation else { return }
                if self.updateAvailable != update { self.updateAvailable = update }
                if self.installed != valid { self.installed = valid }
                if self.identityUnconfirmed != (exists && !valid) { self.identityUnconfirmed = exists && !valid }
                let next = value ?? VirtualAudioDeviceStatus()
                if self.status != next { self.status = next }
            }
        }
    }
    func openPackage(uninstall: Bool) {
        guard !VirtualVolumeController.shared.busy else { return }
        if uninstall && !status.safeToRemove {
            failure = AppLocalization.isEnglish ? "Select another system output and stop virtual-device clients before uninstalling." : "请先在 macOS 中选择其他音频输出并停止虚拟设备的使用，再卸载。"
            return
        }
        let name = uninstall ? "UninstallVirtualAudio" : "InstallVirtualAudio"
        guard let url = Bundle.main.url(forResource:name,withExtension:"pkg",subdirectory:"VirtualAudioPackages") else {
            failure = AppLocalization.isEnglish ? "Installer package unavailable." : "安装包不可用。";return
        }
        failure = nil
        if !NSWorkspace.shared.open(url) { failure = AppLocalization.isEnglish ? "Could not open macOS Installer." : "无法打开 macOS 安装器。" }
        DiagnosticEvents.record("audio",uninstall ? "AUDIO_DRIVER_UNINSTALL_REQUEST" : "AUDIO_DRIVER_INSTALL_REQUEST",result:"opened system Installer; completion not confirmed")
    }
}
