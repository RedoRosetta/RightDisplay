# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
require 'tmpdir'
root = File.expand_path('..',__dir__)
source = File.read(File.join(root,'RightDisplay/Views/ColorProfilesView.swift'))
geometry = source[source.index('struct ICCChartCoordinates {')...source.index('struct ICCXYPlot:')]
Dir.mktmpdir('rightdisplay-chart-','/private/tmp') do |dir|
  path = File.join(dir,'Geometry.swift');File.write(path,"import Foundation\nimport CoreGraphics\n"+geometry)
  exe = File.join(dir,'tests')
  abort 'Compile failed' unless system('xcrun','swiftc','-module-cache-path',File.join(dir,'ModuleCache'),File.join(root,'RightDisplay/Models/ICCProfile.swift'),path,File.join(__dir__,'ICCChartTests.swift'),'-o',exe)
  abort 'Tests failed' unless system(exe)
end
