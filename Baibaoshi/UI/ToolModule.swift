import SwiftUI

// MARK: - 模块元数据（首页卡片 / 搜索 / 收藏 通用）

enum BBCategory: String, CaseIterable, Identifiable {
    case core   = "核心应用"
    case calc   = "计算转换"
    case text   = "文本编码"
    case time   = "时间效率"
    case device = "设备系统"
    case fun    = "趣味生活"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .core:   return "square.stack.3d.up.fill"
        case .calc:   return "function"
        case .text:   return "textformat.abc"
        case .time:   return "clock.fill"
        case .device: return "cpu"
        case .fun:    return "sparkles"
        }
    }

    var colors: [Color] {
        switch self {
        case .core:   return [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)]
        case .calc:   return [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)]
        case .text:   return [Color(hex: 0x7B5CFF), Color(hex: 0xC86BFF)]
        case .time:   return [Color(hex: 0xFF7A18), Color(hex: 0xFFB020)]
        case .device: return [Color(hex: 0x2C3E50), Color(hex: 0x4CA1AF)]
        case .fun:    return [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)]
        }
    }

    var gradient: LinearGradient { Theme.gradient(colors) }
}

struct ToolModule: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]
    let category: BBCategory
    let keywords: [String]
    let destination: () -> AnyView

    init<V: View>(_ id: String,
                  _ title: String,
                  _ subtitle: String,
                  icon: String,
                  colors: [Color],
                  category: BBCategory,
                  keywords: [String] = [],
                  @ViewBuilder destination: @escaping () -> V) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.colors = colors
        self.category = category
        self.keywords = keywords
        self.destination = { AnyView(destination()) }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        let hay = ([title, subtitle] + keywords).joined(separator: " ").lowercased()
        return hay.contains(q)
    }
}

// MARK: - 收藏 / 最近使用

final class ModulePrefs: ObservableObject {
    static let shared = ModulePrefs()

    @Published var favorites: [String] { didSet { UserDefaults.standard.set(favorites, forKey: "bb.favs") } }
    @Published var recents: [String] { didSet { UserDefaults.standard.set(recents, forKey: "bb.recents") } }

    private init() {
        favorites = UserDefaults.standard.stringArray(forKey: "bb.favs") ?? []
        recents = UserDefaults.standard.stringArray(forKey: "bb.recents") ?? []
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) }
        else { favorites.append(id) }
    }

    func markRecent(_ id: String) {
        var r = recents.filter { $0 != id }
        r.insert(id, at: 0)
        if r.count > 8 { r = Array(r.prefix(8)) }
        recents = r
    }

    func module(_ id: String) -> ToolModule? { ModuleRegistry.all.first { $0.id == id } }
}

// MARK: - 首页模块卡片（支持收藏角标 / 紧凑模式）

struct BBModuleCard: View {
    let module: ToolModule
    var favorite: Bool = false

    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var scheme

    private var h: CGFloat { theme.compact ? 92 : 112 }
    private var iconSize: CGFloat { theme.compact ? 30 : 36 }
    private var radius: CGFloat { theme.compact ? 16 : 19 }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.compact ? 6 : 9) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: theme.compact ? 9 : 11, style: .continuous)
                        .fill(Theme.gradient(module.colors))
                        .frame(width: iconSize, height: iconSize)
                        .shadow(color: module.colors.last!.opacity(0.42), radius: 6, y: 3)
                    Image(systemName: module.icon)
                        .font(.system(size: theme.compact ? 14 : 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                Spacer(minLength: 2)
                if favorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: 0xFFC53D))
                        .padding(4)
                        .background(Circle().fill(Color(hex: 0xFFC53D).opacity(0.16)))
                }
            }
            Spacer(minLength: 0)
            Text(module.title)
                .font(.system(size: theme.compact ? 13 : 14.5, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(module.subtitle)
                .font(.system(size: theme.compact ? 9.5 : 10.5, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: h, alignment: .topLeading)
        .padding(theme.compact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.cardBg(scheme == .dark))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1)
                )
        )
        .bbShadow(scheme == .dark)
    }
}
