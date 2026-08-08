import AppKit
import SwiftUI

/// QuietPaper 全局视觉规范
///
/// 字号体系（固定尺寸，让界面保持小巧、统一、不被动态缩放撑大）：
///   largeTitle     26pt   编辑器标题
///   sheetTitle     17pt   Sheet 标题
///   sectionTitle   14pt   侧栏 / 列表区块标题
///   rowTitle       14pt   列表行主标题（medium）
///   rowTitleStrong 14pt   列表行主标题（semibold，搜索结果等）
///   body           15.5pt 编辑器与预览正文
///   secondary      13pt   次要信息（面包屑、状态栏、说明文字）
///   tertiary       12.5pt 最弱层级（时间戳、标签、路径、辅助标注）
///   status         13pt   状态栏文本
///   monospacedCode 14.5pt 代码正文
///   monospacedLabel 12.5pt 代码块语言标签
///
/// 间距与圆角体系：
///   行内圆角 6pt，卡片圆角 8-10pt；列表行垂直内边距 4-6pt，区块头部 10-12pt。
enum AppTypography {
    static let largeTitle = Font.system(size: 26, weight: .semibold)
    static let sheetTitle = Font.system(size: 17, weight: .semibold)
    static let sectionTitle = Font.system(size: 14, weight: .semibold)
    static let rowTitle = Font.system(size: 14, weight: .medium)
    static let rowTitleStrong = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 15.5)
    static let secondary = Font.system(size: 13)
    static let tertiary = Font.system(size: 12.5)
    static let status = Font.system(size: 13)
    static let monospacedCode = Font.system(size: 14.5, design: .monospaced)
    static let monospacedLabel = Font.system(size: 12.5, design: .monospaced)
}

extension View {
    /// 正文级别的字距，让中文阅读更舒展。
    func bodyTracking(_ amount: CGFloat = 1.6) -> some View {
        tracking(amount)
    }
}

/// 适用于内容区的单像素浅色分隔线，降低长时间阅读时的视觉干扰。
struct HairlineDivider: View {
    enum Axis {
        case horizontal
        case vertical
    }

    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.04))
            .frame(
                width: axis == .vertical ? 0.5 : nil,
                height: axis == .horizontal ? 0.5 : nil
            )
            .accessibilityHidden(true)
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .onDisappear {
                if isHovering { NSCursor.arrow.set() }
            }
    }
}

extension View {
    /// 用于按钮、菜单触发器和可选择行；输入框不应使用此修饰器。
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}
