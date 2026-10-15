# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
require 'tmpdir'
root = File.expand_path('..', __dir__)
source = File.read(File.join(root,'RightDisplay/Services/ColorProfileStore.swift'))
info = source[source.index('struct ColorProfileInfo:')...source.index('// Public APIs only.')]
store = source[source.index('@MainActor')..]
snapshot = File.read(File.join(root,'RightDisplay/Models/DisplaySnapshot.swift'))
registry = snapshot[snapshot.index('struct DisplayDeviceDescriptor:')...snapshot.index('struct TimingIdentity:')]
fixtures = File.read(File.join(__dir__,'ICCProfileTests.swift')).split('@main struct ICCProfileTests').first
Dir.mktmpdir('rightdisplay-icc-association-','/private/tmp') do |dir|
  production = File.join(dir,'ProductionStore.swift')
  File.write(production,"import AppKit\nimport Combine\nimport UniformTypeIdentifiers\n"+info+registry+File.read(File.join(__dir__,'ICCProfileAssociationStubs.swift'))+store)
  tests = File.join(dir,'Tests.swift')
  File.write(tests, fixtures+File.read(File.join(__dir__,'ICCProfileAssociationTests.swift')))
  exe = File.join(dir,'tests')
  abort 'Compile failed' unless system('xcrun','swiftc','-module-cache-path',File.join(dir,'ModuleCache'),File.join(root,'RightDisplay/Models/ICCProfile.swift'),production,tests,'-o',exe)
  abort 'Tests failed' unless system(exe)
end
