import SwiftUI
import UIKit
import CoreHaptics

struct HapticsLabView: View {
    @State private var ripple = false
    private let engine = HapticSequencer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(icon: "iphone.radiowaves.left.and.right", colors: Theme.haptics, title: "震动实验室", subtitle: "点击任意按钮体验真实触感反馈")

                section("冲击反馈", desc: "Impact Generator · 五档力度") {
                    hapticRow([("轻", .light), ("适中", .medium), ("重", .heavy), ("柔和", .soft), ("生硬", .rigid)])
                }
                section("通知反馈", desc: "Notification Generator · 状态语义") {
                    notificationRow([("成功", .success), ("警告", .warning), ("错误", .error)])
                }
                section("拨轮反馈", desc: "Selection · 逐格细腻震动") {
                    SelectionDial(onTick: { UISelectionFeedbackGenerator().selectionChanged() })
                }
                section("节奏大师", desc: "CoreHaptics · 自定义 AHAP 序列") {
                    VStack(spacing: 12) {
                        rhythmRow([("❤️ 心跳", .heartbeat), ("🆘 SOS", .sos), ("🥁 鼓点", .drums), ("🌊 涟漪", .ripple)])
                        if !engine.supported {
                            Text("此设备不支持 CoreHaptics 触感引擎")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onTapGesture { }
    }

    private func section(_ title: String, desc: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(desc).font(.caption).foregroundColor(.secondary)
            content()
        }
        .padding(.horizontal, 4)
    }

    private func hapticRow(_ items: [(String, UIImpactFeedbackGenerator.FeedbackStyle)]) -> some View {
        HStack(spacing: 10) {
            ForEach(items, id: \.1) { item in
                HapticTrigger(label: item.0) {
                    UIImpactFeedbackGenerator(style: item.1).impactOccurred()
                }
            }
        }
    }

    private func notificationRow(_ items: [(String, UINotificationFeedbackGenerator.FeedbackType)]) -> some View {
        HStack(spacing: 10) {
            ForEach(items, id: \.1) { item in
                HapticTrigger(label: item.0) {
                    UINotificationFeedbackGenerator().notificationOccurred(item.1)
                }
            }
        }
    }

    private func rhythmRow(_ items: [(String, HapticSequencer.Pattern)]) -> some View {
        HStack(spacing: 10) {
            ForEach(items, id: \.1) { item in
                HapticTrigger(label: item.0) { engine.play(item.1) }
            }
        }
    }
}

// 触发按钮（带按压动画）
struct HapticTrigger: View {
    let label: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            pressed = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { pressed = false }
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.gradient(Theme.haptics))
                        .shadow(color: Theme.haptics[1].opacity(0.4), radius: 6, y: 3)
                )
                .scaleEffect(pressed ? 0.92 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: pressed)
        }
        .buttonStyle(.plain)
    }
}

// 拨轮：滑动切换触发 selection
struct SelectionDial: View {
    var onTick: () -> Void
    @State private var value = 3.0

    var body: some View {
        VStack(spacing: 6) {
            Slider(value: $value, in: 0...10, step: 1) { _ in onTick() }
            HStack {
                Text("位置 \(Int(value))").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("拖动试试 ✨").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
    }
}

// MARK: - CoreHaptics 序列器
final class HapticSequencer {
    enum Pattern { case heartbeat, sos, drums, ripple }

    private var engine: CHHapticEngine?
    var supported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    init() {
        guard supported else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { try? self.engine?.start() }
        try? engine?.start()
    }

    func play(_ p: Pattern) {
        guard let engine else { return }
        let events: [CHHapticEvent]
        switch p {
        case .heartbeat: // 咚-咚 两次心跳
            events = [
                beat(.hapticContinuous, at: 0.0, dur: 0.14, intensity: 1.0),
                beat(.hapticContinuous, at: 0.22, dur: 0.10, intensity: 0.7),
                beat(.hapticContinuous, at: 0.62, dur: 0.14, intensity: 1.0),
                beat(.hapticContinuous, at: 0.84, dur: 0.10, intensity: 0.7)
            ]
        case .sos: // 短短短-长长长-短短短
            var evs: [CHHapticEvent] = []
            for i in 0..<3 { evs.append(beat(.hapticTransient, at: Double(i) * 0.18, dur: 0, intensity: 0.9)) }
            for i in 0..<3 { evs.append(beat(.hapticContinuous, at: 0.7 + Double(i) * 0.32, dur: 0.26, intensity: 1.0)) }
            for i in 0..<3 { evs.append(beat(.hapticTransient, at: 1.85 + Double(i) * 0.18, dur: 0, intensity: 0.9)) }
            events = evs
        case .drums: // 四连鼓点 强弱交替
            events = [
                beat(.hapticTransient, at: 0.00, dur: 0, intensity: 1.0, sharp: 0.2),
                beat(.hapticTransient, at: 0.16, dur: 0, intensity: 0.5, sharp: 0.9),
                beat(.hapticTransient, at: 0.32, dur: 0, intensity: 1.0, sharp: 0.2),
                beat(.hapticTransient, at: 0.48, dur: 0, intensity: 0.5, sharp: 0.9),
                beat(.hapticTransient, at: 0.72, dur: 0, intensity: 1.0, sharp: 0.9)
            ]
        case .ripple: // 一波渐强长震
            events = [beat(.hapticContinuous, at: 0.0, dur: 0.9, intensity: 1.0, sharp: 0.5)]
        }
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? engine.start()
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    private func beat(_ type: CHHapticEvent.EventType, at t: Double, dur: Double,
                      intensity: Float, sharp: Float = 0.6) -> CHHapticEvent {
        CHHapticEvent(eventType: type, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp)
        ], relativeTime: t, duration: dur)
    }
}
