import SwiftUI
import UIKit
import Foundation
import Charts

// MARK: - 电池面板（DevBatteryView）
// 纯本地：实时电量、充放电状态、低电量模式、每 2 秒采样折线、放电速率估算。
// 自定义类型统一 Bat 前缀，避免与主工程命名冲突。

// MARK: - 充放电状态
enum BatPowerState: String {
    case unknown, unplugged, charging, full
    static func from(_ s: UIDevice.BatteryState) -> BatPowerState {
        switch s {
        case .charging:  return .charging
        case .full:      return .full
        case .unplugged: return .unplugged
        default:         return .unknown
        }
    }
    var label: String {
        switch self {
        case .unknown:   return "未知"
        case .unplugged: return "未插电"
        case .charging:  return "充电中"
        case .full:      return "已充满"
        }
    }
    var detail: String {
        switch self {
        case .unknown:   return "电池监控未就绪"
        case .unplugged: return "正在使用电池供电"
        case .charging:  return "已接通电源，电量上升中"
        case .full:      return "已接通电源，电量已满"
        }
    }
    var icon: String {
        switch self {
        case .unknown:   return "questionmark.circle"
        case .unplugged: return "battery.75"
        case .charging:  return "bolt.fill"
        case .full:      return "checkmark.circle.fill"
        }
    }
    var colors: [Color] {
        switch self {
        case .unknown:   return [Color(hex: 0x9AA3B5), Color(hex: 0x5B6478)]
        case .unplugged: return Theme.accentColors()
        case .charging:  return [Color(hex: 0x22C55E), Color(hex: 0x34E0A1)]
        case .full:      return [Color(hex: 0x16A34A), Color(hex: 0x0EA5A5)]
        }
    }
    var isPlugged: Bool { self == .charging || self == .full }
}

// MARK: - 采样点
struct BatSample: Identifiable {
    let id = UUID()
    let date: Date
    let level: Double   // 0 ~ 100
}

