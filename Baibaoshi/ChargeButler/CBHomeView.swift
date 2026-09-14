import SwiftUI
import Charts

// MARK: - 主页

struct CBHomeView: View {
    @EnvironmentObject var m: BatteryMonitor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    RingCard()
                    if m.isPlugged {
                        EstimateCard()
                        ChartCard()
                        StatsRow()
                    } else {
                        IdleCard()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .background(Theme.background(scheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(Theme.heroGradient)
                        Text("电管家").font(.headline)
                    }
                }
            }
        }
    }
}

// MARK: - 电量圆环卡

struct RingCard: View {
    @EnvironmentObject var m: BatteryMonitor
    @Environment(\.colorScheme) private var scheme
    @State private var pulse = false

    private var levelText: String { m.level >= 0 ? "\(m.level)" : "--" }
    private var ringColors: [Color] { BatteryTheme.colors(for: max(m.level, 0)) }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // 底轨
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 20)
                // 电量弧
                Circle()
                    .trim(from: 0, to: CGFloat(max(m.level, 4)) / 100)
                    .stroke(AngularGradient(colors: ringColors + [ringColors[0]],
                                            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColors[0].opacity(m.isPlugged ? (pulse ? 0.75 : 0.35) : 0.25),
                            radius: m.isPlugged ? (pulse ? 16 : 8) : 5)
                    .animation(.spring(response: 0.7, dampingFraction: 0.85), value: m.level)
                // 中央信息
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(levelText)
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .animation(.easeInOut(duration: 0.3), value: m.level)

                    HStack(spacing: 6) {
                        Image(systemName: stateIcon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(stateText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(stateColor.opacity(0.16)))
                    .foregroundColor(stateColor)
                }
            }
            .frame(width: 240, height: 240)

            if m.isPlugged, m.level >= 0, let s = m.session {
                Text("本次已充 +\(max(m.level - s.startLevel, 0))% · 目标 \(m.targetLevel)%")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .cardStyle(scheme)
        .onAppear { startPulse() }
        .onChange(of: m.isPlugged) { _ in startPulse() }
    }

    private func startPulse() {
        guard m.isPlugged else { pulse = false; return }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    private var stateIcon: String {
        switch m.state {
        case .charging: return "bolt.fill"
        case .full: return "checkmark.seal.fill"
        default: return "battery.75"
        }
    }
    private var stateText: String {
        if m.state == .charging, let est = m.estimate { return "充电中 · 剩 \(est.timeText)" }
        return BatteryTheme.stateText(m.state)
    }
    private var stateColor: Color {
        switch m.state {
        case .charging: return Theme.teal
        case .full: return Theme.mint
        default: return Color.secondary
        }
    }
}

// MARK: - 充电预估卡

struct EstimateCard: View {
    @EnvironmentObject var m: BatteryMonitor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("充电预估", systemImage: "gauge.with.needle")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let est = m.estimate {
                    Text(est.sourceNote)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.teal.opacity(0.14)))
                        .foregroundColor(Theme.teal)
                }
            }

            if let est = m.estimate {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("约 \(est.timeText)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.heroGradient)
                    Text("后充至 \(m.targetLevel)%")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    chip(icon: "clock", text: "\(est.doneAtText) 完成")
                    chip(icon: "speedometer", text: est.rateText)
                    chip(icon: "waveform.path.ecg", text: curveShortName(est.curveName))
                }

                // 目标进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Theme.lineGradient)
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(response: 0.7, dampingFraction: 0.85), value: m.level)
                    }
                }
                .frame(height: 8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundColor(.secondary)
                    Text(m.state == .full || m.level >= m.targetLevel
                         ? "已达目标电量 \(m.level)% ✅"
                         : "正在采样充电速率，稍候出预估…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
        }
        .cardStyle(scheme)
    }

    private var progress: CGFloat {
        let target = CGFloat(m.targetLevel)
        let start = CGFloat(m.session?.startLevel ?? m.level)
        let cur = CGFloat(m.level)
        guard target > start else { return 0 }
        return min(max((cur - start) / (target - start), 0.02), 1)
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .foregroundColor(.primary.opacity(0.85))
    }

    private func curveShortName(_ s: String) -> String {
        s.contains("iPhone") ? String(s.split(separator: "·").first ?? "").trimmingCharacters(in: .whitespaces) : s
    }
}

// MARK: - 本次充电曲线卡（Swift Charts）

struct ChartCard: View {
    @EnvironmentObject var m: BatteryMonitor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("本次充电曲线", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let s = m.session {
                    Text(chartStartText(s.start))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            let pts = m.session?.points ?? []
            if pts.count >= 2 {
                Chart(pts) { p in
                    LineMark(x: .value("时间", p.t), y: .value("电量", p.level))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.lineGradient)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    AreaMark(x: .value("时间", p.t), y: .value("电量", p.level))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [Theme.teal.opacity(0.25), Theme.teal.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    PointMark(x: .value("时间", p.t), y: .value("电量", p.level))
                        .foregroundStyle(Theme.mint)
                        .symbolSize(22)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { v in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            if let l = v.as(Int.self) {
                                Text("\(l)%").font(.system(size: 10, design: .rounded)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 170)
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("电量变化后自动绘制曲线")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(height: 150)
            }
        }
        .cardStyle(scheme)
    }
    private func chartStartText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d) + " 开始"
    }
}

// MARK: - 统计行（三迷你卡）

struct StatsRow: View {
    @EnvironmentObject var m: BatteryMonitor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            mini(value: "+\(m.session.map { max(m.level - $0.startLevel, 0) } ?? 0)%",
                 label: "本次已充", icon: "plus.circle.fill", color: Theme.mint)
            mini(value: m.liveRateText,
                 label: "实时速率", icon: "speedometer", color: Theme.teal)
            mini(value: m.sessionDurationText,
                 label: "已充时长", icon: "timer", color: Theme.sky)
        }
    }

    private func mini(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(scheme == .dark ? Theme.card.opacity(0.92) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(scheme == .dark ? Theme.cardStroke : Color.black.opacity(0.05), lineWidth: 1))
        )
    }
}

extension BatteryMonitor {
    var liveRateText: String {
        guard let r = liveRate() else { return "--" }
        return String(format: "%.1f%%/分", r)
    }
    var sessionDurationText: String {
        guard let s = session else { return "--" }
        let mins = Int(s.durationMinutes)
        return mins >= 60 ? "\(mins / 60)时\(mins % 60)分" : "\(max(mins, 0))分钟"
    }
}

// MARK: - 未充电卡

struct IdleCard: View {
    @EnvironmentObject var m: BatteryMonitor
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var h: ChargeHistory

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "powerplug")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.heroGradient)
            Text("未接入充电器")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("插上充电器后自动开始监控\n每充 +5% 通知电量和充满预估")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let avg = h.averageFullDurationMinutes {
                Divider().background(Color.white.opacity(0.08))
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.teal)
                    Text("根据历史，充满约需 \(avgText(avg))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .cardStyle(scheme)
    }

    private func avgText(_ mins: Double) -> String {
        let m = Int(mins.rounded())
        return m >= 60 ? "\(m / 60) 小时 \(m % 60) 分" : "\(m) 分钟"
    }
}
