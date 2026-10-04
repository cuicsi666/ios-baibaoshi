import SwiftUI
import Charts

// MARK: - AI 用量视图：今日花销 + 趋势图 + 历史记录
// 视觉层 V9 重构：BB 设计系统组件（Card/Stat/Ring/Meter/SectionHeader/Pill/EmptyState/Haptic）
// + Swift Charts 趋势柱状图。数据全部来自 AIUsageService 现有字段，未改动 Service。
// 保留功能：今日花销 / 电耗 / 请求 / Token / 本月 / 输入输出拆分 / 历史记录 / 下拉刷新 / 手动刷新。

struct AIUsageView: View {
    @StateObject private var usage = AIUsageService.shared
    @Environment(\.colorScheme) private var scheme

    /// 图表指标：0 花销 / 1 电耗 / 2 请求
    @State private var chartMode: Int = 0

    /// 页面身份色（沿用本页既有蓝紫 nav 色板）
    private var palette: [Color] { Theme.nav }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BBSpacing.l) {
                PageHeader(icon: "brain.head.profile", colors: palette, title: "AI 用量", subtitle: "ipix 网关 · 每日花销")

                if usage.loading && usage.lastUpdated.isEmpty {
                    AIU9LoadingCard(colors: palette)
                }

                if let err = usage.lastError {
                    AIU9ErrorCard(message: err) { usage.fetch() }
                }

                todayCard

                statsCard

                trendCard

                historySection

                statusRow
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: usage.history.count)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .refreshable { usage.fetch() }
        .onAppear { usage.fetch() }
    }

    // MARK: 今日花销（大数字 + 进度环）

    private var todayCard: some View {
        BBCard(padding: 18, radius: BBRadius.l) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "yensign.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.gradient(palette))
                            Text("今日花销")
                                .font(BBFont.cap(12))
                                .foregroundColor(.secondary)
                            BBPill(text: "30000 电 = ¥100", color: palette[0])
                        }
                        Text(usage.today.costDisplay)
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .foregroundStyle(Theme.gradient(palette))
                        Text("今日电耗 \(AIU9Fmt.credit(usage.today.credit)) 电")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                    BBRing(progress: monthProgress,
                           lineWidth: 9,
                           colors: palette,
                           label: AIU9Fmt.percent(monthProgress),
                           caption: "占本月")
                }

                if usage.today.promptTokens > 0 || usage.today.completionTokens > 0 {
                    tokenSplit
                }
            }
        }
    }

    /// 今日电耗占本月电耗的比例（用于进度环）
    private var monthProgress: Double {
        let month = usage.today.monthCredit
        guard month > 0 else { return 0 }
        return max(0, min(1, usage.today.credit / month))
    }

    /// 本月花销（沿用 30000 电 = ¥100 的换算）
    private var monthCostDisplay: String {
        AIU9Fmt.money(usage.today.monthCredit / 30000 * 100)
    }

    /// 输入 / 输出 Token 占比条
    private var tokenSplit: some View {
        let prompt = usage.today.promptTokens
        let completion = usage.today.completionTokens
        let total = max(1, prompt + completion)
        let outputShare = Double(completion) / Double(total)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("输入 \(AIU9Fmt.count(prompt))")
                    .font(BBFont.cap(11))
                    .foregroundColor(.secondary)
                Spacer(minLength: 6)
                Text("输出 \(AIU9Fmt.count(completion))")
                    .font(BBFont.cap(11))
                    .foregroundColor(.secondary)
            }
            BBMeter(value: outputShare, colors: palette, height: 7)
            Text("输入 / 输出 Token 占比")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.85))
        }
        .padding(.top, 2)
    }

    // MARK: 请求 / Token / 本月 统计块

    private var statsCard: some View {
        BBCard(padding: 14, radius: BBRadius.l) {
            HStack(alignment: .center, spacing: 10) {
                BBStat(label: "请求", value: AIU9Fmt.count(usage.today.requests), unit: "次",
                       icon: "arrow.up.arrow.down", colors: palette)
                statDivider
                BBStat(label: "Token", value: AIU9Fmt.count(usage.today.tokens), unit: "tok",
                       icon: "text.alignleft", colors: palette)
                statDivider
                BBStat(label: "本月", value: monthCostDisplay,
                       icon: "calendar", colors: palette)
            }
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.hairline(scheme == .dark))
            .frame(width: 1, height: 42)
    }

    // MARK: 趋势图（Swift Charts）

    /// 最近 14 天的数据，按日期升序
    private var chartDays: [AIUsageDay] {
        Array(usage.history.prefix(14)).sorted { $0.date < $1.date }
    }

    private var metricTitle: String {
        switch chartMode {
        case 1: return "电耗"
        case 2: return "请求"
        default: return "花销"
        }
    }

    private func metricValue(_ day: AIUsageDay) -> Double {
        switch chartMode {
        case 1: return day.credit
        case 2: return Double(day.requests)
        default: return day.cost
        }
    }

    private var metricMax: Double {
        chartDays.map { metricValue($0) }.max() ?? 0
    }

    private var metricSum: Double {
        chartDays.reduce(0) { $0 + metricValue($1) }
    }

    private var metricAvg: Double {
        chartDays.isEmpty ? 0 : metricSum / Double(chartDays.count)
    }

    private var trendCard: some View {
        BBCard(padding: 16, radius: BBRadius.l) {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader(title: "花销趋势", icon: "chart.bar.fill", colors: palette) {
                    Text(chartDays.isEmpty ? "暂无" : "近 \(chartDays.count) 天")
                        .font(BBFont.cap(11))
                        .foregroundColor(.secondary)
                }

                if chartDays.isEmpty {
                    BBEmptyState(icon: "chart.bar.xaxis",
                                 title: "暂无趋势数据",
                                 message: "拉取一次后自动累积每日记录",
                                 colors: palette)
                } else {
                    BBSegmented(options: [("花销", 0), ("电耗", 1), ("请求", 2)], selection: $chartMode)

                    Chart {
                        ForEach(chartDays) { day in
                            BarMark(
                                x: .value("日期", AIU9Fmt.shortDate(day.date)),
                                y: .value(metricTitle, metricValue(day))
                            )
                            .cornerRadius(5)
                            .foregroundStyle(Theme.gradient(palette))
                        }
                        if metricAvg > 0 {
                            RuleMark(y: .value("均值", metricAvg))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(Color.secondary.opacity(0.55))
                                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                                    Text("均值 \(AIU9Fmt.metric(metricAvg, mode: chartMode))")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                            AxisValueLabel().font(BBFont.cap(10))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisValueLabel().font(BBFont.cap(10))
                        }
                    }
                    .frame(height: 170)

                    HStack(spacing: 12) {
                        AIU9LegendItem(key: "最高", value: AIU9Fmt.metric(metricMax, mode: chartMode))
                        AIU9LegendItem(key: "均值", value: AIU9Fmt.metric(metricAvg, mode: chartMode))
                        AIU9LegendItem(key: "合计", value: AIU9Fmt.metric(metricSum, mode: chartMode))
                    }
                }
            }
        }
    }

    // MARK: 历史花销记录

    private var historySection: some View {
        BBCard(padding: 16, radius: BBRadius.l) {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader(title: "花销记录", icon: "clock.arrow.circlepath", colors: palette) {
                    Text("累计 \(usage.totalCostDisplay)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundColor(palette[0])
                }

                if usage.history.isEmpty {
                    BBEmptyState(icon: "tray",
                                 title: "暂无历史记录",
                                 message: "拉取一次后自动累积",
                                 colors: palette)
                } else {
                    VStack(spacing: 0) {
                        ForEach(usage.history) { day in
                            AIU9HistoryRow(day: day,
                                           isLatest: day.id == usage.history.first?.id,
                                           maxCost: historyMaxCost,
                                           showsDivider: day.id != usage.history.last?.id,
                                           colors: palette,
                                           dark: scheme == .dark)
                        }
                    }
                }
            }
        }
    }

    private var historyMaxCost: Double {
        usage.history.map { $0.cost }.max() ?? 0
    }

    // MARK: 底部状态 + 手动刷新

    private var statusRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(usage.lastUpdated.isEmpty ? "下拉刷新 · 或点按右侧按钮" : "更新于 \(usage.lastUpdated)")
                    .font(BBFont.cap(11))
                    .foregroundColor(.secondary)
                Text("数据来源：ipix 网关 · 每 30000 电 = ¥100")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.85))
            }
            Spacer(minLength: 0)
            Button { refresh() } label: {
                HStack(spacing: 6) {
                    if usage.loading {
                        ProgressView().scaleEffect(0.72)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(usage.loading ? "刷新中" : "刷新")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Theme.accent.opacity(0.12))
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(usage.loading)
        }
        .padding(.horizontal, 4)
    }

    private func refresh() {
        BBHaptic.tap()
        usage.fetch {
            if usage.lastError == nil { BBHaptic.success() } else { BBHaptic.warn() }
        }
    }
}

