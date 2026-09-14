import SwiftUI

// MARK: - 主题管理（白/黑切换，默认白）

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @Published var isDark: Bool {
        didSet { UserDefaults.standard.set(isDark, forKey: "bb.dark") }
    }
    private init() {
        isDark = UserDefaults.standard.object(forKey: "bb.dark") as? Bool ?? false
    }
    var scheme: ColorScheme { isDark ? .dark : .light }
}

// MARK: - 模块渐变色

enum Theme {
    static let haptics  = [Color(hex: 0xFF9A5A), Color(hex: 0xFF5E62)]   // 震动 橙红
    static let volume   = [Color(hex: 0x36D1DC), Color(hex: 0x5B86E5)]   // 音量 青蓝
    static let api      = [Color(hex: 0xA86BFF), Color(hex: 0xFF6BB8)]   // API 紫粉
    static let idiom    = [Color(hex: 0xF7B733), Color(hex: 0xFC4A1A)]   // 成语 金橙
    static let router   = [Color(hex: 0x11998E), Color(hex: 0x38EF7D)]   // 路由 绿青
    static let nav      = [Color(hex: 0x4E54C8), Color(hex: 0x8F94FB)]   // 导航 蓝紫
    static let music    = [Color(hex: 0xF953C6), Color(hex: 0xB91D73)]   // 音乐 玫红
    static let charge   = [Color(hex: 0x34E0A1), Color(hex: 0x2AD4C8)]   // 电管家 绿青
    static let superkey = [Color(hex: 0x396AFC), Color(hex: 0x2948FF)]   // 超级按键 蓝
    static let flowtext = [Color(hex: 0x43CBAF), Color(hex: 0x2E9CCA)]   // 流文 青翠
    static let xui      = [Color(hex: 0xFF8C42), Color(hex: 0xFF3D68)]   // XUI 橙红
    static let lobang   = [Color(hex: 0xB06AB3), Color(hex: 0x4568DC)]   // 龙虾帮 紫蓝

    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 兼容别名
typealias ModuleTheme = Theme

// MARK: - 语义色 + 电管家色板（合并进 Theme）

extension Theme {
    // 页面背景语义色（Assets 双外观，自动适配白黑主题）
    static var bgTop: Color { Color("BbBgTop") }
    static var bgBottom: Color { Color("BbBgBottom") }

    // 电管家色板（原 AppTheme）
    static let mint = Color(hex: 0x34E0A1)
    static let teal = Color(hex: 0x2AD4C8)
    static let sky  = Color(hex: 0x3B9EFF)
    static let card = Color(hex: 0x121A2E)
    static let cardStroke = Color.white.opacity(0.07)
    static let heroGradient = ModuleTheme.gradient(ModuleTheme.charge)
    static let lineGradient = LinearGradient(colors: [mint, sky], startPoint: .leading, endPoint: .trailing)

    /// 页面背景渐变（白主题：浅灰蓝 / 黑主题：深蓝黑）
    static func bgPair(_ dark: Bool) -> [Color] {
        dark ? [Color(hex: 0x14141F), Color(hex: 0x0A0A12)]
             : [Color(hex: 0xF4F6FB), Color(hex: 0xE6EAF3)]
    }
    /// 页面背景（电管家模块调用形式）
    static func background(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: bgPair(scheme == .dark), startPoint: .top, endPoint: .bottom)
    }
    /// 卡片底色
    static func cardBg(_ dark: Bool) -> Color {
        dark ? Color(hex: 0x1A1A28).opacity(0.92) : .white
    }
    /// 卡片描边
    static func stroke(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
}

// MARK: - 充电模块卡片样式（兼容原电管家布局）

struct CardStyle: ViewModifier {
    var scheme: ColorScheme
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.cardBg(scheme == .dark))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Theme.stroke(scheme == .dark), lineWidth: 1))
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.35 : 0.06), radius: 14, y: 6)
            )
    }
}

extension View {
    func cardStyle(_ scheme: ColorScheme) -> some View { modifier(CardStyle(scheme: scheme)) }
}

// MARK: - 颜色便捷初始化

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - 模块卡片

struct ModuleCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]
    var lines: Int = 1

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.gradient(colors))
                    .frame(width: 46, height: 46)
                    .shadow(color: colors.last!.opacity(0.45), radius: 8, y: 4)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(lines)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.cardBg(scheme == .dark))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(scheme == .dark ? 0.3 : 0.05), radius: 10, y: 4)
        )
    }
}

// MARK: - 详情页容器标题

struct PageHeader: View {
    let icon: String
    let colors: [Color]
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.gradient(colors))
                    .frame(width: 52, height: 52)
                    .shadow(color: colors.last!.opacity(0.5), radius: 10, y: 5)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}
