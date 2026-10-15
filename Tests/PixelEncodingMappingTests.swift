// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation

@main
struct PixelEncodingMappingTests {
    static func main() throws {
        let titles = ["RGB 4:4:4", "YCbCr 4:4:4", "YCbCr 4:2:2", "YCbCr 4:2:0"]
        for raw in UInt32(0)...3 {
            let encoding = LinkPixelEncoding(rawValue: raw)!
            precondition(encoding.title == titles[Int(raw)])
            let decoded = try JSONDecoder().decode(LinkPixelEncoding.self, from: JSONEncoder().encode(encoding))
            precondition(decoded.rawValue == raw)
            let actual = DisplayLinkDescription(bitDepth: 10, range: 0, eotf: 2, pixelEncoding: raw)
            precondition(actual.encodingText == titles[Int(raw)])
            precondition(actual.matches(actual))
            let roundTrip = try JSONDecoder().decode(DisplayLinkDescription.self, from: JSONEncoder().encode(actual))
            precondition(roundTrip == actual)
            let desired = DesiredLinkState(description: actual)
            precondition(desired.encodingText == actual.encodingText)
            precondition(desired.capability.encodingText == actual.encodingText)
            precondition(desired.exactlyMatches(rawPixelEncoding: raw, bitDepth: 10, hdr: true, systemHDR: true, rawRange: 0, rawEOTF: 2))
            for other in UInt32(0)...3 where other != raw {
                precondition(!desired.exactlyMatches(rawPixelEncoding: other, bitDepth: 10, hdr: true, systemHDR: true))
            }
            precondition(!desired.exactlyMatches(rawPixelEncoding: raw, bitDepth: 12, hdr: true, systemHDR: true))
            precondition(!desired.exactlyMatches(rawPixelEncoding: raw, bitDepth: 10, hdr: true, systemHDR: false))
            let signal = actual.encodingSignal(activeIndex: 0)
            precondition(signal.source == "SLSGetDisplayOutputModeLinkDescriptions")
            precondition(signal.detail.contains("PixelEncoding=\(raw)") && signal.detail.contains("activeIndex=0"))
            precondition(signal.verification != .verified)
        }
        for raw: UInt32 in [4, 99, UInt32.max] {
            precondition(!LinkPixelEncoding.isKnown(raw))
            precondition(LinkPixelEncoding.title(for: raw) == "格式未知")
            let unknown = DisplayLinkDescription(bitDepth: 10, range: 0, eotf: 2, pixelEncoding: raw)
            precondition(unknown.encoding == nil && unknown.bandwidthComponentMultiplier == nil)
            precondition(!unknown.satisfies(color: .yCbCr, bitDepth: 10, hdrEnabled: true))
            precondition(unknown.encodingSignal(activeIndex: 0).verification == .unavailable)
            let decoded = try JSONDecoder().decode(DisplayLinkDescription.self, from: JSONEncoder().encode(unknown))
            precondition(decoded.pixelEncoding == raw)
        }
        precondition(LinkPixelEncoding.title(for: nil) == "格式未知")
        precondition(LinkPixelEncoding.yCbCr444.bandwidthComponentMultiplier == 3)
        precondition(LinkPixelEncoding.yCbCr422.bandwidthComponentMultiplier == 2)
        precondition(LinkPixelEncoding.yCbCr420.bandwidthComponentMultiplier == 1.5)
        let a = DisplayLinkDescription(bitDepth: 10, range: 0, eotf: 2, pixelEncoding: 1)
        let b = DisplayLinkDescription(bitDepth: 10, range: 0, eotf: 2, pixelEncoding: 2)
        precondition(!a.matches(b))
        precondition(DisplayOutputState(descriptions: [a, b], activeIndex: 1).activeDescription == b)
        precondition(DisplayOutputState(descriptions: [a], activeIndex: UInt32.max).activeDescription == nil)
        let rgb12 = DisplayLinkDescription(bitDepth: 12, range: 1, eotf: 2, pixelEncoding: 0)
        let rgb12Limited = DisplayLinkDescription(bitDepth: 12, range: 0, eotf: 2, pixelEncoding: 0)
        let rgb12HLG = DisplayLinkDescription(bitDepth: 12, range: 1, eotf: 3, pixelEncoding: 0)
        let target = DesiredLinkState(description: rgb12)
        precondition(target.capability.identity == rgb12.identity)
        precondition(Set([target.capability, DesiredLinkState(description: rgb12Limited).capability,
                          DesiredLinkState(description: rgb12HLG).capability]).count == 3)
        precondition(LinkEvidencePlanner.exact(target, actual: rgb12, hdr: true))
        precondition(!LinkEvidencePlanner.exact(target, actual: rgb12Limited, hdr: true))
        precondition(!LinkEvidencePlanner.exact(target, actual: rgb12HLG, hdr: true))
        let legacy = DesiredLinkState(rawPixelEncoding: 0, bitDepth: 12, hdrEnabled: true)
        precondition(legacy.identity == nil && !LinkEvidencePlanner.exact(legacy, actual: rgb12, hdr: true))
        let state = DisplayOutputState(descriptions: [a, rgb12], activeIndex: 0)
        precondition(state.activeDescription == a && state.authoritativeDescription == nil)
        precondition(state.slsReportedDescription == a)
        precondition(state.currentReadbackSource.contains("SLS_REPORTED"))
        precondition(a.encodingSignal(activeIndex: 0).verification == .slsReported)
        precondition(a.depthSignal.text == "10 bit" && a.depthSignal.verification == .slsReported)
        let partlyKnown = DisplayLinkDescription(bitDepth: 10, range: 99, eotf: 99, pixelEncoding: 1)
        precondition(partlyKnown.encodingSignal(activeIndex: 0).verification == .slsReported)
        precondition(partlyKnown.depthSignal.verification == .slsReported)
        precondition(!partlyKnown.identity.isKnown)
        precondition(Verification.slsReported != Verification.unavailable)
        precondition(ConnectionTargetResolver.singleField(current: nil, candidates: [a, rgb12], depth: 12) == nil)
        precondition(ConnectionTargetResolver.singleField(current: rgb12.identity, candidates: [rgb12], depth: 12) == target)
        precondition(ConnectionTargetResolver.singleField(current: rgb12.identity, candidates: [rgb12Limited], depth: 12)?.identity == rgb12Limited.identity)
        let rgb10 = DisplayLinkDescription(bitDepth: 10, range: 1, eotf: 2, pixelEncoding: 0)
        let ycc420 = DisplayLinkDescription(bitDepth: 10, range: 0, eotf: 2, pixelEncoding: 3)
        let candidates = [a, rgb12, rgb10, ycc420]
        precondition(ConnectionTargetResolver.singleField(current: a.identity, candidates: candidates, depth: 12) == target)
        precondition(ConnectionTargetResolver.singleField(current: a.identity, candidates: candidates.reversed(), depth: 12) == target)
        precondition(ConnectionTargetResolver.singleField(current: a.identity, candidates: candidates, encoding: 0)?.identity == rgb10.identity)
        precondition(ConnectionTargetResolver.singleField(current: a.identity, candidates: candidates, depth: 8) == nil)
        precondition(ConnectionTargetResolver.singleField(current: a.identity, candidates: [rgb12, rgb12HLG], depth: 12) == target)
        let ambiguous = DisplayLinkDescription(bitDepth: 12, range: 1, eotf: 2, pixelEncoding: 2)
        precondition(ConnectionTargetResolver.singleField(current: a.identity, candidates: [rgb12, ambiguous], depth: 12) == nil)
        let control = ConnectionVerification(target: target, slsReported: rgb12, systemHDR: true)
        precondition(control.control == .pass && control.physical == .unavailable)
        precondition(!control.requiresControlRecovery)
        precondition(LinkEvidencePlanner.exact(target, actual: rgb12, hdr: true))
        let failed = ConnectionVerification(target: target, slsReported: a, systemHDR: true)
        precondition(failed.control == .fail && failed.requiresControlRecovery)
        let missing = ConnectionVerification(target: target, slsReported: nil, systemHDR: true)
        precondition(missing.control == .unavailable && missing.requiresControlRecovery)
        for raw: UInt32 in [99, UInt32.max] {
            let unknown = ConnectionIdentity(pixelEncoding: 0, depth: 12, range: raw, eotf: raw)
            precondition(!unknown.isKnown)
            precondition(unknown.rangeText == "Unknown" && unknown.eotfText == "Unknown")
            let decodedUnknown = try JSONDecoder().decode(ConnectionIdentity.self, from: JSONEncoder().encode(unknown))
            precondition(decodedUnknown == unknown)
        }
        var budget = LinkTestBudget(deadline: Date().addingTimeInterval(120))
        precondition(!budget.shouldStop(now: Date()))
        budget.slsActions = 6; budget.environmentChanges = 2
        precondition(budget.shouldStop(now: Date()))
        budget.slsActions = 0; budget.environmentChanges = 0; budget.noNewResults = 3
        precondition(budget.shouldStop(now: Date()))
        precondition(!LinkEvidencePlanner.exact(target, actual: state.authoritativeDescription, hdr: true))
        func timing(_ rate: Double, _ index: UInt32, _ vrr: Bool? = false) -> TimingIdentity {
            TimingIdentity(displayID: 2, hardwareKey: "fixture", cgsIndex: index,
                ioModeID: Int32(index + 100), width: 1920, height: 1080, pixelWidth: 3840,
                pixelHeight: 2160, rawRefreshRate: rate, vrr: vrr, ioFlags: 3)
        }
        for (integer, fractional) in [(120.0,119.88),(60.0,59.94),(30.0,29.97),(24.0,23.98)] {
            precondition(timing(integer, 1) != timing(fractional, 1))
            precondition(timing(integer, 1).key != timing(fractional, 1).key)
            precondition(RefreshRateText.number(integer) != RefreshRateText.number(fractional))
            precondition(Set([timing(integer, 1), timing(fractional, 1)]).count == 2)
        }
        precondition(timing(120, 1) != timing(120, 1, true))
        precondition(timing(120, 1) != timing(120, 2))
        // Identical formatted labels still retain different raw timing identity.
        precondition(RefreshRateText.number(59.94001) == RefreshRateText.number(59.94002))
        precondition(timing(59.94001, 1) != timing(59.94002, 1))
        let lowRange = ModeRefreshRange(minimum: 48, maximum: 144, source: "fixture per-mode")
        precondition(lowRange.text == "48–144 Hz（VRR）")
        precondition(!ModeRefreshRange(minimum: 40, maximum: nil, source: "partial").isComplete)
        precondition(ModeRefreshRange(minimum: nil, maximum: 120, source: "partial").text.contains("范围未知"))
        precondition(!ModeRefreshRange(minimum: 120, maximum: 40, source: "invalid").isComplete)
        func uiMode(_ rate: Double, _ vrr: Bool?, _ range: ModeRefreshRange = .init(minimum: nil, maximum: nil, source: "fixture")) -> DisplayModeOption {
            DisplayModeOption(id: 1, width: 1920, height: 1080, pixelWidth: 1920,
                pixelHeight: 1080, outputWidth: 1920, outputHeight: 1080,
                refreshRate: rate, isHiDPI: false, vrrState: vrr, ioFlags: 3,
                mode: nil, refreshRange: range)
        }
        let fixedUI = uiMode(120, false)
        let fractionalUI = uiMode(119.88, false)
        let vrrUI = uiMode(120, true, .init(minimum: 40, maximum: 120, source: "fixture mode"))
        precondition(fixedUI.refreshText == "120 Hz")
        precondition(fractionalUI.refreshText == "119.88 Hz")
        precondition(uiMode(59.94, false).refreshText == "59.94 Hz")
        precondition(vrrUI.refreshText == "40–120 Hz（VRR）")
        let fixedOverview = OverviewRefreshText(mode: fixedUI, fallbackText: "ignored", reportedVRR: false)
        precondition(fixedOverview.value == "120 Hz" && fixedOverview.status == "VRR 未启用")
        let vrrOverview = OverviewRefreshText(mode: vrrUI, fallbackText: "ignored", reportedVRR: true)
        precondition(vrrOverview.value == "40–120 Hz" && vrrOverview.status == "VRR 已启用")
        precondition(OverviewRefreshText(mode: uiMode(120, true), fallbackText: "120 Hz", reportedVRR: true).value == "范围未知")
        precondition(OverviewRefreshText(mode: nil, fallbackText: "未知", reportedVRR: nil).status == "VRR 状态未知")
        let protect = TimingConnectionProtection(original: rgb12.identity, systemHDR: true)
        precondition(protect.matches(rgb12.identity, systemHDR: true))
        precondition(!protect.matches(rgb12Limited.identity, systemHDR: true))
        precondition(!protect.matches(rgb12HLG.identity, systemHDR: true))
        precondition(!protect.matches(rgb12.identity, systemHDR: false))
        precondition(!protect.matches(nil, systemHDR: true))
        precondition(!protect.matches(partlyKnown.identity, systemHDR: true))
        precondition(protect.targetExists(in: [a,rgb12]))
        precondition(!protect.targetExists(in: [a,rgb12Limited]))
        precondition(!TimingConnectionProtection(original: nil, systemHDR: true).matches(nil, systemHDR: true))
        precondition(!TimingConnectionProtection(original: rgb12.identity, systemHDR: nil).matches(rgb12.identity, systemHDR: nil))
        let parsed = DisplayCapabilitySummary.system([
            "SupportsVariableRefreshRate": true, "MinimumVariableRefreshRate": 2621440,
            "MaximumVariableRefreshRate": 7864320, "MinimumRefreshRate": 24, "MaximumRefreshRate": 120,
            "SupportsHDRStaticMetadataType1": true, "SupportsPQEOTF": true, "SupportsHLGEOTF": true,
            "SupportsBT2020RGB": 512, "SupportsBT2020YCC": 128])
        precondition(parsed.source == .macOSParsed && parsed.vrr == true)
        precondition(parsed.minimumVRR == 40 && parsed.maximumVRR == 120)
        precondition(parsed.minimumRefresh == 24 && parsed.maximumRefresh == 120)
        precondition(parsed.pq == true && parsed.hlg == true && parsed.hdrStaticMetadataType1 == true)
        precondition(parsed.bt2020RGB == true && parsed.bt2020YCC == true)
        precondition(parsed.fields.allSatisfy { $0.detail.contains("不是 current connection") })
        precondition(DisplayCapabilitySummary.system([:]).vrr == nil)
        precondition(DisplayCapabilitySummary.system([:]).minimumVRR == nil)
        // Valid EDID+CTA fixture tests actual parser and checksum rejection.
        var fixture = [UInt8](repeating: 0, count: 256)
        fixture.replaceSubrange(0..<8, with: [0,255,255,255,255,255,255,0])
        fixture[126] = 1; fixture[128] = 2; fixture[129] = 3; fixture[130] = 12
        fixture.replaceSubrange(132..<140, with: [0xE3,6,0x0C,1,0xE3,5,0xC0,0])
        for start in [0,128] {
            fixture[start+127] = UInt8((256 - fixture[start..<(start+127)].reduce(0) { ($0 + Int($1)) & 255 }) & 255)
        }
        let sink = DisplayCapabilitySummary.edid(Data(fixture))!
        precondition(sink.source == .sinkEDID && sink.pq == true && sink.hlg == true)
        precondition(sink.hdrStaticMetadataType1 == true && sink.bt2020RGB == true && sink.bt2020YCC == true)
        precondition(sink.vrr == nil && sink.minimumVRR == nil && sink.maximumVRR == nil)
        fixture[133] ^= 1
        precondition(DisplayCapabilitySummary.edid(Data(fixture)) == nil)
        precondition(DisplayCapabilitySummary.edid(Data(fixture.prefix(128))) == nil)
        print("PASS: timing identity/fractional/fixed-vrr/ranges, full timing connection protection, EDID+parsed capability separation; mapping 0/1/2/3/unknown, raw round-trip, actual/desired exact comparison, active index, bandwidth, evidence semantics")
    }
}
