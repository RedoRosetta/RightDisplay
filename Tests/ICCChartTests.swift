// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation
import CoreGraphics
@main struct ChartTests {
    static func main() {
        var count = 0
        func check(_ value:Bool,_ text:String) { count += 1;precondition(value,text) }
        for size in [CGSize(width:260,height:280),CGSize(width:420,height:280),CGSize(width:420,height:210)] {
            let chart = ICCChartCoordinates(size:size,xMaximum:0.8,yMaximum:0.9,preserveAspect:true)
            check(abs(chart.box.width/0.8-chart.box.height/0.9)<1e-8,"CIE xy aspect distorted")
            check(chart.box.minX >= 58 && size.height-chart.box.maxY >= 52,"Axis label margins lost")
            let p = chart.point(x:0.3127,y:0.329)
            let xy = chart.value(at:p)!
            check(abs(xy.x-0.3127)<1e-8 && abs(xy.y-0.329)<1e-8,"Hover coordinates incorrect")
            check(chart.value(at:.zero) == nil,"Outside plot reports fictitious coordinates")
        }
        let plot = ICCChartCoordinates(size:CGSize(width:400,height:220))
        check(plot.value(at:plot.point(x:0.5,y:0.5)) == ICCXY(x:0.5,y:0.5),"Calibration normalized readout wrong")
        check(ICCChartCoordinates.interpolate([0,0.25,1],input:0.75) == 0.625,"Curve interpolation incorrect")
        check(ICCChartCoordinates.interpolate([0,1],input:1) == 1,"Last sample unavailable")
        check(ICCChartCoordinates.interpolate([],input:0.5) == nil,"Empty curve fabricated")
        check(ICCChartCoordinates.interpolate([0,1],input:.nan) == nil,"Nonfinite pointer input accepted")
        check(ICCCardArrangement.columns(width:900) == 2 && ICCCardArrangement.columns(width:580) == 1,"Wide/narrow card arrangement incorrect")
        let size = CGSize(width:420,height:260), tip = CGSize(width:180,height:90)
        for cursor in [CGPoint(x:50,y:40),CGPoint(x:410,y:250),CGPoint(x:410,y:30),CGPoint(x:40,y:250)] {
            let p = ICCChartCoordinates.tooltipOrigin(cursor:cursor,container:size,tooltip:tip)
            check(p.x >= 4 && p.y >= 4 && p.x+tip.width <= size.width-4 && p.y+tip.height <= size.height-4,"Tooltip escaped chart boundary")
        }
        let first = ICCChartCoordinates.tooltipOrigin(cursor:CGPoint(x:40,y:40),container:size,tooltip:tip)
        let next = ICCChartCoordinates.tooltipOrigin(cursor:CGPoint(x:60,y:60),container:size,tooltip:tip)
        check(next.x-first.x == 20 && next.y-first.y == 20,"Tooltip does not follow cursor")
        let raw = ICCDeclaredChromaticity.coordinates(.init(x:0.67348,y:0.27904,z:-0.00194))
        check(raw != nil && raw!.x.isFinite && !raw!.isValid,"Existing XYZ data hidden as unavailable")
        check(ICCDeclaredChromaticity.coordinates(.init(x:0,y:0,z:0)) == nil,"Undefined normalization fabricated")
        print("ICC chart presentation: \(count) assertions PASS")
    }
}
