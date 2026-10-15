// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation

var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) { assertions += 1; precondition(value(),message) }
func u16(_ value: Int) -> [UInt8] { [UInt8((value>>8)&255),UInt8(value&255)] }
func u32(_ value: Int) -> [UInt8] { [UInt8((value>>24)&255),UInt8((value>>16)&255),UInt8((value>>8)&255),UInt8(value&255)] }
func fixed(_ value: Double) -> [UInt8] { u32(Int(UInt32(bitPattern:Int32((value*65536).rounded())))) }
func signature(_ s: String) -> [UInt8] { Array(s.utf8) }
func xyz(_ p: [Double]) -> [UInt8] { signature("XYZ ")+[UInt8](repeating:0,count:4)+p.flatMap(fixed) }
func gamma(_ g: Double) -> [UInt8] { signature("curv")+[UInt8](repeating:0,count:4)+u32(1)+u16(Int(g*256)) }
func parametric(_ type: Int, _ params: [Double]) -> [UInt8] { signature("para")+[UInt8](repeating:0,count:4)+u16(type)+u16(0)+params.flatMap(fixed) }
func sampled() -> [UInt8] { signature("curv")+[UInt8](repeating:0,count:4)+u32(4)+[0,10000,32000,65535].flatMap(u16) }
func mluc(_ text: String) -> [UInt8] { let data = [UInt8](text.data(using:.utf16BigEndian)!); return signature("mluc")+[UInt8](repeating:0,count:4)+u32(1)+u32(12)+signature("enUS")+u32(data.count)+u32(28)+data }
func desc(_ text: String) -> [UInt8] { signature("desc")+[UInt8](repeating:0,count:4)+u32(text.utf8.count+1)+signature(text)+[0]+[UInt8](repeating:0,count:78) }
func vcgt() -> [UInt8] { signature("vcgt")+[UInt8](repeating:0,count:4)+u32(0)+u16(3)+u16(4)+u16(2)+Array(repeating:[0,18000,40000,65535].flatMap(u16),count:3).flatMap { $0 } }
func baseTags(_ version: Int) -> [String:[UInt8]] {
    ["wtpt":xyz([0.9642,1,0.8249]),"rXYZ":xyz([0.4361,0.2225,0.0139]),"gXYZ":xyz([0.3851,0.7169,0.0971]),"bXYZ":xyz([0.1431,0.0606,0.7141]),
     "rTRC":gamma(2.2),"gTRC":gamma(2.2),"bTRC":gamma(2.2),"desc":version == 2 ? desc("Fixture v2") : mluc("Fixture v4"),"cprt":signature("text")+[UInt8](repeating:0,count:4)+signature("Test fixture")+[0]]
}
func profile(_ version: Int = 4, tags: [String:[UInt8]]? = nil) -> Data {
    let tags = tags ?? baseTags(version)
    var header = [UInt8](repeating:0,count:128)
    func put(_ index: Int,_ bytes: [UInt8]) { header.replaceSubrange(index..<index+bytes.count,with:bytes) }
    put(8,[UInt8(version),0x30]); put(12,signature("mntr")); put(16,signature("RGB "));put(20,signature("XYZ "));put(36,signature("acsp"))
    for (i,value) in [2026,10,2,12,30,0].enumerated() { put(24+i*2,u16(value)) }
    put(48,signature("TEST"));put(52,signature("MON1"));put(68,[0.9642,1,0.8249].flatMap(fixed))
    var table = u32(tags.count), body: [UInt8] = []
    let start = 132+tags.count*12
    for (name,bytes) in tags.sorted(by:{$0.key < $1.key}) {
        table += signature(name)+u32(start+body.count)+u32(bytes.count)
        body += bytes
        while body.count % 4 != 0 { body.append(0) }
    }
    put(0,u32(128+table.count+body.count))
    return Data(header+table+body)
}
@main struct ICCProfileTests {
    static func main() throws {
        for version in [2,4] {
            let m = try ICCParser.parse(profile(version))
            check(m.structureValid && m.isMatrix && m.gamut?.count == 3,"Matrix v\(version) failed")
            check(m.version == "\(version).3.0" && m.name == "Fixture v\(version)","ICC description/version")
            check(m.creationDate != nil && m.manufacturer == "TEST" && m.model == "MON1","Header metadata/date")
            check(m.vcgt == nil,"Missing VCGT fabricated")
        }
        var tags = baseTags(4);tags.removeValue(forKey:"wtpt")
        check(tryParse(profile(tags:tags)).gamut == nil,"Missing white fabricated")
        tags = baseTags(4); tags.removeValue(forKey:"gXYZ")
        let missing = try ICCParser.parse(profile(tags:tags))
        check(missing.colorants[1] == nil && missing.colorants[2] != nil && missing.gamut == nil,"Primary channel shifted")
        tags = baseTags(4);tags["rTRC"] = gamma(2.2);tags["gTRC"] = parametric(4,[2.4,1,0,1,0.003,0,0]);tags["bTRC"] = sampled()
        let curves = try ICCParser.parse(profile(tags:tags))
        if case .gamma(let g) = curves.trcs[0] { check(abs(g-2.2) < 0.005,"Simple gamma value") } else { fatalError("Gamma classification") }
        if case .parametric(let type,let p) = curves.trcs[1] { check(type == 4 && p.count == 7,"Parametric classification") } else { fatalError("Parametric collapsed to gamma") }
        if case .sampled(let p) = curves.trcs[2] { check(p.count == 4 && p.first == 0 && p.last == 1,"Sampled classification") } else { fatalError("Sampled collapsed") }
        tags["vcgt"] = vcgt()
        let calibrated = try ICCParser.parse(profile(tags:tags))
        if case .table(let p,let bits) = calibrated.vcgt { check(p.count == 3 && p[0].count == 4 && bits == 16,"VCGT table") } else { fatalError("VCGT missing") }
        tags["vcgt"] = signature("vcgt")+[UInt8](repeating:0,count:4)+u32(1)+Array(repeating:[2.2,0,1].flatMap(fixed),count:3).flatMap { $0 }
        if case .formula(let p) = try ICCParser.parse(profile(tags:tags)).vcgt { check(p.count == 3,"VCGT formula") } else { fatalError("VCGT formula") }
        tags["vcgt"] = signature("vcgt")+[UInt8](repeating:0,count:4)+u32(0)
        if case .unsupported = try ICCParser.parse(profile(tags:tags)).vcgt { check(true,"Truncated VCGT") } else { fatalError("Unsafe VCGT") }
        tags = baseTags(4);tags["rXYZ"] = signature("XYZ ")+[UInt8](repeating:0,count:4)
        let truncated = try ICCParser.parse(profile(tags:tags));check(truncated.colorants[0] == nil && truncated.gamut == nil,"Truncated XYZ read")
        tags["rXYZ"] = signature("abcd")+[UInt8](repeating:0,count:16)
        check(tryParse(profile(tags:tags)).gamut == nil,"Unexpected XYZ type accepted")
        tags = baseTags(4); tags["rTRC"] = signature("para")+[UInt8](repeating:0,count:4)+u16(99)+u16(0)
        if case .unsupported = try ICCParser.parse(profile(tags:tags)).trcs[0] { check(true,"Unsupported TRC") } else { fatalError("Unknown TRC") }
        tags = baseTags(4); tags["A2B0"] = signature("mft2")+[UInt8](repeating:0,count:4)+[3,3,2,0]+[1.0,0,0,0,1,0,0,0,1].flatMap(fixed)+u16(2)+u16(2)+[UInt8](repeating:0,count:72)
        let lut = try ICCParser.parse(profile(tags:tags));check(lut.structureValid && lut.hasLUT && lut.gamut == nil,"LUT rejected or false triangle")
        tags = baseTags(4);tags["chad"] = signature("sf32")+[UInt8](repeating:0,count:4)+[1.0,0,0,0,1,0,0,0,1].flatMap(fixed)
        let adapted = try ICCParser.parse(profile(tags:tags));check(adapted.gamut?.count == 3 && adapted.chad?.inverse != nil,"chad matrix")
        let bradford = ICCMatrix(values:[1.0478112,0.0228866,-0.0501270,0.0295424,0.9904844,-0.0170491,-0.0092345,0.0150436,0.7521316])
        let original = ICCXYZ(x:0.95047,y:1,z:1.08883)
        let roundtrip = bradford.inverse!.apply(bradford.apply(original))
        check(abs(roundtrip.x-original.x) < 1e-8 && abs(roundtrip.z-original.z) < 1e-8,"Inverse adaptation")
        tags["chad"] = signature("sf32")+[UInt8](repeating:0,count:40)
        check(tryParse(profile(tags:tags)).gamut == nil,"Singular adaptation ignored")
        var invalid = profile();invalid.replaceSubrange(0..<4,with:u32(0))
        check((try? ICCParser.parse(invalid)) == nil,"Invalid import/header accepted")
        invalid = profile();invalid.replaceSubrange(128..<132,with:u32(Int(UInt32.max)))
        check(!tryParse(invalid).structureValid,"Huge tag table accepted")
        invalid = profile();invalid.replaceSubrange(136..<140,with:u32(Int(UInt32.max)))
        check(!tryParse(invalid).structureValid,"Tag overflow accepted")
        check((try? ICCParser.parse(Data(profile().prefix(100)))) == nil,"Truncated header accepted")
        invalid = profile();invalid.replaceSubrange(26..<28,with:u16(13))
        check(tryParse(invalid).creationDate == nil,"Invalid date normalized into fabricated date")
        invalid = profile();invalid.replaceSubrange(148..<152,with:u32(133))
        check(!tryParse(invalid).structureValid,"Unaligned overlapping tag accepted")
        tags = baseTags(4);tags["chad"] = signature("abcd")+[UInt8](repeating:0,count:36)
        check(tryParse(profile(tags:tags)).gamut == nil,"Unexpected adaptation type ignored")
        tags = baseTags(4);tags["rTRC"] = signature("para")+[UInt8](repeating:0,count:4)+u16(4)+u16(0)+fixed(2.4)
        check(!tryParse(profile(tags:tags)).isMatrix,"Unsupported TRC presented as supported matrix")
        var seed: UInt64 = 42
        for _ in 0..<512 {
            var data = profile()
            seed = seed &* 6364136223846793005 &+ 1
            let offset = Int(seed % UInt64(data.count))
            data[offset] = UInt8(truncatingIfNeeded:seed >> 32)
            _ = try? ICCParser.parse(data)
        }
        check(true,"Deterministic malformed mutations completed without crash")
        let ctx = ICCDisplayContext(displayID:7,connectionInstance:"session-A",generation:UUID(),colorSyncUUID:"uuid-A")
        let target = ICCProfileIdentity(data:profile(),url:URL(fileURLWithPath:"/tmp/a.icc"))
        var txn = ICCAssociationTransaction(context:ctx,target:target);txn.accepted = true
        check(txn.observe(target,context:ctx,timedOut:false) == .waiting,"Request/single read falsely confirmed")
        check(txn.observe(target,context:ctx,timedOut:false) == .confirmed,"Exact association not confirmed")
        let wrong = ICCProfileIdentity(data:profile(2),url:URL(fileURLWithPath:"/tmp/a.icc"))
        check(txn.observe(wrong,context:ctx,timedOut:true) == .unconfirmed,"Mismatch confirmed")
        check(txn.observe(target,context:ICCDisplayContext(displayID:8,connectionInstance:"session-B",generation:ctx.generation,colorSyncUUID:"uuid-B"),timedOut:false) == .stale,"Sibling callback accepted")
        txn.accepted = false;check(txn.observe(target,context:ctx,timedOut:true) == .failed,"Rejected write confirmed")
        check(!target.matches(ICCProfileIdentity(data:profile(),url:URL(fileURLWithPath:"/tmp/b.icc"))),"Different concrete URL confirmed")
        check(target.matches(ICCProfileIdentity(data:profile(),url:nil)),"Data-only association ignored")
        var registry = DisplayIdentityRegistry()
        registry.update([.init(displayID:7,vendor:1,model:2,serial:0),.init(displayID:8,vendor:1,model:2,serial:0)])
        let first = registry.identity(for:7)!, second = registry.identity(for:8)!
        check(first.connectionInstanceKey != second.connectionInstanceKey,"Serial-less ICC context collision")
        registry.invalidate(7);registry.update([.init(displayID:7,vendor:1,model:2,serial:0)])
        check(first.connectionInstanceKey != registry.identity(for:7)!.connectionInstanceKey,"Stale displayID reused")
        check(ICCReferenceGamut.allCases.count == 4 && ICCReferenceGamut.displayP3.primaries[0] == .init(x:0.68,y:0.32),"P3 constants")
        check(ICCReferenceGamut.sRGB.primaries[1] == .init(x:0.30,y:0.60) && ICCReferenceGamut.adobeRGB.primaries[1] == .init(x:0.21,y:0.71),"Reference constants")
        check(ICCReferenceGamut.bt2020.primaries[0] == .init(x:0.708,y:0.292) && ICCReferenceGamut.white == .init(x:0.3127,y:0.3290),"BT2020/D65 constants")
        check(ICCXYZ(x:0,y:0,z:0).xy == nil,"Zero XYZ normalized")
        print("ICC parser/model tests: \(assertions) assertions PASS; deterministic fixtures, no display writes")
    }
    static func tryParse(_ data: Data) -> ICCProfileMetadata { try! ICCParser.parse(data) }
}
