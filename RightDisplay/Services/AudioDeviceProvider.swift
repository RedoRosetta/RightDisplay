// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation

protocol AudioDeviceProviding {
    func devices() throws -> [AudioBridgeDevice]
}
struct AudioDeviceProvider: AudioDeviceProviding {
    private struct Envelope: Decodable { let devices: [AudioBridgeDevice];let error: String? }
    func devices() throws -> [AudioBridgeDevice] {
        let result: Envelope = try AudioBridgeJSON.decode(ABCopyDevicesJSON())
        if let error = result.error { throw AudioBridgeError.message(error) }
        return result.devices
    }
}
enum AudioBridgeError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case let .message(value): return value } }
}
enum AudioBridgeJSON {
    static func decode<T: Decodable>(_ pointer: UnsafeMutablePointer<CChar>?) throws -> T {
        guard let pointer else { throw AudioBridgeError.message("NATIVE_RESULT_UNAVAILABLE") }
        defer { ABFreeString(pointer) }
        return try JSONDecoder().decode(T.self, from: Data(String(cString: pointer).utf8))
    }
}
