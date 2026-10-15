// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import SwiftUI

struct SignalBadge: View {
    let text: String
    let verification: Verification
    var prominent = false

    private var tint: Color {
        switch verification {
        case .verified: .green
        case .slsReported: .blue
        case .inferred: .yellow
        case .unavailable: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.65), radius: 3)
            Text(AppLocalization.string(text == "已验证" ? "系统报告" : text))
                .font(.system(size: prominent ? 15 : 13, weight: prominent ? .semibold : .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(verification == .unavailable ? .secondary : .primary)
        .padding(.horizontal, prominent ? 11 : 9)
        .padding(.vertical, prominent ? 8 : 6)
        .background(.white.opacity(0.07), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.09), lineWidth: 0.5)
        }
        .help(AppLocalization.string(helpText))
    }

    private var helpText: String {
        switch verification {
        case .verified: "由 macOS 公开显示接口读取；不是物理接收端验证"
        case .slsReported: "系统报告的输出状态；最终接收端状态可能不同。"
        case .inferred: "根据系统状态推测，并非 HDMI/DP 链路实测"
        case .unavailable: "macOS 目前没有提供可验证的数据"
        }
    }
}

extension DisplayStatusIndicator {
    var color: Color {
        switch self {
        case .green: .green
        case .yellow: .yellow
        case .gray: .gray
        }
    }
}
