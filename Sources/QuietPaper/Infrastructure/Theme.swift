import AppKit
import SwiftUI

/// 应用主题。每个主题都提供浅色 / 深色两套配色，自动跟随系统外观切换。
enum Theme: String, CaseIterable, Identifiable {
    case system
    case warmPaper
    case forest
    case deepOcean
    case sakura
    case midnight

    static let defaultsKey = "QuietPaper.theme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .warmPaper: "暖纸"
        case .forest: "森林"
        case .deepOcean: "深海"
        case .sakura: "樱花"
        case .midnight: "午夜"
        }
    }

    var summary: String {
        switch self {
        case .system: "使用系统默认外观与强调色"
        case .warmPaper: "温润纸面，琥珀色点缀"
        case .forest: "中性纸面，松绿色点缀"
        case .deepOcean: "冷静纸面，海蓝色点缀"
        case .sakura: "柔和纸面，樱粉色点缀"
        case .midnight: "冷灰纸面，靛紫色点缀"
        }
    }

    var palette: ThemePalette { ThemePalette(theme: self) }

    /// 当前主题（来自 UserDefaults，由设置面板维护）。
    static var current: Theme { stored }

    static var stored: Theme {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return .system }
        return Theme(rawValue: raw) ?? .system
    }

    // 便捷访问当前主题配色，供各视图直接使用。
    static var accent: Color { current.palette.accent }
    static var background: Color { current.palette.background }
    static var control: Color { current.palette.control }
    static var editor: Color { current.palette.editor }
}

/// 主题配色。大面积表面保持低彩度，只让强调色承载主题个性；
/// 文本与分隔线继续使用系统语义色，以保证浅色 / 深色外观中的可读性。
struct ThemePalette {
    let accent: Color
    let background: Color
    let control: Color
    let editor: Color

    init(theme: Theme) {
        switch theme {
        case .system:
            accent = Color(nsColor: .controlAccentColor)
            background = Color(nsColor: .windowBackgroundColor)
            control = Color(nsColor: .controlBackgroundColor)
            editor = Color(nsColor: .textBackgroundColor)
        case .warmPaper:
            accent = Self.dynamic(light: .init(calibratedRed: 0.62, green: 0.42, blue: 0.15, alpha: 1), dark: .init(calibratedRed: 0.88, green: 0.68, blue: 0.34, alpha: 1))
            background = Self.dynamic(light: .init(calibratedRed: 0.961, green: 0.953, blue: 0.938, alpha: 1), dark: .init(calibratedRed: 0.105, green: 0.102, blue: 0.094, alpha: 1))
            control = Self.dynamic(light: .init(calibratedRed: 0.932, green: 0.921, blue: 0.900, alpha: 1), dark: .init(calibratedRed: 0.145, green: 0.140, blue: 0.128, alpha: 1))
            editor = Self.dynamic(light: .init(calibratedRed: 0.992, green: 0.989, blue: 0.982, alpha: 1), dark: .init(calibratedRed: 0.125, green: 0.121, blue: 0.111, alpha: 1))
        case .forest:
            accent = Self.dynamic(light: .init(calibratedRed: 0.20, green: 0.45, blue: 0.30, alpha: 1), dark: .init(calibratedRed: 0.43, green: 0.72, blue: 0.52, alpha: 1))
            background = Self.dynamic(light: .init(calibratedRed: 0.949, green: 0.955, blue: 0.948, alpha: 1), dark: .init(calibratedRed: 0.094, green: 0.103, blue: 0.097, alpha: 1))
            control = Self.dynamic(light: .init(calibratedRed: 0.918, green: 0.931, blue: 0.920, alpha: 1), dark: .init(calibratedRed: 0.123, green: 0.139, blue: 0.127, alpha: 1))
            editor = Self.dynamic(light: .init(calibratedRed: 0.988, green: 0.991, blue: 0.987, alpha: 1), dark: .init(calibratedRed: 0.110, green: 0.118, blue: 0.112, alpha: 1))
        case .deepOcean:
            accent = Self.dynamic(light: .init(calibratedRed: 0.12, green: 0.42, blue: 0.66, alpha: 1), dark: .init(calibratedRed: 0.37, green: 0.67, blue: 0.91, alpha: 1))
            background = Self.dynamic(light: .init(calibratedRed: 0.946, green: 0.953, blue: 0.958, alpha: 1), dark: .init(calibratedRed: 0.087, green: 0.097, blue: 0.107, alpha: 1))
            control = Self.dynamic(light: .init(calibratedRed: 0.912, green: 0.925, blue: 0.935, alpha: 1), dark: .init(calibratedRed: 0.112, green: 0.128, blue: 0.142, alpha: 1))
            editor = Self.dynamic(light: .init(calibratedRed: 0.987, green: 0.990, blue: 0.992, alpha: 1), dark: .init(calibratedRed: 0.101, green: 0.111, blue: 0.121, alpha: 1))
        case .sakura:
            accent = Self.dynamic(light: .init(calibratedRed: 0.79, green: 0.30, blue: 0.47, alpha: 1), dark: .init(calibratedRed: 0.95, green: 0.52, blue: 0.66, alpha: 1))
            background = Self.dynamic(light: .init(calibratedRed: 0.960, green: 0.950, blue: 0.952, alpha: 1), dark: .init(calibratedRed: 0.105, green: 0.095, blue: 0.098, alpha: 1))
            control = Self.dynamic(light: .init(calibratedRed: 0.936, green: 0.918, blue: 0.923, alpha: 1), dark: .init(calibratedRed: 0.145, green: 0.123, blue: 0.129, alpha: 1))
            editor = Self.dynamic(light: .init(calibratedRed: 0.993, green: 0.988, blue: 0.989, alpha: 1), dark: .init(calibratedRed: 0.122, green: 0.109, blue: 0.113, alpha: 1))
        case .midnight:
            accent = Self.dynamic(light: .init(calibratedRed: 0.39, green: 0.32, blue: 0.69, alpha: 1), dark: .init(calibratedRed: 0.65, green: 0.57, blue: 0.94, alpha: 1))
            background = Self.dynamic(light: .init(calibratedRed: 0.947, green: 0.948, blue: 0.955, alpha: 1), dark: .init(calibratedRed: 0.081, green: 0.084, blue: 0.099, alpha: 1))
            control = Self.dynamic(light: .init(calibratedRed: 0.914, green: 0.915, blue: 0.931, alpha: 1), dark: .init(calibratedRed: 0.108, green: 0.111, blue: 0.135, alpha: 1))
            editor = Self.dynamic(light: .init(calibratedRed: 0.988, green: 0.988, blue: 0.992, alpha: 1), dark: .init(calibratedRed: 0.096, green: 0.099, blue: 0.116, alpha: 1))
        }
    }

    /// 构造跟随明暗外观动态变化的颜色。
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
