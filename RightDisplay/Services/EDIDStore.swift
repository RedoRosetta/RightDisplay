// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import AppKit
import CoreGraphics
import IOKit

struct EDIDField: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}

struct EDIDCapabilityEnvelope {
    let hardwareKey: String
    let encodingBitDepths: [UInt32: Set<Int>]
    let supportsYCbCr420: Bool
    let hdrEOTFs: [String]
    let interfaceEvidence: [String]
    let source: String

    var declaredEncodings: [UInt32] { encodingBitDepths.keys.sorted() }
    var declaredBitDepths: [Int] { Array(Set(encodingBitDepths.values.flatMap { $0 })).sorted() }
    var hasHDR: Bool { !hdrEOTFs.isEmpty }
    var semanticCapabilityCount: Int {
        var states = encodingBitDepths.values.reduce(0) { $0 + $1.count }
        if hasHDR, declaredBitDepths.contains(where: { $0 >= 10 }) { states += 1 }
        return states
    }
    var encodingSummary: String {
        declaredEncodings.map { LinkPixelEncoding.title(for: $0) }.joined(separator: "、")
    }
}

enum CapabilityEvidenceSource: String {
    case sinkEDID = "EDID / Sink Capability"
    case macOSParsed = "macOS Interpreted Capability"
}

struct DisplayCapabilitySummary {
    let source: CapabilityEvidenceSource
    var hdrStaticMetadataType1: Bool? = nil
    var pq: Bool? = nil
    var hlg: Bool? = nil
    var bt2020RGB: Bool? = nil
    var bt2020YCC: Bool? = nil
    var vrr: Bool? = nil
    var minimumRefresh: Double? = nil
    var maximumRefresh: Double? = nil
    var minimumVRR: Double? = nil
    var maximumVRR: Double? = nil
    var rawEvidence = ""
    static func fixed16(_ raw: NSNumber?) -> Double? {
        guard let raw, raw.doubleValue.isFinite, raw.doubleValue > 0 else { return nil }
        return raw.doubleValue / 65536.0
    }
    static func system(_ properties: [String: Any]) -> DisplayCapabilitySummary {
        func flag(_ key: String) -> Bool? { (properties[key] as? NSNumber).map { $0.int64Value != 0 } }
        func rate(_ key: String) -> Double? {
            guard let n = properties[key] as? NSNumber, n.doubleValue > 0, n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        var value = DisplayCapabilitySummary(source: .macOSParsed)
        value.hdrStaticMetadataType1 = flag("SupportsHDRStaticMetadataType1")
        value.pq = flag("SupportsPQEOTF"); value.hlg = flag("SupportsHLGEOTF")
        value.bt2020RGB = flag("SupportsBT2020RGB"); value.bt2020YCC = flag("SupportsBT2020YCC")
        value.vrr = flag("SupportsVariableRefreshRate")
        value.minimumRefresh = rate("MinimumRefreshRate"); value.maximumRefresh = rate("MaximumRefreshRate")
        value.minimumVRR = fixed16(properties["MinimumVariableRefreshRate"] as? NSNumber)
        value.maximumVRR = fixed16(properties["MaximumVariableRefreshRate"] as? NSNumber)
        let keys = ["SupportsHDRStaticMetadataType1", "SupportsPQEOTF", "SupportsHLGEOTF", "SupportsBT2020RGB", "SupportsBT2020YCC", "SupportsVariableRefreshRate", "MinimumRefreshRate", "MaximumRefreshRate", "MinimumVariableRefreshRate", "MaximumVariableRefreshRate"]
        value.rawEvidence = keys.map { "\($0)=\(properties[$0].map(String.init(describing:)) ?? "UNAVAILABLE")" }.joined(separator: "; ")
        return value
    }
    static func edid(_ data: Data) -> DisplayCapabilitySummary? {
        let bytes = [UInt8](data)
        guard bytes.count >= 128, Array(bytes.prefix(8)) == [0,255,255,255,255,255,255,0] else { return nil }
        let blocks = Int(bytes[126]) + 1
        guard bytes.count >= blocks * 128, (0..<blocks).allSatisfy({
            bytes[($0 * 128)..<(($0 + 1) * 128)].reduce(0) { ($0 + Int($1)) & 255 } == 0
        }) else { return nil }
        var value = DisplayCapabilitySummary(source: .sinkEDID,
            hdrStaticMetadataType1: false, pq: false, hlg: false, bt2020RGB: false, bt2020YCC: false)
        var raw: [String] = []
        if blocks > 1 {
            for index in 1..<blocks {
                let block = Array(bytes[(index * 128)..<((index + 1) * 128)])
                guard block[0] == 2 else { continue }
                let end = block[2] == 0 ? 4 : Int(block[2])
                guard (4...127).contains(end) else { return nil }
                var cursor = 4
                while cursor < end {
                    let header = block[cursor], length = Int(block[cursor] & 31)
                    guard cursor + 1 + length <= end else { return nil }
                    let payload = Array(block[(cursor + 1)..<(cursor + 1 + length)])
                    if header >> 5 == 7, payload.count >= 3 {
                        if payload[0] == 6 {
                            value.pq = value.pq == true || payload[1] & 4 != 0
                            value.hlg = value.hlg == true || payload[1] & 8 != 0
                            value.hdrStaticMetadataType1 = value.hdrStaticMetadataType1 == true || payload[2] & 1 != 0
                            raw.append("CTA HDR EOTF=\(payload[1]); metadata=\(payload[2])")
                        } else if payload[0] == 5 {
                            value.bt2020RGB = value.bt2020RGB == true || payload[1] & 128 != 0
                            value.bt2020YCC = value.bt2020YCC == true || payload[1] & 64 != 0
                            raw.append("CTA colorimetry=\(payload[1]),\(payload[2])")
                        }
                    }
                    cursor += 1 + length
                }
            }
        }
        value.rawEvidence = raw.joined(separator: "; ")
        return value
    }
    var fields: [EDIDField] {
        let sourceDetail = "\(source.rawValue)。显示器能力，不是 current connection、可写模式列表或物理 active。\(rawEvidence)"
        var result = [("HDR Static Metadata Type 1", hdrStaticMetadataType1), ("PQ EOTF", pq),
                      ("HLG EOTF", hlg), ("BT.2020 RGB", bt2020RGB), ("BT.2020 YCC", bt2020YCC)]
            .map { EDIDField(title: $0.0, value: $0.1.map { $0 ? "支持" : "未声明" } ?? "未知", detail: sourceDetail) }
        if source == .macOSParsed {
            result.append(EDIDField(title: "VRR 能力", value: vrr.map { $0 ? "支持" : "未声明" } ?? "未知", detail: sourceDetail))
            if let minimumRefresh, let maximumRefresh, maximumRefresh >= minimumRefresh {
                result.append(EDIDField(title: "能力刷新率范围", value: "\(RefreshRateText.number(minimumRefresh))–\(RefreshRateText.number(maximumRefresh)) Hz", detail: sourceDetail))
            }
            let range = ModeRefreshRange(minimum: minimumVRR, maximum: maximumVRR, source: source.rawValue)
            result.append(EDIDField(title: "VRR 能力范围", value: range.isComplete ? "\(RefreshRateText.number(minimumVRR!))–\(RefreshRateText.number(maximumVRR!)) Hz" : "未知", detail: sourceDetail + "VRR capability raw 为 16.16；不代替具体 mode range。"))
        }
        return result
    }
}

@MainActor
final class EDIDStore: ObservableObject {
    static let shared = EDIDStore()
    @Published private(set) var data: Data?
    @Published private(set) var fields: [EDIDField] = []
    @Published private(set) var connection = SignalValue(text: "无法识别", verification: .unavailable, source: "IOKit")
    @Published private(set) var status = "尚未读取 EDID"
    @Published private(set) var capabilityEnvelope: EDIDCapabilityEnvelope?
    @Published private(set) var capabilityHardwareKey: String?
    @Published private(set) var sinkCapabilityFields: [EDIDField] = []
    @Published private(set) var macOSCapabilityFields: [EDIDField] = []

