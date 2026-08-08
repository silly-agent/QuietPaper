import SwiftUI

/// 设置面板中的最近删除区块：恢复或永久删除已删除的项目、模块与笔记。
struct TrashSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var items: [DeletedItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("最近删除为空")
                        .font(AppTypography.rowTitleStrong)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 46)
                .background(Theme.control.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: item.kind))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(AppTypography.rowTitleStrong)
                                Text("\(item.kind.rawValue) · \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(AppTypography.tertiary)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("恢复") {
                                model.restore(item)
                                refresh()
                            }
                            .controlSize(.small)
                            .pointingHandCursor()
                            Button("永久删除", role: .destructive) {
                                model.permanentlyDelete(item)
                                refresh()
                            }
                            .controlSize(.small)
                            .pointingHandCursor()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.control.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() { items = model.deletedItems() }

    private func icon(for kind: DeletedItemKind) -> String {
        switch kind {
        case .project: "folder"
        case .module: "square.stack"
        case .note: "doc.text"
        }
    }
}
