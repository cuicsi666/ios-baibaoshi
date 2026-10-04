import SwiftUI

// MARK: - 百宝箱设置 v2（外观 / 更新 / 保活 / 数据 / 关于）

struct SettingsView: View {
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var keepAlive = KeepAliveService.shared
    @ObservedObject var updater = UpdateService.shared
    @EnvironmentObject var chargeHistory: ChargeHistory
    @Environment(\.colorScheme) private var scheme

    @AppStorage("bb.keepAlive") private var keepAliveOn = true
    @State private var showClearAlert = false
    @State private var showShare = false
    @State private var uploadMsg = ""

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "9.0"
    }

    private var logSummary: String {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.log")
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int, size > 0 else {
            return "暂无"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// 0 跟随系统 / 1 浅色 / 2 深色
    private var appearanceBinding: Binding<Int> {
        Binding(
            get: { theme.followSystem ? 0 : (theme.isDark ? 2 : 1) },
            set: { v in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    switch v {
                    case 0: theme.followSystem = true
                    case 1: theme.followSystem = false; theme.isDark = false
                    default: theme.followSystem = false; theme.isDark = true
                    }
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                appearanceCard
                updateCard
                keepAliveCard
                chargeCard
                dataCard
                aboutCard
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("清除全部充电历史？", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { chargeHistory.clear() }
        } message: {
            Text("清除后充电预估将回到纯参考曲线模式")
        }
    }

    // MARK: 外观

    private var appearanceCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 14) {
                BBSectionHeader("外观", icon: "paintbrush.fill")
                BBSegmented(options: [("跟随系统", 0), ("浅色", 1), ("深色", 2)], selection: appearanceBinding)

                VStack(alignment: .leading, spacing: 9) {
                    Text("强调色").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        ForEach(BBAccent.allCases) { a in
                            Button {
                                BBHaptic.select()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { theme.accent = a }
                            } label: {
                                VStack(spacing: 5) {
                                    ZStack {
                                        Circle().fill(Theme.gradient(a.colors)).frame(width: 30, height: 30)
                                        if theme.accent == a {
                                            Circle().strokeBorder(Color.primary.opacity(0.75), lineWidth: 2).frame(width: 36, height: 36)
                                        }
                                    }
                                    Text(a.label).font(.system(size: 9, weight: .medium))
                                        .foregroundColor(theme.accent == a ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Toggle(isOn: Binding(get: { theme.compact }, set: { theme.compact = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("紧凑卡片").font(.system(size: 14, weight: .medium))
                        Text("首页一屏展示更多功能").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .tint(theme.accent)
            }
        }
    }

    // MARK: 软件更新

    @ViewBuilder private var updateCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("软件更新", icon: "arrow.triangle.2.circlepath")
                if updater.checking {
                    HStack(spacing: 10) {
                        ProgressView(); Text("正在检查更新…").foregroundColor(.secondary).font(.system(size: 14))
                    }
                } else if updater.hasUpdate {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill").foregroundColor(Theme.success)
                            Text("发现新版本 V\(updater.newVersion)").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("当前 V\(appVersion)").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        if !updater.releaseNotes.isEmpty {
                            Text(updater.releaseNotes).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(6)
                        }
                        BBPrimaryButton(title: "立即安装（OTA 直装）", icon: "bolt.fill",
                                        colors: [Theme.success, Color(hex: 0x0FA968)]) {
                            updater.installUpdate()
                        }
                        Text("点击后自动跳转 Safari 安装，无需全能签")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                } else {
                    BBRow(title: "当前版本", icon: "app.badge.fill", value: "V\(appVersion)", showsChevron: false)
                    if !updater.message.isEmpty {
                        Text(updater.message).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    BBGhostButton(title: "检查更新", icon: "arrow.clockwise") {
                        updater.check { _ in }
                    }
                }
            }
        }
    }

    // MARK: 后台保活

    private var keepAliveCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("后台保活", icon: "location.fill")
                Toggle(isOn: $keepAliveOn) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("后台常驻保活").font(.system(size: 14, weight: .medium))
                        Text("低功耗定位保持活跃，充电播报 / 蓝牙 / 连接全时段在线")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .tint(theme.accent)
                .onChange(of: keepAliveOn) { _ in KeepAliveService.shared.applySettings() }

                HStack {
                    Label("定位权限", systemImage: "location.fill").font(.system(size: 13))
                    Spacer()
                    Text(authText).foregroundColor(authColor).font(.system(size: 13, weight: .medium))
                }
                if keepAlive.locationAuth != .authorizedAlways {
                    BBGhostButton(title: "去系统设置开启「始终允许」", icon: "arrow.up.forward.app") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Text("定位仅用于系统保活（3 公里低精度，不采集不上报）")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: 充电监控

    private var chargeCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("充电监控", icon: "bolt.fill", colors: Theme.charge)
                BBRow(title: "控制入口", icon: "bolt.fill", value: "电管家模块页底部", colors: Theme.charge)
                BBRow(title: "历史会话", icon: "clock.arrow.circlepath", value: "\(chargeHistory.sessions.count) 次", colors: Theme.charge)
                BBGhostButton(title: "清除充电历史", icon: "trash") { showClearAlert = true }
                    .disabled(chargeHistory.sessions.isEmpty)
                    .opacity(chargeHistory.sessions.isEmpty ? 0.5 : 1)
            }
        }
    }

    // MARK: 数据与日志

    private var dataCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("数据与诊断", icon: "internaldrive.fill")
                BBRow(title: "本地日志", icon: "doc.text", value: logSummary)
                if !uploadMsg.isEmpty {
                    Text(uploadMsg).font(.system(size: 11)).foregroundColor(.secondary)
                }
                BBGhostButton(title: "上传日志到服务器", icon: "icloud.and.arrow.up") {
                    uploadMsg = "上传中…"
                    AppLog.log("Diag", "手动上传日志")
                    AppLog.upload { msg in uploadMsg = msg }
                }
                Text("日志记录模块运行与崩溃现场，出问题时上传给小龙虾分析")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: 关于

    private var aboutCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.accentGradient)
                            .frame(width: 54, height: 54)
                            .shadow(color: theme.accent.secondary.opacity(0.4), radius: 9, y: 4)
                        Image(systemName: "shippingbox.fill").font(.system(size: 24, weight: .semibold)).foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("百宝箱").font(BBFont.title(20))
                        Text("V\(appVersion) · 崔老板专属全能工具台")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Divider()
                BBRow(title: "功能模块", icon: "square.grid.2x2.fill", value: "\(ModuleRegistry.all.count) 个")
                BBRow(title: "全部应用", icon: "app.badge", value: "电管家 · XVP · V监控 · 工具集")
                BBRow(title: "构建", icon: "hammer.fill", value: "GitHub Actions + zsign")
                Text("🦞 由小龙虾持续维护 · 有问题直接喊我")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }

    private var authText: String {
        switch keepAlive.locationAuth {
        case .authorizedAlways: return "始终允许 ✅"
        case .authorizedWhenInUse: return "仅使用期间"
        case .denied, .restricted: return "已拒绝"
        default: return "未授权"
        }
    }

    private var authColor: Color {
        keepAlive.locationAuth == .authorizedAlways ? .green : .orange
    }
}

// MARK: - UIActivityViewController 包装（分享给全能签）

struct ShareSheet: UIViewControllerRepresentable {
    let vc: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { vc }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}
