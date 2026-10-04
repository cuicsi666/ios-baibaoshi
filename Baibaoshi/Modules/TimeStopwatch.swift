import SwiftUI

// MARK: - 毫秒级秒表（TimeStopwatchView）
// 纯本地实现：0.03 秒刷新、分段计次、最快/最慢标记。
// 自定义类型统一使用 Sw 前缀，避免与主工程冲突。

struct SwLap: Identifiable {
    let id: Int              // 第几段（1 开始）
    let total: TimeInterval  // 总时间
    let split: TimeInterval  // 分段用时
}

enum SwFormat {
    /// 分:秒.厘秒（超过 1 小时自动补小时）
    static func clock(_ interval: TimeInterval) -> String {
        let value = max(0, interval)
        let totalHundredths = Int(value * 100)
        let hundredths = totalHundredths % 100
        let totalSeconds = totalHundredths / 100
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, hundredths)
        }
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    /// 两位厘秒（供进度环使用）
    static func hundredths(_ interval: TimeInterval) -> String {
        let value = max(0, interval)
        let h = Int(value * 100) % 100
        return String(format: "%02d", h)
    }

    static func average(_ laps: [SwLap]) -> TimeInterval {
        guard !laps.isEmpty else { return 0 }
        let total = laps.reduce(0) { $0 + $1.split }
        return total / Double(laps.count)
    }
}

