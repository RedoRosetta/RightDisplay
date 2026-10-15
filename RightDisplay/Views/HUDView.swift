// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import SwiftUI

struct HUDView: View {
    let display: DisplaySnapshot?

    var body: some View {
        Group {
            if let display {
                HStack(spacing: 13) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.16))
                        Image(systemName: "display")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppLocalization.string(display.headline))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(AppLocalization.string(display.signalLine))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Label("等待显示器", systemImage: "display.trianglebadge.exclamationmark")
                    .font(.callout.weight(.medium))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusColor: Color {
        switch display?.overallVerification {
        case .verified: .green
        case .slsReported: .blue
        case .inferred: .yellow
        default: .cyan
        }
    }
}

struct CapabilityTestHUDView: View {
    let progress: Int
    let total: Int
    let candidate: String
    let status: String
    let environment: String
    let readback: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: reduceTransparency
                    ? [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)]
                    : [Color.indigo.opacity(0.28), Color.cyan.opacity(0.18), Color.black.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("显示链路测试")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                ProgressView(
                    value: total > 0 ? min(max(Double(progress) / Double(total), 0), 1) : 0,
                    total: 1
                )
                .progressViewStyle(.linear)
                .frame(width: 280)
                .overlay(alignment: .trailing) {
                    Text("\(total > 0 ? Int((Double(progress) / Double(total) * 100).rounded()) : 0)%")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                        .offset(x: 40)
                }
                .frame(height: 16)
                VStack(spacing: 7) {
                    Text(AppLocalization.format("测试目标：%@", environment))
                    Text(AppLocalization.string(candidate))
                        .fontWeight(.semibold)
                    Text(AppLocalization.string(status))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 15, design: .rounded))
                VStack(spacing: 6) {
                    Text("实际读回")
                        .font(.caption.weight(.semibold))
                    Text(AppLocalization.string(readback))
                        .font(.system(size: 14, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                Text("按 Esc 停止测试并恢复测试前设置")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(34)
            .frame(maxWidth: 560)
            .background(
                reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .shadow(color: .black.opacity(reduceTransparency ? 0.12 : 0.22), radius: 30, y: 12)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: status)
        }
    }
}
