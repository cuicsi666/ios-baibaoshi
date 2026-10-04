import SwiftUI

// MARK: - 百宝箱设计系统 v2（BB Design System）
// 统一间距 / 圆角 / 字体 / 强调色 / 语义色，供全部模块复用。

enum BBSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 22
    static let screen: CGFloat = 16
}

enum BBRadius {
    static let s: CGFloat = 10
    static let m: CGFloat = 16
    static let l: CGFloat = 22
    static let xl: CGFloat = 28
}

enum BBFont {
    static func title(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func head(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .regular) }
    static func num(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func cap(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .medium) }
    static var mono: Font { .system(size: 13, design: .monospaced) }
    static var monoBig: Font { .system(size: 26, weight: .semibold, design: .monospaced) }
}

// MARK: - 强调色预设

enum BBAccent: String, CaseIterable, Identifiable {
    case ocean, aurora, sunset, forest, candy, graphite
    var id: String { rawValue }

    var label: String {
        switch self {
        case .ocean: return "深海"
        case .aurora: return "极光"
        case .sunset: return "日落"
        case .forest: return "森林"
        case .candy: return "糖果"
        case .graphite: return "石墨"
        }
    }

    var colors: [Color] {
        switch self {
        case .ocean: return [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)]
        case .aurora: return [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)]
        case .sunset: return [Color(hex: 0xFF7A18), Color(hex: 0xFF3D71)]
        case .forest: return [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)]
        case .candy: return [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)]
        case .graphite: return [Color(hex: 0x5B6478), Color(hex: 0x9AA3B5)]
        }
    }

    var primary: Color { colors[0] }
    var secondary: Color { colors[1] }
}

// MARK: - 语义色 / 强调色（跟随 ThemeManager）

extension Theme {
    /// 当前强调色配色数组（供默认参数使用）
    static func accentColors() -> [Color] { ThemeManager.shared.accent.colors }
    /// 当前强调色
    static var accent: Color { ThemeManager.shared.accent.primary }
    static var accent2: Color { ThemeManager.shared.accent.secondary }
    static var accentGradient: LinearGradient { gradient(ThemeManager.shared.accent.colors) }

    // 语义色
    static let success = Color(hex: 0x22C55E)
    static let warning = Color(hex: 0xF59E0B)
    static let danger  = Color(hex: 0xEF4444)
    static let info    = Color(hex: 0x3B82F6)

    /// 中性面板色（比卡片更淡，用于内嵌区块）
    static func panel(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035)
    }
    /// 弱分隔线
    static func hairline(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
    }
    /// 次级文字
    static var subtle: Color { Color.secondary }
    /// 玻璃拟态卡片底
    static func glass(_ dark: Bool) -> Color {
        dark ? Color(hex: 0x1B1B2A).opacity(0.86) : Color.white.opacity(0.92)
    }
}

// MARK: - 阴影封装

extension View {
    func bbShadow(_ dark: Bool, strong: Bool = false) -> some View {
        self.shadow(color: Color.black.opacity(dark ? (strong ? 0.45 : 0.32) : (strong ? 0.12 : 0.07)),
                    radius: strong ? 16 : 9, y: strong ? 8 : 4)
    }
}

// MARK: - 动态背景（带强调色光晕，随主题变化）

struct BBAuroraBackground: View {
    var scheme: ColorScheme
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            Theme.background(scheme)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Circle()
                        .fill(theme.accent.primary.opacity(scheme == .dark ? 0.28 : 0.16))
                        .frame(width: w * 0.9)
                        .blur(radius: 90)
                        .offset(x: -w * 0.28, y: -h * 0.30)
                    Circle()
                        .fill(theme.accent.secondary.opacity(scheme == .dark ? 0.22 : 0.13))
                        .frame(width: w * 0.8)
                        .blur(radius: 90)
                        .offset(x: w * 0.32, y: h * 0.28)
                }
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// 统一页面背景（含光晕），点击态 / 滚动 / 表单均可使用
    func bbBackground(_ scheme: ColorScheme) -> some View {
        self.background(BBAuroraBackground(scheme: scheme))
    }
}