    func refresh(for display: DisplaySnapshot) {
        capabilityHardwareKey = display.hardwareKey
        sinkCapabilityFields = []; macOSCapabilityFields = []
        guard !display.isBuiltin else {
            data = nil; fields = []; status = "内建屏幕通常不提供标准 EDID";
            capabilityEnvelope = nil
            connection = SignalValue(text: "内建显示接口", verification: .verified, source: "Core Graphics")
            return
        }
        macOSCapabilityFields = interpretedCapabilities(for: display)?.fields ?? []
        let vendor = CGDisplayVendorNumber(display.id)
        let product = CGDisplayModelNumber(display.id)
        let summary = locateFramebufferSummary(vendor: vendor, product: product)
        if let result = locateEDID(vendor: vendor, product: product) {
            data = result.data
            fields = parse(result.data)
            sinkCapabilityFields = DisplayCapabilitySummary.edid(result.data)?.fields ?? []
            capabilityEnvelope = parseCapabilityEnvelope(result.data, hardwareKey: display.hardwareKey)
            connection = connectionValue(result)
            status = edidReadStatus(result.data)
        } else if let summary {
            data = nil
            capabilityEnvelope = nil
            fields = parse(summary: summary, vendor: vendor, product: product)
            connection = connectionValue(summary)
            status = "macOS 仅提供 EDID 身份摘要；原始 128 字节未开放"
        } else {
            data = nil; fields = []; capabilityEnvelope = nil; status = "macOS 未向应用提供此显示器的 EDID"
            connection = SignalValue(text: "接口未验证", verification: .unavailable, source: "IOKit 显示注册表", detail: "未找到可与当前显示器匹配的传输节点。")
        }
    }

    private func interpretedCapabilities(for display: DisplaySnapshot) -> DisplayCapabilitySummary? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var matches: [DisplayCapabilitySummary] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            guard let raw = IORegistryEntryCreateCFProperty(service, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let attributes = raw as? [String: Any], let product = attributes["ProductAttributes"] as? [String: Any],
                  (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value == CGDisplayVendorNumber(display.id),
                  (product["ProductID"] as? NSNumber)?.uint32Value == CGDisplayModelNumber(display.id) else { continue }
            let serial = CGDisplaySerialNumber(display.id)
            if serial != 0 && (product["SerialNumber"] as? NSNumber)?.uint32Value != serial { continue }
            var summary = DisplayCapabilitySummary.system(attributes)
            var path = [CChar](repeating: 0, count: 4096)
            IORegistryEntryGetPath(service, kIOServicePlane, &path)
            summary.rawEvidence = "IORegistry DisplayAttributes path=\(String(cString: path)); " + summary.rawEvidence
            matches.append(summary)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func parseCapabilityEnvelope(_ data: Data, hardwareKey: String) -> EDIDCapabilityEnvelope? {
        let bytes = [UInt8](data)
        guard bytes.count >= 128,
              Array(bytes.prefix(8)) == [0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00] else { return nil }

        let declaredBlockCount = Int(bytes[126]) + 1
        guard bytes.count >= declaredBlockCount * 128,
              (0..<declaredBlockCount).allSatisfy({ blockIndex in
                  let start = blockIndex * 128
                  return bytes[start..<(start + 128)].reduce(0) { ($0 + Int($1)) & 0xff } == 0
              }) else { return nil }

        var depths: [UInt32: Set<Int>] = [0: [8]]
        var supports420 = false
        var hdrEOTFs: Set<String> = []
        var interfaceEvidence: Set<String> = []
        var hdmiDeep10 = false
        var hdmiDeep12 = false
        var y444DeepColor = false
        let declaredExtensionCount = Int(bytes[126])
        let availableExtensionCount = declaredBlockCount - 1

        let extensionCount = min(declaredExtensionCount, availableExtensionCount)
        for blockIndex in extensionCount > 0 ? Array(1...extensionCount) : [] {
            let start = blockIndex * 128
            let block = Array(bytes[start..<(start + 128)])
            guard block[0] == 0x02 else { continue }
            let dtdOffset = block[2] == 0 ? 127 : min(Int(block[2]), 127)
            if block[3] & 0x20 != 0 { depths[LinkPixelEncoding.yCbCr444.rawValue, default: []].insert(8) }
            if block[3] & 0x10 != 0 { depths[LinkPixelEncoding.yCbCr422.rawValue, default: []].insert(8) }
            var offset = 4
            while offset < dtdOffset {
                let header = block[offset]
                if header == 0 { offset += 1; continue }
                let tag = Int(header >> 5)
                let length = Int(header & 0x1f)
                let end = min(offset + 1 + length, dtdOffset)
                guard end > offset + 1 else { break }
                let payload = Array(block[(offset + 1)..<end])
                if tag == 3, payload.count >= 3 {
                    let oui = UInt32(payload[0]) | UInt32(payload[1]) << 8 | UInt32(payload[2]) << 16
                    if oui == 0x000c03 {
                        interfaceEvidence.insert("HDMI VSDB")
                        if payload.count > 5 {
                            hdmiDeep10 = payload[5] & 0x10 != 0
                            hdmiDeep12 = payload[5] & 0x20 != 0
                            y444DeepColor = payload[5] & 0x08 != 0
                        }
                        if payload.count > 6, payload[6] > 0 {
                            interfaceEvidence.insert("Max TMDS \(Int(payload[6]) * 5) MHz")
                        }
                    } else if oui == 0xc45dd8 {
                        interfaceEvidence.insert("HDMI Forum VSDB")
                    }
                } else if tag == 7, let extendedTag = payload.first {
                    let body = payload.dropFirst()
                    if extendedTag == 0x06, let eotf = body.first {
                        if eotf & 0x02 != 0 { hdrEOTFs.insert("Traditional HDR") }
                        if eotf & 0x04 != 0 { hdrEOTFs.insert("PQ") }
                        if eotf & 0x08 != 0 { hdrEOTFs.insert("HLG") }
                    } else if extendedTag == 0x0e || extendedTag == 0x0f {
                        supports420 = true
                    }
                }
                offset = end
            }
        }

        if hdmiDeep10 { depths[0, default: []].insert(10) }
        if hdmiDeep12 { depths[0, default: []].insert(12) }
        if y444DeepColor, depths[LinkPixelEncoding.yCbCr444.rawValue] != nil {
            if hdmiDeep10 { depths[LinkPixelEncoding.yCbCr444.rawValue, default: []].insert(10) }
            if hdmiDeep12 { depths[LinkPixelEncoding.yCbCr444.rawValue, default: []].insert(12) }
        }
        return EDIDCapabilityEnvelope(
            hardwareKey: hardwareKey,
            encodingBitDepths: depths,
            supportsYCbCr420: supports420,
            hdrEOTFs: hdrEOTFs.sorted(),
            interfaceEvidence: interfaceEvidence.sorted(),
            source: "EDID declared"
        )
    }

    var hexText: String {
        guard let data else { return "" }
        return data.enumerated().map { index, byte in
            let prefix = index % 16 == 0 ? String(format: "%04X  ", index) : ""
            let suffix = index % 16 == 15 ? "\n" : " "
            return prefix + String(format: "%02X", byte) + suffix
        }.joined()
    }

    private func edidReadStatus(_ data: Data) -> String {
        let bytes = [UInt8](data)
        guard bytes.count >= 128 else {
            return AppLocalization.format("EDID 数据不完整：仅读取 %d 字节，基础区块不足 128 字节", bytes.count)
        }

        let declaredBlocks = Int(bytes[126]) + 1
        let availableBlocks = bytes.count / 128
        let hasTrailingBytes = bytes.count % 128 != 0
        guard availableBlocks >= declaredBlocks, !hasTrailingBytes else {
            return AppLocalization.format("EDID 数据不完整：基础块声明 %d 个区块，实际读取 %d 个完整区块（%d 字节）", declaredBlocks, availableBlocks, bytes.count)
        }

        let failedChecksums = (0..<declaredBlocks).filter { blockIndex in
            let start = blockIndex * 128
            return bytes[start..<(start + 128)].reduce(0) { ($0 + Int($1)) & 0xFF } != 0
        }
        guard failedChecksums.isEmpty else {
            let labels = failedChecksums.map { String($0) }.joined(separator: "、")
            return AppLocalization.format("EDID 已完整读取，但区块 %@ 校验失败：%d 字节 · %d 个区块", labels, bytes.count, declaredBlocks)
        }

        return AppLocalization.format("EDID 已完整读取且校验通过：%d 字节 · %d 个区块", bytes.count, declaredBlocks)
    }

    func exportBinary() { guard let data else { return }; save(data, name: "Display-EDID.bin", type: "bin") }
    func exportText() { guard let bytes = reportText.data(using: .utf8) else { return }; save(bytes, name: "EDID-Report.txt", type: "txt") }

    private var reportText: String {
        let parsed = (sinkCapabilityFields + macOSCapabilityFields + fields).map { "\($0.title): \($0.value)\n  \($0.detail)" }.joined(separator: "\n")
        return "Right Display EDID Report\n=========================\n\(status)\n连接方式: \(connection.text) [\(connection.verificationText)]\n\n\(parsed)\n\nRaw EDID\n--------\n\(hexText)"
    }

    private func save(_ data: Data, name: String, type: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url) } catch { status = "导出失败：\(error.localizedDescription)" }
    }

