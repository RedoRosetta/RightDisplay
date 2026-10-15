// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation

/// Canonical encoding of SLS LinkDescription values. This is not proof of
/// the final physical HDMI signal; retain the original raw value as evidence.
enum LinkPixelEncoding: UInt32, CaseIterable, Codable {
    case rgb = 0
    case yCbCr444 = 1
    case yCbCr422 = 2
    case yCbCr420 = 3

    var title: String {
        switch self {
        case .rgb: "RGB 4:4:4"
        case .yCbCr444: "YCbCr 4:4:4"
        case .yCbCr422: "YCbCr 4:2:2"
        case .yCbCr420: "YCbCr 4:2:0"
        }
    }

    var bandwidthComponentMultiplier: Double {
        switch self {
        case .rgb, .yCbCr444: 3
        case .yCbCr422: 2
        case .yCbCr420: 1.5
        }
    }

    static func isKnown(_ raw: UInt32) -> Bool { Self(rawValue: raw) != nil }
    static func title(for raw: UInt32?) -> String {
        raw.flatMap(Self.init(rawValue:))?.title ?? "格式未知"
    }
}

/// Presentation health is separate from the provenance of the reported value.
enum DisplayStatusIndicator: Equatable {
    case green, yellow, gray

    static func pixelEncoding(raw: UInt32?, known: Bool) -> Self {
        guard known, let raw, let encoding = LinkPixelEncoding(rawValue: raw) else { return .gray }
        switch encoding {
        case .rgb, .yCbCr444: return .green
        case .yCbCr422, .yCbCr420: return .yellow
        }
    }

    static func hdr(systemManaged: Bool, supported: Bool, enabled: Bool?, known: Bool) -> Self {
        guard known else { return .gray }
        return (systemManaged && supported) || enabled == true ? .green : .gray
    }

    static func vrr(enabled: Bool, known: Bool) -> Self {
        known && enabled ? .green : .gray
    }
}
