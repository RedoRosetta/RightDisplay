# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
# Compile the actual production value types, without instantiating controllers
# or running any hardware/display APIs. No copied production implementation.
require 'tmpdir'
root = File.expand_path('..', __dir__)
def section(path, first, last)
  text = File.read(path)
  start = text.index(first) or abort "Missing production marker: #{first}"
  finish = text.index(last, start) or abort "Missing production marker: #{last}"
  text[start...finish]
end
snapshot = File.join(root, 'RightDisplay/Models/DisplaySnapshot.swift')
controller = File.join(root, 'RightDisplay/Services/DisplayOutputController.swift')
# Static integration checks complement the production value-type tests without
# launching controllers or reading/writing a real display.
store = File.read(File.join(root, 'RightDisplay/Services/DisplayStore.swift'))
abort 'Physical-current gate leaked into controls' if store.include?('.authoritativeDescription')
abort 'Missing SLS snapshot input' unless store.include?('let activeLink = outputState?.slsReportedDescription') &&
  store.include?('activeLink?.encodingSignal') && store.include?('activeLink?.depthSignal')
abort 'Missing full-candidate guard' unless store.include?('state.descriptions.contains(where: { $0.identity == identity })')
abort 'Missing control-only verification' unless store.include?('let matched = !verification.requiresControlRecovery')
view = File.read(File.join(root, 'RightDisplay/Views/SettingsView.swift'))
abort 'Rate-only selection still present' if view.include?('private func refreshBinding(') || view.include?('private func refreshRates(')
vrr_toggle = section(File.join(root, 'RightDisplay/Services/DisplayStore.swift'), '    func setVRREnabled', '    func setDSCEnabled')
abort 'VRR toggle still selects maximum refresh' if vrr_toggle.include?('.max(')
abort 'VRR toggle lacks fresh exact selection' unless vrr_toggle.include?('allModes(for: selectedDisplayID)') && vrr_toggle.include?('candidates.count == 1') && vrr_toggle.include?('$0.refreshRate == current.refreshRate')
abort 'Missing timing candidate precheck'  unless store.include?('protection.targetExists(in: candidateState.descriptions)')
abort 'Missing timing connection verification' unless store.include?('change.protection.matches(state?.slsReportedDescription?.identity, systemHDR: hdr)')
timing = File.read(controller)
abort 'VRR query does not use CGS index' unless timing.include?('vrr?(displayID, index)') && timing.include?('minimum?(displayID, index, &low)')
abort 'Direct IO mode VRR query remains' if timing.include?('isDisplayModeVRR(displayID, modeID)')
abort 'Refresh overview destination missing' unless view.include?('evidence("刷新率", overviewRefreshSignal(d), "speedometer",') && view.include?('destination: .refreshRate,')
abort 'Refresh setting navigation anchor missing' unless view.include?('settingRow("刷新率", "arrow.clockwise", target: .refreshRate)')
abort 'Existing display-output navigation missing' unless view.include?('if let destination { navigate(to: .displayOutput, target: destination) }')
abort 'Refresh navigation target missing' unless File.read(File.join(root, 'RightDisplay/Views/SettingsSupportViews.swift')).include?('    case refreshRate')
abort 'Missing explicit complete candidate selection' unless view.include?('store.applyLinkCapability(candidate, source: "COMPLETE_CANDIDATE")')
models = "import Foundation\nimport CoreGraphics\nenum OutputPreference { case automatic, rgbFullRange, yCbCr }\n"
models += section(snapshot, 'enum Verification:', '// Formatting is presentation only.')
models += section(snapshot, 'enum RefreshRateText', '// Complete connection identity.')
models += section(snapshot, 'struct ConnectionIdentity:', 'enum AutoCorrectionStage:')
models += section(File.join(root, 'RightDisplay/Services/EDIDStore.swift'), 'struct EDIDField:', '@MainActor')
models += section(controller, 'struct DisplayLinkDescription:', 'enum LinkControlIntent:')
models += section(controller, 'struct DisplayOutputState', 'final class CoreDisplayHDRController')
models += section(File.join(root, 'RightDisplay/Models/DisplayCapabilityProfile.swift'), 'struct LinkTransitionContext:', 'enum LinkTestProbeRanker')
Dir.mktmpdir('rightdisplay-mapping-tests-', '/private/tmp') do |dir|
  source = File.join(dir, 'ProductionValueTypes.swift')
  File.write(source, models)
  exe = File.join(dir, 'mapping-tests')
  abort 'Compile failed' unless system('xcrun', 'swiftc', '-module-cache-path', File.join(dir, 'ModuleCache'), File.join(root, 'RightDisplay/Models/LinkPixelEncoding.swift'), source, File.join(__dir__, 'PixelEncodingMappingTests.swift'), '-o', exe)
  abort 'Tests failed' unless system(exe)
end
