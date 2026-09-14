import SwiftUI

// MARK: - 百宝箱设置（主题 / 保活 / 充电监控 / 数据 / 关于）

struct SettingsView: View {
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var keepAlive = KeepAliveService.shared
    @EnvironmentObject var chargeHistory: ChargeHistory
    @Environment(\.colorScheme) private var scheme

    @AppStorage("bb.keepAlive") private var keepAliveOn = true
    @State private var showClearAlert = false

    var body: some View {
        Form {
            Section("外观") {
                Picker(selection: $theme.isDark) {
                    Text("浅色（默认）").tag(false)
                    Text("深色").tag(true)
                } label: {
                    Label("主题", systemImage: theme.isDark ? "moon.fill" : "sun.max.fill")
                }
            }

            Section {
                Toggle(isOn: $keepAliveOn) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("后台常驻保活")
                        Text("低功耗定位保持 App 活跃，充电播报 / XUI 蓝牙 / 流文连接全时段在线")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: keepAliveOn) { _ in
                    KeepAliveService.shared.applySettings()
                }
                HStack {
                    Label("定位权限", systemImage: "location.fill")
                    Spacer()
                    Text(authText)
                        .foregroundColor(authColor)
                        .font(.system(size: 13, weight: .medium))
                }
                if keepAlive.locationAuth != .authorizedAlways {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("去系统设置开启「始终允许」", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            } header: {
                Text("后台保活")
            } footer: {
                Text("定位仅用于系统保活（3 公里低精度，不采集不上报），配合充电时不可闻音轨双保险")
            }

            Section("充电监控") {
                NavigationLink {
                    CBSettingsView()
                } label: {
                    Label("电管家通知与目标", systemImage: "bolt.fill")
                }
                HStack {
                    Label("历史会话", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text("\(chargeHistory.sessions.count) 次").foregroundColor(.secondary)
                }
                Button(role: .destructive) {
                    showClearAlert = true
                } label: {
                    Label("清除充电历史", systemImage: "trash")
                }
                .disabled(chargeHistory.sessions.isEmpty)
            }

            Section("关于") {
                HStack {
                    Label("版本", systemImage: "app.badge.fill")
                    Spacer()
                    Text("2.0 (2)").foregroundColor(.secondary)
                }
                HStack(alignment: .top) {
                    Label("模块", systemImage: "square.grid.2x2")
                    Spacer()
                    Text("电管家 · XUI 遥控 · 超级按键 · 流文 · 龙虾帮 · 工具七件套")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background(scheme))
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("清除全部充电历史？", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { chargeHistory.clear() }
        } message: {
            Text("清除后充电预估将回到纯参考曲线模式")
        }
    }

    private var authText: String {
        switch keepAlive.locationAuth {
        case .authorizedAlways: return "始终允许 ✅"
        case .authorizedWhenInUse: return "仅使用期间"
        case .denied, .restricted: return "已拒绝"
        default: return "未授权"
        }
    }

    private var authColor: Color {
        keepAlive.locationAuth == .authorizedAlways ? .green : .orange
    }
}
