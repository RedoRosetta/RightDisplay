# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Exercise the production presentation inventory with a deterministic monotonic clock.
No display APIs, windows or hardware writes. Also guard the fresh-path boundary.
"""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parent.parent
source=(root/'RightDisplay/Services/DisplayStore.swift').read_text()
cache=source[source.index('struct DisplayObservationInventory<Value>'):source.index('private struct DisplayPresentationInventory')]
out=Path(tempfile.mkdtemp(prefix='RightDisplay-ObservationTests-',dir='/private/tmp'))
program='import Foundation\n'+cache+r'''
var assertions=0,builds=0
func check(_ ok:Bool){assertions+=1;precondition(ok,"inventory assertion \(assertions)")}
var cache=DisplayObservationInventory<Int>()
func read(_ id:UInt32=1,_ key:String="timing-A",_ now:Double,_ force:Bool=false)->Int {
 cache.value(for:id,key:key,now:now,forceFresh:force) {builds+=1;return builds}
}
check(read(1,"timing-A",0)==1)
// Ordinary two-second observations must never full-scan the inventory.
for t in stride(from:2.0,through:118.0,by:2) {check(read(1,"timing-A",t)==1)}
check(builds==1)
check(read(1,"timing-A",120)==2) // conservative reconciliation, not a timer slowdown
check(read(1,"timing-A",121)==2)
check(read(1,"timing-A",122,true)==3) // explicit/event/transaction refresh bypasses cache
check(read(1,"timing-B",123)==4) // raw timing or link evidence changed
check(read(2,"same-model-zero-serial-attachment-B",123)==5) // per-display isolation
check(read(1,"timing-B",124)==4)
cache.invalidate(1);check(read(1,"timing-B",125)==6) // remove/reconnect invalidation
cache.retain([1]);check(read(2,"same-model-zero-serial-attachment-B",126)==7)
check(read(1,"timing-B",1)==8) // backwards/reset clock cannot extend validity
check(read(1,"timing-B",2)==8)
check(read(1,"new-attachment",3)==9)
print("Display observation inventory: \(assertions) assertions PASS; fresh bypass, active changes, topology isolation, bounded reconciliation")
'''
(out/'main.swift').write_text(program)
subprocess.run(['xcrun','swiftc','-warnings-as-errors','-module-cache-path',str(out/'cache'),str(out/'main.swift'),'-o',str(out/'test')],check=True)
subprocess.run([str(out/'test')],check=True)
# Guard integration: allModes itself and all control callers remain uncached.
all_modes=source[source.index('    private func allModes('):source.index('    private func currentTiming(')]
assert 'observationInventory' not in all_modes
assert 'DisplayTimingController.shared.enumerate(displayID: id)' in all_modes
assert 'refreshObservation(forceInventoryRefresh: true)' in source
assert 'self?.refreshObservation(forceInventoryRefresh: false)' in source
snapshot=source[source.index('    private func makeSnapshot('):source.index('    private func allModes(')]
assert 'DisplayTimingController.shared.read(displayID: id, index: $0)' in snapshot
assert 'forceFresh: !reuseObservationInventory' in snapshot
assert 'reuseObservationInventory && activeTiming == nil\n            ? nil' in snapshot
# No idle-cache references within precheck/verification/restore/LinkTest sections.
prefix=source[:source.index('    private func makeSnapshot(')]
for line in prefix.splitlines():
 if 'observationInventory' in line: assert any(x in line for x in ['private var','invalidate(displayID)','retain(Set(ids))'])
print('Fresh-path integration guards: PASS; unchanged transaction enumeration/readback; missing active evidence never falls back to cached VRR')
print('Evidence='+str(out))