// MARK: - 视图
struct DevBatteryView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var level: Double = -1                    // 0~100，-1 不可用
    @State private var state: BatPowerState = .unknown
    @State private var lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var samples: [BatSample] = []
    @State private var timer: Timer?
    @State private var powerObserver: NSObjectProtocol?
    private let samplingInterval: TimeInterval = 2.0
    private let maxSamples = 900

    // MARK: 派生数据
    private var levelText: String { level < 0 ? "--" : String(format: "%.0f%%", level) }
    private var ringColors: [Color] {
        if state.isPlugged { return [Color(hex: 0x22C55E), Color(hex: 0x34E0A1)] }
        if level >= 0 && level <= 20 { return [Theme.danger, Color(hex: 0xFF7A18)] }
        if lowPower { return [Theme.warning, Color(hex: 0xFF7A18)] }
        return Theme.accentColors()
    }
    private var lineColor: Color {
        state.isPlugged ? Theme.success : (level >= 0 && level <= 20 ? Theme.danger : Theme.accent)
    }
    /// 放电速率（%/小时），仅未充电且呈下降趋势时有效
    private var dischargeRate: Double? {
        guard !state.isPlugged else { return nil }
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return nil }
        let hours = last.date.timeIntervalSince(first.date) / 3600
        guard hours > 0.0005 else { return nil }
        let drop = first.level - last.level
        guard drop > 0.05 else { return nil }
        return drop / hours
    }
    private var rateText: String {
        if state.isPlugged { return "充电中" }
        guard let r = dischargeRate else { return "—" }
        return String(format: "%.1f %%/h", r)
    }
    private var remainingText: String {
        guard let r = dischargeRate, r > 0.01, level > 0 else { return "—" }
        let hours = level / r
        if hours >= 99 { return "> 99 小时" }
        let h = Int(hours), m = Int((hours - Double(h)) * 60)
        return h > 0 ? "约 \(h) 小时 \(m) 分" : "约 \(m) 分钟"
    }

    // MARK: Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BBSpacing.l) {
                PageHeader(icon: "battery.100",
                           colors: [Color(hex: 0x22C55E), Color(hex: 0x34E0A1)],
                           title: "电池面板",
                           subtitle: "实时电量 · 充放电状态 · 采样曲线")
                heroCard
                statsRow
                chartCard
                lowPowerCard
                detailCard
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, BBSpacing.s)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("电池面板")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { start() }
        .onDisappear { stop() }
    }

    // MARK: 顶部大环
    private var heroCard: some View {
        BBCard(padding: BBSpacing.l) {
            VStack(spacing: BBSpacing.l) {
                HStack(spacing: 8) {
                    BBPill(text: state.label, color: state.colors.first ?? Theme.accent)
                    if lowPower { BBPill(text: "低电量模式", color: Theme.warning) }
                    Spacer(minLength: 6)
                    Image(systemName: state.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.gradient(state.colors))
                }
                HStack(alignment: .center, spacing: 16) {
                    BBRing(progress: level >= 0 ? level / 100 : 0,
                           lineWidth: 11, colors: ringColors,
                           label: levelText, caption: "当前电量")
                        .scaleEffect(1.42)
                        .frame(width: 138, height: 138)
                    VStack(alignment: .leading, spacing: 12) {
                        heroMini(icon: "arrow.down.right", title: "放电速率", value: rateText,
                                 colors: [Theme.info, Theme.accent2])
                        heroMini(icon: "clock", title: "预计可用", value: remainingText,
                                 colors: [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)])
                        heroMini(icon: "waveform.path.ecg", title: "本次采样", value: "\(samples.count) 个点",
                                 colors: [Color(hex: 0xF59E0B), Color(hex: 0xFF7A18)])
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    private func heroMini(icon: String, title: String, value: String, colors: [Color]) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.gradient(colors))
                    .frame(width: 24, height: 24)
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: 关键指标
    private var statsRow: some View {
        BBCard(padding: BBSpacing.l, radius: BBRadius.m) {
            HStack(alignment: .top, spacing: 10) {
                BBStat(label: "电量", value: level < 0 ? "--" : String(format: "%.0f", level),
                       unit: "%", icon: "bolt.fill", colors: ringColors)
                BBStat(label: "状态", value: state.label, icon: "powerplug.fill", colors: state.colors)
                BBStat(label: "低电量", value: lowPower ? "开" : "关", icon: "leaf.fill",
                       colors: lowPower ? [Theme.warning, Color(hex: 0xFF7A18)]
                                        : [Theme.success, Color(hex: 0x34E0A1)])
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 采样曲线
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: BBSpacing.m) {
            BBSectionHeader(title: "电量采样曲线", icon: "chart.xyaxis.line", colors: [Theme.info, Theme.accent2]) {
                Text("每 \(Int(samplingInterval)) 秒").font(.system(size: 11)).foregroundColor(.secondary)
            }
            BBCard(padding: BBSpacing.m, radius: BBRadius.m) {
                VStack(alignment: .leading, spacing: 10) {
                    if samples.count < 2 {
                        VStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(Theme.gradient([Theme.info, Theme.accent2]))
                            Text("正在采集电量…").font(BBFont.head(15))
                            Text("进入页面后每 2 秒记录一次")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity).frame(height: 150)
                    } else {
                        Chart(samples) { s in
                            AreaMark(x: .value("时间", s.date), y: .value("电量", s.level))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Theme.gradient([lineColor.opacity(0.30),
                                                                 lineColor.opacity(0.02)]))
                            LineMark(x: .value("时间", s.date), y: .value("电量", s.level))
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                .foregroundStyle(lineColor)
                            if let last = samples.last {
                                PointMark(x: .value("时间", last.date), y: .value("电量", last.level))
                                    .symbolSize(50)
                                    .foregroundStyle(lineColor)
                            }
                        }
                        .chartYScale(domain: 0.0...100.0)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.14))
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v))%").font(.system(size: 9)).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.14))
                                AxisValueLabel(format: .dateTime.hour().minute())
                            }
                        }
                        .frame(height: 158)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(lineColor).frame(width: 7, height: 7)
                        Text(state.isPlugged ? "充电曲线" : "放电曲线")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Text(samples.isEmpty ? "等待数据" : "始 \(String(format: "%.0f%%", samples[0].level)) → 今 \(levelText)")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: 低电量模式
    private var lowPowerCard: some View {
        VStack(alignment: .leading, spacing: BBSpacing.m) {
            BBSectionHeader("节能状态", icon: "leaf.fill", colors: [Theme.warning, Color(hex: 0xFF7A18)])
            BBCard(padding: BBSpacing.l, radius: BBRadius.m) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Theme.gradient(lowPower ? [Theme.warning, Color(hex: 0xFF7A18)]
                                                             : [Theme.success, Color(hex: 0x34E0A1)]))
                                .frame(width: 44, height: 44)
                            Image(systemName: lowPower ? "leaf.fill" : "leaf")
                                .font(.system(size: 19, weight: .semibold)).foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lowPower ? "低电量模式已开启" : "低电量模式已关闭").font(BBFont.head(15))
                            Text(lowPower ? "系统正在限制后台活动以延长续航"
                                          : "系统以正常性能运行，未限制后台活动")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    BBMeter(value: lowPower ? 1 : 0,
                            colors: lowPower ? [Theme.warning, Color(hex: 0xFF7A18)]
                                             : [Theme.success, Color(hex: 0x34E0A1)], height: 8)
                }
            }
        }
    }

    // MARK: 明细
    private var detailCard: some View {
        VStack(alignment: .leading, spacing: BBSpacing.m) {
            BBSectionHeader("电池明细", icon: "info.circle.fill")
            BBCard(padding: BBSpacing.l, radius: BBRadius.m) {
                VStack(spacing: 11) {
                    BBRow(title: "充放电状态", icon: state.icon, value: state.label, colors: state.colors)
                    BBRow(title: "状态说明", icon: "text.alignleft", value: state.detail,
                          colors: [Theme.info, Theme.accent2])
                    BBRow(title: "精确电量", icon: "percent",
                          value: level < 0 ? "系统未提供" : String(format: "%.2f%%", level), colors: ringColors)
                    BBRow(title: "放电速率", icon: "speedometer", value: rateText,
                          colors: [Theme.info, Theme.accent2])
                    BBRow(title: "预计可用", icon: "clock", value: remainingText,
                          colors: [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)])
                    BBRow(title: "采样间隔", icon: "timer", value: String(format: "%.0f 秒", samplingInterval),
                          colors: [Color(hex: 0xF59E0B), Color(hex: 0xFF7A18)])
                }
            }
        }
    }
    // MARK: 生命周期
    private func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: samplingInterval, repeats: true) { _ in
            DispatchQueue.main.async { refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    private func stop() {
        timer?.invalidate()
        timer = nil
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
        }
        powerObserver = nil
    }
    private func refresh() {
        let dev = UIDevice.current
        let raw = dev.batteryLevel
        state = BatPowerState.from(dev.batteryState)
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if raw >= 0 {
            let p = max(0, min(100, Double(raw) * 100))
            level = p
            samples.append(BatSample(date: Date(), level: p))
            if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        }
    }
}