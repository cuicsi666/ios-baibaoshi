import SwiftUI

// MARK: - 百宝箱根视图：全部模块卡片化展示

struct RootView: View {
    @EnvironmentObject var volume: VolumeMonitor
    @EnvironmentObject var router: RouterPoller
    @EnvironmentObject var idioms: IdiomStore
    @EnvironmentObject var monitor: BatteryMonitor
    @EnvironmentObject var chargeHistory: ChargeHistory
    @EnvironmentObject var ble: BLEManager
    @ObservedObject var nav = NavService.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var keepAlive = KeepAliveService.shared

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

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
                VStack(alignment: .leading, spacing: 18) {
                    header
                    appSection
                    toolSection
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Theme.background(theme.scheme).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(ModuleTheme.gradient(ModuleTheme.charge))
                        Text("百宝箱").font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        theme.isDark.toggle()
                    } label: {
                        Image(systemName: theme.isDark ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(theme.isDark ? .orange : .indigo)
                    }
                }
            }
        }
        .onAppear {
            router.start(); idioms.start(); NavService.shared.load()
            KeepAliveService.shared.applySettings()
        }
        .preferredColorScheme(theme.scheme)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(greeting)，崔老板")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Text("🦞").font(.system(size: 32))
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
        .padding(.top, 12)
    }

    // MARK: 应用区（融合的独立应用）

    @ViewBuilder private var appSection: some View {
        sectionTitle("应用", systemImage: "square.grid.2x2.fill")
        LazyVGrid(columns: cols, spacing: 14) {
            NavigationLink(destination: CBHomeView()) {
                ModuleCard(title: "电管家",
                           subtitle: chargeSubtitle,
                           icon: "bolt.fill", colors: ModuleTheme.charge)
            }
            NavigationLink(destination: XUIRemoteHomeView()) {
                ModuleCard(title: "XUI 遥控",
                           subtitle: "板子遥控 · 手柄 · 中继",
                           icon: "cpu.fill", colors: ModuleTheme.xui)
            }
            NavigationLink(destination: SuperKeyView().environmentObject(RecorderService.shared)) {
                ModuleCard(title: "超级按键",
                           subtitle: "说话 → 识别 → AI → 播报",
                           icon: "mic.fill", colors: ModuleTheme.superkey)
            }
            NavigationLink(destination: FlowTextView()) {
                ModuleCard(title: "流文",
                           subtitle: ble.connected ? "已连接 · 文字流动中" : "板子说话 → 键盘流入",
                           icon: "text.cursor.rainbow", colors: ModuleTheme.flowtext, lines: 2)
            }
            NavigationLink(destination: WebAssistantView()) {
                ModuleCard(title: "龙虾帮",
                           subtitle: "OpenClaw 控制台 · 三端切换",
                           icon: "globe.asia.australia.fill", colors: ModuleTheme.lobang, lines: 2)
            }
        }
    }

    // MARK: 工具区（原百宝匣七件套）

    @ViewBuilder private var toolSection: some View {
        sectionTitle("工具", systemImage: "wrench.and.screwdriver.fill")
        LazyVGrid(columns: cols, spacing: 14) {
            NavigationLink(destination: HapticsLabView()) {
                ModuleCard(title: "震动实验室", subtitle: "12 种触感 · 节奏大师", icon: "iphone.radiowaves.left.and.right", colors: ModuleTheme.haptics)
            }
            NavigationLink(destination: VolumeTestView()) {
                ModuleCard(title: "音量测试", subtitle: "当前 \(Int(volume.volume * 100))% · 图形化", icon: "speaker.wave.3.fill", colors: ModuleTheme.volume)
            }
            NavigationLink(destination: ApiLabView()) {
                ModuleCard(title: "API 实验室", subtitle: "内置 + 自定义调用", icon: "antenna.radiowaves.left.and.right", colors: ModuleTheme.api)
            }
            NavigationLink(destination: IdiomView()) {
                ModuleCard(title: "励志成语", subtitle: idioms.current.text, icon: "text.book.closed.fill", colors: ModuleTheme.idiom, lines: 2)
            }
            NavigationLink(destination: RouterMonitorView()) {
                ModuleCard(title: "路由器监控", subtitle: routerSub, icon: "wifi.router.fill", colors: ModuleTheme.router, lines: 2)
            }
            NavigationLink(destination: NavStationView()) {
                ModuleCard(title: "导航站", subtitle: "全站 \(nav.linksCount) 站点 · 随机逛", icon: "map.fill", colors: ModuleTheme.nav)
            }
            NavigationLink(destination: WebEntryView(config: .music)) {
                ModuleCard(title: "AI 音乐", subtitle: "music-dl · 边搜边下", icon: "music.note.list", colors: ModuleTheme.music)
            }
            NavigationLink(destination: SettingsView()) {
                ModuleCard(title: "设置", subtitle: "主题 · 保活 · 通知 · 数据", icon: "gearshape.fill", colors: [Color(hex: 0x8E9AAF), Color(hex: 0x5C6672)])
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
            Text("百宝箱 V2 · 全能工具台")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            if keepAlive.enabled {
                Text(keepAlive.active ? "后台保活运行中 · 定位低功耗模式" : "后台保活待授权")
                    .font(.system(size: 10))
                    .foregroundColor(keepAlive.active ? .green.opacity(0.8) : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ModuleTheme.gradient(ModuleTheme.charge))
            Text(text)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.top, 4)
    }
}
