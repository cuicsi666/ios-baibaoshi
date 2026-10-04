import SwiftUI
import UIKit
import AudioToolbox
import UserNotifications

// MARK: - 番茄钟（TimePomodoroView）
// 纯本地：25 分钟专注 / 5 分钟休息，时长可调并持久化到 bb.pomo.*；
// 阶段自动切换、进度环 + 大号倒计时、今日番茄数（按 yyyy-MM-dd 存 UserDefaults）。
// 自定义类型统一 Pomo 前缀，避免与主工程冲突。

enum PomoPhase: String {
    case focus
    case rest

    var title: String { self == .focus ? "专注中" : "休息中" }
    var idleTitle: String { self == .focus ? "准备专注" : "准备休息" }
    var icon: String { self == .focus ? "brain.head.profile" : "cup.and.saucer.fill" }
    var colors: [Color] {
        self == .focus ? [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)]
                       : [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)]
    }
    var accent: Color { colors[0] }
}

enum PomoFormat {
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
enum PomoNotify {
    static let id = "bb.pomo.end"

    static func requestAuth(_ done: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { done(granted) }
        }
    }

    static func schedule(after seconds: TimeInterval, phase: PomoPhase) {
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = phase == .focus ? "专注结束" : "休息结束"
        content.body = phase == .focus ? "该休息一下了 ☕️" : "回到专注，继续加油 💪"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func cancel() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
}

/// 今日番茄计数（按 yyyy-MM-dd 存 UserDefaults，跨天自动归零）
enum PomoStore {
    static func todayKey(_ date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    static func count() -> Int { UserDefaults.standard.integer(forKey: "bb.pomo.count." + todayKey()) }

    static func bump() -> Int {
        let key = "bb.pomo.count." + todayKey()
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
        UserDefaults.standard.set(next, forKey: "bb.pomo.count")
        return next
    }
}

struct TimePomodoroView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("bb.pomo.focus") private var focusMinutes = 25
    @AppStorage("bb.pomo.rest") private var restMinutes = 5
    @AppStorage("bb.pomo.auto") private var autoContinue = true

    @State private var phase: PomoPhase = .focus
    @State private var remaining: TimeInterval = 25 * 60
    @State private var running = false
    @State private var target: Date?
    @State private var timer: Timer?
    @State private var authorized = false
    @State private var todayCount = 0
    @State private var roundCount = 0

