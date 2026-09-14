import UIKit
import AVFoundation
import Combine

/// 电量监控核心服务
/// - 前台 + 后台（充电时静音保活）持续监控电量
/// - 每 +5% 发本地通知（电量 + 预估充满时间）
/// - 充满 / 达到目标电量提醒
/// - 拔电自动保存会话到历史，反哺预估
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    // MARK: 状态
    @Published var level: Int = -1
    @Published var state: UIDevice.BatteryState = .unknown
    @Published var session: ChargeSession?
    @Published var estimate: Estimate?
    @Published var lastNotifiedLevel: Int = -1
    @Published var fullNotified: Bool = false
    @Published var machineId: String = "unknown"

    private var timer: Timer?
    private var player: AVAudioPlayer?
    let estimator = ChargeEstimator.shared
    private let history = ChargeHistory.shared
    private let ud = UserDefaults.standard

    var isPlugged: Bool { state == .charging || state == .full }

    // MARK: 设置项（实时读 UserDefaults）
    var notifyEnabled: Bool { ud.object(forKey: "notifyEnabled") as? Bool ?? true }
    var stepNotifyEnabled: Bool { ud.object(forKey: "stepNotifyEnabled") as? Bool ?? true }
    var fullNotifyEnabled: Bool { ud.object(forKey: "fullNotifyEnabled") as? Bool ?? true }
    var keepAliveEnabled: Bool { ud.object(forKey: "bb.keepAlive") as? Bool ?? true }
    var targetLevel: Int { ud.object(forKey: "targetLevel") as? Int ?? 100 }

    // MARK: 启动

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        machineId = Self.machineIdentifier()

        NotificationCenter.default.addObserver(self, selector: #selector(battChanged),
                                               name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(battChanged),
                                               name: UIDevice.batteryStateDidChangeNotification, object: nil)

        // 轮询双保险（保活下后台 Timer 持续跑；前台 10s / 后台 30s）
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh(initial: true)
    }

    @objc private func battChanged() { refresh() }

    // MARK: 状态机

    func refresh(initial: Bool = false) {
        let dev = UIDevice.current
        let newLevel = dev.batteryLevel >= 0 ? Int(round(dev.batteryLevel * 100)) : -1
        let newState = dev.batteryState

        let oldLevel = level
        let oldState = state
        level = newLevel
        state = newState

        if isPlugged {
            // 新会话
            if session == nil {
                var s = ChargeSession(start: Date())
                s.startLevel = newLevel
                s.endLevel = newLevel
                s.device = machineId
                s.points = [ChargePoint(t: Date(), level: newLevel)]
                session = s
                lastNotifiedLevel = newLevel
                fullNotified = false
                objectWillChange.send()
            }

            // 电量变化：记录数据点
            if newLevel != oldLevel || initial, var s = session {
                s.points.append(ChargePoint(t: Date(), level: newLevel))
                s.endLevel = newLevel
                session = s
            }

            if newState == .charging {
                handleStepNotify()
            }
            handleFullNotify()

            updateEstimate()
            // 充电时静音音频保活（配合全局定位保活）
            if keepAliveEnabled { KeepAliveService.shared.startAudioKeepAlive() } else { KeepAliveService.shared.stopAudioKeepAlive() }
        } else {
            // 拔电：结束会话
            if oldState == .charging || oldState == .full, var s = session {
                s.end = Date()
                s.endLevel = max(oldLevel, s.endLevel)
                if s.durationMinutes >= 3 && s.points.count >= 2 {
                    history.add(s)
                }
                session = nil
                estimate = nil
                lastNotifiedLevel = -1
                fullNotified = false
            }
            KeepAliveService.shared.stopAudioKeepAlive()
        }
    }

    // MARK: 通知

    private func handleStepNotify() {
        guard notifyEnabled, stepNotifyEnabled, let s = session else { return }
        guard newLevelReached5(s: s) else { return }

        let target = targetLevel
        let remaining = estimate
        var body: String
        if let est = remaining, level < target {
            body = "预计 \(est.timeText)后充满（\(est.doneAtText)）· 速率 \(est.rateText)"
        } else {
            body = "目标 \(target)%，即将到达"
        }
        NotificationManager.shared.send(title: "⚡️ 已充至 \(level)%（+\(level - s.startLevel)%）",
                                        body: body,
                                        id: "step-\(level)-\(Int(s.start.timeIntervalSince1970))")
        lastNotifiedLevel = level
        objectWillChange.send()
    }

    private func newLevelReached5(s: ChargeSession) -> Bool {
        guard lastNotifiedLevel >= 0 else { return false }
        guard level >= lastNotifiedLevel + 5 else { return false }
        guard level < targetLevel else { return false }
        // 会话开始后至少 1 个样本
        return s.points.count >= 1
    }

    private func handleFullNotify() {
        guard notifyEnabled, fullNotifyEnabled, !fullNotified, var s = session else { return }
        let target = targetLevel
        let hitFull = state == .full && target >= 100
        let hitTarget = target < 100 && level >= target
        guard hitFull || hitTarget else { return }

        let title = hitFull ? "🔋 已充满 100%" : "✅ 已达目标 \(target)%"
        let mins = s.durationMinutes
        let m = Int(mins.rounded())
        let durText = m >= 60 ? "\(m / 60) 小时 \(m % 60) 分" : "\(max(m, 1)) 分钟"
        NotificationManager.shared.send(title: title,
                                        body: "本次充电 \(durText)，共充入 +\(s.endLevel - s.startLevel)%，拔掉充电器保护电池 🔌",
                                        id: "full-\(Int(s.start.timeIntervalSince1970))")
        fullNotified = true
        s.reachedFull = hitFull
        session = s
        objectWillChange.send()
    }

    // MARK: 预估

    private func updateEstimate() {
        guard let s = session, state == .charging, level >= 0, level < targetLevel else {
            if estimate != nil { estimate = nil }
            return
        }
        let live = liveRate()
        let est = estimator.estimate(level: level,
                                     target: targetLevel,
                                     liveRate: live,
                                     history: history.bucketRates(),
                                     curve: estimator.bestCurve(for: machineId))
        estimate = est
    }

    /// 近 10 分钟实时速率（%/min），样本不足退回最近两点
    func liveRate() -> Double? {
        guard let s = session, s.points.count >= 2 else { return nil }
        let cutoff = Date().addingTimeInterval(-10 * 60)
        let recent = s.points.filter { $0.t >= cutoff }
        let pts = recent.count >= 2 ? recent : Array(s.points.suffix(2))
        guard let first = pts.first, let last = pts.last,
              last.t > first.t, last.level > first.level else { return nil }
        return Double(last.level - first.level) / (last.t.timeIntervalSince(first.t) / 60)
    }

    // MARK: 设置变更入口

    func applySettings() {
        refresh()
    }

    // MARK: 机型

    static func machineIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
