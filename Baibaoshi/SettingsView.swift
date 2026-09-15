import SwiftUI

// MARK: - 百宝箱设置（主题 / 保活 / 充电监控 / 数据 / 关于）

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

    private var logSummary: String {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.log")
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int, size > 0 else {
            return "暂无"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var body: some View {
        Form {
            Section("外观") {
                Picker(selection: $theme.isDark) {
                    Text("浅色（默认）").tag(false)
                    Text("深色").tag(true)
                } label: {
                    Label("主题", systemImage: theme.isDark ? "moon.fill" : "sun.max.fill")
                }
            }

            softwareUpdateSection

            Section {
                Toggle(isOn: $keepAliveOn) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("后台常驻保活")
                        Text("低功耗定位保持 App 活跃，充电播报 / XUI 蓝牙 / 流文连接全时段在线")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: keepAliveOn) { _ in
                    KeepAliveService.shared.applySettings()
                }
                HStack {
                    Label("定位权限", systemImage: "location.fill")
                    Spacer()
                    Text(authText)
                        .foregroundColor(authColor)
                        .font(.system(size: 13, weight: .medium))
                }
                if keepAlive.locationAuth != .authorizedAlways {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("去系统设置开启「始终允许」", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            } header: {
                Text("后台保活")
            } footer: {
                Text("定位仅用于系统保活（3 公里低精度，不采集不上报），配合充电时不可闻音轨双保险")
            }

            Section("充电监控") {
                HStack {
                    Label("控制入口", systemImage: "bolt.fill")
                    Spacer()
                    Text("电管家模块页底部").font(.system(size: 13)).foregroundColor(.secondary)
                }
                HStack {
                    Label("历史会话", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text("\(chargeHistory.sessions.count) 次").foregroundColor(.secondary)
                }
                Button(role: .destructive) {
                    showClearAlert = true
                } label: {
                    Label("清除充电历史", systemImage: "trash")
                }
                .disabled(chargeHistory.sessions.isEmpty)
            }

            Section {
                HStack {
                    Label("本地日志", systemImage: "doc.text")
                    Spacer()
                    Text(logSummary).font(.system(size: 12)).foregroundColor(.secondary)
                }
                Button {
                    uploadMsg = "上传中…"
                    AppLog.log("Diag", "手动上传日志")
                    AppLog.upload { msg in uploadMsg = msg }
                } label: {
                    Label("上传日志到服务器", systemImage: "icloud.and.arrow.up")
                }
                if !uploadMsg.isEmpty {
                    Text(uploadMsg).font(.system(size: 11)).foregroundColor(.secondary)
                }
            } header: {
                Text("诊断日志")
            } footer: {
                Text("日志记录模块运行与崩溃现场，出问题时上传给小龙虾分析")
            }

            Section("关于") {
                HStack {
                    Label("版本", systemImage: "app.badge.fill")
                    Spacer()
                    Text("2.0 (2)").foregroundColor(.secondary)
                }
                HStack(alignment: .top) {
                    Label("模块", systemImage: "square.grid.2x2")
                    Spacer()
                    Text("电管家 · 流文 · 工具七件套")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background(scheme))
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("清除全部充电历史？", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { chargeHistory.clear() }
        } message: {
            Text("清除后充电预估将回到纯参考曲线模式")
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

    // MARK: 软件更新（Gitea Release → 飞牛静态分发 → 全能签安装）

    @ViewBuilder private var softwareUpdateSection: some View {
        Section("软件更新") {
            if updater.checking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在检查更新…").foregroundColor(.secondary)
                }
            } else if updater.hasUpdate {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                        Text("发现新版本 V\(updater.newVersion)")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("当前 V\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1")")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if !updater.releaseNotes.isEmpty {
                        Text(updater.releaseNotes)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(6)
                    }
                }

                if updater.downloading {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: updater.downloadProgress)
                        Text("下载中 \(Int(updater.downloadProgress * 100))%")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else if updater.downloadedIPA != nil {
                    Button {
                        showShare = true
                    } label: {
                        Label("安装更新（选择全能签）", systemImage: "square.and.arrow.up.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                } else {
                    Button {
                        updater.download()
                    } label: {
                        Label("下载更新包", systemImage: "arrow.down.circle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                if !updater.message.isEmpty {
                    Text(updater.message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Button {
                    updater.check { _ in }
                } label: {
                    Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                }
                if !updater.message.isEmpty {
                    Text(updater.message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Label("当前版本", systemImage: "app.badge.fill")
                    Spacer()
                    Text("V\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1")")
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let vc = updater.shareSheet() {
                ShareSheet(vc: vc)
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - UIActivityViewController 包装（分享给全能签）

struct ShareSheet: UIViewControllerRepresentable {
    let vc: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { vc }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}