// MARK: - 数值格式化（仅用于展示，不改数据）

fileprivate enum AIU9Fmt {
    static func money(_ value: Double) -> String {
        String(format: "¥%.2f", value)
    }

    static func credit(_ value: Double) -> String {
        if value >= 100 || value == value.rounded() { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    static func count(_ value: Int) -> String {
        let d = Double(value)
        if d >= 1_000_000 { return String(format: "%.2fM", d / 1_000_000) }
        if d >= 10_000 { return String(format: "%.1fK", d / 1_000) }
        if d >= 1_000 { return String(format: "%.2fK", d / 1_000) }
        return "\(value)"
    }

    static func percent(_ value: Double) -> String {
        "\(Int((max(0, min(1, value)) * 100).rounded()))%"
    }

    static func shortDate(_ date: String) -> String {
        date.count >= 10 ? String(date.suffix(5)) : date
    }

    static func metric(_ value: Double, mode: Int) -> String {
        switch mode {
        case 1: return "\(credit(value)) 电"
        case 2: return "\(count(Int(value.rounded()))) 次"
        default: return money(value)
        }
    }
}

// MARK: - 加载中骨架卡片

fileprivate struct AIU9LoadingCard: View {
    var colors: [Color]
    @State private var pulse = false

    var body: some View {
        BBCard(padding: 16, radius: BBRadius.l) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.85)
                    Text("正在拉取今日用量…")
                        .font(BBFont.cap(13))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                AIU9SkeletonBar(widthRatio: 0.62, height: 34, colors: colors, pulse: pulse)
                HStack(spacing: 10) {
                    AIU9SkeletonBar(widthRatio: 1, height: 38, colors: colors, pulse: pulse)
                    AIU9SkeletonBar(widthRatio: 1, height: 38, colors: colors, pulse: pulse)
                    AIU9SkeletonBar(widthRatio: 1, height: 38, colors: colors, pulse: pulse)
                }
            }
        }
        .opacity(pulse ? 0.6 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

fileprivate struct AIU9SkeletonBar: View {
    var widthRatio: CGFloat
    var height: CGFloat
    var colors: [Color]
    var pulse: Bool

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.gradient(colors))
                .opacity(pulse ? 0.16 : 0.32)
                .frame(width: geo.size.width * widthRatio, height: height)
        }
        .frame(height: height)
    }
}

