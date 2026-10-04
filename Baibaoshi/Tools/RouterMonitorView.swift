import SwiftUI
import Charts

struct RouterMonitorView: View {
    @EnvironmentObject var router: RouterPoller
    @Environment(\.colorScheme) private var scheme
    @State private var editMode = false
    @State private var draftURL = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "wifi.router.fill", colors: Theme.router,
                           title: "路由器监控",
                           subtitle: "OpenWrt sysmon 接口 · 每 5 秒自动刷新")

                statusBar

                if router.online, let s = router.sys {
                    cpuHero(s)

                    HStack(alignment: .top, spacing: 12) {
                        tempCard(s)
                        memCard(s)
                    }

                    loadCard(s)
                    devicesCard(s)
                    infoCard(s)
                } else {
                    offlineCard
                }

                urlEditor
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .refreshable { router.refresh() }
    }

    // MARK: - 连接状态胶囊

    private var statusBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                RM9PulseDot(color: router.online ? Theme.success : Theme.danger)
                Text(router.online ? "已连接" : "未连接")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(router.online ? Theme.success : Theme.danger)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill((router.online ? Theme.success : Theme.danger).opacity(0.14)))

            if router.online, let s = router.sys {
                Text(s.host)
                    .font(BBFont.cap(12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if !router.history.isEmpty {
                BBPill(text: "采样 \(router.history.count)/60", color: Theme.router[0])
            }
        }
    }

    // MARK: - CPU 大数字 + 历史曲线

    private func cpuHero(_ s: Sysmon) -> some View {
        let avg = router.history.isEmpty ? 0 : router.history.reduce(0, +) / Double(router.history.count)
        let peak = router.history.max() ?? 0

        return BBCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "cpu")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.gradient(Theme.router))
                            Text("CPU 使用率")
                                .font(BBFont.cap(12))
                                .foregroundColor(.secondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(Int(s.cpu.rounded()))")
                                .font(.system(size: 48, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.gradient(Theme.router))
                            Text("%")
                                .font(BBFont.head(18))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 6) {
                        BBPill(text: cpuLevelText(s.cpu), color: cpuLevelColor(s.cpu))
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("平均 \(Int(avg.rounded()))% · 峰值 \(Int(peak.rounded()))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            Text("近 \(router.history.count) 次采样")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if router.history.isEmpty {
                    RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                        .fill(Theme.panel(scheme == .dark))
                        .frame(height: 120)
                        .overlay(
                            Text("等待采样数据…")
                                .font(BBFont.cap(12))
                                .foregroundColor(.secondary)
                        )
                } else {
                    Chart {
                        ForEach(Array(router.history.indices), id: \.self) { i in
                            AreaMark(x: .value("采样", i), y: .value("CPU", router.history[i]))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(LinearGradient(colors: [Theme.router[1].opacity(0.45),
                                                                        Theme.router[1].opacity(0.02)],
                                                                startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("采样", i), y: .value("CPU", router.history[i]))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Theme.gradient(Theme.router))
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        }
                        RuleMark(y: .value("平均", avg))
                            .foregroundStyle(Theme.router[0].opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, lineDash: [3, 3]))
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(values: [0, 50, 100]) {
                            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                            AxisValueLabel().font(.caption2)
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    // MARK: - 温度 / 内存

    private func tempCard(_ s: Sysmon) -> some View {
        BBCard(padding: 14, radius: BBRadius.m) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.gradient([tempColor(s.temp ?? 0), tempColor(s.temp ?? 0).opacity(0.6)]))
                    Text("CPU 温度")
                        .font(BBFont.cap(12))
                        .foregroundColor(.secondary)
                }

                if let t = s.temp {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", t))
                            .font(BBFont.num(28))
                            .foregroundColor(tempColor(t))
                            .monospacedDigit()
                        Text("°C")
                            .font(BBFont.cap(12))
                            .foregroundColor(.secondary)
                    }
                    BBMeter(value: min(max(t / 100, 0.02), 1),
                            colors: [tempColor(t), tempColor(t).opacity(0.55)],
                            height: 8)
                    Text(tempLabel(t))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("--")
                        .font(BBFont.num(28))
                        .foregroundColor(.secondary)
                    Text("无温度传感器")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    BBMeter(value: 0, colors: Theme.router, height: 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func memCard(_ s: Sysmon) -> some View {
        let ratio = s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0
        let buffRatio = s.memTotal > 0 ? Double(s.memBuff) / Double(s.memTotal) : 0

        return BBCard(padding: 14, radius: BBRadius.m) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.gradient(Theme.router))
                    Text("内存")
                        .font(BBFont.cap(12))
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", ratio * 100))
                        .font(BBFont.num(28))
                        .foregroundStyle(Theme.gradient(Theme.router))
                        .monospacedDigit()
                    Text("%")
                        .font(BBFont.cap(12))
                        .foregroundColor(.secondary)
                }

                BBMeter(value: ratio, colors: Theme.router, height: 8)

                Text("\(mb(s.memUsed)) / \(mb(s.memTotal))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 10) {
                    RM9LegendDot(color: Theme.router[0], text: "已用 \(Int(ratio * 100))%")
                    RM9LegendDot(color: Theme.router[1].opacity(0.5), text: "缓存 \(Int(buffRatio * 100))%")
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 系统负载

    private func loadCard(_ s: Sysmon) -> some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("系统负载", icon: "gauge", colors: Theme.router)

                HStack(spacing: 10) {
                    BBStat(label: "1 分钟", value: String(format: "%.2f", s.load1),
                           icon: "clock", colors: Theme.router)
                    BBStat(label: "5 分钟", value: String(format: "%.2f", s.load5),
                           icon: "clock.arrow.circlepath", colors: Theme.router)
                    BBStat(label: "15 分钟", value: String(format: "%.2f", s.load15),
                           icon: "timer", colors: Theme.router)
                }

                BBMeter(value: min(max(s.load1 / 4.0, 0.02), 1),
                        colors: [loadColor(s.load1), loadColor(s.load1).opacity(0.55)],
                        height: 8)

                Text("可用内存 \(mb(s.memAvail)) · 负载判读以 1 分钟值为准")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 在线设备

    private func devicesCard(_ s: Sysmon) -> some View {
        BBCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.gradient(Theme.router))
                        .frame(width: 52, height: 52)
                        .shadow(color: Theme.router[1].opacity(0.4), radius: 8, y: 4)
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("在线设备")
                        .font(BBFont.cap(12))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(s.leases)")
                            .font(BBFont.num(30))
                            .monospacedDigit()
                        Text("台")
                            .font(BBFont.cap(12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 6)

                BBPill(text: "DHCP 租约", color: Theme.router[0])
            }
        }
    }

    // MARK: - 系统信息

    private func infoCard(_ s: Sysmon) -> some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("系统信息", icon: "info.circle.fill", colors: Theme.router)

                BBRow(title: "主机名", icon: "desktopcomputer", value: s.host, colors: Theme.router)
                Divider().opacity(0.5)
                BBRow(title: "型号", icon: "cpu", value: s.model, colors: Theme.router)
                Divider().opacity(0.5)
                BBRow(title: "运行时长", icon: "clock", value: uptimeText(s.uptime), colors: Theme.router)
            }
        }
    }

    // MARK: - 离线 / 未连接空状态

    private var offlineCard: some View {
        BBCard {
            VStack(spacing: 14) {
                BBEmptyState(icon: "wifi.exclamationmark",
                             title: "路由器不在线",
                             message: "未收到 sysmon 接口响应\n请检查网络连接与接口地址是否正确",
                             colors: [Theme.warning, Theme.danger])

                HStack(spacing: 12) {
                    BBPrimaryButton(title: "重试", icon: "arrow.clockwise", colors: Theme.router) {
                        router.refresh()
                    }
                    BBGhostButton(title: "配置地址", icon: "gearshape.fill") {
                        draftURL = router.urlString
                        editMode = true
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: - 接口设置（保留地址配置 + 手动刷新）

    private var urlEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            BBSectionHeader("接口设置", icon: "gearshape.fill", colors: Theme.router)

            BBCard(padding: 14, radius: BBRadius.m) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.gradient(Theme.router))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("sysmon 接口地址")
                                .font(BBFont.cap(12))
                                .foregroundColor(.secondary)
                            Text(router.urlString)
                                .font(BBFont.mono)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    HStack(spacing: 12) {
                        BBPrimaryButton(title: "刷新数据", icon: "arrow.clockwise", colors: Theme.router) {
                            router.refresh()
                        }
                        BBGhostButton(title: "修改地址", icon: "pencil") {
                            draftURL = router.urlString
                            editMode = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $editMode) { editorSheet }
    }

    private var editorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                BBSectionHeader("sysmon 接口 URL", icon: "link", colors: Theme.router)

                TextField("http://6.6.6.1:8080/cgi-bin/sysmon", text: $draftURL)
                    .font(BBFont.mono)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                            .fill(Theme.panel(scheme == .dark))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                            .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1)
                    )

                Text("示例：http://6.6.6.1:8080/cgi-bin/sysmon")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                BBPrimaryButton(title: "保存并刷新", icon: "checkmark", colors: Theme.router) {
                    router.urlString = draftURL
                    router.refresh()
                    editMode = false
                }

                Spacer(minLength: 0)
            }
            .padding(BBSpacing.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BBAuroraBackground(scheme: scheme))
            .navigationTitle("接口地址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editMode = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - helpers

    private func cpuLevelText(_ v: Double) -> String {
        if v < 30 { return "空闲" }
        if v < 70 { return "正常" }
        if v < 90 { return "繁忙" }
        return "过载 ⚠️"
    }

    private func cpuLevelColor(_ v: Double) -> Color {
        if v < 30 { return Theme.success }
        if v < 70 { return Theme.info }
        if v < 90 { return Theme.warning }
        return Theme.danger
    }

    private func loadColor(_ v: Double) -> Color {
        if v < 1.0 { return Theme.success }
        if v < 2.5 { return Theme.warning }
        return Theme.danger
    }

    private func tempColor(_ t: Double) -> Color {
        if t < 50 { return .green }
        if t < 65 { return .orange }
        return .red
    }

    private func tempLabel(_ t: Double) -> String {
        if t < 50 { return "凉爽 ✅" }
        if t < 65 { return "正常" }
        return "偏高 ⚠️"
    }

    private func mb(_ kb: Int) -> String { "\(kb / 1024)MB" }

    private func uptimeText(_ sec: Int) -> String {
        let d = sec / 86400, h = (sec % 86400) / 3600, m = (sec % 3600) / 60
        if d > 0 { return "\(d) 天 \(h) 小时 \(m) 分" }
        if h > 0 { return "\(h) 小时 \(m) 分" }
        return "\(m) 分钟"
    }
}

// MARK: - fileprivate 小组件（RM9 前缀防冲突）

private struct RM9PulseDot: View {
    var color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .scaleEffect(pulse ? 2.2 : 1.0)
                    .opacity(pulse ? 0 : 0.9)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

private struct RM9LegendDot: View {
    var color: Color
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
