// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
@main struct ICCProfileAssociationTests {
    @MainActor static func settle(_ predicate: () -> Bool) async {
        for _ in 0..<1000 { if predicate() { return }; try? await Task.sleep(nanoseconds:1_000_000) }
        precondition(predicate(),"Async transaction never reached terminal state")
    }
    @MainActor static func main() async throws {
        let current = ColorProfileInfo(url:URL(fileURLWithPath:"/tmp/current.icc"),identity:ICCProfileIdentity(data:profile(2),url:URL(fileURLWithPath:"/tmp/current.icc")),name:"Current",source:.system,metadata:try ICCParser.parse(profile(2)),colorSyncVerified:true)
        let target = ColorProfileInfo(url:URL(fileURLWithPath:"/tmp/target.icc"),identity:ICCProfileIdentity(data:profile(4),url:URL(fileURLWithPath:"/tmp/target.icc")),name:"Target",source:.system,metadata:try ICCParser.parse(profile(4)),colorSyncVerified:true)
        var registry = DisplayIdentityRegistry(); registry.update([.init(displayID:7,vendor:1,model:2,serial:0),.init(displayID:8,vendor:1,model:2,serial:0)])
        let a = DisplaySnapshot(id:7,deviceIdentity:registry.identity(for:7)), b = DisplaySnapshot(id:8,deviceIdentity:registry.identity(for:8))
        let owner = DisplayStore();owner.displays = [a,b];owner.selectedDisplay = a
        PublicColorSyncProfiles.target = target; PublicColorSyncProfiles.observed = current
        let model = ColorProfileStore(readbackInterval:1_000_000)
        model.refresh(display:a,store:owner);await settle { !model.loading }
        check(model.current?.identity == current.identity,"Fresh current association failed")
        owner.occupied = true;model.apply(target,store:owner)
        check(PublicColorSyncProfiles.requests == 0 && !model.busy,"Operation ownership bypass")
        owner.occupied = false;PublicColorSyncProfiles.afterRequest = { PublicColorSyncProfiles.observed = target }
        model.apply(target,store:owner);await settle { !model.busy }
        check(model.status.hasSuffix("CONFIRMED") && !model.status.contains("UNCONFIRMED") && model.current?.identity == target.identity,"Exact readback not confirmed")
        check(owner.lease == nil && owner.releases == 1 && PublicColorSyncProfiles.requests == 1,"Transaction lease/write count")
        PublicColorSyncProfiles.afterRequest = nil;PublicColorSyncProfiles.observed = current
        model.apply(target,store:owner);await settle { !model.busy }
        check(model.status.hasSuffix("UNCONFIRMED") && owner.lease == nil,"Mismatch/timeout falsely confirmed or permanently busy")
        PublicColorSyncProfiles.accepted = false
        model.apply(target,store:owner);await settle { !model.busy }
        check(model.status.hasSuffix("FAILED") && owner.lease == nil,"Rejected request not terminal")
        PublicColorSyncProfiles.accepted = true;PublicColorSyncProfiles.observed = target
        PublicColorSyncProfiles.afterRequest = { owner.selectedDisplay = b;owner.colorProfileGeneration = UUID() }
        model.apply(target,store:owner);await settle { !model.busy }
        check(model.status.contains("context changed") && owner.lease == nil,"Sibling context callback accepted")
        PublicColorSyncProfiles.afterRequest = nil
        model.refresh(display:b,store:owner);await settle { !model.loading }
        let siblingContext = ColorProfileStore.displayContext(b,store:owner)
        check(siblingContext?.connectionInstance != a.deviceIdentity?.connectionInstanceKey,"Serial-zero sibling isolation failed")
        owner.selectedDisplay = a
        let before = PublicColorSyncProfiles.requests;model.apply(target,store:owner)
        check(PublicColorSyncProfiles.requests == before,"Stale selected context wrote profile")
        model.refresh(display:a,store:owner);await settle { !model.loading }
        PublicColorSyncProfiles.target = current
        model.apply(target,store:owner);await settle { !model.busy }
        check(PublicColorSyncProfiles.requests == before && model.status.contains("target/context changed"),"Replaced profile file accepted")
        PublicColorSyncProfiles.target = target
        PublicColorSyncProfiles.sharedUUID = true
        check(ColorProfileStore.displayContext(a,store:owner) == nil,"Ambiguous ColorSync UUID permitted write context")
        PublicColorSyncProfiles.sharedUUID = false
        model.apply(target,store:owner);model.cancel(store:owner);await Task.yield()
        check(!model.busy && owner.lease == nil && PublicColorSyncProfiles.requests == before,"Cancelled queued request wrote profile")
        print("ICC production-store association tests: \(assertions) assertions PASS; fake backend, no ColorSync writes")
    }
}
