import SwiftUI

// MARK: - XUI 遥控页（v2.4 浅色主题，与播报页一致）
struct XUIControlView: View {
    @StateObject private var xui = XUIManager.shared
    @StateObject private var relay = XUITunnelRelay.shared
    @StateObject private var logger = XUILogger.shared
    @State private var volume: Double = 60
    @State private var brightness: Double = 1
    @State private var copiedFlash = false
    @State private var crashReport: String? = nil
    @State private var sliderEditing: String? = nil   // v3.47: 当前拖动中的滑条("bri"/"vol"), 苹果式气泡
    @State private var showGamepad = false   // v4.0: 点游戏自动进手柄
    @State private var clearFlash = false    // v4.0: 一键清理反馈

    // v4.0: 删壁纸/设置入口; 保留 AI余量/监控/升级/游戏/桌面
    private let apps = ["AI余量", "监控", "升级", "游戏", "桌面"]
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    private let accent = Color(red: 0.0, green: 0.55, blue: 0.75)
    private let softBlue = Color(red: 0.05, green: 0.55, blue: 0.85)

    var body: some View {
        ZStack {
            // 浅色渐变背景（与播报页一致）
            LinearGradient(colors: [
                Color(red: 0.93, green: 0.95, blue: 0.98),
                Color(red: 0.86, green: 0.91, blue: 0.96),
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 头部状态卡（同款蓝色渐变）
                    HStack(spacing: 10) {
                        Text("🦞").font(.system(size: 30))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("XUI")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                Text("v4.3")   // v4.3: 常亮/防误触开关+充电左侧iPhone电量
                                    .font(.caption2.bold())
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.white.opacity(0.25)))
                            }
                            Text(xui.statusText)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        Spacer()
                        // v3.30: 右上角不再显示电量/版本(老板要求只删右上角这个, 状态卡已还原显示)
                        Circle().fill(statusColor).frame(width: 9, height: 9)
                    }
                    .padding(18)
                    .background(
                        LinearGradient(colors: [softBlue, Color(red: 0.0, green: 0.35, blue: 0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: accent.opacity(0.25), radius: 12, x: 0, y: 5)

                    // 设备状态卡 —— 连接状态 + 蓝牙 + 电量 + 固件版本(v3.30 恢复电量/版本显示)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle().fill(statusColor).frame(width: 10, height: 10)
                            Text(xui.state.paired ? "已连接" : (xui.state.connected ? "连接中..." : "未连接（自动重连中）"))
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "battery.75")
                                .foregroundColor(xui.info.battery >= 20 ? .green : .orange)
                            Text(xui.info.battery >= 0 ? "\(xui.info.battery)%" : "--")
                                .font(.subheadline.bold())
                                .foregroundColor(xui.info.battery >= 20 ? .green : .orange)
                        }
                        Divider()
                        HStack {
                            Text("固件版本")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(xui.info.version)
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Text("蓝牙")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            // v4.0: RSSI 信号强度显示
                            HStack(spacing: 4) {
                                if xui.rssi > -60 { Text("📶 强").foregroundColor(.green) }
                                else if xui.rssi > -75 { Text("📶 中").foregroundColor(.orange) }
                                else if xui.rssi > -90 { Text("📶 弱").foregroundColor(.red) }
                                else { Text("📶 无").foregroundColor(.gray) }
                                Text(xui.state.paired ? "已连接" : (xui.state.connected ? "连接中" : "断开"))
                                    .font(.subheadline.bold())
                                    .foregroundColor(statusColor)
                            }
                        }
                        Divider()
                        HStack {
                            Text("内存")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(xui.info.mem >= 0 ? "内部 \(xui.info.mem)KB / 外部 \(xui.info.memExt)KB" : "--")
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundColor(xui.info.mem >= 30 ? .green : (xui.info.mem >= 0 ? .orange : .primary))
                        }
                        // v4.0: 删除存储显示(老板要求)
                    }
                    .padding(18)
                    .background(whiteCard)

                    // v4.1: 推送偏好设置（可开关充电/连接通知）
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "bell.badge.fill").foregroundColor(accent)
                            Text("推送通知").font(.headline).foregroundColor(.primary)
                            Spacer()
                        }
                        Toggle(isOn: Binding(
                            get: { XUIManager.notifEnabled(XUIManager.NotifKey.charge) },
                            set: { XUIManager.setNotif(XUIManager.NotifKey.charge, $0) }
                        )) {
                            Text("充电 / 充满提醒").font(.subheadline).foregroundColor(.primary)
                        }
                        .tint(accent)
                        Divider()
                        Toggle(isOn: Binding(
                            get: { XUIManager.notifEnabled(XUIManager.NotifKey.conn) },
                            set: { XUIManager.setNotif(XUIManager.NotifKey.conn, $0) }
                        )) {
                            Text("连接 / 断开提醒").font(.subheadline).foregroundColor(.primary)
                        }
                        .tint(accent)
                    }
                    .padding(18)
                    .background(whiteCard)

                    // v4.3: 板子开关（常亮 + 防误触）—— 与板子下拉控制中心同步, 状态来自 INFO
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "switch.2").foregroundColor(accent)
                            Text("板子开关").font(.headline).foregroundColor(.primary)
                            Spacer()
                        }
                        Toggle(isOn: Binding(
                            get: { xui.info.alwaysOn },
                            set: { on in
                                xui.info.alwaysOn = on
                                xui.sendCtrl(on ? "ao:1" : "ao:0")
                            }
                        )) {
                            Text("常亮模式").font(.subheadline).foregroundColor(.primary)
                        }
                        .tint(accent)
                        .disabled(!xui.state.paired)
                        .opacity(xui.state.paired ? 1 : 0.4)
                        Divider()
                        Toggle(isOn: Binding(
                            get: { xui.info.antiTouch },
                            set: { on in
                                xui.info.antiTouch = on
                                xui.sendCtrl(on ? "at:1" : "at:0")
                            }
                        )) {
                            Text("防误触模式").font(.subheadline).foregroundColor(.primary)
                        }
                        .tint(accent)
                        .disabled(!xui.state.paired)
                        .opacity(xui.state.paired ? 1 : 0.4)
                    }
                    .padding(18)
                    .background(whiteCard)

                    // 应用宫格（白卡）
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "square.grid.2x2.fill").foregroundColor(accent)
                            Text("打开应用").font(.headline).foregroundColor(.primary)
                            Spacer()
                        }
                        LazyVGrid(columns: cols, spacing: 10) {
                            ForEach(apps, id: \.self) { name in
                                Button {
                                    // v4.0: 点游戏 = 板子进游戏 + APP 自动进手柄(联动)
                                    if name == "游戏" {
                                        xui.sendCtrl("app:游戏")
                                        showGamepad = true
                                    } else {
                                        xui.sendCtrl("app:\(name)")
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: appIcon(name))
                                            .font(.system(size: 24))
                                            .foregroundColor(accent)
                                        Text(name)
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray6))
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(!xui.state.paired)
                                .opacity(xui.state.paired ? 1 : 0.4)
                            }
                        }
                    }
                    .padding(18)
                    .background(whiteCard)

                    // 滑条卡（v3.47: 拖动实时发送+苹果式拖拽气泡）
                    VStack(spacing: 16) {
                        sliderRow(id: "bri", title: "💡 亮度", value: $brightness) { v in
                            xui.sendCtrl("bri:\(Int(v))")
                        }
                        Divider()
                        sliderRow(id: "vol", title: "🔊 音量", value: $volume) { v in
                            xui.sendCtrl("vol:\(Int(v))")
                        }
                    }
                    .padding(18)
                    .background(whiteCard)

                    // 电源操作（v4.0: 加回一键清理后台——真正释放内存）
                    HStack(spacing: 12) {
                        Button {
                            // v4.0: 先回桌面再清后台(与固件 xui_close_bg_apps_for_ota 同款, 关掉所有后台App腾内存)
                            xui.sendCtrl("app:桌面")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                xui.sendCtrl("bg:clear")
                            }
                            clearFlash = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                clearFlash = false
                            }
                        } label: {
                            Label(clearFlash ? "已清理!" : "清理后台", systemImage: "trash")
                                .font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(clearFlash ? Color.green : Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

                        Button {
                            xui.sendCtrl("reboot")
                        } label: {
                            Label("重启", systemImage: "arrow.clockwise")
                                .font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

                        Button {
                            xui.sendCtrl("shutdown")
                        } label: {
                            Label("关机", systemImage: "power")
                                .font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    .disabled(!xui.state.paired)
                    .opacity(xui.state.paired ? 1 : 0.4)

                    // 中继状态
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(accent)
                            Text("BLE 中继：\(relay.relayCount) 次")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        // V3.7: 诊断详情 —— 最近转发URL/大小/错误, 一眼看出卡在哪
                        if !relay.lastRelay.isEmpty {
                            Text(relay.lastRelay)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        if !relay.lastError.isEmpty {
                            Text("❌ \(relay.lastError)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }
                    }
                    .padding(14)
                    .background(whiteCard)

                    // V3.9: 运行日志卡 —— 连接/操作/转发全程记录, 右上角一键复制发给小龙虾
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(accent)
                            Text("运行日志 (\(logger.entries.count))")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Button {
                                let _ = logger.copyAll()
                                copiedFlash = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copiedFlash = false
                                }
                            } label: {
                                Label(copiedFlash ? "已复制!" : "复制日志", systemImage: "doc.on.doc")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(copiedFlash ? Color.green : Color.blue)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        if logger.entries.isEmpty && crashReport == nil {
                            Text("暂无日志，扫描连接板子后自动记录")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 3) {
                                    if let c = crashReport {
                                        Text("🧨 崩溃报告:\n\(c.prefix(1500))")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.red)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(6)
                                            .background(Color.red.opacity(0.08))
                                            .cornerRadius(6)
                                        Button("清除崩溃报告") {
                                            CrashCatcher.clearCrash()
                                            crashReport = nil
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                        .padding(.bottom, 4)
                                    }
                                    let recent = Array(logger.entries.suffix(20).enumerated().reversed())
                                    ForEach(recent, id: \.offset) { pair in
                                        Text(pair.element)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.primary.opacity(0.85))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                    .padding(14)
                    .background(whiteCard)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            xui.startAutoConnect()   // V3.17: 进页面即自动连(发现XUI→连接→配对全自动)
            if xui.state.connected { xui.refreshInfo() }
            // V3.14: 启动时检查崩溃报告, 并入日志卡顶部方便复制
            if crashReport == nil, let c = CrashCatcher.readCrash(), !c.isEmpty {
                crashReport = c
                logger.log("🧨 检测到上次崩溃报告! 点击复制日志即可带走")
            }
        }
        // v4.0: 点游戏自动进手柄(全屏盖板)
        .fullScreenCover(isPresented: $showGamepad) {
            GamepadView(showSelf: { showGamepad = false })
        }
    }

    private var statusColor: Color {
        if xui.state.paired { return .green }
        if xui.state.connected { return .blue }
        return .white.opacity(0.6)
    }

    private var whiteCard: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(Color(.systemBackground))
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(.systemGray5), lineWidth: 0.5)
            )
    }

    private func sliderRow(id: String, title: String, value: Binding<Double>, onCommit: @escaping (Double) -> Void) -> some View {
        let editing = sliderEditing == id   // 仅当前滑条显示气泡
        return HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: 62, alignment: .leading)
            VStack(spacing: 2) {
                // v3.47: 拖动中实时大数值气泡（苹果控制中心风格）
                if editing {
                    Text("\(Int(value.wrappedValue))%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(accent))
                        .shadow(color: accent.opacity(0.4), radius: 6, x: 0, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
                Slider(value: value, in: 0...100) { editing in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        sliderEditing = editing ? id : nil
                    }
                    if !editing { onCommit(value.wrappedValue) }   // 松手补发最终值
                }
                .onChange(of: value.wrappedValue) { newVal in
                    if sliderEditing == id { onCommit(newVal) }   // v3.47: 拖动中实时发送
                }
                .tint(accent)
            }
            Text("\(Int(value.wrappedValue))%")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 36)
        }
    }

    private func appIcon(_ name: String) -> String {
        switch name {
        case "AI余量": return "cpu"
        case "监控": return "gauge.with.dots.needle.bottom.50percent"
        case "升级": return "arrow.up.circle.fill"
        case "游戏": return "gamecontroller.fill"
        case "桌面": return "house.fill"   // v3.49: 桌面图标(点击回表盘)
        default: return "circle.grid.2x2.fill"
        }
    }
}