    private struct EDIDResult {
        let data: Data
        let path: String
        let physicalConnector: String?
        let transportType: String?
        let transportDescription: String?
        let linkRate: String?
        let laneCount: Int?
        let source: String
    }

    private func locateEDID(vendor: UInt32, product: UInt32) -> EDIDResult? {
        // Apple Silicon publishes the complete sink EDID on the active
        // IOPortTransportStateDisplayPort node, even when the physical Mac port
        // is HDMI. This is the most specific source because the same node also
        // identifies the physical parent connector and the internal transport.
        if let result = locateTransportEDID(vendor: vendor, product: product) {
            return result
        }

        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS,
              iterator != 0 else { return nil }
        defer { IOObjectRelease(iterator) }
        var matchedResult: EDIDResult?
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            defer { IOObjectRelease(service) }
            let rawValue = IORegistryEntryCreateCFProperty(service, "IODisplayEDIDOriginal" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                ?? IORegistryEntryCreateCFProperty(service, "IODisplayEDID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            guard let value = rawValue as? Data else { continue }
            var props: Unmanaged<CFMutableDictionary>?
            IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
            let dict = props?.takeRetainedValue() as? [String: Any]
            let bytes = [UInt8](value)
            let edidVendor = bytes.count >= 12 ? UInt32(UInt16(bytes[8]) << 8 | UInt16(bytes[9])) : nil
            let edidProduct = bytes.count >= 12 ? UInt32(UInt16(bytes[10]) | UInt16(bytes[11]) << 8) : nil
            let v = (dict?["DisplayVendorID"] as? NSNumber)?.uint32Value ?? edidVendor
            let p = (dict?["DisplayProductID"] as? NSNumber)?.uint32Value ?? edidProduct
            guard v == vendor, p == product else { continue }
            var path = [CChar](repeating: 0, count: 4096)
            IORegistryEntryGetPath(service, kIOServicePlane, &path)
            let result = EDIDResult(
                data: value,
                path: String(cString: path),
                physicalConnector: nil,
                transportType: nil,
                transportDescription: nil,
                linkRate: nil,
                laneCount: nil,
                source: "IOKit IODisplayEDID"
            )
            if matchedResult != nil { return nil }
            matchedResult = result
        }
        return matchedResult
    }

    private func locateTransportEDID(vendor: UInt32, product: UInt32) -> EDIDResult? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOPortTransportStateDisplayPort"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var matchedResult: EDIDResult?
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { continue }

            let metadata = properties["Metadata"] as? [String: Any]
            guard let edid = (properties["EDID"] as? Data) ?? (metadata?["EDID"] as? Data),
                  edidMatches(edid, vendor: vendor, product: product) else { continue }

            var path = [CChar](repeating: 0, count: 4096)
            IORegistryEntryGetPath(service, kIOServicePlane, &path)
            let parentConnector = properties["ParentBuiltInPortTypeDescription"] as? String
            let sinkConnector = metadata?["DFP Type Description"] as? String
            let physicalConnector = parentConnector ?? sinkConnector

            let result = EDIDResult(
                data: edid,
                path: String(cString: path),
                physicalConnector: physicalConnector,
                transportType: properties["TransportTypeDescription"] as? String,
                transportDescription: properties["TransportDescription"] as? String,
                linkRate: properties["LinkRateDescription"] as? String,
                laneCount: (properties["LaneCount"] as? NSNumber)?.intValue,
                source: "Apple Silicon IOPortTransportStateDisplayPort.EDID"
            )
            if matchedResult != nil { return nil }
            matchedResult = result
        }
        return matchedResult
    }

