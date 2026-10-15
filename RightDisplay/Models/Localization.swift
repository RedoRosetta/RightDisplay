// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system: "跟随系统"
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var resolvedIdentifier: String {
        switch self {
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        case .system:
            Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
                ? "zh-Hans"
                : "en"
        }
    }

    var locale: Locale { Locale(identifier: resolvedIdentifier) }
}

enum AppLocalization {
    static let preferenceKey = "appLanguage"

    private static let localizedBundles: [String: Bundle] = {
        ["en", "zh-Hans"].reduce(into: [:]) { bundles, identifier in
            guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return }
            bundles[identifier] = bundle
        }
    }()

    static var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system
    }

    static var resolvedIdentifier: String { selectedLanguage.resolvedIdentifier }
    static var isEnglish: Bool { resolvedIdentifier == "en" }

    static func string(_ key: String) -> String {
        guard resolvedIdentifier == "en",
              let bundle = localizedBundles[resolvedIdentifier] else { return key }
        let value = bundle.localizedString(forKey: key, value: key, table: nil)
        return value == key ? englishFallback(key) : value
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: Locale(identifier: resolvedIdentifier),
            arguments: arguments
        )
    }

    private static func englishFallback(_ source: String) -> String {
        var result = source
        let replacements: [(String, String)] = [
            // Dynamic readback and EDID descriptions are assembled with live values.
            // Translate their fixed clauses before the shorter legacy fallback terms.
            ("已找到 ", "Found "),
            (" 台在线设备，保留 ", " online devices; retained "),
            (" 台已知设备", " known devices"),
            (" 默认音频输出", " default audio output"),
            ("系统 HDR 状态尚未同步", "The system HDR state has not synchronized yet"),
            ("触发原因：", "Trigger: "),
            ("无法切换显示模式（Core Graphics 错误 ", "Could not switch display mode (Core Graphics error "),
            ("自动测试 · ", "Automatic test · "),
            ("规则：", "Policy: "),
            (" 将保持分辨率、HiDPI、刷新率、VRR 与 HDR 状态不变。", " Resolution, HiDPI, refresh rate, VRR, and HDR will remain unchanged."),
            ("正在请求 WindowServer 重新协商", "requesting WindowServer renegotiation"),
            ("macOS 没有稳定采用目标组合；当前实际输出：", "macOS did not stably adopt the target combination; actual output: "),
            ("macOS 没有稳定采用所选设置。当前实际输出：", "macOS did not stably adopt the selected setting. Actual output: "),
            ("系统连续复读验证通过：", "Repeated system readback verified: "),
            ("操作已生效；系统联动调整为 ", "The change took effect; the system also adjusted to "),
            ("复读结果：", "Readback: "),
            ("按当前 ", "Based on the current "),
            ("未压缩需求超过链路有效载荷，因此推断 DSC 必须启用", "the uncompressed requirement exceeds the link payload, so DSC is inferred as necessary"),
            ("带宽不足以证明 DSC 已关闭", "bandwidth alone cannot prove that DSC is off"),
            ("原生分辨率匹配；这是面板标称色域，不是校色后的覆盖率实测", " native resolution match; this is the panel's nominal gamut, not measured post-calibration coverage"),
            ("的十亿色能力标示面板上限；macOS 没有公开当前内屏扫描输出位深", " billion-color capability indicates the panel limit; macOS does not expose the current built-in scan-out bit depth"),
            ("编码 ", "Encoding "),
            ("导出失败：", "Export failed: "),
            ("连接方式: ", "Connection type: "),
            ("字节 25–34，以 10 bit 定点数解析：", "Bytes 25–34, parsed as 10-bit fixed-point values: "),
            ("Right Display 尚未识别此扩展类型；区块校验状态：", "Right Display does not recognize this extension type yet; block checksum: "),
            ("EDID 声明的输入色深 ", "EDID-declared input bit depth "),
            ("这描述接收端能力，不等于当前链路实际输出色深", "This describes receiver capability, not the actual current link bit depth"),
            ("白/同步电平 ", "White/sync levels "),
            ("同步能力位 ", "sync capability bits "),
            ("白点", "white point"),
            ("基础块字节 ", "Base-block bytes "),
            ("描述符标签 ", "descriptor tag "),
            ("垂直刷新范围、水平扫描范围；最大像素时钟 ", "vertical refresh and horizontal scan ranges; maximum pixel clock "),
            ("后续字节定义额外时序公式", "Subsequent bytes define an additional timing formula"),
            ("原始内容已保留在十六进制视图", "the raw content is retained in hex view"),
            ("像素时钟 ", "Pixel clock "),
            ("总时序 ", "total timing "),
            ("详细时序从字节 ", "detailed timings begin at byte "),
            ("能力标志：", "capability flags: "),
            ("校验和 ", "checksum "),
            ("区块内字节 ", "block bytes "),
            ("最大码率 ", "maximum bit rate "),
            ("或格式相关值 ", "or format-dependent value "),
            (" 声道", " channels"),
            ("VIC 表示 CTA 标准电视时序；它描述接收端能力，不证明当前正在使用该模式", "VIC denotes a CTA standard TV timing; it describes receiver capability, not proof that this mode is currently in use"),
            ("厂商自定义能力数据；未套用未知厂商的私有位定义", "Vendor-defined capability data; unknown vendor-private bits were not interpreted"),
            ("这是接收端报告的声道位置能力，不代表 macOS 当前音频流", "These are receiver-reported speaker positions, not the current macOS audio stream"),
            ("原始负载：", "Raw payload: "),
            ("扫描：", "Scan: "),
            ("这里描述接收端对过扫描、欠扫描及量化范围选择的支持，不代表当前输出设置", "This describes receiver support for overscan, underscan, and quantization-range selection, not current output settings"),
            ("原始标志 ", "raw flags "),
            ("这是由 OUI 所属厂商定义的视频能力负载。未取得该厂商公开字段定义时仅展示身份与原始数据，不猜测私有位含义", "This video-capability payload is defined by the OUI vendor. Without public field definitions, only identity and raw data are shown; private bits are not guessed"),
            ("声明 xvYCC、sYCC、Adobe RGB、BT.2020、DCI-P3 等扩展颜色空间能力", "Declares extended color-space capabilities such as xvYCC, sYCC, Adobe RGB, BT.2020, and DCI-P3"),
            ("期望最大亮度代码 ", "desired maximum luminance code "),
            ("这里表示接收能力，不等于 HDR 当前已开启", "This indicates receiver capability, not that HDR is currently on"),
            (" 个优先级条目", " preference entries"),
            ("接收端对 SVD/DTD 的显示格式偏好", "Receiver display-format preferences for SVD/DTD"),
            ("原始值：", "Raw values: "),
            (" 个仅 4:2:0 模式", " 4:2:0-only modes"),
            ("这些时序只能使用 YCbCr 4:2:0", "These timings can use only YCbCr 4:2:0"),
            ("按位对应同一 CTA 扩展内视频数据块的 SVD，表示哪些模式也支持 4:2:0", "Bits map to SVDs in the same CTA extension's video data block and indicate which modes also support 4:2:0"),
            ("当前采用的公开标准资料中没有足够定义可可靠解释该标签。它可能是保留值、后续修订字段或厂商实现；Right Display 保留完整原始负载而不猜测含义", "Available public standards do not define this tag reliably enough. It may be reserved, revised, or vendor-specific; Right Display retains the full raw payload without guessing its meaning"),
            ("深色能力：", "deep-color capability: "),
            ("该上限是接收端能力，并非当前链路实测速率", "This limit describes receiver capability, not a measured current link rate"),
            ("检测到：", "detected: "),
            ("此数据块表明接收端具备相应 HDMI 能力，但不能单独证明当前使用 FRL、DSC 或具体 HDMI 协议版本", "This block indicates receiver HDMI capability, but alone cannot prove current use of FRL, DSC, or a specific HDMI protocol version"),
            ("有效负载 ", "payload "),
            ("音频格式代码 ", "audio format code "),
            ("外部接口确认为 HDMI；Apple 内部显示路径为 ", "The external interface is confirmed as HDMI; Apple's internal display path is "),
            ("内部 DisplayPort 链路不能证明外部 HDMI 当前采用 FRL 或 TMDS", "The internal DisplayPort link does not prove that external HDMI currently uses FRL or TMDS"),
            ("接口 ", "Interface "),
            ("H 前肩/同步/后肩 ", "H front porch/sync/back porch "),
            ("V 前肩/同步/后肩 ", "V front porch/sync/back porch "),
            ("图像尺寸 ", "image size "),
            ("来源字节偏移 ", "source byte offset "),
            ("标签 0x02；数据块集合位于字节 ", "Tag 0x02; the data-block collection spans bytes "),
            ("扩展标签 0x01", "Extended tag 0x01"),
            (" 开始", " starts"),
            ("标签 ", "Tag "),
            ("目标：", "Target: "),
            ("自动校正 · ", "Automatic correction · "),
            ("macOS 未接受显示器软插拔请求（IOKit ", "macOS did not accept the display soft-replug request (IOKit "),
            ("显示器 ", "Display "),
            ("按 ", "Based on "),
            ("原生分辨率匹配", "native resolution match"),
            ("与活动像素最低带宽计算，", "and the minimum active-pixel bandwidth, "),
            ("这不是接收端直接回报", "this is not a direct receiver report"),
            ("计算可在未压缩有效载荷内传输", "can fit within the uncompressed link payload"),
            ("输出 ", "Output "),
            (" · 界面 ", " · Interface "),
            ("读取当前显示输出模式的像素编码与量化范围字段", "Read the pixel-encoding and quantization-range fields from the current display output mode"),
            ("读取当前输出模式的像素编码与量化范围字段", "Read the pixel-encoding and quantization-range fields from the current output mode"),
            ("读取当前显示输出模式的活动链路索引", "Read the active-link index from the current display output mode"),
            ("直接读取系统设置中的高动态范围开关", "Read the High Dynamic Range switch directly from macOS settings"),
            ("读取当前模式的 VRR 标记；macOS 未公开最终 HDMI Forum VRR 数据包", "Read the current mode's VRR flag; macOS does not expose the final HDMI Forum VRR packet"),
            ("首个详细时序为首选", "First detailed timing is preferred"),
            ("未标记首选时序", "No preferred timing marked"),
            ("全部通过", "All Passed"),
            ("存在失败区块", "One or more blocks failed"),
            ("已读取完整 EDID", "Complete EDID read"),
            ("点击条目展开完整解释", "Click an item to expand the full explanation"),
            ("系统提供", "Provided by System"),
            ("基础块声明", "Declared by Base Block"),
            ("CTA 扬声器分配数据块", "CTA Speaker Allocation Data Block"),
            ("CTA HDR 静态元数据块", "CTA HDR Static Metadata Data Block"),
            ("CTA YCbCr 4:2:0 能力映射", "CTA YCbCr 4:2:0 Capability Map"),
            ("CTA 视频能力数据块", "CTA Video Capability Data Block"),
            ("CTA 视频数据块", "CTA Video Data Block"),
            ("CTA 音频数据块", "CTA Audio Data Block"),
            ("CTA 色度数据块", "CTA Colorimetry Data Block"),
            ("CTA 扩展标签数据块", "CTA Extended Tag Data Block"),
            ("CTA 厂商特定数据块", "CTA Vendor-Specific Data Block"),
            ("基础块详细时序", "Base Block Detailed Timing"),
            ("CTA‑861 详细时序", "CTA‑861 Detailed Timing"),
            ("显示器名称描述符", "Display Name Descriptor"),
            ("文本序列号描述符", "Text Serial Number Descriptor"),
            ("ASCII 文本描述符", "ASCII Text Descriptor"),
            ("基础块监视器描述符", "Base Block Monitor Descriptor"),
            ("文本描述符", "Text Descriptor"),
            ("HDMI Forum 厂商数据块", "HDMI Forum Vendor Data Block"),
            ("HDMI 厂商数据块", "HDMI Vendor Data Block"),
            ("个短视频描述符", "short video descriptors"),
            ("个短音频描述符", "short audio descriptors"),
            ("个原生 DTD", "native DTDs"),
            ("个映射位", "mapping bits"),
            ("量化与扫描行为", "Quantization and Scan Behavior"),
            ("物理地址", "Physical Address"),
            ("最大字符率", "Maximum Character Rate"),
            ("最大 TMDS", "Maximum TMDS"),
            ("扩展标签", "Extended Tag"),
            ("扩展区块", "Extension Block"),
            ("数据块", "Data Block"),
            ("修订版", "Revision"),
            ("版本", "Version"),
            ("前左/前右", "Front Left/Right"),
            ("低频效果", "Low-Frequency Effects"),
            ("前中", "Front Center"),
            ("后左/后右", "Rear Left/Right"),
            ("后中", "Rear Center"),
            ("传统 SDR", "Traditional SDR"),
            ("传统 HDR", "Traditional HDR"),
            ("个区块", "blocks"),
            (" 个", ""),
            ("字节", "bytes"),
            ("项", "items"),
            ("第 ", "Week "),
            (" 周", ""),
            (" 年", ""),
            ("离散时序", "Discrete timings"),
            ("连续频率", "Continuous frequency"),
            ("主动关闭", "Active Off"),
            ("待机", "Standby"),
            ("挂起", "Suspend"),
            ("未声明", "Not Declared"),
            ("通过", "Passed"),
            ("失败", "Failed"),
            ("未提供", "Not Provided"),
            ("数据不足", "Insufficient Data"),
            ("macOS 高动态范围设置", "macOS High Dynamic Range Setting"),
            ("高动态范围", "High Dynamic Range"),
            ("来源：", "Source: "),
            ("已连接", "Connected"),
            ("正在连接", "Connecting"),
            ("未连接", "Disconnected"),
            ("在线", "Online"),
            ("上次连接", "Last Connected"),
            ("内建显示器", "Built-in Display"),
            ("内建显示接口", "Built-in display interface"),
            ("当前外接接口", "Current external interface"),
            ("无法识别", "Unrecognized"),
            ("接口未验证", "Interface not verified"),
            ("不可验证", "Unavailable"),
            ("已验证", "Verified"),
            ("推断", "Inferred"),
            ("不可用", "Unavailable"),
            ("已启用", "Enabled"),
            ("未启用", "Disabled"),
            ("已开启", "On"),
            ("已关闭", "Off"),
            ("系统自动管理", "Managed by macOS"),
            ("系统复读确认", "System readback confirmed"),
            ("用户保留确认", "User confirmed"),
            ("验证失败", "Verification failed"),
            ("动态", "Dynamic"),
            ("英寸", "inches"),
            ("最高", "Up to"),
            ("当前", "Current"),
            ("未知", "Unknown"),
            ("是", "Yes"),
            ("否", "No")
        ]
        for (chinese, english) in replacements {
            result = result.replacingOccurrences(of: chinese, with: english)
        }
        result = result
            .replacingOccurrences(of: "；", with: "; ")
            .replacingOccurrences(of: "，", with: ", ")
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "（", with: " (")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "：", with: ": ")
            .replacingOccurrences(of: "、", with: ", ")
        return result
    }
}
