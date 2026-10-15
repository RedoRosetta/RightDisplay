// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import SwiftUI
import ColorSync

struct ColorProfilesView: View {
    let display: DisplaySnapshot
    @EnvironmentObject private var store: DisplayStore
    @StateObject private var profiles = ColorProfileStore()
    @State private var reference: ICCReferenceGamut = .displayP3
    @State private var expandedSources: Set<ColorProfileInfo.Source> = [.device]
    @State private var pending: ColorProfileInfo?
    @State private var selectedInspection: ColorProfileInfo?
    private func l(_ zh: String, _ en: String) -> String { AppLocalization.isEnglish ? en : zh }
    private var contextKey: String { "\(display.deviceIdentity?.connectionInstanceKey ?? "unknown")|\(store.colorProfileGeneration)" }
    private var detailProfile: ColorProfileInfo? { selectedInspection ?? profiles.inspected ?? profiles.current }
    var body: some View {
        VStack(spacing:18) {
            currentCard
            if let profile = detailProfile {
                if profile.id != profiles.current?.id {
                    GlassCard(verticalPadding:10) {
                        HStack(spacing:12) {
                            Image(systemName:"doc.text.magnifyingglass")
                                .font(.system(size:13,weight:.semibold)).foregroundStyle(Color.accentColor)
                                .frame(width:30,height:30)
                                .background(Color.accentColor.opacity(0.06),in:RoundedRectangle(cornerRadius:9))
                            VStack(alignment:.leading,spacing:3) {
                                Text(l("正在检查","Inspecting")).font(.caption).foregroundStyle(.secondary)
                                Text(profile.name).font(.callout.weight(.medium)).lineLimit(2).textSelection(.enabled)
                            }
                            Spacer(minLength:12)
                            Button(l("返回当前描述文件","Return to current")) { selectedInspection = nil; profiles.clearInspection() }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
                ICCProfileCardLayout {
                    metadataCard(profile)
                    characteristicsCard(profile)
                }.frame(maxWidth:.infinity)
                ICCProfileCardLayout {
                    gamutCard(profile)
                    calibrationCard(profile)
                }.frame(maxWidth:.infinity)
            }
            availableCard
            if let error = profiles.lastError { Text(l("操作未完成；悬停查看具体原因。",error)).help(error).font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
        }
        .task(id:contextKey) { selectedInspection = nil; profiles.refresh(display:display,store:store) }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name(kColorSyncDisplayDeviceProfilesNotification!.takeUnretainedValue() as String))) { _ in profiles.refresh(display:display,store:store) }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name(kColorSyncProfileRepositoryChangeNotification!.takeUnretainedValue() as String))) { _ in profiles.refresh(display:display,store:store) }
        .onDisappear { profiles.cancel(store:store) }
        .alert(l("套用色彩描述文件","Apply color profile"),isPresented:Binding(get:{ pending != nil },set:{ if !$0 { pending = nil } })) {
            Button(l("取消","Cancel"),role:.cancel) { pending = nil }
            Button(l("套用","Apply")) { if let target = pending { profiles.apply(target,store:store) }; pending = nil }
        } message: {
            Text(l("为「\(display.name)」套用所选描述文件。系统回读一致后才确认已套用。","Apply to “\(display.name)”. Confirmation requires matching system readback.")+"\n"+(pending?.name ?? ""))
        }
    }
    private var currentCard: some View {
        GlassCard(title:l("当前描述文件","Current Profile"),icon:"paintpalette") {
            VStack(alignment:.leading,spacing:7) {
                Text(profiles.current?.name ?? l("当前使用状态不可用","Current association unavailable")).font(.title2.weight(.semibold))
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.center,spacing:16) {
                        currentSummary
                        Spacer(minLength:16)
                        currentActions
                    }
                    VStack(alignment:.leading,spacing:10) {
                        currentSummary
                        HStack { Spacer(minLength:0); currentActions }
                    }
                }
            }.help(l("系统使用的描述文件不是物理输出或实时测量。","System association is not physical output or live measurement."))
        }
    }
    private var currentSummary: some View {
        HStack(spacing:12) {
            if let p = profiles.current {
                Text("ICC \(p.metadata.version) · \(p.metadata.colorSpace) · \(p.metadata.pcs) \(l("连接空间","PCS"))").font(.callout).foregroundStyle(.secondary)
            }
            Text(associationStatus).help(profiles.status).font(.caption).foregroundStyle(.secondary)
        }.fixedSize(horizontal:true,vertical:false)
    }
    private var currentActions: some View {
        HStack(spacing:8) {
            if profiles.loading || profiles.busy { ProgressView().controlSize(.small) }
            Button(l("重新读取","Refresh")) { selectedInspection = nil; profiles.refresh(display:display,store:store) }.buttonStyle(CompactActionButtonStyle(primary:true)).disabled(profiles.busy)
            Button(l("打开／检查 ICC","Open / Inspect ICC")) { selectedInspection = nil; profiles.inspectFile(store:store) }.buttonStyle(CompactActionButtonStyle()).disabled(profiles.busy)
        }.fixedSize()
    }
    private func row(_ title: String, _ value: String?) -> some View {
        HStack(alignment:.top,spacing:12) { Text(fieldTitle(title)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).frame(width:105,alignment:.leading); Text(value ?? l("不可用","Unavailable")).monospacedDigit().textSelection(.enabled).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading) }.font(.callout).frame(minHeight:20,alignment:.topLeading).modifier(CardSubmenuInset())
    }
    private func metadataCard(_ p: ColorProfileInfo) -> some View {
        GlassCard(title:l("描述文件信息","Profile Information"),icon:"doc.text",fillsAvailableHeight:true) {
            VStack(alignment:.leading,spacing:8) {
                row("Created",p.metadata.creationDate?.formatted(date:.abbreviated,time:.shortened))
                row("Manufacturer",p.metadata.manufacturer)
                if let url = p.url {
                    HStack(alignment:.top,spacing:12) {
                        Text(l("文件位置","Location")).foregroundStyle(.secondary).frame(width:105,alignment:.leading)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                            Label(url.path, systemImage:"folder").lineLimit(2).truncationMode(.middle)
                        }.buttonStyle(.link).frame(maxWidth:.infinity,alignment:.leading).help(l("在 Finder 中显示文件","Reveal in Finder"))
                    }.font(.callout).modifier(CardSubmenuInset())
                } else { row("Location / source",l("ColorSync 数据；无可靠文件路径","ColorSync data; file path unavailable")) }
                row("Name",p.name); row("File",p.url?.lastPathComponent)
                row("Source",sourceName(p.source)); row("ICC version",p.metadata.version)
                row("Profile class",p.metadata.profileClass)
                row("Color space / PCS","\(p.metadata.colorSpace) / \(p.metadata.pcs)")
                row("Model",p.metadata.model); row("Copyright",p.metadata.copyright)
                row("ColorSync validation",p.colorSyncVerified ? l("结构验证通过","Structure verified") : l("不可用／验证未通过","Unavailable / validation failed"))
                Spacer(minLength:0)
                if !p.metadata.issues.isEmpty { Text(l("部分标签不可用（\(p.metadata.issues.count) 项）；悬停查看原始诊断。",p.metadata.issues.joined(separator:"\n"))).help(p.metadata.issues.joined(separator:"\n")).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func xy(_ value: ICCXYZ?) -> String? {
        guard let value, let point = ICCDeclaredChromaticity.coordinates(value) else { return nil }
        let text = String(format:"x %.5f · y %.5f",point.x,point.y)
        return point.isValid ? text : text + l("（超出绘图范围）"," (outside plot range)")
    }
    private func characteristicsCard(_ p: ColorProfileInfo) -> some View {
        GlassCard(title:l("色彩特性","Color Characteristics"),icon:"circle.lefthalf.filled",fillsAvailableHeight:true) {
            VStack(alignment:.leading,spacing:8) {
                row("Profile White Point",xy(p.metadata.white))
                ForEach(0..<3,id:\.self) { i in row(["Red colorant xy","Green colorant xy","Blue colorant xy"][i],xy(p.metadata.colorants[i])) }
                Spacer(minLength:8)
                row("Matrix profile",p.metadata.isMatrix ? l("RGB 矩阵与色调曲线","RGB matrix/TRC") : l("不可用／查找表或矩阵不完整","Unavailable / LUT or incomplete matrix"))
                if p.metadata.colorants.allSatisfy({ $0 != nil }) {
                    VStack(alignment:.leading,spacing:8) {
                        Text(fieldTitle("RGB → PCS matrix")).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        Grid(alignment:.trailing,horizontalSpacing:10,verticalSpacing:7) {
                            ForEach(0..<3,id:\.self) { i in
                                GridRow {
                                    ForEach(0..<3,id:\.self) { j in
                                        let c = p.metadata.colorants[j]!
                                        Text(String(format:"%.5f",[c.x,c.y,c.z][i])).monospaced().textSelection(.enabled).frame(maxWidth:.infinity,alignment:.trailing)
                                    }
                                }
                            }
                        }
                    }.font(.callout).modifier(CardSubmenuInset())

                }
                Spacer(minLength:8)
                ForEach(0..<3,id:\.self) { i in
                    row(["Red TRC","Green TRC","Blue TRC"][i],trcText(p.metadata.trcs[i]))
                    if case .parametric(_,let parameters) = p.metadata.trcs[i] { row("Parameters",parameters.map { String(format:"%.5g",$0) }.joined(separator:", ")) }
                }
            }.frame(maxHeight:.infinity,alignment:.topLeading)
        }
    }
    private func gamutCard(_ p: ColorProfileInfo) -> some View {
        GlassCard(title:l("色域","Gamut"),subtitle:l("CIE 1931 xy · 描述文件模型","CIE 1931 xy · Profile model"),icon:"triangle",fillsAvailableHeight:true) {
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:10) {
                    Text(l("参考色域","Reference")).font(RightDisplayUI.rowLabel)
                    NativeSelectionPicker(
                        options:ICCReferenceGamut.allCases.map { .init(id:$0.rawValue,title:$0.rawValue) },
                        selectedID:reference.rawValue,fallbackTitle:reference.rawValue,prominent:true
                    ) { id in if let gamut = ICCReferenceGamut(rawValue:id) { reference = gamut } }
                    .frame(width:166,height:30)
                    .accessibilityLabel(l("参考色域","Reference gamut")).accessibilityValue(reference.rawValue)
                }.modifier(CardSubmenuInset()).frame(height:44,alignment:.topLeading)
                if let triangle = p.metadata.gamut {
                    if p.metadata.chad != nil {
                        ICCXYPlot(profile:triangle,white:p.metadata.gamutWhite,reference:reference.primaries).frame(height:330)
                        Text(l("● 描述文件色域   ┄ 参考色域 · D65","● Profile gamut   ┄ Reference gamut · D65")).font(.caption)
                    } else {
                        HStack {
                            VStack { ICCXYPlot(profile:triangle,white:p.metadata.gamutWhite,reference:nil); Text(l("描述文件标签 xy","Profile tag xy")).font(.caption) }
                            VStack { ICCXYPlot(profile:nil,white:ICCReferenceGamut.white,reference:reference.primaries); Text(l("参考色域 xy · D65","Reference xy · D65")).font(.caption) }
                        }.frame(height:330)
                    }
                } else {
                    ICCXYPlot(profile:nil,white:ICCReferenceGamut.white,reference:reference.primaries).frame(height:330)
                }
                Spacer(minLength:0)
                Text(gamutExplanation(p)).font(.caption).foregroundStyle(.secondary).frame(minHeight:44,alignment:.topLeading)
            }
        }
    }
    private func calibrationCard(_ p: ColorProfileInfo) -> some View {
        GlassCard(title:l("校准曲线","Calibration Curves"),subtitle:l("VCGT · 描述文件内的校准信息","VCGT · stored calibration information"),icon:"waveform.path",fillsAvailableHeight:true) {
            VStack(alignment:.leading,spacing:12) {
                VStack(alignment:.leading,spacing:9) {
                    row("VCGT",p.metadata.vcgt == nil ? l("无","Absent") : l("有","Present"))
                    if let vcgt = p.metadata.vcgt { row("Curve information",vcgtText(vcgt)) }
                }.frame(height:44,alignment:.topLeading)
                if let vcgt = p.metadata.vcgt, !vcgt.curves.isEmpty {
                    ICCCalibrationPlot(curves:vcgt.curves).frame(height:330)
                } else {
                    Text(p.metadata.vcgt == nil ? l("描述文件未包含校准曲线","No calibration curves in this profile") : l("校准曲线暂不可绘制","Calibration curves unavailable for plotting"))
                        .font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity).frame(height:330)
                }
                Spacer(minLength:0)
                Text(l("这些是描述文件内存储的校准曲线，不证明当前图形处理器已应用校准查找表；不是色域或物理测量。","Calibration curves stored in the profile do not prove a currently applied GPU LUT; not gamut or physical measurement.")).font(.caption).foregroundStyle(.secondary).frame(minHeight:44,alignment:.topLeading)
            }
        }
    }
    private func gamutExplanation(_ profile: ColorProfileInfo) -> String {
        let context: String
        if profile.metadata.gamut == nil { context = gamutLimitation(profile.metadata) }
        else if profile.metadata.chad == nil {
            context = l("缺少可靠的色适应矩阵，原始适应基准不可确认；分图显示，不叠加或计算覆盖率。","No reliable chad: source adaptation basis unavailable. Separate plots; no overlay or coverage claim.")
        } else { context = l("已按适应矩阵还原描述文件源色度。","Inverse chad restores profile source chromaticity.") }
        return context + " " + l("二维色度图不表示色域体积、覆盖率或显示器实测能力。","Two-dimensional chromaticity does not represent gamut volume, coverage or measured display capability.")
    }
    private func gamutLimitation(_ metadata: ICCProfileMetadata) -> String {
        if AppLocalization.isEnglish { return "Simple RGB triangle unavailable; reference only. Profile metadata remains available." }
        if metadata.hasLUT { return "查找表型描述文件不适用于简单 RGB 三角形表示；仅显示参考色域。" }
        if metadata.white == nil || metadata.colorants.contains(where:{ $0 == nil }) { return "白点或原色标签缺失；不能绘制完整三角形，仅显示参考色域。" }
        if metadata.colorants.compactMap({ $0 }).contains(where:{ $0.xy == nil }) { return "原色 XYZ 标签存在，但转换后的 xy 超出简单三角形绘图范围；仅显示参考色域。" }
        return "色适应矩阵或色调曲线暂不适用于简单三角形表示；仅显示参考色域。"
    }
    private var associationStatus: String {
        if AppLocalization.isEnglish { return profiles.status.replacingOccurrences(of: "MACOS_PROFILE_ASSOCIATION · ", with: "macOS profile association · ") }
        if profiles.busy { return "正在套用并等待系统回读" }
        if profiles.status.contains("UNCONFIRMED") { return "未确认；系统回读未一致或上下文已变化" }
        if profiles.status.contains("CONFIRMED") { return "macOS 已确认套用" }
        if profiles.status.contains("FAILED") { return "套用失败" }
        return profiles.current != nil ? "macOS 当前使用" : "当前使用状态不可用"
    }
    private func sourceName(_ source: ColorProfileInfo.Source) -> String {
        switch source {
        case .system: return l("系统提供","System")
        case .device: return l("设备关联","Device-associated")
        case .user: return l("用户提供","User")
        case .other: return l("其他／未知","Other / Unknown")
        case .opened: return l("已打开文件；未安装","Opened file; not installed")
        }
    }
    private func fieldTitle(_ title: String) -> String {
        guard !AppLocalization.isEnglish else { return title }
        return ["Name":"名称","File":"文件名","Location / source":"文件位置", "Source":"来源","ICC version":"ICC 版本","Profile class":"描述文件类别","Color space / PCS":"色彩／连接空间","Created":"创建日期","Manufacturer":"制造商标识","Model":"型号标识","Copyright":"版权","ColorSync validation":"ColorSync 验证","Profile White Point":"描述文件白点","Red colorant xy":"红色色度 xy","Green colorant xy":"绿色色度 xy","Blue colorant xy":"蓝色色度 xy","Matrix profile":"矩阵类型","RGB → PCS matrix":"RGB → 连接空间矩阵","Red TRC":"红色色调曲线","Green TRC":"绿色色调曲线","Blue TRC":"蓝色色调曲线","Parameters":"参数","Curve information":"曲线信息"][title] ?? title
    }
    private func trcText(_ curve: ICCTRC?) -> String? {
        guard let curve else { return nil }
        if AppLocalization.isEnglish { return curve.summary }
        switch curve {
        case .gamma(let g): return String(format:"伽马 %.4g",g)
        case .parametric(let type,let parameters): return "参数曲线类型 \(type) · \(parameters.count) 个参数"
        case .sampled(let values): return "采样曲线 · \(values.count) 个样本"
        case .unsupported: return "不可用／暂不支持此曲线"
        }
    }
    private func vcgtText(_ curve: ICCVCGT) -> String {
        if AppLocalization.isEnglish { return curve.summary }
        switch curve {
        case .table(let values,let bits): return "\(values.count) 通道 · \(values.first?.count ?? 0) 个样本 · \(bits) 位"
        case .formula(let values): return "\(values.count) 通道 · 伽马／最小／最大值公式"
        case .unsupported: return "存在，但暂不支持解析"
        }
    }
    private var availableCard: some View {
        GlassCard(title:l("可用描述文件","Available Profiles"),icon:"list.bullet.rectangle") {
            VStack(alignment:.leading,spacing:10) {
                ForEach([ColorProfileInfo.Source.system,.device,.user,.other],id: \.self) { source in
                    let items = profiles.profiles.filter { $0.source == source }
                    VStack(spacing:0) {
                        Button {
                            if expandedSources.contains(source) { expandedSources.remove(source) } else { expandedSources.insert(source) }
                        } label: {
                            HStack(spacing:12) {
                                Image(systemName:source == .system ? "desktopcomputer" : source == .device ? "display" : source == .user ? "person.crop.circle" : "folder")
                                    .foregroundStyle(Color.accentColor).frame(width:30,height:30)
                                    .background(Color.accentColor.opacity(0.06),in:RoundedRectangle(cornerRadius:9))
                                VStack(alignment:.leading,spacing:4) {
                                    Text(sourceName(source)).font(.callout.weight(.semibold))
                                    Text(l("\(items.count) 个描述文件","\(items.count) profiles")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName:expandedSources.contains(source) ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }.modifier(CardSubmenuInset()).padding(.vertical,14).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityValue(expandedSources.contains(source) ? l("已展开","Expanded") : l("已折叠","Collapsed"))
                        if expandedSources.contains(source) {
                            ScrollView {
                              LazyVStack(spacing:0) {
                            ForEach(items) { p in
                                Divider()
                                HStack(spacing:12) {
                                    Image(systemName:"doc.richtext").foregroundStyle(.secondary).frame(width:30)
                                    VStack(alignment:.leading,spacing:5) {
                                        Text(p.name).font(.callout.weight(.medium)).lineLimit(2)
                                        Text("\(p.metadata.colorSpace) · ICC \(p.metadata.version)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength:8)
                                    if profiles.current?.identity == p.identity {
                                        HStack(spacing:6) {
                                            Circle().fill(Color.green).frame(width:7,height:7)
                                            Text(l("当前配置","Current profile")).font(.callout.weight(.medium))
                                        }.fixedSize().accessibilityElement(children:.combine)
                                    }
                                    Button(l("检查","Inspect")) { selectedInspection = p }
                                        .buttonStyle(CompactActionButtonStyle(primary:true)).fixedSize()
                                    Button(l("套用","Apply")) { pending = p }
                                        .buttonStyle(CompactActionButtonStyle()).fixedSize().disabled(profiles.busy || !p.switchEligible || profiles.current?.identity == p.identity)
                                }.frame(height:68).padding(.leading,2 * RightDisplayUI.submenuIndent)
                            }
                              }
                            }.frame(height:CGFloat(min(4,items.count))*69)
                            if items.isEmpty { Text(l("暂无描述文件","No profiles")).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,12).padding(.leading,42) }
                        }
                    }
                    if source != .other { Divider() }
                }
            }
        }
    }
}
struct ICCProfileCardLayout: Layout {
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) -> CGSize {
        let width = proposal.width ?? 680
        let columns = ICCCardArrangement.columns(width:width)
        let cellWidth = columns == 2 ? (width-18)/2 : width
        let heights = subviews.map { $0.sizeThatFits(.init(width:cellWidth,height:nil)).height }
        return CGSize(width:width,height:columns == 2 ? (heights.max() ?? 0) : heights.reduce(0,+)+CGFloat(max(0,heights.count-1))*18)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let columns = ICCCardArrangement.columns(width:bounds.width)
        let width = columns == 2 ? (bounds.width-18)/2 : bounds.width
        var y = bounds.minY
        for (index,view) in subviews.enumerated() {
            view.place(at:CGPoint(x:bounds.minX+(columns == 2 ? CGFloat(index)*(width+18) : 0),y:y),anchor:.topLeading,proposal:.init(width:width,height:columns == 2 ? bounds.height : nil))
            if columns == 1 { y += view.sizeThatFits(.init(width:width,height:nil)).height+18 }
        }
    }
}
struct ICCChartTooltip<Content:View>: View {
    let cursor:CGPoint
    let container:CGSize
    @ViewBuilder let content:Content
    @State private var measured = CGSize(width:160,height:80)
    var body:some View {
        let origin = ICCChartCoordinates.tooltipOrigin(cursor:cursor,container:container,tooltip:measured)
        content.padding(8).frame(maxWidth:max(1,container.width-8),alignment:.leading)
            .fixedSize(horizontal:true,vertical:true)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:7))
            .onGeometryChange(for:CGSize.self) { $0.size } action: { if measured != $0 { measured = $0 } }
            .position(x:origin.x+measured.width/2,y:origin.y+measured.height/2)
            .allowsHitTesting(false)
    }
}
// Presentation geometry only; never participates in profile/timing identity.
struct ICCChartCoordinates {
    let box: CGRect
    let xMaximum: Double
    let yMaximum: Double
    init(size: CGSize, xMaximum: Double = 1, yMaximum: Double = 1, preserveAspect: Bool = false) {
        let width = max(1,size.width-78), height = max(1,size.height-70)
        let scale = min(width/xMaximum,height/yMaximum)
        let plotWidth = preserveAspect ? scale*xMaximum : width
        let plotHeight = preserveAspect ? scale*yMaximum : height
        box = CGRect(x:58+(width-plotWidth)/2,y:18,width:plotWidth,height:plotHeight)
        self.xMaximum = xMaximum; self.yMaximum = yMaximum
    }
    func point(x:Double,y:Double) -> CGPoint {
        CGPoint(x:box.minX+x/xMaximum*box.width,y:box.maxY-y/yMaximum*box.height)
    }
    func value(at point:CGPoint) -> ICCXY? {
        guard box.contains(point) else { return nil }
        return ICCXY(x:Double((point.x-box.minX)/box.width)*xMaximum,y:Double((box.maxY-point.y)/box.height)*yMaximum)
    }
    static func tooltipOrigin(cursor:CGPoint,container:CGSize,tooltip:CGSize) -> CGPoint {
        let gap:CGFloat = 14, margin:CGFloat = 4
        let x = cursor.x+gap+tooltip.width <= container.width-margin ? cursor.x+gap : cursor.x-gap-tooltip.width
        let y = cursor.y+gap+tooltip.height <= container.height-margin ? cursor.y+gap : cursor.y-gap-tooltip.height
        return CGPoint(x:max(margin,min(x,container.width-tooltip.width-margin)),y:max(margin,min(y,container.height-tooltip.height-margin)))
    }
    static func interpolate(_ samples:[Double], input:Double) -> Double? {
        guard !samples.isEmpty, input.isFinite, (0...1).contains(input) else { return nil }
        let index = input*Double(samples.count-1), low = Int(index), high = min(low+1,samples.count-1)
        return samples[low]+(samples[high]-samples[low])*(index-Double(low))
    }
}
struct ICCCardArrangement {
    static func columns(width:CGFloat) -> Int { width >= 680 ? 2 : 1 }
}
struct ICCDeclaredChromaticity {
    static func coordinates(_ value:ICCXYZ) -> ICCXY? {
        let sum = value.x+value.y+value.z
        guard sum.isFinite, sum > 0 else { return nil }
        let xy = ICCXY(x:value.x/sum,y:value.y/sum)
        return xy.x.isFinite && xy.y.isFinite ? xy : nil
    }
}
// Bound hover publications without a timer or delayed work after disappearance.
// The static drawing is a separate equatable subtree; hover updates only the readout.
// Mouse events schedule one cancellable reveal; moving does not publish coordinates.
final class ICCChartInspection: ObservableObject {
    @Published private(set) var location: CGPoint?
    private var pending: DispatchWorkItem?
    private var latest: CGPoint?
    private var generation: UInt64 = 0
    static let dwell: TimeInterval = 0.35