    private var phaseTotal: TimeInterval { TimeInterval(max(1, phase == .focus ? focusMinutes : restMinutes) * 60) }
    private var remainInt: Int { Int(ceil(max(0, remaining))) }
    private var progress: Double { phaseTotal > 0 ? min(1, max(0, remaining / phaseTotal)) : 0 }
    private var percent: Int { Int((progress * 100).rounded()) }
    private var statusText: String {
        running ? phase.title : (remaining < phaseTotal ? "已暂停 · \(phase.title)" : phase.idleTitle)
    }
    private var statusColor: Color { running ? phase.accent : Theme.warning }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "timer.circle.fill",
                           colors: [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)],
                           title: "番茄钟",
                           subtitle: "\(focusMinutes) 分钟专注 · \(restMinutes) 分钟休息")
                mainCard
                HStack(spacing: 10) {
                    BBPrimaryButton(title: running ? "暂停" : (remaining < phaseTotal ? "继续" : "开始专注"),
                                    icon: running ? "pause.fill" : "play.fill",
                                    colors: running ? [Color(hex: 0xFF7A18), Color(hex: 0xFF3D71)]
                                                    : phase.colors) { toggleRun() }
                    BBGhostButton(title: "跳过", icon: "forward.fill") { skip() }
                }
                statsCard
                settingsCard
                infoCard
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("番茄钟")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            todayCount = PomoStore.count()
            PomoNotify.requestAuth { granted in authorized = granted }
        }
        .onChange(of: scenePhase) { value in
            if value == .active {
                todayCount = PomoStore.count()   // 跨天自动重新读取（新日期键为 0）
                refreshFromTarget()
                if running { startTimer() }
            } else if value == .background {
                stopTimer()
            }
        }
        .onChange(of: focusMinutes) { _ in syncDurations() }
        .onChange(of: restMinutes) { _ in syncDurations() }
        .onDisappear {
            stopTimer()
            PomoNotify.cancel()
        }
    }
    // MARK: 主显示卡

    private var mainCard: some View {
        BBCard {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    BBPill(text: phase.title, color: phase.accent)
                    BBPill(text: statusText, color: statusColor)
                    Spacer()
                    BBPill(text: "第 \(max(1, roundCount)) 轮", color: Theme.info)
                }
                BBRing(progress: progress, lineWidth: 9, colors: phase.colors,
                       label: "\(percent)%", caption: phase == .focus ? "专注" : "休息")
                    .scaleEffect(1.7)
                    .frame(width: 170, height: 170)
                Text(PomoFormat.clock(remainInt))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.gradient(phase.colors))
                BBMeter(value: progress, colors: phase.colors, height: 8)
                Text(phase == .focus ? "保持专注，别切出去 👀" : "放松眼睛，站起来走走 🚶")
                    .font(BBFont.cap(11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
    // MARK: 今日统计 / 设置 / 说明

    private var statsCard: some View {
        BBCard {
            HStack(spacing: 12) {
                BBStat(label: "今日完成", value: "\(todayCount)", unit: "个",
                       icon: "checkmark.seal.fill", colors: [Color(hex: 0x22C55E), Color(hex: 0x14B8A6)])
                BBStat(label: "专注时长", value: "\(todayCount * focusMinutes)", unit: "分钟",
                       icon: "hourglass", colors: [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)])
            }
        }
    }

    private var settingsCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("时长设置", icon: "slider.horizontal.3", colors: phase.colors)
                stepperRow(title: "专注时长", value: focusMinutes, unit: "分钟",
                           colors: [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)],
                           icon: "brain.head.profile") { delta in
                    focusMinutes = min(60, max(5, focusMinutes + delta))
                }
                Divider().overlay(Theme.hairline(scheme == .dark))
                stepperRow(title: "休息时长", value: restMinutes, unit: "分钟",
                           colors: [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)],
                           icon: "cup.and.saucer.fill") { delta in
                    restMinutes = min(30, max(1, restMinutes + delta))
                }
                Divider().overlay(Theme.hairline(scheme == .dark))
                Toggle(isOn: $autoContinue) {
                    Text("阶段结束自动开始下一阶段").font(.system(size: 14, weight: .medium))
                }
                .toggleStyle(SwitchToggleStyle(tint: phase.accent))
                Text("专注 / 休息时长会自动保存到 bb.pomo.*，下次打开继续沿用")
                    .font(BBFont.cap(10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func stepperRow(title: String, value: Int, unit: String,
                            colors: [Color], icon: String,
                            onStep: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.gradient(colors))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer(minLength: 6)
            Text("\(value) \(unit)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(phase.accent)
            stepButton(icon: "minus") { onStep(-1) }
            stepButton(icon: "plus") { onStep(1) }
        }
        .disabled(running)
        .opacity(running ? 0.5 : 1)
    }

    private func stepButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            BBHaptic.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(phase.accent)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(phase.accent.opacity(0.14))
                        .overlay(Circle().strokeBorder(phase.accent.opacity(0.25), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private var infoCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                BBRow(title: "通知权限", icon: "bell.badge.fill",
                      value: authorized ? "已允许" : "未允许（仅响铃）",
                      colors: authorized ? [Theme.success, Color(hex: 0x14B8A6)]
                                         : [Theme.warning, Color(hex: 0xFF7A18)])
                Divider().overlay(Theme.hairline(scheme == .dark))
                BBKV(key: "阶段时长", value: "专注 \(focusMinutes) 分 · 休息 \(restMinutes) 分")
                BBKV(key: "自动接续", value: autoContinue ? "开启" : "关闭")
            }
        }
    }
    // MARK: 逻辑

    private func toggleRun() {
        if running {
            refreshFromTarget()
            running = false
            target = nil
            stopTimer()
            PomoNotify.cancel()
            BBHaptic.select()
        } else {
            if remainInt <= 0 { syncDurations() }
            target = Date().addingTimeInterval(remaining)
            running = true
            startTimer()
            PomoNotify.schedule(after: remaining, phase: phase)
            BBHaptic.success()
        }
    }

    private func skip() {
        guard !running else { BBHaptic.warn(); return }
        advance(autoStart: false, countIt: false)
    }

    private func syncDurations() {
        guard !running else { return }
        remaining = phaseTotal
    }

    /// 切换阶段；countIt 为 true 时记一次今日番茄
    private func advance(autoStart: Bool, countIt: Bool) {
        stopTimer()
        PomoNotify.cancel()
        let finished = phase
        if finished == .focus && countIt { todayCount = PomoStore.bump() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            phase = (finished == .focus) ? .rest : .focus
            if finished == .focus { roundCount += 1 }
            remaining = phaseTotal
            target = nil
            running = false
        }
        if autoStart {
            target = Date().addingTimeInterval(remaining)
            running = true
            startTimer()
            PomoNotify.schedule(after: remaining, phase: phase)
        }
    }

    private func refreshFromTarget() {
        guard running, let target else { return }
        let left = target.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            completePhase()
        } else {
            remaining = left
        }
    }

    private func completePhase() {
        AudioServicesPlaySystemSound(1005)
        BBHaptic.success()
        advance(autoStart: autoContinue, countIt: true)
    }

    private func startTimer() {
        stopTimer()
        let ticker = Timer(timeInterval: 0.25, repeats: true) { _ in
            DispatchQueue.main.async { refreshFromTarget() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
