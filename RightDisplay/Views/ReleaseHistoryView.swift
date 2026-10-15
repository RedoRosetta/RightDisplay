// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
import SwiftUI

struct ReleaseHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("历史更新说明").font(.title2.weight(.semibold))
                    Text("Right Display｜正确显示 的主要功能性变化").foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(22)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(RightDisplayReleaseHistory.notes) { note in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(AppLocalization.string(note.title)).font(.headline)
                                Spacer()
                                Text(note.version).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                            }
                            ForEach(note.changes, id: \.self) { change in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption).foregroundStyle(Color.accentColor)
                                        .padding(.top, 2)
                                    Text(AppLocalization.string(change)).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 650, height: 660)
    }
}