    func moved(_ point: CGPoint?) {
        guard latest != point else { return }
        latest = point
        generation &+= 1
        pending?.cancel(); pending = nil
        if location != nil { location = nil }
        guard let point else { return }
        let token = generation
        let reveal = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.latest == point else { return }
            self.pending = nil
            self.location = point
        }
        pending = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: reveal)
    }
    func clicked(_ point: CGPoint) {
        generation &+= 1
        pending?.cancel(); pending = nil
        latest = point
        if location != point { location = point }
    }
    func cancel() { moved(nil) }
    deinit { pending?.cancel() }
}

private struct ICCInspectionInteraction: ViewModifier {
    @ObservedObject var inspection: ICCChartInspection
    func body(content: Content) -> some View {
        content.contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): inspection.moved(point)
                case .ended: inspection.cancel()
                }
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { inspection.clicked($0.location) })
            .onDisappear { inspection.cancel() }
    }
}

struct ICCChartHoverGate {
    private(set) var location: CGPoint?
    private var lastAcceptedTime: TimeInterval = -.infinity
    static let interval: TimeInterval = 1.0 / 30.0
    mutating func update(_ proposed: CGPoint?, now: TimeInterval) -> Bool {
        guard proposed != location else { return false }
        guard let proposed else {
            location = nil; lastAcceptedTime = -.infinity; return true
        }
        guard location == nil || now - lastAcceptedTime >= Self.interval else { return false }
        location = proposed; lastAcceptedTime = now; return true
    }
}
struct ICCXYPlot: View {
    let profile: [ICCXY]?, white: ICCXY?, reference: [ICCXY]?
    @StateObject private var inspection = ICCChartInspection()
    private var hover: CGPoint? { inspection.location }
    private var english: Bool { AppLocalization.isEnglish }
    var body: some View {
        GeometryReader { proxy in
            let axes = ICCChartCoordinates(size:proxy.size,xMaximum:0.8,yMaximum:0.9,preserveAspect:true)
            ICCXYDrawing(size:proxy.size,profile:profile,white:white,reference:reference,english:english).equatable()
.modifier(ICCInspectionInteraction(inspection: inspection))
            .overlay(alignment:.topLeading) {
                if let hover, let xy = axes.value(at:hover) {
                    ICCChartTooltip(cursor:hover,container:proxy.size) {
                    VStack(alignment:.leading,spacing:3) {
                        Text(String(format:"x %.4f · y %.4f",xy.x,xy.y))
                        if let label = nearbyLabel(hover,axes:axes) { Text(label) }
                    }.font(.caption2.monospacedDigit())
                    }
                }
            }
        }.help(english ? "x = X/(X+Y+Z), y = Y/(X+Y+Z): normalized chromaticity, not luminance." : "x = X/(X+Y+Z)，y = Y/(X+Y+Z)：归一化色度坐标，不表示亮度。")
        .accessibilityLabel(english ? "CIE 1931 xy profile and reference coordinates" : "CIE 1931 xy 描述文件与参考色域坐标")
    }
    private func nearbyLabel(_ location:CGPoint,axes:ICCChartCoordinates) -> String? {
        var points: [(ICCXY,String)] = []
        for (index,p) in (profile ?? []).enumerated() { points.append((p,(english ? "Profile " : "描述文件 ")+["R","G","B"][index % 3])) }
        for (index,p) in (reference ?? []).enumerated() { points.append((p,(english ? "Reference " : "参考色域 ")+["R","G","B"][index % 3])) }
        if let white { points.append((white,english ? "White point" : "白点")) }
        let close = points.min { a,b in
            let p = axes.point(x:a.0.x,y:a.0.y),q = axes.point(x:b.0.x,y:b.0.y)
            return hypot(p.x-location.x,p.y-location.y) < hypot(q.x-location.x,q.y-location.y)
        }
        guard let close else { return nil };let p = axes.point(x:close.0.x,y:close.0.y)
        return hypot(p.x-location.x,p.y-location.y) <= 12 ? close.1+String(format:" · %.4f, %.4f",close.0.x,close.0.y) : nil
    }
}
struct ICCCalibrationPlot: View {
    let curves: [[Double]]
    @StateObject private var inspection = ICCChartInspection()
    private var hover: CGPoint? { inspection.location }
    private var english: Bool { AppLocalization.isEnglish }
    var body: some View {
        GeometryReader { proxy in
            let axes = ICCChartCoordinates(size:proxy.size)
            ICCCalibrationDrawing(size:proxy.size,curves:curves,english:english).equatable()
.modifier(ICCInspectionInteraction(inspection: inspection))
            .overlay(alignment:.topLeading) {
                if let hover, let value = axes.value(at:hover) {
                    ICCChartTooltip(cursor:hover,container:proxy.size) {
                    VStack(alignment:.leading,spacing:3) {
                        Text(String(format:english ? "Input %.4f" : "输入 %.4f",value.x))
                        ForEach(curves.indices,id: \.self) { index in
                            if let y = ICCChartCoordinates.interpolate(curves[index],input:value.x) {
                                Text(String(format:"%@ %.4f",curves.count == 1 ? (english ? "Output" : "输出") : ["R","G","B"][index % 3],y))
                            }
                        }
                        Text(english ? "Stored curve · linear interpolation" : "存储曲线 · 线性插值").foregroundStyle(.secondary)
                    }.font(.caption2.monospacedDigit())
                    }
                }
            }
        }.accessibilityLabel(english ? "VCGT calibration: input and output normalized to 0–1" : "VCGT 校准曲线：输入与输出均归一化至 0–1")
    }
}

