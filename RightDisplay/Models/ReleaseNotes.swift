// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import Foundation

struct ReleaseNote: Identifiable {
    let id: String
    let version: String
    let title: String
    let changes: [String]
}

enum RightDisplayReleaseHistory {
    static let currentVersion: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未提供"
        return version
    }()

    static let notes: [ReleaseNote] = [
        ReleaseNote(id:"release10",version:"1.0",title:"RightDisplay 1.0",changes:[
            "App 内 SRC 缓冲按会话规格准备，修正大 I/O 消费窗口。",
            "保留目标返回恢复与手动停止行为；虚拟音量采用固定灰色说明。",
            "RNSL 1.0 非商业源码许可；独立发行包采用 Ad-hoc 签名，未经 Apple 公证。"
        ]),
        ReleaseNote(id:"beta04",version:"0.4 Beta",title:"显示诊断、虚拟音频与界面完善",changes:[
            "新增虚拟音频转发与软件音量控制，支持保存目标设备、自动启动及异常中断后的恢复操作。",
            "新增 ICC 描述文件检查、色域与校准曲线展示，以及描述文件管理。",
            "完善 EDID 能力解析、显示链路测试与诊断报告，区分系统报告、推断和未验证状态。",
            "统一快捷面板与高级设置的布局、状态提示和控件样式，优化交互更新。"
        ]),
        ReleaseNote(id:"beta03",version:"0.3 Beta",title:"显示控制与信号诊断",changes:[
            "完善分辨率、HiDPI、刷新率、颜色格式、色深及 HDR 等显示控制。",
            "增加模式切换确认与自动回退，完善显示器身份及连接变化处理。",
            "扩展当前信号、显示器能力与 EDID 展示，增加诊断报告。"
        ]),
        ReleaseNote(id:"beta02",version:"0.2 Beta",title:"多语言与 Apple TV 音频",changes:[
            "新增跟随系统、简体中文和 English 界面语言。",
            "优化 Apple TV 音频发现、连接和音量控制。",
            "完善快捷面板、显示器信息与应用安装体验。"
        ]),
        ReleaseNote(id:"beta01",version:"0.1 Beta",title:"首次 Beta 与视觉标识",changes:[
            "建立公开 Beta 发布基线，启用全新的 Right Display 应用图标。",
            "状态栏与快捷面板采用同源图标，兼顾深色与浅色界面的清晰度。"
        ])
    ]
}
