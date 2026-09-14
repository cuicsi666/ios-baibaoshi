import SwiftUI
import Charts

struct RouterMonitorView: View {
    @EnvironmentObject var router: RouterPoller
    @State private var editMode = false
    @State private var draftURL = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(icon: "wifi.router.fill", colors: Theme.router, title: "路由器监控", subtitle: "OpenWrt sysmon 接口 · 每 5 秒自动刷新")

                if !router.online {
                    offline
                } else if let s = router.sys {
                    headCard(s)
                    cpuCard(s)
                    tempCard(s)
                    memoryCard(s)
                    statsCard(s)
                }

                urlEditor
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .refreshable { router.refresh() }
    }

    private var offline: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 44)).foregroundColor(.secondary)
            Text("路由器不在线 / 接口无响应").font(.subheadline).foregroundColor(.secondary)
            Button("重试") { router.refresh() }
                .buttonStyle(.borderedProminent).tint(Theme.router[0])
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private func headCard(_ s: Sysmon) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.gradient(Theme.router)).frame(width: 54, height: 54)
                Image(systemName: "checkmark").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(s.host).font(.title3.bold())
                Text("\(s.model) · 已在线 \(uptimeText(s.uptime))").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(spacing: 2) {
                Image(systemName: "person.3.fill").font(.subheadline).foregroundColor(Theme.router[0])
                Text("\(s.leases) 台").font(.caption.weight(.semibold))
                Text("在线设备").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private func cpuCard(_ s: Sysmon) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CPU 使用率").font(.headline)
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(s.cpu, 100)) / 100)
                        .stroke(Theme.gradient(Theme.router), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring, value: s.cpu)
                    Text("\(Int(s.cpu))%").font(.system(size: 20, weight: .heavy, design: .rounded))
                }
                .frame(width: 86, height: 86)
                Chart(router.history.indices.map { i in (i, router.history[i]) }, id: \.0) { pair in
                    LineMark(x: .value("t", pair.0), y: .value("cpu", pair.1))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.router[1].gradient)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    AreaMark(x: .value("t", pair.0), y: .value("cpu", pair.1))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.linearGradient(colors: [Theme.router[1].opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { AxisValueLabel().font(.caption2) }
                }
                .frame(height: 100)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private func tempCard(_ s: Sysmon) -> some View {
        HStack(spacing: 14) {
            if let t = s.temp {
                Image(systemName: "thermometer.medium").font(.system(size: 30))
                    .foregroundColor(tempColor(t))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f ℃", t)).font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("CPU 温度 · " + tempLabel(t)).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Gauge(value: t, in: 30...90) {
                    Text("温度")
                }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(tempColor(t))
                    .frame(width: 90)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private func memoryCard(_ s: Sysmon) -> some View {
        let total = Double(s.memTotal)
        let used = Double(s.memUsed) / total
        let buff = Double(s.memBuff) / total
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("内存").font(.headline)
                Spacer()
                Text("\(mb(s.memUsed)) / \(mb(s.memTotal))").font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(Theme.gradient(Theme.router)).frame(width: geo.size.width * used)
                    Rectangle().fill(Theme.router[1].opacity(0.35)).frame(width: geo.size.width * buff)
                }
                .frame(height: 12, alignment: .leading)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .animation(.spring, value: used)
            }
            .frame(height: 12)
            HStack(spacing: 14) {
                dot(Theme.router[0], "已用 \(Int(used * 100))%")
                dot(Theme.router[1].opacity(0.35), "缓存 \(Int(buff * 100))%")
                dot(.white.opacity(0.15), "可用 \(mb(s.memAvail))")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private func statsCard(_ s: Sysmon) -> some View {
        HStack(spacing: 10) {
            statBox("负载 1m", String(format: "%.2f", s.load1))
            statBox("负载 5m", String(format: "%.2f", s.load5))
            statBox("负载 15m", String(format: "%.2f", s.load15))
        }
    }

    private func statBox(_ k: String, _ v: String) -> some View {
        VStack(spacing: 4) {
            Text(v).font(.system(size: 22, weight: .heavy, design: .rounded))
            Text(k).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
    }

    private var urlEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { editMode = true; draftURL = router.urlString } label: {
                Label("接口地址设置", systemImage: "gearshape").font(.caption).foregroundColor(.secondary)
            }
            .sheet(isPresented: $editMode) {
                NavigationStack {
                    Form {
                        Section("sysmon 接口 URL") {
                            TextField("http://6.6.6.1:8080/cgi-bin/sysmon", text: $draftURL)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Button("保存并刷新") {
                                router.urlString = draftURL
                                router.refresh()
                                editMode = false
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // helpers
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
    private func dot(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(s).font(.caption2).foregroundColor(.secondary)
        }
    }
    private func uptimeText(_ sec: Int) -> String {
        let d = sec / 86400, h = (sec % 86400) / 3600, m = (sec % 3600) / 60
        if d > 0 { return "\(d)天\(h)小时" }
        if h > 0 { return "\(h)小时\(m)分" }
        return "\(m)分钟"
    }
}
