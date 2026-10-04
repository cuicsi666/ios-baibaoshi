import SwiftUI
import Charts

// MARK: - 主页（V9 视觉层重构：统一 BB 设计系统）

struct CBHomeView: View {
    @EnvironmentObject var m: BatteryMonitor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: BBSpacing.l) {
                // 顶部充电大环
                RingCard()

                if m.isPlugged {
                    StatsRow()       // 状态统计块
                    EstimateCard()   // 预估信息卡
                    ChartCard()      // 本次充电曲线
                } else {
                    IdleCard()
                }

                CBV9HistoryEntry()   // 历史入口

                // 控制入口固定在页面底部（SettingsView 亦以此说明）
                CBV9NotifySection()
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Theme.gradient(Theme.charge))
                    Text("电管家").font(.headline)
                }
            }
        }
    }
}

// MARK: - 电量圆环卡（顶部大环）

struct RingCard: View {
    @EnvironmentObject var m: BatteryMonitor
    @Environment(\.colorScheme) private var scheme
    @State private var pulse = false

    private var levelText: String { m.level >= 0 ? "\(m.level)" : "--" }
    private var ringColors: [Color] { BatteryTheme.colors(for: max(m.level, 0)) }
    private var progress: Double { Double(max(m.level, 0)) / 100 }
    private var glow: Double { m.isPlugged ? (pulse ? 1.0 : 0.5) : 0.35 }

    var body: some View {
        BBCard(padding: BBSpacing.l, radius: BBRadius.xl) {
            VStack(spacing: 18) {
                ring
                summary
            }
        }
        .onAppear { startPulse() }
        .onChange(of: m.isPlugged) { _ in startPulse() }
    }

    // MARK: 大环本体

    private var ring: some View {
        ZStack {
            // 强调色光晕（充电时随呼吸脉动）
            Circle()
                .fill(Theme.gradient(ringColors))
                .frame(width: 186, height: 186)
                .blur(radius: 46)
                .opacity(0.20 * glow)

            // 底轨
            Circle()
                .stroke(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
                        lineWidth: 18)

            // 电量弧
            Circle()
                .trim(from: 0, to: CGFloat(max(progress, 0.001)))
                .stroke(AngularGradient(colors: ringColors + [ringColors[0]],
                                        center: .center,
                                        startAngle: .degrees(-90),
                                        endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColors[0].opacity(0.18 + 0.35 * glow),
                        radius: m.isPlugged ? (pulse ? 15 : 8) : 5)
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: m.level)

            // 中央读数
            VStack(spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(levelText)
                        .font(BBFont.num(66))
                    Text("%")
                        .font(BBFont.head(22))
                        .foregroundColor(.secondary)
                }
                .animation(.easeInOut(duration: 0.25), value: m.level)

                BBPill(text: stateText, color: stateColor)

                if m.isPlugged, let est = m.estimate {
                    Text("预计 \(est.doneAtText) 充满")
                        .font(BBFont.cap(11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(6)
        }
        .frame(width: 230, height: 230)
        .frame(maxWidth: .infinity)
    }

    // MARK: 环下摘要（目标 + 进度条）

    private var summary: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                BBPill(text: "目标 \(m.targetLevel)%", color: Theme.teal)
                if m.isPlugged, m.level >= 0, let s = m.session {
                    Text("本次已充 +\(max(m.level - s.startLevel, 0))%")
                        .font(BBFont.cap(12))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                if m.isPlugged, m.level >= 0, m.level < m.targetLevel {
                    Text("还差 \(m.targetLevel - m.level)%")
                        .font(BBFont.cap(12))
                        .foregroundColor(.secondary)
                }
            }
            BBMeter(value: progress, colors: ringColors, height: 6)
        }
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
        BBCard(padding: BBSpacing.l, radius: BBRadius.l) {
            VStack(alignment: .leading, spacing: 14) {
                BBSectionHeader(title: "充电预估", icon: "gauge.with.needle", colors: Theme.charge) {
                    if let est = m.estimate {
                        BBPill(text: est.sourceNote, color: Theme.teal)
                    }
                }

                if let est = m.estimate {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("约 \(est.timeText)")
                                .font(BBFont.num(30))
                                .foregroundStyle(Theme.lineGradient)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)

                            Text("后充至 \(m.targetLevel)% · \(est.doneAtText) 完成")
                                .font(BBFont.cap(12))
                                .foregroundColor(.secondary)

                            HStack(spacing: 6) {
                                BBPill(text: est.rateText, color: Theme.teal)
                                BBPill(text: curveShortName(est.curveName), color: Theme.sky)
                            }
                        }
                        Spacer(minLength: 0)
                        BBRing(progress: progress,
                               lineWidth: 9,
                               colors: Theme.charge,
                               label: "\(Int(progress * 100))%",
                               caption: "目标进度")
                    }

                    // 目标进度条
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("当前 \(max(m.level, 0))%")
                            Spacer()
                            Text("目标 \(m.targetLevel)%")
                        }
                        .font(BBFont.cap(11))
                        .foregroundColor(.secondary)

                        BBMeter(value: progress, colors: [Theme.mint, Theme.sky], height: 8)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: (m.state == .full || m.level >= m.targetLevel) ? "checkmark.seal.fill" : "hourglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.gradient(Theme.charge))
                        Text(m.state == .full || m.level >= m.targetLevel
                             ? "已达目标电量 \(m.level)% ✅"
                             : "正在采样充电速率，稍候出预估…")
                            .font(BBFont.body(13))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                            .fill(Theme.panel(scheme == .dark))
                    )
                }
            }
        }
    }

    private var progress: Double {
        let target = Double(m.targetLevel)
        let start = Double(m.session?.startLevel ?? m.level)
        let cur = Double(m.level)
        guard target > start else { return 0 }
        return min(max((cur - start) / (target - start), 0.02), 1)
    }

    private func curveShortName(_ s: String) -> String {
        s.contains("iPhone") ? String(s.split(separator: "·").first ?? "").trimmingCharacters(in: .whitespaces) : s
    }
}