struct ICCXYDrawing: View, Equatable {
    let size: CGSize
    let profile: [ICCXY]?, white: ICCXY?, reference: [ICCXY]?
    let english: Bool
    var body: some View {
        let axes = ICCChartCoordinates(size:size,xMaximum:0.8,yMaximum:0.9,preserveAspect:true)
            Canvas { context,size in
                func point(_ xy:ICCXY) -> CGPoint { axes.point(x:xy.x,y:xy.y) }
                var grid = Path()
                for i in 0...8 {
                    let x = Double(i)/10
                    grid.move(to:axes.point(x:x,y:0));grid.addLine(to:axes.point(x:x,y:0.9))
                    context.draw(Text(String(format:"%.1f",x)).font(.system(size:9)).foregroundColor(.secondary),at:CGPoint(x:axes.point(x:x,y:0).x,y:axes.box.maxY+13))
                }
                for i in 0...9 {
                    let y = Double(i)/10
                    grid.move(to:axes.point(x:0,y:y));grid.addLine(to:axes.point(x:0.8,y:y))
                    context.draw(Text(String(format:"%.1f",y)).font(.system(size:9)).foregroundColor(.secondary),at:CGPoint(x:axes.box.minX-16,y:axes.point(x:0,y:y).y))
                }
                context.stroke(grid,with:.color(.secondary.opacity(0.15)),lineWidth:0.5)
                func polygon(_ points:[ICCXY]) -> Path { Path { p in guard let first = points.first else { return };p.move(to:point(first));for xy in points.dropFirst() { p.addLine(to:point(xy)) };p.closeSubpath() } }
                if let reference { context.stroke(polygon(reference),with:.color(.secondary),style:StrokeStyle(lineWidth:1.5,dash:[5,4])) }
                if let profile { context.fill(polygon(profile),with:.color(.accentColor.opacity(0.12)));context.stroke(polygon(profile),with:.color(.accentColor),lineWidth:2) }
                if let white { let p = point(white);context.fill(Path(ellipseIn:CGRect(x:p.x-3,y:p.y-3,width:6,height:6)),with:.color(.primary)) }
                context.draw(Text(english ? "Chromaticity x" : "色度 x").font(.system(size:10)),at:CGPoint(x:axes.box.midX,y:axes.box.maxY+35))
                var vertical = context
                vertical.translateBy(x:axes.box.minX-43,y:axes.box.midY);vertical.rotate(by:.degrees(-90))
                vertical.draw(Text(english ? "Chromaticity y" : "色度 y").font(.system(size:10)),at:.zero)
            }
    }
}
struct ICCCalibrationDrawing: View, Equatable {
    let size: CGSize
    let curves: [[Double]]
    let english: Bool
    var body: some View {
        let axes = ICCChartCoordinates(size:size)
            Canvas { context,size in
                let colors: [Color] = [.red,.green,.blue]
                var grid = Path()
                for step in 0...4 {
                    let value = Double(step)/4
                    grid.move(to:axes.point(x:value,y:0));grid.addLine(to:axes.point(x:value,y:1))
                    grid.move(to:axes.point(x:0,y:value));grid.addLine(to:axes.point(x:1,y:value))
                    context.draw(Text(String(format:"%.2g",value)).font(.system(size:9)).foregroundColor(.secondary),at:CGPoint(x:axes.point(x:value,y:0).x,y:axes.box.maxY+13))
                    context.draw(Text(String(format:"%.2g",value)).font(.system(size:9)).foregroundColor(.secondary),at:CGPoint(x:axes.box.minX-16,y:axes.point(x:0,y:value).y))
                }
                context.stroke(grid,with:.color(.secondary.opacity(0.15)),lineWidth:0.5)
                for (channel,values) in curves.enumerated() where values.count > 1 {
                    var path = Path()
                    for (i,y) in values.enumerated() { let p = axes.point(x:Double(i)/Double(values.count-1),y:y);if i == 0 { path.move(to:p) } else { path.addLine(to:p) } }
                    context.stroke(path,with:.color(curves.count == 1 ? .primary : colors[channel % 3]),lineWidth:1.5)
                }
                context.draw(Text(english ? "Input (0–1)" : "输入值（0–1）").font(.system(size:10)),at:CGPoint(x:axes.box.midX,y:axes.box.maxY+35))
                var vertical = context
                vertical.translateBy(x:axes.box.minX-43,y:axes.box.midY);vertical.rotate(by:.degrees(-90))
                vertical.draw(Text(english ? "Calibration output (0–1)" : "校准输出值（0–1）").font(.system(size:10)),at:.zero)
            }
    }
}
