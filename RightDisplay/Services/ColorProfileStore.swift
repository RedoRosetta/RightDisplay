// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import Combine
import ColorSync
import CoreGraphics
import UniformTypeIdentifiers

struct ColorProfileInfo: Identifiable {
    enum Source: String { case system = "System", user = "User", device = "Display/device-associated", other = "Other/Unknown", opened = "Opened file · not installed" }
    let url: URL?
    let identity: ICCProfileIdentity
    let name: String
    let source: Source
    let metadata: ICCProfileMetadata
    let colorSyncVerified: Bool
    var id: String { "\(identity.digest)|\(identity.path ?? "data-only")" }
    var switchEligible: Bool { url != nil && colorSyncVerified && metadata.structureValid && metadata.profileClass == "mntr" && ["RGB","GRAY"].contains(metadata.colorSpace) }
}

// Public APIs only. No global CGDisplayRestoreColorSyncSettings or private lookup.
enum PublicColorSyncProfiles {
    private static var displayClass: CFString { kColorSyncDisplayDeviceClass!.takeUnretainedValue() }
    static func uuid(_ id: UInt32) -> CFUUID? { CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() }
    static func uuidString(_ id: UInt32) -> String? {
        guard id != 0, CGDisplayIsOnline(id) != 0, let uuid = uuid(id) else { return nil }
        return CFUUIDCreateString(nil,uuid) as String
    }
    static func deviceInfo(_ id: UInt32) -> [String:Any]? {
        guard let uuid = uuid(id) else { return nil }
        return ColorSyncDeviceCopyDeviceInfo(displayClass, uuid)?.takeRetainedValue() as? [String:Any]
    }
    private static func info(_ profile: ColorSyncProfile, url: URL?, source: ColorProfileInfo.Source) throws -> ColorProfileInfo {
        var error: Unmanaged<CFError>?
        guard let data = ColorSyncProfileCopyData(profile, &error)?.takeRetainedValue() else {
            throw NSError(domain: "ColorSync",code: 1,userInfo: [NSLocalizedDescriptionKey:error?.takeRetainedValue().localizedDescription ?? "Profile data unavailable"])
        }
        let bytes = data as Data
        let metadata = try ICCParser.parse(bytes)
        var errors: Unmanaged<CFError>?, warnings: Unmanaged<CFError>?
        let verified = ColorSyncProfileVerify(profile, &errors, &warnings)
        _ = errors?.takeRetainedValue(); _ = warnings?.takeRetainedValue()
        let description = ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() as String?
        return ColorProfileInfo(url: url, identity: ICCProfileIdentity(data:bytes,url:url), name: description ?? metadata.name ?? url?.lastPathComponent ?? "Unnamed profile",
            source:source,metadata:metadata,colorSyncVerified:verified)
    }
    static func current(_ id: UInt32) throws -> ColorProfileInfo {
        guard id != 0, CGDisplayIsOnline(id) != 0,
              let profile = ColorSyncProfileCreateWithDisplayID(id)?.takeRetainedValue() else {
            throw NSError(domain:"ColorSync",code:2,userInfo:[NSLocalizedDescriptionKey:"Current association unavailable"])
        }
        let url = ColorSyncProfileGetURL(profile,nil)?.takeUnretainedValue() as URL?
        return try info(profile,url:url,source:.device)
    }
    static func inspect(_ url: URL, source: ColorProfileInfo.Source) throws -> ColorProfileInfo {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.isFileURL, FileManager.default.isReadableFile(atPath:resolved.path),
              let size = try resolved.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey]).fileSize,
              size <= ICCParser.maximumBytes,
              (try resolved.resourceValues(forKeys:[.isRegularFileKey])).isRegularFile == true else {
            throw NSError(domain:"ICC",code:3,userInfo:[NSLocalizedDescriptionKey:"File unavailable or too large"])
        }
        // Validate original file structure before ColorSync can repair/normalize it.
        let raw = try Data(contentsOf:resolved)
        let parsed = try ICCParser.parse(raw)
        guard parsed.structureValid else { throw NSError(domain:"ICC",code:4,userInfo:[NSLocalizedDescriptionKey:"Malformed ICC tag structure"]) }
        guard let profile = ColorSyncProfileCreateWithURL(resolved as CFURL,nil)?.takeRetainedValue() else {
            throw NSError(domain:"ColorSync",code:5,userInfo:[NSLocalizedDescriptionKey:"Unsupported profile file"])
        }
        return try info(profile,url:resolved,source:source)
    }
    static func available(_ id: UInt32, current: ColorProfileInfo?) -> [ColorProfileInfo] {
        let user = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/ColorSync/Profiles")
        var urls: [URL:ColorProfileInfo.Source] = [:]
        for (root, source) in [(URL(fileURLWithPath:"/System/Library/ColorSync/Profiles"),ColorProfileInfo.Source.system),
                               (URL(fileURLWithPath:"/Library/ColorSync/Profiles"),.system),(user,.user)] {
            guard let files = FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) else { continue }
            for case let file as URL in files where ["icc","icm"].contains(file.pathExtension.lowercased()) {
                urls[file.standardizedFileURL.resolvingSymlinksInPath()] = source
            }
        }
        if let device = deviceInfo(id) {
            func addURLs(_ object: Any) {
                if let url = object as? URL, url.isFileURL { urls[url.standardizedFileURL.resolvingSymlinksInPath()] = .device }
                else if let dictionary = object as? [String:Any] { for item in dictionary.values { addURLs(item) } }
            }
            addURLs(device)
        }
        if let url = current?.url { urls[url.standardizedFileURL.resolvingSymlinksInPath()] = .device }
        return urls.compactMap { try? inspect($0.key,source:$0.value) }.filter { $0.metadata.profileClass == "mntr" && ["RGB","GRAY"].contains($0.metadata.colorSpace) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func associate(_ profile: ColorProfileInfo, context: ICCDisplayContext) -> Bool {
        guard let url = profile.url, profile.switchEligible,
              uuidString(context.displayID) == context.colorSyncUUID, let uuid = uuid(context.displayID),
              deviceInfo(context.displayID) != nil else { return false }
        let values: [CFString:Any] = [kColorSyncDeviceDefaultProfileID!.takeUnretainedValue():url as CFURL,
            kColorSyncProfileUserScope!.takeUnretainedValue():kCFPreferencesCurrentUser as Any,
            kColorSyncProfileHostScope!.takeUnretainedValue():kCFPreferencesCurrentHost as Any]
        return ColorSyncDeviceSetCustomProfiles(displayClass,uuid,values as CFDictionary)
    }
}