// MARK: - 本次充电曲线卡（Swift Charts）

struct ChartCard: View {
    @EnvironmentObject var m: BatteryMonitor
    @EnvironmentObject var h: ChargeHistory
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        BBCard(padding: BBSpacing.l, radius: BBRadius.l) {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader(title: "充电曲线", icon: "chart.xyaxis.line") {
                    if let s = m.session {
                        BBPill(text: chartStartText(s.start), color: Theme.accent)
                    }
                }

                if sessionPoints.count >= 2 {
                    chart
                    legend
                } else {
                    emptyChart
                }
            }
        }
    }

    // MARK: 数据源（仅来自 BatteryMonitor.session 与 ChargeHistory.sessions）

    /// 本次会话曲线：x = 会话开始后的分钟数，y = 电量
    private var sessionPoints: [CBV9ChartPoint] {
        guard let s = m.session else { return [] }
        var out: [CBV9ChartPoint] = []
        for (i, p) in s.points.enumerated() {
            out.append(CBV9ChartPoint(id: "cur-\(i)",
                                      mins: p.t.timeIntervalSince(s.start) / 60,
                                      level: p.level,
                                      series: "本次"))
        }
        return out
    }

    /// 历史会话曲线（最近 3 次，灰蓝虚线作对照）：x 同样用「会话开始后分钟数」
    private var historyPoints: [CBV9ChartPoint] {
        var out: [CBV9ChartPoint] = []
        for (i, s) in h.sessions.prefix(3).enumerated() {
            for (j, p) in s.points.enumerated() {
                out.append(CBV9ChartPoint(id: "his-\(i)-\(j)",
                                          mins: p.t.timeIntervalSince(s.start) / 60,
                                          level: p.level,
                                          series: "历史 \(i + 1)"))
            }
        }
        return out
    }

    private var chart: some View {
        Chart {
            ForEach(historyPoints) { p in
                LineMark(x: .value("分钟", p.mins),
                         y: .value("电量", p.level),
                         series: .value("系列", p.series))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.accent.opacity(0.26))
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 4]))
            }

            ForEach(sessionPoints) { p in
                AreaMark(x: .value("分钟", p.mins),
                         y: .value("电量", p.level))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [Theme.teal.opacity(0.26), Theme.teal.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))

                LineMark(x: .value("分钟", p.mins),
                         y: .value("电量", p.level),
                         series: .value("系列", p.series))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.lineGradient)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                PointMark(x: .value("分钟", p.mins),
                          y: .value("电量", p.level))
                    .foregroundStyle(Theme.mint)
                    .symbolSize(20)
            }

            RuleMark(y: .value("目标", m.targetLevel))
                .foregroundStyle(Theme.warning.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("目标 \(m.targetLevel)%")
                        .font(BBFont.cap(10))
                        .foregroundColor(Theme.warning)
                }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.hairline(scheme == .dark))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(axisMinutes(v))
                            .font(BBFont.cap(10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(Theme.hairline(scheme == .dark))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%")
                            .font(BBFont.cap(10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(height: 168)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: Theme.teal, text: "本次")
            if !historyPoints.isEmpty {
                legendItem(color: Theme.accent.opacity(0.5), text: "历史")
            }
            legendItem(color: Theme.warning.opacity(0.7), text: "目标线")
            Spacer(minLength: 0)
            if let s = m.session {
                Text("已记录 \(s.points.count) 个点")
                    .font(BBFont.cap(10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(BBFont.cap(10)).foregroundColor(.secondary)
        }
    }

    private var emptyChart: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.gradient(Theme.charge))
            Text("电量变化后自动绘制曲线")
                .font(BBFont.cap(12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                .fill(Theme.panel(scheme == .dark))
        )
    }

    private func chartStartText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d) + " 开始"
    }

    private func axisMinutes(_ mins: Double) -> String {
        let v = Int(mins.rounded())
        if v < 60 { return "\(v)分" }
        return "\(v / 60)时\(v % 60)分"
    }
}