// MARK: - 错误提示卡片（带重试）

fileprivate struct AIU9ErrorCard: View {
    let message: String
    var onRetry: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.warning.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.warning)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("数据拉取失败")
                    .font(BBFont.cap(13))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Button {
                BBHaptic.tap()
                onRetry()
            } label: {
                Text("重试")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.warning)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.warning.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: BBRadius.l, style: .continuous)
                .fill(Theme.warning.opacity(scheme == .dark ? 0.10 : 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: BBRadius.l, style: .continuous)
                        .strokeBorder(Theme.warning.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

// MARK: - 单行历史记录（含相对花销条）

fileprivate struct AIU9HistoryRow: View {
    let day: AIUsageDay
    let isLatest: Bool
    let maxCost: Double
    let showsDivider: Bool
    var colors: [Color]
    var dark: Bool

    private var ratio: Double {
        guard maxCost > 0 else { return 0 }
        return max(0.03, min(1, day.cost / maxCost))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(day.dateDisplay)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if isLatest {
                    BBPill(text: "最新", color: Theme.success)
                }
                Spacer(minLength: 6)
                Text(day.costDisplay)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.gradient(colors))
            }
            BBMeter(value: ratio, colors: colors, height: 5)
            HStack(spacing: 12) {
                miniStat(icon: "bolt.fill", text: "\(AIU9Fmt.credit(day.credit)) 电")
                miniStat(icon: "arrow.up.arrow.down", text: "\(AIU9Fmt.count(day.requests)) 次")
                miniStat(icon: "text.alignleft", text: "\(AIU9Fmt.count(day.tokens)) tok")
                Spacer(minLength: 0)
            }
            if showsDivider {
                Rectangle()
                    .fill(Theme.hairline(dark))
                    .frame(height: 1)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
    }

    private func miniStat(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.9))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 图例项

fileprivate struct AIU9LegendItem: View {
    let key: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(key)
                .font(BBFont.cap(10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AIUsageService {
    var totalCostDisplay: String {
        String(format: "¥%.2f", history.reduce(0) { $0 + $1.cost })
    }
}
