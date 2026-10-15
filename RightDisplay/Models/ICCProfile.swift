// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation
import CryptoKit

struct ICCXYZ: Equatable {
    let x: Double, y: Double, z: Double
    var xy: ICCXY? {
        let sum = x + y + z
        guard sum.isFinite, sum > 0 else { return nil }
        let point = ICCXY(x: x / sum, y: y / sum)
        return point.isValid ? point : nil
    }
}
struct ICCXY: Equatable {
    let x: Double, y: Double
    var isValid: Bool { x.isFinite && y.isFinite && x >= 0 && y > 0 && x + y <= 1.0001 }
}
struct ICCMatrix: Equatable {
    let values: [Double] // Row-major, maps source XYZ to PCS XYZ for chad.
    var inverse: ICCMatrix? {
        guard values.count == 9 else { return nil }
        let a = values
        let d = a[0]*(a[4]*a[8]-a[5]*a[7])-a[1]*(a[3]*a[8]-a[5]*a[6])+a[2]*(a[3]*a[7]-a[4]*a[6])
        guard d.isFinite, abs(d) > 1e-10 else { return nil }
        return ICCMatrix(values: [a[4]*a[8]-a[5]*a[7],a[2]*a[7]-a[1]*a[8],a[1]*a[5]-a[2]*a[4],a[5]*a[6]-a[3]*a[8],a[0]*a[8]-a[2]*a[6],a[2]*a[3]-a[0]*a[5],a[3]*a[7]-a[4]*a[6],a[1]*a[6]-a[0]*a[7],a[0]*a[4]-a[1]*a[3]].map { $0/d })
    }
    func apply(_ p: ICCXYZ) -> ICCXYZ {
        ICCXYZ(x: values[0]*p.x+values[1]*p.y+values[2]*p.z,
               y: values[3]*p.x+values[4]*p.y+values[5]*p.z,
               z: values[6]*p.x+values[7]*p.y+values[8]*p.z)
    }
}
enum ICCTRC: Equatable {
    case gamma(Double), parametric(Int, [Double]), sampled([Double]), unsupported(String)
    var summary: String {
        switch self {
        case .gamma(let g): return String(format: "Gamma %.4g", g)
        case .parametric(let type, let p): return "Parametric type \(type) · \(p.count) parameters"
        case .sampled(let p): return "Sampled curve · \(p.count) samples"
        case .unsupported(let reason): return "Unavailable / \(reason)"
        }
    }
}
enum ICCVCGT: Equatable {
    case table([[Double]], Int), formula([[Double]]), unsupported(String)
    var curves: [[Double]] {
        switch self {
        case .table(let values, _): return values
        case .formula(let channels): return channels.map { p in (0...128).map { p[1] + (p[2]-p[1])*pow(Double($0)/128,p[0]) } }
        case .unsupported: return []
        }
    }
    var summary: String {
        switch self {
        case .table(let channels, let bits): return "\(channels.count) channels · \(channels.first?.count ?? 0) samples · \(bits) bit"
        case .formula(let channels): return "\(channels.count) channels · gamma/min/max formula"
        case .unsupported(let reason): return "Unsupported: \(reason)"
        }
    }
}
struct ICCProfileMetadata {
    let version: String, profileClass: String, colorSpace: String, pcs: String
    let creationDate: Date?
    let manufacturer: String?, model: String?
    let name: String?, copyright: String?
    let white: ICCXYZ?
    let colorants: [ICCXYZ?] // R/G/B; missing entries retain their channel.
    let trcs: [ICCTRC?]
    let chad: ICCMatrix?
    let vcgt: ICCVCGT?
    let hasLUT: Bool
    let structureValid: Bool
    let issues: [String]
    var isMatrix: Bool { colorSpace == "RGB" && pcs == "XYZ" && !hasLUT && colorants.allSatisfy { $0 != nil } && trcs.allSatisfy { curve in
        guard let curve else { return false }; if case .unsupported = curve { return false }; return true
    } }
    var gamut: [ICCXY]? {
        guard isMatrix, let white, white.xy != nil else { return nil }
        let transform: (ICCXYZ) -> ICCXYZ = { chad?.inverse?.apply($0) ?? $0 }
        // A present but singular/unsupported adaptation cannot be ignored.
        guard chad == nil || chad?.inverse != nil else { return nil }
        let points = colorants.compactMap { $0 }.map(transform).compactMap(\.xy)
        guard points.count == 3, transform(white).xy != nil else { return nil }
        return points
    }
    var gamutWhite: ICCXY? { guard gamut != nil, let white else { return nil }; return (chad?.inverse?.apply(white) ?? white).xy }
    var gamutBasis: String { chad != nil ? "Inverse chad · profile source xy" : "ICC tag xy · adaptation unavailable" }
}
struct ICCProfileIdentity: Equatable {
    let digest: String
    let path: String?
    init(data: Data, url: URL?) {
        digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        path = url?.standardizedFileURL.resolvingSymlinksInPath().path
    }
    func matches(_ observed: Self) -> Bool {
        digest == observed.digest && (path == nil || observed.path == nil || path == observed.path)
    }
}
struct ICCDisplayContext: Equatable {
    let displayID: UInt32
    let connectionInstance: String
    let generation: UUID
    let colorSyncUUID: String
}
struct ICCAssociationTransaction {
    enum Result: String { case waiting = "WAITING", confirmed = "CONFIRMED", unconfirmed = "UNCONFIRMED", failed = "FAILED", stale = "STALE_CONTEXT" }
    let context: ICCDisplayContext
    let target: ICCProfileIdentity
    var accepted = false
    var stableReads = 0
    mutating func observe(_ value: ICCProfileIdentity?, context fresh: ICCDisplayContext?, timedOut: Bool) -> Result {
        guard fresh == context else { return .stale }
        guard accepted else { return .failed }
        stableReads = value.map { target.matches($0) } == true ? stableReads + 1 : 0
        if stableReads >= 2 { return .confirmed }
        return timedOut ? .unconfirmed : .waiting
    }
}

