import SwiftUI

// MARK: - ESXi 监控数据模型

struct ESXiStats {
    var host: String = ""
    var cpu: Double = 0
    var memory: Double = 0
    var memoryTotal: Int = 0
    var memoryUsed: Int = 0
    var datastore: Double = 0
    var datastoreTotal: Int = 0
    var datastoreUsed: Int = 0
    var temp: Double = 0
    var uptime: Int = 0
    var vms: [VMInfo] = []
}

struct VMInfo: Identifiable {
    let id = UUID()
    var name: String
    var state: String // poweredOn/powerOff/suspended
    var guestOS: String
}

// MARK: - ESXi 监控视图

struct ESXiMonitorView: View {
    @State private var stats = ESXiStats()
    @State private var loading = false
    @State private var error: String?
    @State private var editMode = false
    @State private var draftHost = ""
    @State private var draftUser = ""
    @State private var draftPass = ""
    @AppStorage("esxi.host") private var host = "6.6.6.149"
    @AppStorage("esxi.user") private var user = "root"
    @AppStorage("esxi.pass") private var pass = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(icon: "server.rack", colors: Theme.xui, title: "ESXi 监控", subtitle: "SOAP API · 手动刷新")

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if let error = error {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundColor(.orange)
                        Text(error).font(.subheadline).foregroundColor(.secondary)
                        Button("重试") { Task { await refresh() } }
                            .buttonStyle(.borderedProminent).tint(Theme.xui[0])
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 46)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                } else {
                    headCard
                    cpuCard
                    memoryCard
                    datastoreCard
                    if stats.temp > 0 { tempCard }
                    vmListCard
                }

                settingsButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .refreshable { Task { await refresh() } }
        .onAppear { if stats.host.isEmpty { Task { await refresh() } } }
        .sheet(isPresented: $editMode) {
            NavigationStack {
                Form {
                    Section("ESXi 主机") {
                        TextField("IP 或域名", text: $draftHost).keyboardType(.URL).autocorrectionDisabled()
                        TextField("用户名", text: $draftUser).autocorrectionDisabled()
                        SecureField("密码", text: $draftPass)
                        Button("保存并刷新") {
                            host = draftHost; user = draftUser; pass = draftPass
                            editMode = false
                            Task { await refresh() }
                        }
                    }
                }
                .navigationTitle("ESXi 设置")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var headCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.gradient(Theme.xui)).frame(width: 54, height: 54)
                Image(systemName: "checkmark").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(stats.host.isEmpty ? "未连接" : stats.host).font(.title3.bold())
                Text(stats.uptime > 0 ? "已运行 \(uptimeText(stats.uptime))" : "ESXi 主机").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CPU 使用率").font(.headline)
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(stats.cpu, 100)) / 100)
                        .stroke(Theme.gradient(Theme.xui), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring, value: stats.cpu)
                    Text("\(Int(stats.cpu))%").font(.system(size: 20, weight: .heavy, design: .rounded))
                }
                .frame(width: 86, height: 86)
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    statRow("核心数", "—")
                    statRow("频率", "—")
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("内存").font(.headline)
                Spacer()
                Text("\(mb(stats.memoryUsed)) / \(mb(stats.memoryTotal))").font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(Theme.gradient(Theme.xui)).frame(width: geo.size.width * stats.memory / 100)
                }
                .frame(height: 12, alignment: .leading)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .animation(.spring, value: stats.memory)
            }
            .frame(height: 12)
            HStack {
                dot(Theme.xui[0], "已用 \(Int(stats.memory))%")
                Spacer()
                dot(.white.opacity(0.15), "可用 \(mb(stats.memoryTotal - stats.memoryUsed))")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private var datastoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("存储").font(.headline)
                Spacer()
                Text("\(mb(stats.datastoreUsed)) / \(mb(stats.datastoreTotal))").font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(Theme.gradient(Theme.xui)).frame(width: geo.size.width * stats.datastore / 100)
                }
                .frame(height: 12, alignment: .leading)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .animation(.spring, value: stats.datastore)
            }
            .frame(height: 12)
            HStack {
                dot(Theme.xui[0], "已用 \(Int(stats.datastore))%")
                Spacer()
                dot(.white.opacity(0.15), "可用 \(mb(stats.datastoreTotal - stats.datastoreUsed))")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private var tempCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "thermometer.medium").font(.system(size: 30)).foregroundColor(tempColor(stats.temp))
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f ℃", stats.temp)).font(.system(size: 26, weight: .heavy, design: .rounded))
                Text("CPU 温度 · " + tempLabel(stats.temp)).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private var vmListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("虚拟机 (\(stats.vms.count))").font(.headline)
            if stats.vms.isEmpty {
                Text("暂无虚拟机").font(.caption).foregroundColor(.secondary).padding(.vertical, 20).frame(maxWidth: .infinity)
            } else {
                ForEach(stats.vms) { vm in
                    HStack {
                        Circle().fill(vm.state == "poweredOn" ? .green : .gray).frame(width: 8, height: 8)
                        Text(vm.name).font(.subheadline)
                        Spacer()
                        Text(vm.state == "poweredOn" ? "运行中" : "已关机").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private var settingsButton: some View {
        Button {
            draftHost = host; draftUser = user; draftPass = pass
            editMode = true
        } label: {
            Label("ESXi 连接设置", systemImage: "gearshape").font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 数据获取

    private func refresh() async {
        loading = true
        error = nil
        // TODO: 调用 SOAP API 获取数据（暂时用模拟数据）
        try? await Task.sleep(nanoseconds: 500_000_000)
        stats = ESXiStats(host: host, cpu: 35, memory: 62, memoryTotal: 32768, memoryUsed: 20316, datastore: 45, datastoreTotal: 102400, datastoreUsed: 46080, temp: 52, uptime: 864000, vms: [
            VMInfo(name: "Ubuntu", state: "poweredOn", guestOS: "Ubuntu Linux"),
            VMInfo(name: "Windows 10", state: "poweredOff", guestOS: "Windows 10")
        ])
        loading = false
    }

    // helpers
    private func statRow(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.caption).foregroundColor(.secondary); Spacer(); Text(v).font(.caption.monospacedDigit()) }
    }
    private func tempColor(_ t: Double) -> Color { t < 50 ? .green : t < 65 ? .orange : .red }
    private func tempLabel(_ t: Double) -> String { t < 50 ? "凉爽 ✅" : t < 65 ? "正常" : "偏高 ⚠️" }
    private func mb(_ kb: Int) -> String { kb >= 1024 ? "\(kb/1024)GB" : "\(kb)MB" }
    private func dot(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 8, height: 8); Text(s).font(.caption2).foregroundColor(.secondary) }
    }
    private func uptimeText(_ sec: Int) -> String {
        let d = sec/86400, h = (sec%86400)/3600, m = (sec%3600)/60
        if d > 0 { return "\(d)天\(h)小时" }; if h > 0 { return "\(h)小时\(m)分" }; return "\(m)分钟"
    }
}
