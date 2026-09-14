import SwiftUI

// MARK: - 设置页

struct CBSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var h: ChargeHistory

    @AppStorage("notifyEnabled") private var notifyOn = true
    @AppStorage("stepNotifyEnabled") private var stepOn = true
    @AppStorage("fullNotifyEnabled") private var fullOn = true
    @AppStorage("keepAliveEnabled") private var keepAliveOn = true
    @AppStorage("targetLevel") private var target = 100

    @State private var showClearAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $notifyOn) {
                        Label("电量通知", systemImage: "bell.fill")
                    }
                    .tint(Theme.teal)
                    .onChange(of: notifyOn) { _ in BatteryMonitor.shared.applySettings() }

                    if notifyOn {
                        Toggle(isOn: $stepOn) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("每充 +5% 播报")
                                Text("充电中每增加 5%，通知当前电量和充满预估")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tint(Theme.teal)

                        Toggle(isOn: $fullOn) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("充满 / 达标提醒")
                                Text("充至 100% 或达到目标电量时通知")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tint(Theme.teal)

                        Picker(selection: $target) {
                            Text("80%（护电池）").tag(80)
                            Text("90%").tag(90)
                            Text("100%（充满）").tag(100)
                        } label: {
                            Label("目标电量", systemImage: "target")
                        }
                        .onChange(of: target) { _ in BatteryMonitor.shared.applySettings() }
                    }
                } header: {
                    Text("通知")
                }

                Section {
                    Toggle(isOn: $keepAliveOn) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("充电时保持后台活跃")
                            Text("播放一条人耳不可闻的音轨，防止 iOS 冻结 App 导致漏报。插入充电器时耗电可忽略")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(Theme.teal)
                    .onChange(of: keepAliveOn) { _ in BatteryMonitor.shared.applySettings() }
                } header: {
                    Text("后台监控")
                } footer: {
                    Text("保持后台活跃 + 屏幕锁定时也能正常播报；若从后台划掉 App，监控会停止，重新打开即恢复")
                }

                Section {
                    HStack {
                        Label("历史会话", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text("\(h.sessions.count) 次")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Label("参考曲线", systemImage: "waveform.path.ecg")
                        Spacer()
                        Text("公开评测数据 · \(BatteryMonitor.shared.estimator.reference.updated)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Button(role: .destructive) {
                        showClearAlert = true
                    } label: {
                        Label("清除历史数据", systemImage: "trash")
                    }
                    .disabled(h.sessions.isEmpty)
                } header: {
                    Text("预估数据")
                } footer: {
                    Text("预估算法：实时速率 + 历史分段统计 + 机型参考曲线三源加权，充电记录越多越准")
                }

                Section {
                    HStack {
                        Label("版本", systemImage: "app.badge.fill")
                        Spacer()
                        Text("1.0 (1)").foregroundColor(.secondary)
                    }
                    HStack(alignment: .top) {
                        Label("数据说明", systemImage: "info.circle")
                        Spacer()
                        Text("内置曲线整理自 20W PD 公开充电评测，App 会自动按机型选择并持续用本机历史校准")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 190)
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("充电设置")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Theme.background(scheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(Theme.heroGradient)
                        Text("设置").font(.headline)
                    }
                }
            }
            .alert("清除全部历史数据？", isPresented: $showClearAlert) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) { h.clear() }
            } message: {
                Text("清除后预估将回到纯参考曲线模式")
            }
        }
    }
}
