import SwiftUI

// MARK: - 百宝箱根视图 v2：搜索 + 收藏 + 分类网格

struct RootView: View {
    @EnvironmentObject var router: RouterPoller
    @EnvironmentObject var idioms: IdiomStore
    @EnvironmentObject var monitor: BatteryMonitor
    @EnvironmentObject var chargeHistory: ChargeHistory
    @EnvironmentObject var ble: BLEManager
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var keepAlive = KeepAliveService.shared
    @ObservedObject var updater = UpdateService.shared
    @ObservedObject var prefs = ModulePrefs.shared

    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var showAll = false

    private var cols: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        default: return "晚上好"
        }
    }

    var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    searchBar
                    if query.isEmpty {
                        quickSection
                        ForEach(BBCategory.allCases) { cat in
                            let mods = ModuleRegistry.modules(in: cat)
                            if !mods.isEmpty { categorySection(cat, mods) }
                        }
                        footer
                    } else {
                        searchResults
                    }
                }
                .padding(.horizontal, BBSpacing.screen)
                .padding(.bottom, 30)
            }
            .background(BBAuroraBackground(scheme: scheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(Theme.accentGradient)
                        Text("百宝箱").font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        BBHaptic.tap()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            theme.isDark.toggle()
                        }
                    } label: {
                        Image(systemName: theme.isDark ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.isDark ? .orange : theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showAll) { AllModulesView() }
        }
        .onAppear {
            router.start(); idioms.start()
            KeepAliveService.shared.applySettings()
            updater.silentCheck()
        }
        .preferredColorScheme(theme.preferredScheme)
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(greeting)，崔老板")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    HStack(spacing: 6) {
                        Text(dateText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        if keepAlive.active {
                            HStack(spacing: 3) {
                                Circle().fill(Theme.success).frame(width: 5, height: 5)
                                Text("保活中").font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Theme.success)
                            }
                        }
                    }
                }
                Spacer()
                ZStack {
                    Circle().fill(Theme.accentGradient).opacity(0.16).frame(width: 52, height: 52)
                    Text("🦞").font(.system(size: 28))
                }
            }
            if updater.hasUpdate {
                Button { updater.installUpdate() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("新版本 V\(updater.newVersion) 可安装").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.gradient([Theme.success, Color(hex: 0x0FA968)])))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.top, 8)
    }

    // MARK: 搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            TextField("搜索 \(ModuleRegistry.all.count) 个功能…", text: $query)
                .font(.system(size: 14))
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            Button { showAll = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.cardBg(scheme == .dark))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
        )
        .bbShadow(scheme == .dark)
    }

    // MARK: 收藏 / 最近使用

    @ViewBuilder private var quickSection: some View {
        let favs = prefs.favorites.compactMap { prefs.module($0) }
        if !favs.isEmpty {
            sectionTitle("收藏", icon: "star.fill", colors: [Color(hex: 0xFFC53D), Color(hex: 0xFF8C42)])
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(favs) { cardFor($0) }
            }
        }
        let recents = prefs.recents.compactMap { prefs.module($0) }.filter { !prefs.isFavorite($0.id) }
        if !recents.isEmpty {
            sectionTitle("最近使用", icon: "clock.arrow.circlepath", colors: Theme.accentColors())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recents) { m in
                        NavigationLink(destination: m.destination().onAppear { prefs.markRecent(m.id) }) {
                            HStack(spacing: 7) {
                                Image(systemName: m.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.gradient(m.colors))
                                Text(m.title).font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(Capsule().fill(Theme.cardBg(scheme == .dark)))
                            .overlay(Capsule().strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
                            .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: 分类分区

    @ViewBuilder private func categorySection(_ cat: BBCategory, _ mods: [ToolModule]) -> some View {
        sectionTitle(cat.rawValue, icon: cat.icon, colors: cat.colors)
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(mods) { cardFor($0) }
        }
    }

    @ViewBuilder private func cardFor(_ m: ToolModule) -> some View {
        NavigationLink(destination: m.destination()
            .onAppear { prefs.markRecent(m.id) }) {
            BBModuleCard(module: m, favorite: prefs.isFavorite(m.id))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                BBHaptic.select()
                withAnimation { prefs.toggleFavorite(m.id) }
            } label: {
                Label(prefs.isFavorite(m.id) ? "取消收藏" : "收藏", systemImage: prefs.isFavorite(m.id) ? "star.slash" : "star")
            }
        }
    }

    // MARK: 搜索结果

    @ViewBuilder private var searchResults: some View {
        let results = ModuleRegistry.search(query)
        if results.isEmpty {
            BBEmptyState(icon: "magnifyingglass", title: "没有找到相关功能", message: "换个关键词试试，或点右上角查看全部")
        } else {
            sectionTitle("搜索结果 · \(results.count)", icon: "magnifyingglass", colors: Theme.accentColors())
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(results) { cardFor($0) }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("百宝箱 V\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "9.0") · \(ModuleRegistry.all.count) 个功能")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            if keepAlive.enabled {
                Text(keepAlive.active ? "后台保活运行中 · 定位低功耗模式" : "后台保活待授权")
                    .font(.system(size: 10))
                    .foregroundColor(keepAlive.active ? .green.opacity(0.85) : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func sectionTitle(_ text: String, icon: String, colors: [Color]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gradient(colors))
            Text(text)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: - 全部功能列表

struct AllModulesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @ObservedObject var prefs = ModulePrefs.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("搜索功能", text: $query).font(.system(size: 14))
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.cardBg(scheme == .dark)))

                    ForEach(BBCategory.allCases) { cat in
                        let mods = ModuleRegistry.modules(in: cat).filter { $0.matches(query) }
                        if !mods.isEmpty {
                            ForEach(mods) { m in
                                NavigationLink(destination: m.destination().onAppear { prefs.markRecent(m.id) }) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Theme.gradient(m.colors)).frame(width: 38, height: 38)
                                            Image(systemName: m.icon)
                                                .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                                            Text(m.subtitle).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        if prefs.isFavorite(m.id) {
                                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundColor(Color(hex: 0xFFC53D))
                                        }
                                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary.opacity(0.5))
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardBg(scheme == .dark)))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        withAnimation { prefs.toggleFavorite(m.id) }
                                    } label: {
                                        Label(prefs.isFavorite(m.id) ? "取消收藏" : "收藏", systemImage: "star")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(BBAuroraBackground(scheme: scheme))
            .navigationTitle("全部功能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