struct TimeStopwatchView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var accumulated: TimeInterval = 0
    @State private var startDate = Date()
    @State private var now = Date()
    @State private var running = false
    @State private var laps: [SwLap] = []
    @State private var timer: Timer?

    private var elapsed: TimeInterval {
        running ? accumulated + now.timeIntervalSince(startDate) : accumulated
    }

    private var fastestID: Int? {
        guard laps.count >= 2, let best = laps.map({ $0.split }).min() else { return nil }
        return laps.first { $0.split == best }?.id
    }

    private var slowestID: Int? {
        guard laps.count >= 2, let worst = laps.map({ $0.split }).max() else { return nil }
        return laps.first { $0.split == worst }?.id
    }

    private var maxSplit: TimeInterval {
        max(laps.map { $0.split }.max() ?? 1, 0.01)
    }

    private var statusText: String {
        if running { return "计时中" }
        if accumulated > 0 { return "已暂停" }
        return "就绪"
    }

    private var statusColor: Color {
        if running { return Theme.success }
        if accumulated > 0 { return Theme.warning }
        return Theme.accent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "stopwatch.fill",
                           colors: [Color(hex: 0xFF6B6B), Color(hex: 0xFF9F1C)],
                           title: "秒表",
                           subtitle: "间隔刷新 · 支持分段计次")

                mainCard

                HStack(spacing: 10) {
                    BBPrimaryButton(title: running ? "暂停" : (accumulated > 0 ? "继续" : "开始"),
                                    icon: running ? "pause.fill" : "play.fill",
                                    colors: running ? [Color(hex: 0xFF7A18), Color(hex: 0xFF3D71)]
                                                    : [Color(hex: 0x22C55E), Color(hex: 0x14B8A6)]) {
                        toggleRun()
                    }
                    BBGhostButton(title: "计次", icon: "flag.fill") {
                        markLap()
                    }
                }

                HStack(spacing: 10) {
                    BBPrimaryButton(title: "复位", icon: "arrow.counterclockwise",
                                    colors: [Color(hex: 0x64748B), Color(hex: 0x94A3B8)]) {
                        reset()
                    }
                }

                if laps.count >= 2 {
                    summaryCard
                }

                BBSectionHeader("分段记录", icon: "list.number") {
                    Text("\(laps.count) 段")
                        .font(BBFont.cap(11))
                        .foregroundColor(.secondary)
                }

                if laps.isEmpty {
                    BBCard {
                        BBEmptyState(icon: "flag", title: "暂无分段",
                                     message: "计时过程中点击「计次」记录每一段用时")
                    }
                } else {
                    BBCard(padding: 12, radius: BBRadius.m) {
                        VStack(spacing: 10) {
                            ForEach(Array(laps.reversed())) { lap in
                                lapRow(lap)
                                if lap.id != laps.first?.id {
                                    Rectangle()
                                        .fill(Theme.hairline(scheme == .dark))
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("秒表")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stopTimer() }
    }

    // MARK: 主显示卡

    private var mainCard: some View {
        let centi = elapsed.truncatingRemainder(dividingBy: 1)
        let minuteFraction = elapsed.truncatingRemainder(dividingBy: 60) / 60

        return BBCard {
            HStack(spacing: 14) {
                BBRing(progress: centi,
                       lineWidth: 9,
                       colors: [Color(hex: 0xFF6B6B), Color(hex: 0xFF9F1C)],
                       label: SwFormat.hundredths(elapsed),
                       caption: "厘秒")

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        BBPill(text: statusText, color: statusColor)
                        BBPill(text: "\(laps.count) 段", color: Theme.info)
                    }
                    Text(SwFormat.clock(elapsed))
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    BBMeter(value: minuteFraction,
                            colors: [Color(hex: 0xFF6B6B), Color(hex: 0xFF9F1C)],
                            height: 6)
                    Text("当前整分钟内进度 \(Int(minuteFraction * 100))%")
                        .font(BBFont.cap(10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: 最快 / 最慢 / 平均

    private var summaryCard: some View {
        BBCard {
            HStack(spacing: 12) {
                BBStat(label: "最快分段",
                       value: SwFormat.clock(laps.first { $0.id == fastestID }?.split ?? 0),
                       icon: "bolt.fill",
                       colors: [Color(hex: 0x22C55E), Color(hex: 0x14B8A6)])
                BBStat(label: "最慢分段",
                       value: SwFormat.clock(laps.first { $0.id == slowestID }?.split ?? 0),
                       icon: "tortoise.fill",
                       colors: [Color(hex: 0xEF4444), Color(hex: 0xF97316)])
                BBStat(label: "平均分段",
                       value: SwFormat.clock(SwFormat.average(laps)),
                       icon: "function",
                       colors: Theme.accentColors())
            }
        }
    }

    // MARK: 分段行

    private func lapRow(_ lap: SwLap) -> some View {
        let isFast = lap.id == fastestID
        let isSlow = lap.id == slowestID
        let tint: Color = isFast ? Theme.success : (isSlow ? Theme.danger : Theme.accent)

        return HStack(spacing: 10) {
            BBPill(text: "第 \(lap.id) 段", color: tint)

            VStack(alignment: .leading, spacing: 5) {
                Text(SwFormat.clock(lap.split))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(isFast ? Theme.success : (isSlow ? Theme.danger : .primary))
                BBMeter(value: lap.split / maxSplit,
                        colors: isFast ? [Color(hex: 0x22C55E), Color(hex: 0x14B8A6)]
                                       : (isSlow ? [Color(hex: 0xEF4444), Color(hex: 0xF97316)]
                                                 : Theme.accentColors()),
                        height: 4)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                Text(SwFormat.clock(lap.total))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                if isFast || isSlow {
                    BBPill(text: isFast ? "最快" : "最慢",
                           color: isFast ? Theme.success : Theme.danger)
                }
            }
        }
    }

    // MARK: 逻辑

    private func toggleRun() {
        if running {
            accumulated += now.timeIntervalSince(startDate)
            running = false
            now = Date()
            stopTimer()
            BBHaptic.select()
        } else {
            startDate = Date()
            now = Date()
            running = true
            startTimer()
            BBHaptic.success()
        }
    }

    private func markLap() {
        guard running || accumulated > 0 else {
            BBHaptic.warn()
            return
        }
        let total = elapsed
        let previous = laps.last?.total ?? 0
        let lap = SwLap(id: laps.count + 1, total: total, split: total - previous)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            laps.append(lap)
        }
        BBHaptic.success()
    }

    private func reset() {
        stopTimer()
        running = false
        accumulated = 0
        now = Date()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            laps.removeAll()
        }
        BBHaptic.warn()
    }

    private func startTimer() {
        stopTimer()
        let ticker = Timer(timeInterval: 0.03, repeats: true) { _ in
            DispatchQueue.main.async { now = Date() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