@MainActor
final class ColorProfileStore: ObservableObject {
    @Published private(set) var current: ColorProfileInfo?
    @Published private(set) var profiles: [ColorProfileInfo] = []
    @Published private(set) var inspected: ColorProfileInfo?
    @Published private(set) var busy = false
    @Published private(set) var loading = false
    @Published private(set) var status = "MACOS_PROFILE_ASSOCIATION · UNAVAILABLE"
    @Published private(set) var lastError: String?
    private var context: ICCDisplayContext?
    private var readToken = UUID()
    private var operationToken = UUID()
    private var operation: Task<Void,Never>?
    private var lease: UUID?
    private let readbackInterval: UInt64
    init(readbackInterval: UInt64 = 400_000_000) { self.readbackInterval = readbackInterval }
    func clearInspection() { inspected = nil }

    static func displayContext(_ display: DisplaySnapshot, store: DisplayStore) -> ICCDisplayContext? {
        guard let device = display.deviceIdentity, let uuid = PublicColorSyncProfiles.uuidString(display.id),
              store.displays.filter({ PublicColorSyncProfiles.uuidString($0.id) == uuid }).count == 1 else { return nil }
        return ICCDisplayContext(displayID:display.id,connectionInstance:device.connectionInstanceKey,
            generation:store.colorProfileGeneration,colorSyncUUID:uuid)
    }
    private func freshContext(_ store: DisplayStore) -> ICCDisplayContext? {
        guard let display = store.selectedDisplay else { return nil }
        return Self.displayContext(display,store:store)
    }
    func refresh(display: DisplaySnapshot, store: DisplayStore) {
        let next = Self.displayContext(display,store:store)
        if next != context { cancel(store:store); context = next; current = nil; profiles = []; inspected = nil }
        guard !busy else { return }
        let token = UUID(); readToken = token; loading = true; lastError = nil
        guard let next else { loading = false; status = "MACOS_PROFILE_ASSOCIATION · UNAVAILABLE (display identity)"; return }
        Task {
            let result = await Task.detached { () -> (ColorProfileInfo?,[ColorProfileInfo],String?) in
                do { let current = try PublicColorSyncProfiles.current(next.displayID); return (current,PublicColorSyncProfiles.available(next.displayID,current:current),nil) }
                catch { return (nil,PublicColorSyncProfiles.available(next.displayID,current:nil),error.localizedDescription) }
            }.value
            guard readToken == token, freshContext(store) == next, !busy else { return }
            current = result.0; profiles = result.1; lastError = result.2; loading = false
            status = current != nil ? "CURRENT_ASSOCIATED_PROFILE · macOS / ColorSync" : "MACOS_PROFILE_ASSOCIATION · UNAVAILABLE"
        }
    }
    func apply(_ selected: ColorProfileInfo, store: DisplayStore) {
        guard !busy, let context, freshContext(store) == context,
              let target = profiles.first(where: { $0.id == selected.id }), target.switchEligible,
              let display = store.selectedDisplay, let device = display.deviceIdentity,
              let reservation = store.reserveColorProfileOperation(device) else { lastError = "显示操作占用或显示器上下文不可用；未关联描述文件。"; return }
        let token = UUID(); operationToken = token; readToken = UUID(); lease = reservation
        busy = true; status = "MACOS_PROFILE_ASSOCIATION · WAITING"; lastError = nil
        operation = Task {
            defer {
                store.releaseColorProfileOperation(reservation)
                if operationToken == token { busy = false; lease = nil; operation = nil }
            }
            do {
                guard !Task.isCancelled, operationToken == token, freshContext(store) == context else { return }
                // Reopen the concrete enumerated URL; a replaced file is not the chosen identity.
                guard let url = target.url else { throw ICCParser.Failure.invalidHeader }
                let freshTarget = try PublicColorSyncProfiles.inspect(url,source:target.source)
                guard !Task.isCancelled, operationToken == token else { return }
                guard target.identity == freshTarget.identity, freshContext(store) == context else {
                    status = "MACOS_PROFILE_ASSOCIATION · UNCONFIRMED (target/context changed)"; return
                }
                var transaction = ICCAssociationTransaction(context:context,target:target.identity)
                transaction.accepted = PublicColorSyncProfiles.associate(freshTarget,context:context)
                DiagnosticEvents.record("color-profile","association.request",target:"displayID=\(context.displayID)",requested:target.identity.digest,
                    method:"ColorSyncDeviceSetCustomProfiles",result:transaction.accepted ? "ACCEPTED (not confirmed)" : "REJECTED")
                guard transaction.accepted else { status = "MACOS_PROFILE_ASSOCIATION · FAILED"; return }
                for attempt in 0..<12 {
                    try await Task.sleep(nanoseconds:readbackInterval)
                    guard operationToken == token else { return }
                    guard freshContext(store) == context else { status = "MACOS_PROFILE_ASSOCIATION · UNCONFIRMED (context changed)"; return }
                    let observed = await Task.detached { try? PublicColorSyncProfiles.current(context.displayID) }.value
                    guard !Task.isCancelled, operationToken == token else { return }
                    guard freshContext(store) == context else { status = "MACOS_PROFILE_ASSOCIATION · UNCONFIRMED (context changed)"; return }
                    let result = transaction.observe(observed?.identity,context:freshContext(store),timedOut:attempt == 11)
                    DiagnosticEvents.record("color-profile","association.readback",target:"displayID=\(context.displayID)",requested:target.identity.digest,
                        observed:observed?.identity.digest,method:"ColorSyncProfileCreateWithDisplayID",result:result.rawValue)
                    if result != .waiting {
                        current = observed; status = "MACOS_PROFILE_ASSOCIATION · \(result.rawValue)"; return
                    }
                }
            } catch is CancellationError { }
            catch { if operationToken == token { lastError = error.localizedDescription; status = "MACOS_PROFILE_ASSOCIATION · FAILED" } }
        }
    }
    func inspectFile(store: DisplayStore) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["icc","icm"].compactMap { UTType(filenameExtension:$0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = try PublicColorSyncProfiles.inspect(url,source:.opened)
            guard profile.colorSyncVerified else { throw ICCParser.Failure.invalidHeader }
            inspected = profile; lastError = nil
            // Inspection does not install or associate. Refresh repository separately.
            if let display = store.selectedDisplay { refresh(display:display,store:store) }
        } catch { inspected = nil; lastError = "无法检查 ICC：\(error.localizedDescription)" }
    }
    func cancel(store: DisplayStore) {
        readToken = UUID(); operationToken = UUID(); operation?.cancel(); operation = nil
        if let lease { store.releaseColorProfileOperation(lease) }
        lease = nil; busy = false; loading = false
    }
}
