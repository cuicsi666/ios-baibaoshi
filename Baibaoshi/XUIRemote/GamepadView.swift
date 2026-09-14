import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════
// XUI 掌机手柄 v3.43 —— 横屏复古掌机风格（GBA 式双握）
//   · 上方：横向掌机屏幕区（状态/方向/连接信息）
//   · 下方左侧：传统圆形十字方向键（支持滑动 8 向）
//   · 下方右侧：A/B 圆形动作键 + SELECT/START 小键
//   · 深色背景、立体按压感、无手机截图感
// BLE: pad:<key>:<0/1> / back
// ═══════════════════════════════════════════════════════════════
struct GamepadView: View {
    @StateObject private var xui = XUIManager.shared
    @State private var held = Set<String>()
    @State private var joyDirs: Set<String> = []
    var showSelf: (() -> Void)? = nil   // v4.0: 点游戏自动进手柄后, 返回按钮回主控页

    private let bezel = Color(red: 0.16, green: 0.17, blue: 0.22)
    private let screenInner = Color(red: 0.045, green: 0.055, blue: 0.09)
    private let padGray = Color(red: 0.32, green: 0.33, blue: 0.38)
    private let padGrayDark = Color(red: 0.20, green: 0.21, blue: 0.25)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if w >= h {
                consoleLayout(w: w, h: h)   // 横屏：直接掌机布局
            } else {
                // V3.45: 竖屏也强制横屏掌机 —— 内容旋转 90° 显示，旋转手机必有反应
                consoleLayout(w: h, h: w)
                    .rotationEffect(.degrees(90))
                    .frame(width: w, height: h)
                    .clipped()
            }
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea())
        .statusBarHidden()
    }

    // ═══ 横屏掌机主布局 ═══
    private func consoleLayout(w: CGFloat, h: CGFloat) -> some View {
        return VStack(spacing: 6) {
            // ── 状态条 ──
            HStack(spacing: 10) {
                Text("🕹 XUI 掌机")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                if xui.state.paired {
                    Label("已连接", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                } else if xui.state.connected {
                    Label("连接中", systemImage: "link")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.yellow)
                } else {
                    Label("未连接", systemImage: "xmark.circle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            // ── 掌机屏幕区（横向） ──
            consoleScreen
                .frame(height: h * 0.34)
                .padding(.horizontal, 12)

            // ── 操作区（左方向键 | 中 SELECT/START+上下选游戏+返回 | 右 A/B）V4.0: 间距拉开+上下选键+确认 ──
            HStack(spacing: 6) {
                // 左栏：十字键（贴左侧, 外拉）
                VStack(spacing: 4) {
                    dpadView(size: min(w * 0.34, h * 0.44))
                    Text("方向")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity)

                // 中栏：SELECT/START + 上下选游戏 + 确认 + 返回（V4.0: 上下键切游戏, 确认键=START）
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        smallKey("SELECT", key: "select")
                        smallKey("START", key: "start")
                    }
                    // 确认键（=START, 游戏里开始 / 菜单确认）
                    Button {
                        xui.sendCtrl("pad:start:1")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            xui.sendCtrl("pad:start:0")
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("确认")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(LinearGradient(colors: [Color.green, Color.green.opacity(0.75)],
                                                          startPoint: .top, endPoint: .bottom))
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .shadow(color: Color.green.opacity(0.45), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                    // 返回（V4.0: 有 showSelf 时回主控页, 无则发 back 给板子）
                    Button {
                        if let s = showSelf { s() }
                        else { xui.sendCtrl("back") }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.left")
                            Text("返回")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(LinearGradient(colors: [Color.orange, Color.orange.opacity(0.75)],
                                                          startPoint: .top, endPoint: .bottom))
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .shadow(color: Color.orange.opacity(0.45), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)

                // 右栏：A/B（贴右侧, 外拉）V4.0: 与方向键间距拉开
                VStack(spacing: 2) {
                    HStack(spacing: 30) {
                        roundKey("B", Color(red: 0.25, green: 0.55, blue: 0.95), key: "b", r: min(w * 0.082, h * 0.16))
                        roundKey("A", Color(red: 0.92, green: 0.30, blue: 0.30), key: "a", r: min(w * 0.082, h * 0.16))
                    }
                    Text("跳 / 攻")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)   // V4.0: 两侧外拉留边
            .padding(.bottom, 6)
        }
    }

    // ═══ 掌机屏幕（装饰+状态反馈） ═══
    private var consoleScreen: some View {
        ZStack {
            // 外壳边框（立体）
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [bezel, bezel.opacity(0.85)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 8, y: 4)

            // 内屏
            RoundedRectangle(cornerRadius: 10)
                .fill(screenInner)
                .padding(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.25, green: 0.35, blue: 0.45).opacity(0.5), lineWidth: 1.5)
                        .padding(10)
                )

            // 屏幕内容
            VStack(spacing: 4) {
                HStack {
                    Text("Nintendo-style")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.30))
                    Spacer()
                    Text(xui.state.paired ? "ONLINE" : "STANDBY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(xui.state.paired ? .green.opacity(0.8) : .gray.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                Spacer()

                // 方向指示（四个箭头）
                HStack(spacing: 22) {
                    arrowInd("arrowtriangle.up.fill", dir: "up")
                    arrowInd("arrowtriangle.down.fill", dir: "down")
                    arrowInd("arrowtriangle.left.fill", dir: "left")
                    arrowInd("arrowtriangle.right.fill", dir: "right")
                }
                .padding(.bottom, 6)

                // 状态行
                Text(statusLine)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.bottom, 12)
            }
        }
    }

    private var statusLine: String {
        if !xui.state.connected { return "waiting board..." }
        if xui.state.paired {
            let b = xui.info.battery
            let v = xui.info.version
            return b >= 0 ? "BAT \(b)% · FW \(v)" : "FW \(v)"
        }
        return "pairing..."
    }

    private func arrowInd(_ icon: String, dir: String) -> some View {
        let on = joyDirs.contains(dir)
        return Image(systemName: icon)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(on ? Color(red: 0.30, green: 0.85, blue: 0.95) : .white.opacity(0.14))
            .shadow(color: on ? Color(red: 0.30, green: 0.85, blue: 0.95).opacity(0.7) : .clear, radius: 6)
    }

    // ═══ 传统圆形十字方向键（滑动 8 向） ═══
    private func dpadView(size: CGFloat) -> some View {
        let armW = size * 0.34
        let armH = size * 0.28
        return ZStack {
            // 底盘（凹陷）
            Circle()
                .fill(RadialGradient(colors: [padGrayDark, Color.black.opacity(0.7)],
                                     center: .center, startRadius: 0, endRadius: size * 0.55))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.7), radius: 8, y: 4)

            // 十字凸起（横臂+竖臂）
            RoundedRectangle(cornerRadius: armH / 2)
                .fill(dpadFace)
                .frame(width: armW, height: armH)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            RoundedRectangle(cornerRadius: armH / 2)
                .fill(dpadFace)
                .frame(width: armH, height: armW)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)

            // 方向臂高亮（按下反馈）
            dpadArm(.up, size: size, armW: armW, armH: armH)
            dpadArm(.down, size: size, armW: armW, armH: armH)
            dpadArm(.left, size: size, armW: armW, armH: armH)
            dpadArm(.right, size: size, armW: armW, armH: armH)

            // 中心凹陷
            Circle()
                .fill(RadialGradient(colors: [padGrayDark, Color.black.opacity(0.8)],
                                     center: .center, startRadius: 0, endRadius: size * 0.14))
                .frame(width: size * 0.22, height: size * 0.22)
                .shadow(color: .black.opacity(0.6), radius: 3)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    let c = CGPoint(x: size / 2, y: size / 2)
                    let dx = v.location.x - c.x
                    let dy = v.location.y - c.y
                    let len = sqrt(dx * dx + dy * dy)
                    let dead = size * 0.12
                    guard len > dead else { setDirs([]); return }
                    let deg = atan2(Double(dy), Double(dx)) * 180.0 / .pi
                    var out: Set<String> = []
                    if deg > -22.5 && deg <= 22.5 { out.insert("right") }
                    else if deg > 22.5 && deg <= 67.5 { out.formUnion(["right", "down"]) }
                    else if deg > 67.5 && deg <= 112.5 { out.insert("down") }
                    else if deg > 112.5 && deg <= 157.5 { out.formUnion(["left", "down"]) }
                    else if deg > 157.5 || deg <= -157.5 { out.insert("left") }
                    else if deg > -157.5 && deg <= -112.5 { out.formUnion(["left", "up"]) }
                    else if deg > -112.5 && deg <= -67.5 { out.insert("up") }
                    else if deg > -67.5 && deg <= -22.5 { out.formUnion(["right", "up"]) }
                    setDirs(out)
                }
                .onEnded { _ in setDirs([]) }
        )
    }

    private var dpadFace: LinearGradient {
        LinearGradient(colors: [padGray.opacity(0.95), padGrayDark],
                       startPoint: .top, endPoint: .bottom)
    }

    // 十字键单臂高亮
    private func dpadArm(_ dir: DirectionInd, size: CGFloat, armW: CGFloat, armH: CGFloat) -> some View {
        let on = joyDirs.contains(dir.rawValue)
        let (x, y) = dpadArmOffset(dir, size: size)
        return RoundedRectangle(cornerRadius: armH / 2)
            .fill(on ? Color.white.opacity(0.28) : .clear)
            .frame(width: armW, height: armH)
            .overlay(
                Image(systemName: dir.symbol)
                    .font(.system(size: size * 0.12, weight: .bold))
                    .foregroundColor(on ? .white : .white.opacity(0.30))
            )
            .offset(x: x, y: y)
    }

    private func dpadArmOffset(_ dir: DirectionInd, size: CGFloat) -> (CGFloat, CGFloat) {
        let d = size * 0.32
        switch dir {
        case .up: return (0, -d)
        case .down: return (0, d)
        case .left: return (-d, 0)
        case .right: return (d, 0)
        }
    }

    private enum DirectionInd: String {
        case up, down, left, right
        var symbol: String {
            switch self {
            case .up: return "arrowtriangle.up.fill"
            case .down: return "arrowtriangle.down.fill"
            case .left: return "arrowtriangle.left.fill"
            case .right: return "arrowtriangle.right.fill"
            }
        }
    }

    // ═══ A/B 圆形动作键（立体+按压） ═══
    private func roundKey(_ label: String, _ color: Color, key: String, r: CGFloat) -> some View {
        let on = held.contains(key)
        return Text(label)
            .font(.system(size: r * 0.55, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .frame(width: r * 2, height: r * 2)
            .background(
                Circle()
                    .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.6)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
            .overlay(
                Circle().stroke(Color.black.opacity(0.4), lineWidth: 4)
                    .offset(y: 3)
                    .mask(Circle().padding(2))
            )
            .shadow(color: color.opacity(0.6), radius: 8, y: 4)
            .scaleEffect(on ? 0.90 : 1.0)
            .brightness(on ? 0.25 : 0)
            .animation(.spring(response: 0.12, dampingFraction: 0.5), value: on)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in press(key) }
                    .onEnded { _ in release(key) }
            )
    }

    // ═══ SELECT / START ═══
    private func smallKey(_ label: String, key: String) -> some View {
        let on = held.contains(key)
        return Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white.opacity(0.9))
            .frame(width: 62, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(colors: [padGray.opacity(0.9), padGrayDark],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            .scaleEffect(on ? 0.92 : 1.0)
            .brightness(on ? 0.2 : 0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in press(key) }
                    .onEnded { _ in release(key) }
            )
    }

    // ═══ 方向发送 ═══
    private func setDirs(_ newDirs: Set<String>) {
        for d in joyDirs where !newDirs.contains(d) { release(d) }
        for d in newDirs where !joyDirs.contains(d) { press(d) }
        joyDirs = newDirs
    }

    private func press(_ key: String) {
        guard !held.contains(key) else { return }
        held.insert(key)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        xui.sendCtrl("pad:\(key):1")
    }
    private func release(_ key: String) {
        guard held.contains(key) else { return }
        held.remove(key)
        xui.sendCtrl("pad:\(key):0")
    }
}