enum ICCParser {
    static let maximumBytes = 16 * 1024 * 1024
    enum Failure: Error { case invalidHeader, unsupportedVersion }
    static func parse(_ bytes: Data) throws -> ICCProfileMetadata {
        let d = [UInt8](bytes)
        func u16(_ i: Int) -> Int { Int(d[i]) << 8 | Int(d[i+1]) }
        func u32(_ i: Int) -> Int { Int(d[i]) << 24 | Int(d[i+1]) << 16 | Int(d[i+2]) << 8 | Int(d[i+3]) }
        func sig(_ i: Int) -> String { String(bytes: d[i..<i+4], encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown" }
        guard d.count >= 132, d.count <= maximumBytes, sig(36) == "acsp", u32(0) >= 132, u32(0) <= d.count else { throw Failure.invalidHeader }
        guard [2,4].contains(Int(d[8])) else { throw Failure.unsupportedVersion }
        let end = u32(0), count = u32(128)
        var tags: [String: [UInt8]] = [:], issues: [String] = [], spans: [Range<Int>] = []
        var structural = count <= 4096 && count <= (end-132)/12
        if structural {
            for i in 0..<count {
                let entry = 132+i*12, name = sig(entry), offset = u32(entry+4), length = u32(entry+8)
                guard offset >= 132+count*12, offset % 4 == 0, length >= 8, offset <= end, length <= end-offset else {
                    structural = false; issues.append("\(name): invalid tag bounds"); continue
                }
                let span = offset..<offset+length
                guard !spans.contains(where: { $0.overlaps(span) && $0 != span }), tags[name] == nil else {
                    structural = false; issues.append("\(name): overlapping/duplicate tag"); continue
                }
                spans.append(span); tags[name] = Array(d[span])
            }
        } else { issues.append("Truncated/oversized tag table") }
        func tag(_ name: String) -> ICCBytes? { tags[name].map(ICCBytes.init) }
        func xyz(_ name: String) -> ICCXYZ? {
            guard let t = tag(name) else { return nil }
            guard t.signature == "XYZ", t.d.count >= 20 else { issues.append("\(name): unsupported/truncated XYZ"); return nil }
            return ICCXYZ(x: t.fixed(8), y: t.fixed(12), z: t.fixed(16))
        }
        func text(_ name: String) -> String? { tag(name)?.text }
        let dateParts = (0..<6).map { u16(24+$0*2) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: dateParts[0], month: dateParts[1], day: dateParts[2], hour: dateParts[3], minute: dateParts[4], second: dateParts[5])
        let date = cal.date(from: components).flatMap { cal.dateComponents([.year,.month,.day,.hour,.minute,.second], from: $0) == components ? $0 : nil }
        func metadataSignature(_ at: Int) -> String? { d[at..<at+4].allSatisfy { $0 == 0 } ? nil : sig(at) }
        let white = xyz("wtpt"), primaries = ["rXYZ","gXYZ","bXYZ"].map(xyz)
        let curves = ["rTRC","gTRC","bTRC"].map { tag($0)?.trc }
        var chad: ICCMatrix?
        if let t = tag("chad") {
            if t.signature == "sf32", t.d.count >= 44 { chad = ICCMatrix(values: (0..<9).map { t.fixed(8+$0*4) }) }
            else { issues.append("chad: unsupported/truncated"); chad = ICCMatrix(values: []) }
        }
        return ICCProfileMetadata(version: "\(d[8]).\(d[9] >> 4).\(d[9] & 15)", profileClass: sig(12), colorSpace: sig(16), pcs: sig(20), creationDate: date,
            manufacturer: text("dmnd") ?? metadataSignature(48), model: text("dmdd") ?? metadataSignature(52), name: text("desc"), copyright: text("cprt"),
            white: white, colorants: primaries, trcs: curves, chad: chad, vcgt: tag("vcgt")?.vcgt,
            hasLUT: tags.keys.contains { $0.hasPrefix("A2B") || $0.hasPrefix("B2A") || $0.hasPrefix("D2B") || $0.hasPrefix("B2D") }, structureValid: structural, issues: issues)
    }
}
private struct ICCBytes {
    let d: [UInt8]
    init(_ d: [UInt8]) { self.d = d }
    var signature: String { String(bytes: d.prefix(4), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "Unknown" }
    func u16(_ i: Int) -> Int { Int(d[i]) << 8 | Int(d[i+1]) }
    func u32(_ i: Int) -> Int { Int(d[i]) << 24 | Int(d[i+1]) << 16 | Int(d[i+2]) << 8 | Int(d[i+3]) }
    func fixed(_ i: Int) -> Double { Double(Int32(bitPattern: UInt32(u32(i)))) / 65536 }
    var text: String? {
        switch signature {
        case "text": return String(bytes: d.dropFirst(8).prefix { $0 != 0 }, encoding: .utf8)
        case "desc":
            guard d.count >= 12 else { return nil }; let n = u32(8)
            guard n > 0, n <= d.count-12 else { return nil }
            return String(bytes: d[12..<12+n].prefix { $0 != 0 }, encoding: .ascii)
        case "mluc":
            guard d.count >= 16 else { return nil }; let n = u32(8), size = u32(12)
            guard n > 0, n <= 4096, size >= 12, size <= d.count, n <= (d.count-16)/size else { return nil }
            for i in 0..<n {
                let p = 16+i*size, length = u32(p+4), offset = u32(p+8)
                guard length % 2 == 0, offset >= 16+n*size, offset <= d.count, length <= d.count-offset else { continue }
                if let value = String(data: Data(d[offset..<offset+length]), encoding: .utf16BigEndian) { return value }
            }
            return nil
        default: return nil
        }
    }
    var trc: ICCTRC {
        if signature == "curv", d.count >= 12 {
            let n = u32(8)
            if n == 0 { return .gamma(1) }
            guard n <= 4096, n <= (d.count-12)/2 else { return .unsupported("truncated/oversized curve") }
            if n == 1 { let g = Double(u16(12))/256; return g > 0 ? .gamma(g) : .unsupported("invalid gamma") }
            return .sampled((0..<n).map { Double(u16(12+$0*2))/65535 })
        }
        if signature == "para", d.count >= 12 {
            let type = u16(8), sizes = [1,3,4,5,7]
            guard type < sizes.count, d.count >= 12+sizes[type]*4 else { return .unsupported("parametric type/bounds") }
            let p = (0..<sizes[type]).map { fixed(12+$0*4) }
            guard p[0] > 0 else { return .unsupported("invalid gamma") }
            return type == 0 ? .gamma(p[0]) : .parametric(type,p)
        }
        return .unsupported("tag type/bounds")
    }
    var vcgt: ICCVCGT {
        guard signature == "vcgt", d.count >= 12 else { return .unsupported("tag type/bounds") }
        switch u32(8) {
        case 0:
            guard d.count >= 18 else { return .unsupported("truncated table") }
            let channels = u16(12), n = u16(14), size = u16(16)
            guard [1,3].contains(channels), n >= 2, n <= 4096, [1,2].contains(size), channels*n*size <= d.count-18 else { return .unsupported("table dimensions/bounds") }
            return .table((0..<channels).map { c in (0..<n).map { i in let p = 18+(c*n+i)*size; return size == 1 ? Double(d[p])/255 : Double(u16(p))/65535 } }, size*8)
        case 1:
            guard d.count >= 48 else { return .unsupported("truncated formula") }
            let p = (0..<3).map { c in (0..<3).map { fixed(12+(c*3+$0)*4) } }
            guard p.allSatisfy({ $0[0] > 0 && $0[1] >= 0 && $0[2] <= 1 && $0[1] <= $0[2] }) else { return .unsupported("invalid formula") }
            return .formula(p)
        default: return .unsupported("unknown curve type")
        }
    }
}
enum ICCReferenceGamut: String, CaseIterable, Identifiable {
    case sRGB = "sRGB / Rec.709", displayP3 = "Display P3", adobeRGB = "Adobe RGB", bt2020 = "BT.2020"
    var id: String { rawValue }
    var primaries: [ICCXY] {
        switch self {
        case .sRGB: return [.init(x:0.64,y:0.33),.init(x:0.30,y:0.60),.init(x:0.15,y:0.06)]
        case .displayP3: return [.init(x:0.68,y:0.32),.init(x:0.265,y:0.69),.init(x:0.15,y:0.06)]
        case .adobeRGB: return [.init(x:0.64,y:0.33),.init(x:0.21,y:0.71),.init(x:0.15,y:0.06)]
        case .bt2020: return [.init(x:0.708,y:0.292),.init(x:0.170,y:0.797),.init(x:0.131,y:0.046)]
        }
    }
    static let white = ICCXY(x:0.3127,y:0.3290)
}
