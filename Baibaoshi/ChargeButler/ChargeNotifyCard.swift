import SwiftUI

// MARK: - 充电通知控制卡（直接放在电管家详情页底部）

struct ChargeNotifyCard: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var m = BatteryMonitor.shared

    @AppStorage("notifyEnabled") private var notifyOn = true
    @AppStorage("stepNotifyEnabled") private var stepOn = true
    @AppStorage("fullNotifyEnabled") private var fullOn = true
    @AppStorage("targetLevel") private var target = 100
    @AppStorage("notifyWindow") private var window = "all"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("通知控制", systemImage: "bell.badge.fill")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(windowText)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.teal.opacity(0.14)))
                    .foregroundColor(AppTheme.teal)
            }

            Toggle(isOn: $notifyOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("充电播报").font(.system(size: 14, weight: .medium))
                    Text("每充 +5% 通知电量和充满预估")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .tint(AppTheme.teal)
            .onChange(of: notifyOn) { _ in m.applySettings() }

            if notifyOn {
                // 时段选择
                VStack(alignment: .leading, spacing: 8) {
                    Text("播报时段").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    Picker("", selection: $window) {
                        Text("全天").tag("all")
                        Text("白班 7点-19点").tag("day")
                        Text("夜班 19点-7点").tag("night")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: window) { _ in m.applySettings() }
                }

                Toggle(isOn: $fullOn) {
                    Text("充满 / 达标提醒").font(.system(size: 14, weight: .medium))
                }
                .tint(AppTheme.teal)
                .onChange(of: fullOn) { _ in m.applySettings() }

                HStack {
                    Text("目标电量").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Picker("", selection: $target) {
                        Text("80%").tag(80)
                        Text("90%").tag(90)
                        Text("100%").tag(100)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    .onChange(of: target) { _ in m.applySettings() }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(scheme == .dark ? Theme.card.opacity(0.92) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.stroke(scheme == .dark), lineWidth: 1))
        )
    }

    private var windowText: String {
        switch window {
        case "day": return "白班 07:00-19:00"
        case "night": return "夜班 19:00-07:00"
        default: return "全天播报"
        }
    }
}
