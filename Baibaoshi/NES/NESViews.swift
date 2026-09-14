import SwiftUI
import UIKit

// MARK: - 游戏机主页（游戏库）

struct NESHomeView: View {
    @StateObject private var engine = NESEngine.shared
    @State private var games = NESEngine.romList()
    @State private var active: (name: String, rom: URL)?
    private let cols = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if engine.running, let g = active {
                    NESGameView(gameName: g.name)
                } else {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(games, id: \.name) { g in
                            Button {
                                active = g
                                engine.start(rom: g.rom)
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        if let url = g.icon, let img = UIImage(contentsOfFile: url.path) {
                                            Image(uiImage: img)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 96, height: 88)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        } else {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: 96, height: 88)
                                            Image(systemName: "gamecontroller.fill").foregroundColor(.secondary)
                                        }
                                    }
                                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                                    Text(g.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Theme.background(themeScheme))
        .navigationTitle("游戏机")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if engine.running {
                    Button {
                        engine.stop()
                        active = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var themeScheme: ColorScheme { ThemeManager.shared.isDark ? .dark : .light }
}

// MARK: - 游戏页：屏幕 + 复古手柄

struct NESGameView: View {
    @ObservedObject var engine = NESEngine.shared
    @State private var padBits: UInt32 = 0
    let gameName: String

    var body: some View {
        VStack(spacing: 14) {
            // 屏幕
            if let img = engine.frameImage {
                Image(uiImage: UIImage(cgImage: img))
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(CGSize(width: 256, height: 240), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 2))
                    .shadow(color: .black.opacity(0.4), radius: 10)
                    .padding(.horizontal, 12)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black)
                    .aspectRatio(CGSize(width: 256, height: 240), contentMode: .fit)
                    .overlay(Text("载入中…").foregroundColor(.gray))
                    .padding(.horizontal, 12)
            }

            Text(gameName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 2)

            // 手柄
            ControllerPad(padBits: $padBits)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
        .onDisappear { padBits = 0; engine.setPad(0) }
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - 手柄（摇杆 + AB + 选择/开始）

struct ControllerPad: View {
    @Binding var padBits: UInt32

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            JoyStick(padBits: $padBits)
            Spacer()
            VStack(spacing: 10) {
                PadButton(label: "SELECT", bit: 4, padBits: $padBits, capsule: true)
                PadButton(label: "START", bit: 8, padBits: $padBits, capsule: true)
            }
            Spacer()
            HStack(spacing: 14) {
                PadButton(label: "B", bit: 2, padBits: $padBits, diameter: 62, color: Color(hex: 0xFF5E62))
                PadButton(label: "A", bit: 1, padBits: $padBits, diameter: 62, color: Color(hex: 0x34C759))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .padding(.bottom, 4)
    }
}

// MARK: - 摇杆（连续跟踪 + 8 扇区含斜向 + 死区）

struct JoyStick: View {
    @Binding var padBits: UInt32
    @State private var offset: CGSize = .zero
    private let radius: CGFloat = 46
    private let knob: CGFloat = 58
    private let deadZone: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.07))
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1.5))
                .frame(width: radius * 2 + knob, height: radius * 2 + knob)
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: radius * 1.4, height: radius * 1.4)
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x3B9EFF), Color(hex: 0x2AD4C8)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: knob, height: knob)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 2))
                .shadow(color: Color(hex: 0x2AD4C8).opacity(0.5), radius: 6)
                .offset(offset)
        }
        .frame(width: radius * 2 + knob, height: radius * 2 + knob)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    let dx = v.translation.width, dy = v.translation.height
                    let len = sqrt(dx * dx + dy * dy)
                    let k = len > radius ? radius / len : 1
                    offset = CGSize(width: dx * k, height: dy * k)
                    padBits = Self.bitsFor(dx: dx, dy: dy, deadZone: deadZone)
                }
                .onEnded { _ in
                    offset = .zero
                    padBits = 0
                }
        )
    }

    /// 8 扇区（每 45° 一向，天然支持斜向组合）
    static func bitsFor(dx: CGFloat, dy: CGFloat, deadZone: CGFloat) -> UInt32 {
        let (up, down, left, right): UInt32 = (16, 32, 64, 128)
        if sqrt(dx * dx + dy * dy) < deadZone { return 0 }
        var deg = atan2(dy, dx) * 180 / .pi + 360 + 22.5   // 以右为 0°，顺时针
        if deg >= 360 { deg -= 360 }
        switch Int(deg / 45) {
        case 0: return right
        case 1: return right | down
        case 2: return down
        case 3: return down | left
        case 4: return left
        case 5: return left | up
        case 6: return up
        case 7: return up | right
        default: return 0
        }
    }
}

// MARK: - 按键（按下持续生效）

struct PadButton: View {
    let label: String
    let bit: UInt32
    @Binding var padBits: UInt32
    var diameter: CGFloat = 0
    var color: Color = Color(hex: 0x8E9AAF)
    var capsule = false
    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(.system(size: capsule ? 11 : 20, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: capsule ? 74 : diameter, height: capsule ? 30 : diameter)
            .background(
                Group {
                    if capsule {
                        Capsule().fill(color.opacity(0.85))
                    } else {
                        Circle().fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.7)],
                                                     startPoint: .top, endPoint: .bottom))
                    }
                }
                .shadow(color: color.opacity(0.4), radius: pressed ? 2 : 6)
            )
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
            .contentShape(capsule ? AnyShape(Capsule()) : AnyShape(Circle()))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed { pressed = true; padBits |= bit }
                    }
                    .onEnded { _ in
                        pressed = false
                        padBits &= ~bit
                    }
            )
    }
}
