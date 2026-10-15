// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
// Fake ColorSync/DisplayStore boundary; the production ColorProfileStore is compiled unchanged.
struct DisplaySnapshot { let id: UInt32; let deviceIdentity: DisplayDeviceIdentity? }
@MainActor final class DisplayStore {
    var displays: [DisplaySnapshot] = []
    var selectedDisplay: DisplaySnapshot?
    var colorProfileGeneration = UUID()
    var occupied = false
    var lease: UUID?
    var releases = 0
    func reserveColorProfileOperation(_ device: DisplayDeviceIdentity) -> UUID? {
        guard !occupied, lease == nil, selectedDisplay?.deviceIdentity == device else { return nil }
        let token = UUID(); lease = token; return token
    }
    func releaseColorProfileOperation(_ token: UUID) { if lease == token { lease = nil; releases += 1 } }
}
enum DiagnosticEvents { static func record(_ a:String,_ b:String,target:String,requested:String,observed:String? = nil,method:String,result:String) {} }
enum PublicColorSyncProfiles {
    static var observed: ColorProfileInfo!
    static var target: ColorProfileInfo!
    static var accepted = true
    static var requests = 0
    static var sharedUUID = false
    static var afterRequest: (() -> Void)?
    static func uuidString(_ id: UInt32) -> String? { sharedUUID ? "ambiguous-uuid" : "uuid-\(id)" }
    static func current(_ id: UInt32) throws -> ColorProfileInfo { observed }
    static func available(_ id: UInt32,current:ColorProfileInfo?) -> [ColorProfileInfo] { [target] }
    static func inspect(_ url: URL,source:ColorProfileInfo.Source) throws -> ColorProfileInfo { target }
    static func associate(_ profile:ColorProfileInfo,context:ICCDisplayContext) -> Bool { requests += 1; afterRequest?(); return accepted }
}
