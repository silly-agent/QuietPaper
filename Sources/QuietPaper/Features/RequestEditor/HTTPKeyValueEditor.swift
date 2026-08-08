import SwiftUI

struct HTTPKeyValueEditor: View {
    @Binding var items: [HTTPKeyValue]
    let keyPlaceholder: String
    let valuePlaceholder: String
    let addLabel: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 18)
                Text(keyPlaceholder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(valuePlaceholder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 24)
            }
            .font(AppTypography.tertiary)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 18)
            .frame(height: 32)

            HairlineDivider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($items) { $item in
                        HTTPKeyValueRow(
                            item: $item,
                            keyPlaceholder: keyPlaceholder,
                            valuePlaceholder: valuePlaceholder,
                            onDelete: { remove(item.id) }
                        )
                        HairlineDivider()
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            items.append(HTTPKeyValue())
                        }
                    } label: {
                        Label(addLabel, systemImage: "plus")
                            .font(AppTypography.secondary)
                            .foregroundStyle(Color.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
    }

    private func remove(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.14)) {
            items.removeAll { $0.id == id }
        }
    }
}

private struct HTTPKeyValueRow: View {
    @Binding var item: HTTPKeyValue
    let keyPlaceholder: String
    let valuePlaceholder: String
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("启用", isOn: $item.isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .frame(width: 18)
                .pointingHandCursor()

            field(keyPlaceholder, text: $item.key)
            field(valuePlaceholder, text: $item.value)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(isHovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("删除此项")
            .opacity(isHovering ? 1 : 0.35)
            .pointingHandCursor()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 5)
        .opacity(item.isEnabled ? 1 : 0.52)
        .background(isHovering ? Color.primary.opacity(0.025) : Color.clear)
        .onHover { isHovering = $0 }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(Theme.editor.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}
