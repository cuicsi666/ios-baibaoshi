import SwiftUI

// MARK: - 百宝箱设置 v2（外观 / 更新 / 保活 / 数据 / 关于）

struct SettingsView: View {
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var keepAlive = KeepAliveService.shared
    @EnvironmentObject var chargeHistory: ChargeHistory
    @Environment(\.colorScheme) private var scheme

    @AppStorage("bb.keepAlive") private var keepAliveOn = true
    @State private var showClearAlert = false
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
                iconCard
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
                .tint(Theme.accent)
            }
        }
    }

    // MARK: 应用图标

    @ObservedObject private var iconMgr = AppIconManager.shared

    private var iconCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 14) {
                BBSectionHeader("应用图标", icon: "app.badge.fill")
                Text("换一套桌面图标，看看哪个顺眼 🦞")
                    .font(.system(size: 11)).foregroundColor(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(iconMgr.styles) { st in
                            Button {
                                BBHaptic.select()
                                iconMgr.set(st.id)
                            } label: {
                                VStack(spacing: 7) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(LinearGradient(colors: st.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 62, height: 62)
                                            .overlay(
                                                Image(systemName: "shippingbox.fill")
                                                    .font(.system(size: 26, weight: .semibold))
                                                    .foregroundColor(.white)
                                            )
                                            .shadow(color: st.colors[0].opacity(0.35), radius: 7, y: 4)
                                        if iconMgr.current == st.id {
                                            RoundedRectangle(cornerRadius: 21, style: .continuous)
                                                .strokeBorder(Theme.accent, lineWidth: 2.5)
                                                .frame(width: 70, height: 70)
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 17))
                                                .foregroundColor(Theme.accent)
                                                .background(Circle().fill(Color(.systemBackground)).frame(width: 15, height: 15))
                                                .offset(x: 26, y: 26)
                                        }
                                    }
                                    .frame(width: 72, height: 72)
                                    Text(st.name)
                                        .font(.system(size: 10, weight: iconMgr.current == st.id ? .semibold : .regular))
                                        .foregroundColor(iconMgr.current == st.id ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Text("切换后系统会弹一次确认，点「更改图标」即可")
                    .font(.system(size: 10)).foregroundColor(.secondary)
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
                .tint(Theme.accent)
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
                        Text("星辰").font(BBFont.title(20))
                        Text("V\(appVersion) · 崔老板的星辰工具箱")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Divider()
                BBRow(title: "功能模块", icon: "square.grid.2x2.fill", value: "\(ModuleRegistry.all.count) 个")
                BBRow(title: "全部应用", icon: "app.badge", value: "电管家 · 远程控制 · V监控 · 工具集")
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


// MARK: - 应用图标管理（iOS 备用图标）

final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    struct Style: Identifiable {
        let id: String
        let name: String
        let colors: [Color]
    }

    /// 第一个为默认图标，其余为 Assets 里的备用图标（AppIcon1...5）
    let styles: [Style] = [
        .init(id: "AppIcon",  name: "星海", colors: [Color(hex: 0x4F8DFD), Color(hex: 0x7C4DFF)]),
        .init(id: "AppIcon1", name: "朝霞", colors: [Color(hex: 0xFF9A62), Color(hex: 0xFF5F8F)]),
        .init(id: "AppIcon2", name: "极光", colors: [Color(hex: 0x2ED6C4), Color(hex: 0x38A3FF)]),
        .init(id: "AppIcon3", name: "樱紫", colors: [Color(hex: 0xB388FF), Color(hex: 0xFF8BCB)]),
        .init(id: "AppIcon4", name: "琥珀", colors: [Color(hex: 0xFFC24B), Color(hex: 0xFF8A3D)]),
    ]

    @Published var current: String = UIApplication.shared.alternateIconName ?? "AppIcon"

    func set(_ id: String) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target: String? = (id == "AppIcon") ? nil : id
        UIApplication.shared.setAlternateIconName(target) { [weak self] err in
            DispatchQueue.main.async {
                if err == nil {
                    self?.current = id
                    BBHaptic.success()
                } else {
                    BBHaptic.warn()
                }
            }
        }
    }
}
