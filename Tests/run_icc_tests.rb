# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
require 'tmpdir'
root = File.expand_path('..', __dir__)
snapshot = File.read(File.join(root,'RightDisplay/Models/DisplaySnapshot.swift'))
registry = snapshot[snapshot.index('struct DisplayDeviceDescriptor:')...snapshot.index('struct TimingIdentity:')]
Dir.mktmpdir('rightdisplay-icc-tests-','/private/tmp') do |dir|
  model = File.join(dir,'ProductionDisplayIdentity.swift')
  File.write(model,"import Foundation\n"+registry)
  exe = File.join(dir,'icc-tests')
  abort 'Compile failed' unless system('xcrun','swiftc','-module-cache-path',File.join(dir,'ModuleCache'),File.join(root,'RightDisplay/Models/ICCProfile.swift'),model,File.join(__dir__,'ICCProfileTests.swift'),'-o',exe)
  abort 'Tests failed' unless system(exe)
end
