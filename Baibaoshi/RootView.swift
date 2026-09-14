import SwiftUI

// MARK: - 百宝箱根视图：模块卡片化展示

struct RootView: View {
    @EnvironmentObject var router: RouterPoller
    @EnvironmentObject var idioms: IdiomStore
    @EnvironmentObject var monitor: BatteryMonitor
    @EnvironmentObject var chargeHistory: ChargeHistory
    @EnvironmentObject var ble: BLEManager
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var keepAlive = KeepAliveService.shared
    @ObservedObject var updater = UpdateService.shared

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

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
                    appSection
                    toolSection
                    footer
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .background(Theme.background(theme.scheme).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(Theme.gradient(Theme.charge))
                        Text("百宝箱").font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        theme.isDark.toggle()
                    } label: {
                        Image(systemName: theme.isDark ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.isDark ? .orange : .indigo)
                    }
                }
            }
        }
        .onAppear {
            router.start(); idioms.start()
            KeepAliveService.shared.applySettings()
            updater.silentCheck()
        }
        .preferredColorScheme(theme.scheme)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(greeting)，崔老板")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Text("🦞").font(.system(size: 30))
            }
            HStack(spacing: 6) {
                Text(dateText + " · 百宝箱已就绪")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if keepAlive.active {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.top, 10)
    }

    // MARK: 应用区

    @ViewBuilder private var appSection: some View {
        sectionTitle("应用", systemImage: "square.grid.2x2.fill")
        LazyVGrid(columns: cols, spacing: 10) {
            NavigationLink(destination: CBHomeView()) {
                ModuleCard(title: "电管家",
                           subtitle: chargeSubtitle,
                           icon: "bolt.fill", colors: Theme.charge)
            }
            NavigationLink(destination: FlowTextView()) {
                ModuleCard(title: "流文",
                           subtitle: ble.connected ? "已连接 · 文字流动中" : "板子说话 → 键盘流入",
                           icon: "text.cursor.rainbow", colors: Theme.flowtext, lines: 2)
            }
            NavigationLink(destination: XVPPlayerView()) {
                ModuleCard(title: "XVP 播放器",
                           subtitle: "内置前端 · 时间密码",
                           icon: "play.rectangle.fill", colors: [Color(hex: 0x654EA3), Color(hex: 0xEAAFC8)])
            }
            NavigationLink(destination: VAppPlayerView()) {
                ModuleCard(title: "V监控",
                           subtitle: "ESXi + OpenWrt 直连监控",
                           icon: "server.rack", colors: [Color(hex: 0x2C3E50), Color(hex: 0x4CA1AF)], lines: 2)
            }
        }
    }

    // MARK: 工具区

    @ViewBuilder private var toolSection: some View {
        sectionTitle("工具", systemImage: "wrench.and.screwdriver.fill")
        LazyVGrid(columns: cols, spacing: 10) {
            NavigationLink(destination: IdiomView()) {
                ModuleCard(title: "励志成语", subtitle: idioms.current.text, icon: "text.book.closed.fill", colors: Theme.idiom, lines: 2)
            }
            NavigationLink(destination: RouterMonitorView()) {
                ModuleCard(title: "路由器监控", subtitle: routerSub, icon: "wifi.router.fill", colors: Theme.router, lines: 2)
            }
            NavigationLink(destination: SettingsView()) {
                ModuleCard(title: "设置", subtitle: updater.hasUpdate ? "有新版本 V\(updater.newVersion) 🆕" : "主题 · 保活 · 更新",
                           icon: "gearshape.fill", colors: [Color(hex: 0x8E9AAF), Color(hex: 0x5C6672)])
            }
        }
    }

    private var chargeSubtitle: String {
        if monitor.isPlugged {
            if let est = monitor.estimate { return "充电中 · 剩 \(est.timeText)" }
            return "充电中 · 采样速率"
        }
        return "电量 \(monitor.level >= 0 ? "\(monitor.level)%" : "--") · +5% 播报"
    }

    private var routerSub: String {
        guard let s = router.sys, router.online else { return "未连接 · 点击配置" }
        return String(format: "%@ · CPU %.0f%% · %.0f°", s.host, s.cpu, s.temp ?? 0)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("百宝箱 V4 · 全能工具台")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            if keepAlive.enabled {
                Text(keepAlive.active ? "后台保活运行中 · 定位低功耗模式" : "后台保活待授权")
                    .font(.system(size: 10))
                    .foregroundColor(keepAlive.active ? .green.opacity(0.8) : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gradient(Theme.charge))
            Text(text)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.top, 2)
    }
}