// MARK: - 状态统计块（三栏 BBStat）

struct StatsRow: View {
    @EnvironmentObject var m: BatteryMonitor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        BBCard(padding: BBSpacing.l, radius: BBRadius.l) {
            VStack(alignment: .leading, spacing: 14) {
                BBSectionHeader(title: "实时状态", icon: "waveform.path.ecg", colors: [Theme.mint, Theme.teal]) {
                    BBPill(text: m.isPlugged ? "充电中" : "使用电池",
                           color: m.isPlugged ? Theme.teal : Color.secondary)
                }

                HStack(alignment: .top, spacing: 10) {
                    BBStat(label: "本次已充",
                           value: "+\(m.session.map { max(m.level - $0.startLevel, 0) } ?? 0)",
                           unit: "%",
                           icon: "plus.circle.fill",
                           colors: [Theme.mint, Theme.teal])

                    divider

                    BBStat(label: "实时速率",
                           value: rateValue,
                           unit: "%/分",
                           icon: "speedometer",
                           colors: [Theme.teal, Theme.sky])

                    divider

                    BBStat(label: "已充时长",
                           value: m.sessionDurationText,
                           icon: "timer",
                           colors: [Theme.sky, Theme.accent])
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline(scheme == .dark))
            .frame(width: 1, height: 36)
    }

    private var rateValue: String {
        guard let r = m.liveRate() else { return "--" }
        return String(format: "%.1f", r)
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
        BBCard(padding: BBSpacing.l, radius: BBRadius.l) {
            VStack(spacing: 14) {
                BBEmptyState(icon: "powerplug.fill",
                             title: "未接入充电器",
                             message: "插上充电器后自动开始监控\n每充 +5% 通知电量和充满预估",
                             colors: Theme.charge)

                if let avg = h.averageFullDurationMinutes {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.gradient([Theme.teal, Theme.sky]))
                        Text("根据历史，充满约需 \(avgText(avg))")
                            .font(BBFont.cap(12))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                            .fill(Theme.panel(scheme == .dark))
                    )
                }
            }
        }
    }

    private func avgText(_ mins: Double) -> String {
        let m = Int(mins.rounded())
        return m >= 60 ? "\(m / 60) 小时 \(m % 60) 分" : "\(m) 分钟"
    }
}

// MARK: - 通知控制容器（内部仍为 ChargeNotifyCard，功能入口完全保留）

fileprivate struct CBV9NotifySection: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ChargeNotifyCard()
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.16), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: Theme.accent.opacity(scheme == .dark ? 0.20 : 0.09), radius: 16, y: 7)
    }
}

// MARK: - 历史入口

fileprivate struct CBV9HistoryEntry: View {
    @EnvironmentObject var h: ChargeHistory
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationLink(destination: CBHistoryView()) {
            BBCard(padding: 14, radius: BBRadius.m) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.gradient(Theme.charge))
                            .frame(width: 34, height: 34)
                            .shadow(color: Theme.mint.opacity(0.35), radius: 5, y: 3)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("充电历史").font(BBFont.head(15))
                        Text(subtitle).font(BBFont.cap(11)).foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if h.sessions.isEmpty { return "暂无记录 · 拔电后自动保存" }
        guard let avg = h.averageFullDurationMinutes else { return "\(h.sessions.count) 次记录" }
        let mins = Int(avg.rounded())
        let t = mins >= 60 ? "\(mins / 60)时\(mins % 60)分" : "\(mins)分钟"
        return "\(h.sessions.count) 次记录 · 平均充满 \(t)"
    }
}

// MARK: - 曲线数据点（仅由现有 ChargePoint 映射，不新增采集字段）

fileprivate struct CBV9ChartPoint: Identifiable {
    let id: String
    let mins: Double
    let level: Int
    let series: String
}
