import SwiftUI
import UIKit
import AudioToolbox
import UserNotifications

// MARK: - 倒计时（TimeCountdownView）
// 纯本地：快捷预设 + 自定义时分秒 + 大进度环；结束本地通知 + 系统提示音；
// 从后台返回按结束时间戳校正剩余秒数。自定义类型统一 Cd 前缀。

struct CdPreset: Identifiable {
    let id: Int
    let title: String
    let seconds: Int
}

enum CdFormat {
    /// 完整时分秒：h:mm:ss / mm:ss
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%02d:%02d", m, sec)
    }

    /// 环内短格式：超 1 小时显示 h:mm
    static func short(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// 本地通知封装：权限失败一律静默降级，绝不崩溃
enum CdNotify {
    static let id = "bb.countdown.end"

    static func requestAuth(_ done: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { done(granted) }
        }
    }

    static func schedule(after seconds: TimeInterval) {
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "倒计时结束"
        content.body = "设定的时间已到，点按查看。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

struct TimeCountdownView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var presets: [CdPreset] = [
        CdPreset(id: 0, title: "1 分", seconds: 60), CdPreset(id: 1, title: "3 分", seconds: 180),
        CdPreset(id: 2, title: "5 分", seconds: 300), CdPreset(id: 3, title: "10 分", seconds: 600),
        CdPreset(id: 4, title: "15 分", seconds: 900), CdPreset(id: 5, title: "25 分", seconds: 1500),
        CdPreset(id: 6, title: "30 分", seconds: 1800)]

    @State private var total: TimeInterval = 300
    @State private var remaining: TimeInterval = 300
    @State private var running = false
    @State private var target: Date?
    @State private var timer: Timer?
    @State private var customH = 0
    @State private var customM = 5
    @State private var customS = 0
    @State private var authorized = false
    @State private var showDone = false

    private var remainInt: Int { Int(ceil(max(0, remaining))) }
    private var progress: Double { total > 0 ? min(1, max(0, remaining / total)) : 0 }
    private var percent: Int { Int((progress * 100).rounded()) }
    private var ringColors: [Color] {
        if showDone { return [Theme.success, Color(hex: 0x14B8A6)] }
        return running ? [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)] : Theme.accentColors()
    }
    private var statusText: String {
        showDone ? "已完成" : (running ? "倒计时中" : (remaining < total ? "已暂停" : "就绪"))
    }
    private var statusColor: Color {
        showDone ? Theme.success : (running ? Theme.info : (remaining < total ? Theme.warning : Theme.accent))
    }
    private var customSeconds: Int { customH * 3600 + customM * 60 + customS }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "timer",
                           colors: [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)],
                           title: "倒计时",
                           subtitle: "快捷预设 · 结束时提醒")
                mainCard
                BBSectionHeader(title: "快捷预设", icon: "bolt.fill") {
                    Text("点按即设定").font(BBFont.cap(11)).foregroundColor(.secondary)
                }
                presetCard
                customCard
                HStack(spacing: 10) {
                    BBPrimaryButton(title: running ? "暂停" : (remaining < total ? "继续" : "开始"),
                                    icon: running ? "pause.fill" : "play.fill",
                                    colors: running ? [Color(hex: 0xFF7A18), Color(hex: 0xFF3D71)]
                                                    : [Color(hex: 0x22C55E), Color(hex: 0x14B8A6)]) {
                        toggleRun()
                    }
                    BBGhostButton(title: "重置", icon: "arrow.counterclockwise") { reset() }
                }
                infoCard
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("倒计时")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { CdNotify.requestAuth { granted in authorized = granted } }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                refreshFromTarget()          // 后台回来按时间差校正
                if running { startTimer() }
            } else if phase == .background {
                stopTimer()
            }
        }
        .onDisappear {
            stopTimer()
            CdNotify.cancel()
        }
    }

    // MARK: 主显示卡

    private var mainCard: some View {
        BBCard {
            HStack(spacing: 6) {
                BBRing(progress: showDone ? 1 : progress,
                       lineWidth: 9, colors: ringColors,
                       label: CdFormat.short(remainInt), caption: "\(percent)%")
                    .scaleEffect(1.55)
                    .frame(width: 148, height: 148)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        BBPill(text: statusText, color: statusColor)
                        BBPill(text: CdFormat.clock(Int(total)), color: Theme.accent)
                    }
                    Text(CdFormat.clock(remainInt))
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    BBMeter(value: showDone ? 1 : progress, colors: ringColors, height: 8)
                    Text("剩余 \(percent)% · 已用 \(100 - percent)%")
                        .font(BBFont.cap(10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 预设 / 自定义

    private var presetCard: some View {
        BBCard(padding: 12, radius: BBRadius.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        BBChip(text: preset.title, systemImage: "clock",
                               selected: Int(total) == preset.seconds && remaining == total) {
                            applyPreset(preset)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var customCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.gradient(Theme.accentColors()))
                    Text("自定义时长").font(BBFont.head(16))
                    Spacer()
                    Text(CdFormat.clock(customSeconds))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
                HStack(spacing: 0) {
                    pickerColumn(title: "时", range: 0...23, selection: $customH)
                    pickerColumn(title: "分", range: 0...59, selection: $customM)
                    pickerColumn(title: "秒", range: 0...59, selection: $customS)
                }
                .padding(.vertical, -6)
                Button {
                    BBHaptic.tap()
                    applyCustom()
                } label: {
                    Text("应用自定义时长")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                            .fill(Theme.accentGradient))
                }
                .buttonStyle(.plain)
                .disabled(customSeconds == 0)
                .opacity(customSeconds == 0 ? 0.5 : 1)
            }
        }
    }

    private func pickerColumn(title: String, range: ClosedRange<Int>,
                              selection: Binding<Int>) -> some View {
        VStack(spacing: 2) {
            Picker("", selection: selection) {
                ForEach(range, id: \.self) { value in Text("\(value)").tag(value) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .clipped()
            Text(title).font(BBFont.cap(11)).foregroundColor(.secondary)
        }
    }

    // MARK: 说明卡

    private var infoCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                BBRow(title: "通知权限", icon: "bell.badge.fill",
                      value: authorized ? "已允许" : "未允许（仅响铃）",
                      colors: authorized ? [Theme.success, Color(hex: 0x14B8A6)]
                                         : [Theme.warning, Color(hex: 0xFF7A18)])
                Divider().overlay(Theme.hairline(scheme == .dark))
                BBRow(title: "结束提示", icon: "speaker.wave.2.fill",
                      value: "系统提示音 + 触感", colors: [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)])
                Divider().overlay(Theme.hairline(scheme == .dark))
                BBKV(key: "总时长", value: CdFormat.clock(Int(total)))
                BBKV(key: "后台校正", value: "按结束时间戳自动对齐")
            }
        }
    }

    // MARK: 逻辑

    private func applyPreset(_ preset: CdPreset) {
        guard !running else { BBHaptic.warn(); return }
        stopTimer()
        showDone = false
        total = TimeInterval(preset.seconds)
        remaining = total
        customH = preset.seconds / 3600
        customM = (preset.seconds % 3600) / 60
        customS = preset.seconds % 60
        BBHaptic.select()
    }

    private func applyCustom() {
        guard !running, customSeconds > 0 else { BBHaptic.warn(); return }
        stopTimer()
        showDone = false
        total = TimeInterval(customSeconds)
        remaining = total
        BBHaptic.success()
    }

    private func toggleRun() {
        if running {
            refreshFromTarget()
            running = false
            target = nil
            stopTimer()
            CdNotify.cancel()
            BBHaptic.select()
        } else {
            guard remainInt > 0 else { reset(); return }
            showDone = false
            target = Date().addingTimeInterval(remaining)
            running = true
            startTimer()
            CdNotify.schedule(after: remaining)
            BBHaptic.success()
        }
    }

    private func reset() {
        stopTimer()
        running = false
        target = nil
        showDone = false
        remaining = total
        CdNotify.cancel()
        BBHaptic.warn()
    }

    private func refreshFromTarget() {
        guard running, let target else { return }
        let left = target.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            finish()
        } else {
            remaining = left
        }
    }

    private func finish() {
        stopTimer()
        running = false
        target = nil
        remaining = 0
        CdNotify.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showDone = true }
        AudioServicesPlaySystemSound(1005)
        BBHaptic.success()
    }

    private func startTimer() {
        stopTimer()
        let ticker = Timer(timeInterval: 0.1, repeats: true) { _ in
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