    private func edidMatches(_ data: Data, vendor: UInt32, product: UInt32) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 128,
              Array(bytes.prefix(8)) == [0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00] else { return false }
        let edidVendor = UInt32(UInt16(bytes[8]) << 8 | UInt16(bytes[9]))
        let edidProduct = UInt32(UInt16(bytes[10]) | UInt16(bytes[11]) << 8)
        return edidVendor == vendor && edidProduct == product
    }

    private struct FramebufferSummary {
        let uuid: String
        let upstream: String
        let downstream: String
        let path: String
    }

    private func locateFramebufferSummary(vendor: UInt32, product: UInt32) -> FramebufferSummary? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOMobileFramebufferShim"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        let expectedPrefix = String(format: "%04X%04X", vendor, product)
        var matchedResult: FramebufferSummary?
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
            guard let dict = properties?.takeRetainedValue() as? [String: Any],
                  let transport = dict["Transport"] as? [String: Any] else { continue }
            let uuid = (dict["EDID UUID"] as? String)
                ?? (dict["EDID UUID"] as? UUID)?.uuidString
                ?? ""
            let normalized = uuid.replacingOccurrences(of: "-", with: "").uppercased()
            var path = [CChar](repeating: 0, count: 4096)
            IORegistryEntryGetPath(service, kIOServicePlane, &path)
            let result = FramebufferSummary(
                uuid: uuid,
                upstream: transport["Upstream"] as? String ?? "未知",
                downstream: transport["Downstream"] as? String ?? "未知",
                path: String(cString: path)
            )
            if normalized.hasPrefix(expectedPrefix) {
                if matchedResult != nil { return nil }
                matchedResult = result
            }
        }
        return matchedResult
    }

    private func parse(summary: FramebufferSummary, vendor: UInt32, product: UInt32) -> [EDIDField] {
        let hex = summary.uuid.replacingOccurrences(of: "-", with: "")
        let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { index -> UInt8? in
            let start = hex.index(hex.startIndex, offsetBy: index)
            let end = hex.index(start, offsetBy: min(2, hex.distance(from: start, to: hex.endIndex)))
            return UInt8(hex[start..<end], radix: 16)
        }
        let manufacturerCode = UInt16(vendor & 0xffff)
        let manufacturer = [10, 5, 0].map { shift -> Character in
            Character(UnicodeScalar(Int((manufacturerCode >> shift) & 0x1F) + 64)!)
        }
        var result = [
            EDIDField(title: "制造商与产品", value: "\(String(manufacturer)) · 0x\(String(format: "%04X", product))", detail: "来自 Apple 显示管线公开的 EDID 身份摘要。"),
            EDIDField(title: "EDID 身份 UUID", value: summary.uuid.isEmpty ? "未提供" : summary.uuid, detail: "这不是完整的 128 字节 EDID，不能替代原始文件。"),
            EDIDField(title: "传输路径", value: "\(summary.upstream) → \(summary.downstream)", detail: "来自 IOMobileFramebufferShim 的 Transport 字段。")
        ]
        if bytes.count >= 16 {
            let year = 1990 + Int(bytes[9])
            let gamma = bytes[15] == 0xff ? "由扩展数据定义" : String(format: "%.2f", (Double(bytes[15]) + 100) / 100)
            result.append(EDIDField(title: "生产时间", value: "第 \(bytes[8]) 周 · \(year) 年", detail: "由 EDID 身份摘要中的制造周与年份字段解析。"))
            result.append(EDIDField(title: "EDID 版本", value: "\(bytes[10]).\(bytes[11])", detail: "由 EDID 身份摘要解析。"))
            result.append(EDIDField(title: "物理尺寸与 Gamma", value: "\(bytes[13]) × \(bytes[14]) cm · Gamma \(gamma)", detail: "显示器报告值可能不准确；并非软件测量结果。"))
        }
        return result
    }

    private func connectionValue(_ summary: FramebufferSummary) -> SignalValue {
        let downstream = summary.downstream.lowercased()
        let upstream = summary.upstream.lowercased()
        if downstream.contains("hdmi") {
            return SignalValue(
                text: "HDMI（协议版本未验证）",
                verification: .inferred,
                source: "Apple 显示管线 Transport",
                detail: upstream.contains("dp") ? "系统报告内部路径为 DisplayPort → HDMI；它不能证明当前协商为 HDMI 2.1。" : "系统报告下游接口为 HDMI，但没有公开当前协议版本。"
            )
        }
        if downstream.contains("dp") || downstream.contains("displayport") {
            return SignalValue(
                text: "DisplayPort（版本未验证）",
                verification: .inferred,
                source: "Apple 显示管线 Transport",
                detail: "可能经 USB‑C 或 Thunderbolt 输出；系统没有公开当前 DisplayPort 协议版本。"
            )
        }
        return SignalValue(text: "\(summary.upstream) → \(summary.downstream)", verification: .inferred, source: "Apple 显示管线 Transport", detail: summary.path)
    }

    private func parse(_ data: Data) -> [EDIDField] {
        let b = [UInt8](data); guard b.count >= 128 else { return [] }
        let manufacturerCode = (UInt16(b[8]) << 8) | UInt16(b[9])
        let manufacturer = [10, 5, 0].map { shift -> Character in
            Character(UnicodeScalar(Int((manufacturerCode >> shift) & 0x1F) + 64)!)
        }
        let product = UInt16(b[10]) | (UInt16(b[11]) << 8)
        let serial = UInt32(b[12]) | (UInt32(b[13]) << 8) | (UInt32(b[14]) << 16) | (UInt32(b[15]) << 24)
        let year = 1990 + Int(b[17]); let width = Int(b[21]); let height = Int(b[22])
        let gamma = b[23] == 0xFF ? "由扩展数据定义" : String(format: "%.2f", (Double(b[23]) + 100) / 100)
        let declaredExtensions = Int(b[126])
        let availableBlocks = b.count / 128
        let availableExtensions = max(0, availableBlocks - 1)
        let blockChecksums = (0..<availableBlocks).map { block -> Bool in
            let start = block * 128
            return b[start..<(start + 128)].reduce(0) { ($0 + Int($1)) & 0xFF } == 0
        }
        let displayName = descriptorText(type: 0xfc, bytes: b)
        let digitalInput = (b[20] & 0x80) != 0
        let inputDetail = digitalInput ? digitalInputDescription(b[20]) : analogInputDescription(b[20])
        let chromaticity = chromaticityDescription(b)
        let established = establishedTimings(b)
        let standard = standardTimings(b)
        var result = [
            EDIDField(title: "显示器名称", value: displayName ?? "未提供", detail: "来自 EDID 0xFC 显示器名称描述符。"),
            EDIDField(title: "制造商与产品", value: "\(String(manufacturer)) · 0x\(String(format: "%04X", product))", detail: "字节 8–11：EISA 制造商代码和产品 ID。"),
            EDIDField(title: "设备序列号", value: serial == 0 ? "未提供" : String(serial), detail: "字节 12–15；导出文件可能包含可识别设备的信息。"),
            EDIDField(title: "EDID 版本", value: "\(b[18]).\(b[19])", detail: "字节 18–19：基础区块版本与修订号。"),
            EDIDField(title: "生产时间", value: "第 \(b[16]) 周 · \(year) 年", detail: "字节 16–17。"),
            EDIDField(title: "视频输入定义", value: digitalInput ? "数字输入" : "模拟输入", detail: "字节 20（0x14）：\(inputDetail)"),
            EDIDField(title: "物理尺寸", value: width > 0 && height > 0 ? "\(width) × \(height) cm" : "未提供", detail: "字节 21–22；这是显示器报告值，可能不准确。"),
            EDIDField(title: "Gamma", value: gamma, detail: "字节 23：显示传递特性的基础 Gamma。"),
            EDIDField(title: "色度坐标与白点", value: chromaticity, detail: "EDID / Sink Capability；字节 25–34，以 10 bit 定点数解析；不是当前输出色域或测量结果。"),
            EDIDField(title: "显示能力标志", value: featureDescription(b[24]), detail: "字节 24：DPMS、首选时序、连续频率和基础颜色类型。"),
            EDIDField(title: "Established Timings", value: established.isEmpty ? "未声明" : "\(established.count) 项", detail: established.isEmpty ? "字节 35–37 未设置既定时序位。" : established.joined(separator: "；")),
            EDIDField(title: "Standard Timings", value: standard.isEmpty ? "未声明" : "\(standard.count) 项", detail: standard.isEmpty ? "字节 38–53 未提供标准时序。" : standard.joined(separator: "；")),
            EDIDField(
                title: "扩展区块",
                value: declaredExtensions == availableExtensions ? "\(availableExtensions) 个" : "系统提供 \(availableExtensions) 个 · 基础块声明 \(declaredExtensions) 个",
                detail: "可能包含 CTA‑861、DisplayID、HDR、音频与 HDMI 能力；导出时保留 macOS 提供的原始数据。"
            ),
            EDIDField(
                title: "区块校验",
                value: blockChecksums.allSatisfy { $0 } ? "全部通过（\(availableBlocks)/\(availableBlocks)）" : "存在失败区块",
                detail: "每个 128 字节区块相加后低 8 位应为 0。"
            )
        ]

        for offset in stride(from: 54, through: 108, by: 18) {
            result.append(contentsOf: parseBaseDescriptor(b, offset: offset))
        }
        for block in 1..<availableBlocks {
            let start = block * 128
            switch b[start] {
            case 0x02:
                result.append(contentsOf: parseCTA861(Array(b[start..<(start + 128)]), blockNumber: block))
            case 0x70:
                result.append(contentsOf: parseDisplayID(Array(b[start..<(start + 128)]), blockNumber: block))
            case 0x10:
                result.append(EDIDField(title: "扩展区块 \(block) · VTB-EXT", value: "Video Timing Block", detail: "标签 0x10；包含额外视频时序。原始区块已保留，可在十六进制视图或导出文件中检查。"))
            default:
                result.append(EDIDField(title: "扩展区块 \(block)", value: String(format: "未知标签 0x%02X", b[start]), detail: "Right Display 尚未识别此扩展类型；区块校验状态：\(blockChecksums[block] ? "通过" : "失败")。"))
            }
        }
        return result
    }

    private func digitalInputDescription(_ byte: UInt8) -> String {
        let depth = [0: "未定义", 1: "6 bit", 2: "8 bit", 3: "10 bit", 4: "12 bit", 5: "14 bit", 6: "16 bit"][(byte >> 4) & 0x07] ?? "保留值"
        let interface = [0: "未定义", 1: "DVI", 2: "HDMI-a", 3: "HDMI-b", 4: "MDDI", 5: "DisplayPort"][(byte & 0x0f)] ?? "保留值"
        return "接口 \(interface)，EDID 声明的输入色深 \(depth)。这描述接收端能力，不等于当前链路实际输出色深。"
    }

    private func analogInputDescription(_ byte: UInt8) -> String {
        let levels = ["+0.7/−0.3 V", "+0.714/−0.286 V", "+1.0/−0.4 V", "+0.7/0 V"]
        return "白/同步电平 \(levels[Int((byte >> 5) & 0x03)])；同步能力位 0x\(String(format: "%02X", byte & 0x1f))。"
    }

    private func featureDescription(_ byte: UInt8) -> String {
        let standby = byte & 0x80 != 0 ? "待机" : nil
        let suspend = byte & 0x40 != 0 ? "挂起" : nil
        let off = byte & 0x20 != 0 ? "主动关闭" : nil
        let preferred = byte & 0x02 != 0 ? "首个详细时序为首选" : "未标记首选时序"
        let continuous = byte & 0x01 != 0 ? "连续频率" : "离散时序"
        let power = [standby, suspend, off].compactMap { $0 }.joined(separator: "、")
        return "\(preferred)；\(continuous)；DPMS：\(power.isEmpty ? "未声明" : power)。"
    }

    private func chromaticityDescription(_ b: [UInt8]) -> String {
        guard b.count > 34 else { return "数据不足" }
        func coordinate(_ high: UInt8, _ low: UInt8) -> String {
            String(format: "%.4f", Double((UInt16(high) << 2) | UInt16(low & 0x03)) / 1024.0)
        }
        let rx = coordinate(b[27], b[25] >> 6), ry = coordinate(b[28], b[25] >> 4)
        let gx = coordinate(b[29], b[25] >> 2), gy = coordinate(b[30], b[25])
        let bx = coordinate(b[31], b[26] >> 6), by = coordinate(b[32], b[26] >> 4)
        let wx = coordinate(b[33], b[26] >> 2), wy = coordinate(b[34], b[26])
        return "R(\(rx), \(ry))，G(\(gx), \(gy))，B(\(bx), \(by))，白点(\(wx), \(wy))。"
    }

    private func establishedTimings(_ b: [UInt8]) -> [String] {
        let table: [(Int, UInt8, String)] = [
            (35, 0x80, "720×400 @ 70 Hz"), (35, 0x40, "720×400 @ 88 Hz"),
            (35, 0x20, "640×480 @ 60 Hz"), (35, 0x10, "640×480 @ 67 Hz"),
            (35, 0x08, "640×480 @ 72 Hz"), (35, 0x04, "640×480 @ 75 Hz"),
            (35, 0x02, "800×600 @ 56 Hz"), (35, 0x01, "800×600 @ 60 Hz"),
            (36, 0x80, "800×600 @ 72 Hz"), (36, 0x40, "800×600 @ 75 Hz"),
            (36, 0x20, "832×624 @ 75 Hz"), (36, 0x10, "1024×768i @ 87 Hz"),
            (36, 0x08, "1024×768 @ 60 Hz"), (36, 0x04, "1024×768 @ 70 Hz"),
            (36, 0x02, "1024×768 @ 75 Hz"), (36, 0x01, "1280×1024 @ 75 Hz"),
            (37, 0x80, "1152×870 @ 75 Hz")
        ]
        return table.compactMap { b[$0.0] & $0.1 != 0 ? $0.2 : nil }
    }

    private func standardTimings(_ b: [UInt8]) -> [String] {
        var result: [String] = []
        for offset in stride(from: 38, through: 52, by: 2) {
            let xByte = b[offset], timing = b[offset + 1]
            if xByte == 0x01 && timing == 0x01 { continue }
            let width = (Int(xByte) + 31) * 8
            let ratio = Int(timing >> 6)
            let height: Int
            switch ratio { case 0: height = width * 10 / 16; case 1: height = width * 3 / 4; case 2: height = width * 4 / 5; default: height = width * 9 / 16 }
            result.append("\(width)×\(height) @ \(Int(timing & 0x3f) + 60) Hz")
        }
        return result
    }

    private func parseBaseDescriptor(_ b: [UInt8], offset: Int) -> [EDIDField] {
        guard offset + 17 < b.count else { return [] }
        if b[offset] != 0 || b[offset + 1] != 0 {
            return [detailedTimingField(Array(b[offset..<(offset + 18)]), title: "基础块详细时序 \((offset - 54) / 18 + 1)", byteOffset: offset)]
        }
        let tag = b[offset + 3]
        switch tag {
        case 0xfc, 0xff, 0xfe:
            let names: [UInt8: String] = [0xfc: "显示器名称描述符", 0xff: "文本序列号描述符", 0xfe: "ASCII 文本描述符"]
            let text = String(bytes: b[(offset + 5)..<(offset + 18)].prefix { $0 != 0x0a && $0 != 0 }, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "无法解码"
            return [EDIDField(title: names[tag] ?? "文本描述符", value: text, detail: "基础块字节 \(offset)–\(offset + 17)，描述符标签 0x\(String(format: "%02X", tag))。")]
        case 0xfd:
            let minV = b[offset + 5], maxV = b[offset + 6], minH = b[offset + 7], maxH = b[offset + 8], clock = Int(b[offset + 9]) * 10
            return [EDIDField(title: "显示范围限制", value: "\(minV)–\(maxV) Hz · \(minH)–\(maxH) kHz", detail: "基础块字节 \(offset)–\(offset + 17)：垂直刷新范围、水平扫描范围；最大像素时钟 \(clock == 0 ? "未提供" : "\(clock) MHz")。后续字节定义额外时序公式。")]
        default:
            return [EDIDField(title: "基础块监视器描述符", value: String(format: "标签 0x%02X", tag), detail: "基础块字节 \(offset)–\(offset + 17)；原始内容已保留在十六进制视图。")]
        }
    }

    private func detailedTimingField(_ d: [UInt8], title: String, byteOffset: Int) -> EDIDField {
        guard d.count >= 18 else { return EDIDField(title: title, value: "数据不足", detail: "") }
        let clockKHz = (Int(d[1]) << 8 | Int(d[0])) * 10
        let hActive = Int(d[2]) | (Int(d[4] & 0xf0) << 4), hBlank = Int(d[3]) | (Int(d[4] & 0x0f) << 8)
        let vActive = Int(d[5]) | (Int(d[7] & 0xf0) << 4), vBlank = Int(d[6]) | (Int(d[7] & 0x0f) << 8)
        let hFront = Int(d[8]) | (Int(d[11] & 0xc0) << 2), hSync = Int(d[9]) | (Int(d[11] & 0x30) << 4)
        let vFront = Int(d[10] >> 4) | (Int(d[11] & 0x0c) << 2), vSync = Int(d[10] & 0x0f) | (Int(d[11] & 0x03) << 4)
        let hSize = Int(d[12]) | (Int(d[14] & 0xf0) << 4), vSize = Int(d[13]) | (Int(d[14] & 0x0f) << 8)
        let hz = hActive + hBlank > 0 && vActive + vBlank > 0 ? Double(clockKHz * 1000) / Double((hActive + hBlank) * (vActive + vBlank)) : 0
        let interlaced = d[17] & 0x80 != 0 ? "隔行" : "逐行"
        return EDIDField(title: title, value: String(format: "%d×%d @ %.3f Hz", hActive, vActive, hz), detail: "像素时钟 \(String(format: "%.3f", Double(clockKHz) / 1000)) MHz；总时序 \(hActive + hBlank)×\(vActive + vBlank)；H 前肩/同步/后肩 \(hFront)/\(hSync)/\(max(0, hBlank - hFront - hSync))；V 前肩/同步/后肩 \(vFront)/\(vSync)/\(max(0, vBlank - vFront - vSync))；图像尺寸 \(hSize)×\(vSize) mm；\(interlaced)。来源字节偏移 \(byteOffset)。")
    }

    private func parseCTA861(_ block: [UInt8], blockNumber: Int) -> [EDIDField] {
        guard block.count == 128 else { return [] }
        let revision = block[1]
        let dtdOffset = block[2] == 0 ? 127 : min(Int(block[2]), 127)
        let flags = block[3]
        let capabilities = [
            flags & 0x80 != 0 ? "默认欠扫描" : nil,
            flags & 0x40 != 0 ? "基本音频" : nil,
            flags & 0x20 != 0 ? "YCbCr 4:4:4" : nil,
            flags & 0x10 != 0 ? "YCbCr 4:2:2" : nil
        ].compactMap { $0 }
        var result = [EDIDField(
            title: "扩展区块 \(blockNumber) · CTA‑861",
            value: "修订版 \(revision) · \(Int(flags & 0x0f)) 个原生 DTD",
            detail: "标签 0x02；数据块集合位于字节 4–\(max(4, dtdOffset - 1))，详细时序从字节 \(dtdOffset) 开始。能力标志：\(capabilities.isEmpty ? "无" : capabilities.joined(separator: "、"))。校验和 \(block.reduce(0) { ($0 + Int($1)) & 0xff } == 0 ? "通过" : "失败")。"
        )]

        var offset = 4
        var dataBlockIndex = 1
        while offset < dtdOffset {
            let header = block[offset]
            if header == 0 { offset += 1; continue }
            let tag = Int(header >> 5), length = Int(header & 0x1f)
            let end = min(offset + 1 + length, dtdOffset)
            guard end > offset + 1 else { break }
            let payload = Array(block[(offset + 1)..<end])
            result.append(parseCTADataBlock(tag: tag, payload: payload, blockNumber: blockNumber, index: dataBlockIndex, offset: offset))
            offset = end
            dataBlockIndex += 1
        }

        var dtdIndex = 1
        var dtd = dtdOffset
        while dtd + 17 < 127, block[dtd] != 0 || block[dtd + 1] != 0 {
            result.append(detailedTimingField(Array(block[dtd..<(dtd + 18)]), title: "CTA‑861 详细时序 \(dtdIndex)", byteOffset: blockNumber * 128 + dtd))
            dtd += 18
            dtdIndex += 1
        }
        return result
    }

    private func parseCTADataBlock(tag: Int, payload: [UInt8], blockNumber: Int, index: Int, offset: Int) -> EDIDField {
        let location = "扩展区块 \(blockNumber)，数据块 \(index)，区块内字节 \(offset)–\(offset + payload.count)"
        switch tag {
        case 1:
            var formats: [String] = []
            for i in stride(from: 0, to: payload.count - payload.count % 3, by: 3) {
                let formatID = Int(payload[i] >> 3), channels = Int(payload[i] & 0x07) + 1
                let format = audioFormatName(formatID)
                let rates = [(0x40, "192"), (0x20, "176.4"), (0x10, "96"), (0x08, "88.2"), (0x04, "48"), (0x02, "44.1"), (0x01, "32")].compactMap { payload[i + 1] & UInt8($0.0) != 0 ? $0.1 : nil }
                let extra: String
                if formatID == 1 {
                    let depths = [(0x01, "16"), (0x02, "20"), (0x04, "24")].compactMap { payload[i + 2] & UInt8($0.0) != 0 ? $0.1 : nil }
                    extra = "；LPCM \(depths.joined(separator: "/")) bit"
                } else {
                    extra = "；最大码率 \(Int(payload[i + 2]) * 8) kbit/s 或格式相关值 0x\(String(format: "%02X", payload[i + 2]))"
                }
                formats.append("\(format)，\(channels) 声道，\(rates.joined(separator: "/")) kHz\(extra)")
            }
            return EDIDField(title: "CTA 音频数据块", value: "\(formats.count) 个短音频描述符", detail: "\(formats.joined(separator: "；"))。\(location)。")
        case 2:
            let modes = payload.map { byte -> String in
                let decoded = decodeCTAShortVideoDescriptor(byte)
                return "VIC \(decoded.vic)：\(ctaVideoMode(decoded.vic))\(decoded.native ? "（原生）" : "")"
            }
            return EDIDField(title: "CTA 视频数据块", value: "\(modes.count) 个短视频描述符", detail: "\(modes.joined(separator: "；"))。VIC 表示 CTA 标准电视时序；它描述接收端能力，不证明当前正在使用该模式。\(location)。")
        case 3:
            guard payload.count >= 3 else { return EDIDField(title: "CTA 厂商数据块", value: "数据不足", detail: location) }
            let oui = UInt32(payload[0]) | UInt32(payload[1]) << 8 | UInt32(payload[2]) << 16
            if oui == 0x000c03 { return parseHDMIVSDB(payload, location: location) }
            if oui == 0xc45dd8 { return parseHDMIForumVSDB(payload, location: location) }
            return EDIDField(title: "CTA 厂商特定数据块", value: String(format: "IEEE OUI %06X", oui), detail: "厂商自定义能力数据；未套用未知厂商的私有位定义。\(location)。")
        case 4:
            let byte = payload.first ?? 0
            let speakers = [(0x01, "前左/前右"), (0x02, "低频效果 LFE"), (0x04, "前中"), (0x08, "后左/后右"), (0x10, "后中"), (0x20, "前左中/前右中"), (0x40, "后左中/后右中"), (0x80, "前左宽/前右宽")].compactMap { byte & UInt8($0.0) != 0 ? $0.1 : nil }
            return EDIDField(title: "CTA 扬声器分配数据块", value: speakers.isEmpty ? "未声明扬声器位置" : speakers.joined(separator: "、"), detail: "这是接收端报告的声道位置能力，不代表 macOS 当前音频流。\(location)。")
        case 7:
            return parseCTAExtendedBlock(payload, location: location)
        default:
            return EDIDField(title: "CTA 数据块", value: "标签 \(tag) · \(payload.count) 字节", detail: "原始负载：\(payload.map { String(format: "%02X", $0) }.joined(separator: " "))。\(location)。")
        }
    }

    private func parseCTAExtendedBlock(_ payload: [UInt8], location: String) -> EDIDField {
        guard let extendedTag = payload.first else { return EDIDField(title: "CTA 扩展数据块", value: "空数据", detail: location) }
        let body = Array(payload.dropFirst())
        switch extendedTag {
        case 0x00:
            let value = body.first ?? 0
            let scanNames = ["CE": scanBehavior(Int(value & 0x03)), "IT": scanBehavior(Int((value >> 2) & 0x03)), "PT": scanBehavior(Int((value >> 4) & 0x03))]
                .map { "\($0.key) \($0.value)" }.sorted().joined(separator: "；")
            let quantization = [value & 0x40 != 0 ? "RGB 量化范围可选" : "RGB 量化范围未声明可选", value & 0x80 != 0 ? "YCC 量化范围可选" : "YCC 量化范围未声明可选"]
            return EDIDField(title: "CTA 视频能力数据块", value: "扫描：\(scanNames)", detail: "\(quantization.joined(separator: "；"))。这里描述接收端对过扫描、欠扫描及量化范围选择的支持，不代表当前输出设置。原始标志 0x\(String(format: "%02X", value))。\(location)。")
        case 0x01:
            guard body.count >= 3 else {
                return EDIDField(title: "CTA 厂商特定视频数据块", value: "数据不足", detail: "扩展标签 0x01；原始负载：\(body.map { String(format: "%02X", $0) }.joined(separator: " "))。\(location)。")
            }
            let oui = UInt32(body[0]) | UInt32(body[1]) << 8 | UInt32(body[2]) << 16
            return EDIDField(title: "CTA 厂商特定视频数据块", value: String(format: "IEEE OUI %06X", oui), detail: "这是由 OUI 所属厂商定义的视频能力负载。未取得该厂商公开字段定义时仅展示身份与原始数据，不猜测私有位含义。原始负载：\(body.dropFirst(3).map { String(format: "%02X", $0) }.joined(separator: " "))。\(location)。")
        case 0x05:
            let flags = body.prefix(2).map { String(format: "0x%02X", $0) }.joined(separator: " ")
            return EDIDField(title: "CTA 色度数据块", value: colorimetryDescription(body), detail: "声明 xvYCC、sYCC、Adobe RGB、BT.2020、DCI-P3 等扩展颜色空间能力；原始标志 \(flags)。\(location)。")
        case 0x06:
            let eotf = body.first ?? 0
            let eotfs = [(0x01, "传统 SDR"), (0x02, "传统 HDR"), (0x04, "PQ / SMPTE ST 2084"), (0x08, "HLG")].compactMap { eotf & UInt8($0.0) != 0 ? $0.1 : nil }
            let metadata = body.count > 1 && body[1] & 0x01 != 0 ? "静态元数据 Type 1" : "未声明静态元数据类型"
            let luminance = body.count > 2 ? "；期望最大亮度代码 \(body[2])" : ""
            return EDIDField(title: "CTA HDR 静态元数据块", value: eotfs.isEmpty ? "未声明 EOTF" : eotfs.joined(separator: "、"), detail: "\(metadata)\(luminance)。这里表示接收能力，不等于 HDR 当前已开启。\(location)。")
        case 0x0d:
            return EDIDField(title: "CTA 视频格式优先级数据块", value: "\(body.count) 个优先级条目", detail: "接收端对 SVD/DTD 的显示格式偏好。原始值：\(body.map { String(format: "%02X", $0) }.joined(separator: " "))。\(location)。")
        case 0x0e:
            let modes = body.map { "VIC \(Int($0))：\(ctaVideoMode(Int($0)))" }
            return EDIDField(title: "CTA YCbCr 4:2:0 视频数据块", value: "\(modes.count) 个仅 4:2:0 模式", detail: "\(modes.joined(separator: "；"))。这些时序只能使用 YCbCr 4:2:0。\(location)。")
        case 0x0f:
            return EDIDField(title: "CTA YCbCr 4:2:0 能力映射", value: "\(body.count * 8) 个映射位", detail: "按位对应同一 CTA 扩展内视频数据块的 SVD，表示哪些模式也支持 4:2:0。原始值：\(body.map { String(format: "%02X", $0) }.joined(separator: " "))。\(location)。")
        default:
            return EDIDField(title: "CTA 未公开／保留扩展标签", value: String(format: "扩展标签 0x%02X · %d 字节", extendedTag, body.count), detail: "当前采用的公开标准资料中没有足够定义可可靠解释该标签。它可能是保留值、后续修订字段或厂商实现；Right Display 保留完整原始负载而不猜测含义：\(body.map { String(format: "%02X", $0) }.joined(separator: " "))。\(location)。")
        }
    }

    private func scanBehavior(_ value: Int) -> String {
        switch value {
        case 0: return "未说明"
        case 1: return "始终过扫描"
        case 2: return "始终欠扫描"
        default: return "两者均支持"
        }
    }

    private func parseHDMIVSDB(_ p: [UInt8], location: String) -> EDIDField {
        let address = p.count >= 5 ? "\(p[3] >> 4).\(p[3] & 0x0f).\(p[4] >> 4).\(p[4] & 0x0f)" : "未提供"
        let deep = p.count > 5 ? [p[5] & 0x10 != 0 ? "30 bit" : nil, p[5] & 0x20 != 0 ? "36 bit" : nil, p[5] & 0x40 != 0 ? "48 bit" : nil, p[5] & 0x08 != 0 ? "YCbCr 4:4:4 深色" : nil].compactMap { $0 } : []
        let clock = p.count > 6 ? "\(Int(p[6]) * 5) MHz" : "未提供"
        return EDIDField(title: "HDMI 厂商数据块", value: "物理地址 \(address) · 最大 TMDS \(clock)", detail: "HDMI Licensing OUI 0x000C03；深色能力：\(deep.isEmpty ? "未声明" : deep.joined(separator: "、"))。该上限是接收端能力，并非当前链路实测速率。\(location)。")
    }

    private func parseHDMIForumVSDB(_ p: [UInt8], location: String) -> EDIDField {
        let version = p.count > 3 ? p[3] : 0
        let rate = p.count > 4 ? Int(p[4]) * 5 : 0
        var features: [String] = []
        if p.count > 5 { if p[5] & 0x80 != 0 { features.append("SCDC") }; if p[5] & 0x40 != 0 { features.append("RR capable") }; if p[5] & 0x08 != 0 { features.append("LTE 340 Mcsc scramble") } }
        if p.count > 7 { if p[7] & 0x40 != 0 { features.append("ALLM") }; if p[7] & 0x08 != 0 { features.append("VRR") }; if p[7] & 0x04 != 0 { features.append("QMS") }; if p[7] & 0x02 != 0 { features.append("QFT") } }
        return EDIDField(title: "HDMI Forum 厂商数据块", value: "版本 \(version) · 最大字符率 \(rate == 0 ? "未提供" : "\(rate) MHz")", detail: "HDMI Forum OUI 0xC45DD8；检测到：\(features.isEmpty ? "未解析到附加能力位" : features.joined(separator: "、"))。此数据块表明接收端具备相应 HDMI 能力，但不能单独证明当前使用 FRL、DSC 或具体 HDMI 协议版本。\(location)。")
    }

    private func parseDisplayID(_ block: [UInt8], blockNumber: Int) -> [EDIDField] {
        let version = block.count > 1 ? block[1] : 0, length = block.count > 2 ? Int(block[2]) : 0
        var fields = [EDIDField(title: "扩展区块 \(blockNumber) · DisplayID", value: "版本 \(version >> 4).\(version & 0x0f) · 有效负载 \(length) 字节", detail: "DisplayID 使用可变长度数据块描述高分辨率时序、显示参数、接口和分块拓扑。区块标签 0x70。")]
        var offset = 5, index = 1
        let limit = min(5 + length, 127)
        while offset + 2 < limit {
            let tag = block[offset], revision = block[offset + 1], count = Int(block[offset + 2])
            guard offset + 3 + count <= limit else { break }
            fields.append(EDIDField(title: "DisplayID 数据块 \(index)", value: String(format: "标签 0x%02X · 修订版 %d · %d 字节", tag, revision, count), detail: "区块内字节 \(offset)–\(offset + 2 + count)。原始负载：\(block[(offset + 3)..<(offset + 3 + count)].map { String(format: "%02X", $0) }.joined(separator: " "))。"))
            offset += 3 + count; index += 1
        }
        return fields
    }

    private func audioFormatName(_ id: Int) -> String {
        [1: "LPCM", 2: "AC-3", 3: "MPEG-1", 4: "MP3", 5: "MPEG-2", 6: "AAC LC", 7: "DTS", 8: "ATRAC", 10: "E-AC-3", 11: "DTS-HD", 12: "MAT / Dolby TrueHD", 13: "DST", 14: "WMA Pro"][id] ?? "音频格式代码 \(id)"
    }

    private func colorimetryDescription(_ bytes: [UInt8]) -> String {
        guard let first = bytes.first else { return "数据不足" }
        var names: [String] = []
        let firstNames = [(0x01, "xvYCC601"), (0x02, "xvYCC709"), (0x04, "sYCC601"), (0x08, "Adobe YCC601"), (0x10, "Adobe RGB"), (0x20, "BT.2020 cYCC"), (0x40, "BT.2020 YCC"), (0x80, "BT.2020 RGB")]
        names += firstNames.compactMap { first & UInt8($0.0) != 0 ? $0.1 : nil }
        if bytes.count > 1 { if bytes[1] & 0x80 != 0 { names.append("DCI-P3") } }
        return names.isEmpty ? "未设置已知颜色空间位" : names.joined(separator: "、")
    }

    private func ctaVideoMode(_ vic: Int) -> String {
        let modes: [Int: String] = [
            1: "640×480p 59.94/60 Hz 4:3", 2: "720×480p 59.94/60 Hz 4:3", 3: "720×480p 59.94/60 Hz 16:9",
            4: "1280×720p 59.94/60 Hz 16:9", 5: "1920×1080i 59.94/60 Hz 16:9", 16: "1920×1080p 59.94/60 Hz 16:9",
            17: "720×576p 50 Hz 4:3", 18: "720×576p 50 Hz 16:9", 19: "1280×720p 50 Hz 16:9", 20: "1920×1080i 50 Hz 16:9",
            31: "1920×1080p 50 Hz 16:9", 32: "1920×1080p 23.98/24 Hz 16:9", 33: "1920×1080p 25 Hz 16:9", 34: "1920×1080p 29.97/30 Hz 16:9",
            93: "3840×2160p 23.98/24 Hz 16:9", 94: "3840×2160p 25 Hz 16:9", 95: "3840×2160p 29.97/30 Hz 16:9",
            96: "3840×2160p 50 Hz 16:9", 97: "3840×2160p 59.94/60 Hz 16:9", 98: "4096×2160p 23.98/24 Hz 256:135",
            99: "4096×2160p 25 Hz 256:135", 100: "4096×2160p 29.97/30 Hz 256:135", 101: "4096×2160p 50 Hz 256:135", 102: "4096×2160p 59.94/60 Hz 256:135",
            117: "3840×2160p 100 Hz 16:9", 118: "3840×2160p 119.88/120 Hz 16:9"
        ]
        return modes[vic] ?? "CTA 标准时序（名称表未收录）"
    }

    private func decodeCTAShortVideoDescriptor(_ byte: UInt8) -> (vic: Int, native: Bool) {
        if byte >= 129 && byte <= 192 {
            return (Int(byte & 0x7f), true)
        }
        return (Int(byte), false)
    }

    private func descriptorText(type: UInt8, bytes: [UInt8]) -> String? {
        guard bytes.count >= 126 else { return nil }
        for offset in stride(from: 54, through: 108, by: 18) where
            bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 2] == 0 && bytes[offset + 3] == type {
            let scalars = bytes[(offset + 5)..<(offset + 18)].prefix { $0 != 0x0a && $0 != 0x00 }
            let text = String(bytes: scalars, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let text, !text.isEmpty { return text }
        }
        return nil
    }

    private func connectionValue(_ result: EDIDResult) -> SignalValue {
        let lower = result.path.lowercased()
        let connector = result.physicalConnector?.lowercased() ?? ""
        let transport = result.transportType?.lowercased() ?? ""
        let bytes = [UInt8](result.data)
        let hasHDMIForum = bytes.windows(ofCount: 3).contains { Array($0) == [0xD8, 0x5D, 0xC4] }
        if connector.contains("hdmi") {
            let internalPath = result.transportDescription ?? result.transportType ?? "未提供"
            let link = [result.linkRate, result.laneCount.map { "\($0) lanes" }].compactMap { $0 }.joined(separator: " · ")
            let capability = hasHDMIForum ? "接收端 EDID 含 HDMI Forum 数据块，表明具备 HDMI 2.1 相关能力；" : ""
            return SignalValue(
                text: "HDMI · 传输模式未确认",
                verification: .unavailable,
                source: "IOKit ParentBuiltInPortTypeDescription",
                detail: "\(capability)外部接口确认为 HDMI；Apple 内部显示路径为 \(internalPath)\(link.isEmpty ? "" : "（\(link)）")。内部 DisplayPort 链路不能证明外部 HDMI 当前采用 FRL 或 TMDS。"
            )
        }
        if connector.contains("displayport") || transport.contains("displayport") || lower.contains("displayport") {
            return SignalValue(text: "DisplayPort（物理端口类型未完全验证）", verification: .inferred, source: result.source, detail: result.transportDescription ?? result.path)
        }
        if bytes.windows(ofCount: 3).contains(where: { Array($0) == [0x03, 0x0C, 0x00] || Array($0) == [0xD8, 0x5D, 0xC4] }) {
            return SignalValue(text: hasHDMIForum ? "HDMI · 接收端具备 HDMI 2.1 能力（接口推断）" : "HDMI（EDID 推断）", verification: .inferred, source: "EDID HDMI 厂商数据块", detail: "EDID 表明接收端支持 HDMI，但不能单独证明 Mac 当前端口或实际协商版本。")
        }
        return SignalValue(text: "DisplayPort／HDMI 未验证", verification: .unavailable, source: "IOKit 与 EDID")
    }
}

private extension Array where Element == UInt8 {
    func windows(ofCount count: Int) -> [ArraySlice<UInt8>] {
        guard count > 0, self.count >= count else { return [] }
        return (0...(self.count - count)).map { self[$0..<($0 + count)] }
    }
}
