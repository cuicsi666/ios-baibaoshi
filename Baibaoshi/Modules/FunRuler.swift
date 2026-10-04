import SwiftUI
import CoreMotion
// MARK: - 尺子 + 水平仪（FunRulerView）
// 纯本地：①屏幕尺子（cm / inch 双刻度，Canvas 绘制，可校准并持久化 bb.ruler.cal）；
// ②水平仪（CMMotionManager 加速度计，X/Y 重力分量换算倾角，圆形气泡 + 触感提示）。
// 自定义类型统一 Ruler / Level 前缀，避免与主工程冲突。
enum RulerTool: Int, CaseIterable {
    case ruler = 0
    case level = 1
    var title: String { self == .ruler ? "屏幕尺子" : "水平仪" }
    var short: String { self == .ruler ? "尺子" : "水平仪" }
    var icon: String { self == .ruler ? "ruler.fill" : "arrow.up.and.down.and.arrow.left.and.right" }
    var colors: [Color] {
        switch self {
        case .ruler: return [Color(hex: 0x5B86E5), Color(hex: 0x36D1DC)]
        case .level: return [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)]
        }
    }
    var accent: Color { colors[0] }
}
enum RulerMetrics {
    /// iPhone 逻辑基准：1pt ≈ 1/163 英寸（163ppi @1x），物理密度 = 163 × scale。
    static let basePPI: CGFloat = 163
    static var screenScale: CGFloat { UIScreen.main.scale }
    static var screenSize: CGSize { UIScreen.main.bounds.size }
    static var basePointsPerCm: CGFloat { basePPI / 2.54 }      // ≈ 64.17 pt/cm
    static var basePointsPerInch: CGFloat { basePPI }           // ≈ 163 pt/inch
    static func pointsPerCm(_ cal: Double) -> CGFloat {
        max(12, basePointsPerCm * CGFloat(cal))
    }
    static func pointsPerInch(_ cal: Double) -> CGFloat {
        max(30, basePointsPerInch * CGFloat(cal))
    }
    static func cm(_ points: CGFloat, cal: Double) -> Double {
        Double(points) / Double(pointsPerCm(cal))
    }
    static func inch(_ points: CGFloat, cal: Double) -> Double {
        Double(points) / Double(pointsPerInch(cal))
    }
}
/// 通用单刻度尺：从底边向上画线，顶部标数字（0 对齐视图左边缘）。
struct RulerScaleView: View {
    var pointsPerUnit: CGFloat
    var subsPerUnit: Int
    var mediumEvery: Int
    var labelEvery: Int
    var colors: [Color]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            guard w > 24, h > 24, pointsPerUnit > 6, subsPerUnit > 1 else { return }
            let step = pointsPerUnit / CGFloat(subsPerUnit)
            let count = max(1, Int(w / step))
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: colors),
                startPoint: .zero,
                endPoint: CGPoint(x: w, y: 0))
            for i in 0...count {
                let x = CGFloat(i) * step
                if x > w - 0.5 { break }
                let isLabel = i % labelEvery == 0
                let isMedium = i % mediumEvery == 0
                let frac: CGFloat = isLabel ? 0.60 : (isMedium ? 0.38 : 0.22)
                var p = Path()
                p.move(to: CGPoint(x: x, y: h))
                p.addLine(to: CGPoint(x: x, y: h - h * frac))
                ctx.stroke(p, with: shading, lineWidth: isLabel ? 1.6 : 1)
                if isLabel {
                    ctx.draw(Text("\(i / labelEvery)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(colors.first ?? .primary),
                        at: CGPoint(x: x + 2.5, y: 4), anchor: .topLeading)
                }
            }
        }
    }
}
final class LevelMotion: ObservableObject {
    @Published var available = true
    @Published var hasData = false
    @Published var tiltX: Double = 0        // 左右倾角（度，+ 表示右侧偏低）
    @Published var tiltY: Double = 0        // 前后倾角（度，+ 表示顶部偏低）
    private let manager = CMMotionManager()
    var total: Double { min(90, (tiltX * tiltX + tiltY * tiltY).squareRoot()) }
    var isLevel: Bool { hasData && total < 1.0 }
    func start() {
        guard manager.isAccelerometerAvailable else {
            available = false
            hasData = false
            return
        }
        available = true
        manager.accelerometerUpdateInterval = 1.0 / 60.0
        manager.startAccelerometerUpdates(to: OperationQueue.main) { [weak self] data, _ in
            guard let self = self, let a = data?.acceleration else { return }
            let x = max(-1.0, min(1.0, a.x))
            let y = max(-1.0, min(1.0, a.y))
            self.tiltX = asin(x) * 180 / .pi
            self.tiltY = asin(y) * 180 / .pi
            self.hasData = true
        }
    }
    func stop() {
        manager.stopAccelerometerUpdates()
        hasData = false
        tiltX = 0
        tiltY = 0
    }
}
struct LevelBubbleView: View {
    let tiltX: Double
    let tiltY: Double
    let isLevel: Bool
    let active: Bool
    let colors: [Color]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height)
            let radius: CGFloat = side / 2 - 8
            let maxShift: CGFloat = radius * 0.70
            let k: CGFloat = maxShift / 18.0                       // 18° 达到最大偏移
            let ox: CGFloat = max(-maxShift, min(maxShift, -CGFloat(tiltX) * k))
            let oy: CGFloat = max(-maxShift, min(maxShift, CGFloat(tiltY) * k))
            ZStack {
                Circle().fill(Theme.panel(scheme == .dark))
                Circle()
                    .strokeBorder(Theme.hairline(scheme == .dark), lineWidth: 1)
                    .frame(width: side - 16, height: side - 16)
                ForEach(1...2) { i in
                    Circle()
                        .strokeBorder(Theme.hairline(scheme == .dark), lineWidth: 1)
                        .frame(width: (side - 16) * CGFloat(i) / 3, height: (side - 16) * CGFloat(i) / 3)
                }
                // 中心十字与 1° 容差圈
                Rectangle().fill(Theme.hairline(scheme == .dark)).frame(width: side - 16, height: 1)
                Rectangle().fill(Theme.hairline(scheme == .dark)).frame(width: 1, height: side - 16)
                Circle()
                    .strokeBorder((isLevel ? Theme.success : Color.secondary).opacity(0.45),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: radius * 0.22, height: radius * 0.22)
                Circle()
                    .fill(isLevel ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Theme.gradient(colors)))
                    .frame(width: 54, height: 54)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
                    .shadow(color: (isLevel ? Theme.success : colors.last!).opacity(0.45), radius: 12, y: 4)
                    .offset(x: ox, y: oy)
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: ox)
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: oy)
                if !active {
                    Text("传感器未启动")
                        .font(BBFont.cap(12))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
struct FunRulerView: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("bb.ruler.tool") private var toolRaw = 0
    @AppStorage("bb.ruler.cal") private var cal: Double = 1.0
    @StateObject private var motion = LevelMotion()
    private var tool: RulerTool { RulerTool(rawValue: toolRaw) ?? .ruler }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: tool.icon, colors: tool.colors,
                           title: "尺子 · 水平仪", subtitle: "屏幕尺子与气泡水平仪合二为一")
                BBCard(padding: 6, radius: BBRadius.m) {
                    BBSegmented(options: [("屏幕尺子", 0), ("水平仪", 1)],
                                selection: Binding(get: { toolRaw }, set: { switchTool($0) }))
                }
                if tool == .ruler { rulerSection } else { levelSection }
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("尺子 · 水平仪")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if tool == .level { motion.start() } }
        .onDisappear { motion.stop() }
        .onChange(of: toolRaw) { v in
            if (RulerTool(rawValue: v) ?? .ruler) == .level { motion.start() } else { motion.stop() }
        }
    }
    // MARK: 尺子
    private var rulerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            BBCard(padding: 12, radius: BBRadius.m) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        BBSectionHeader("厘米刻度", icon: "ruler.fill", colors: tool.colors)
                        Spacer()
                        BBPill(text: "0 = 卡片左边缘", color: tool.accent)
                    }
                    RulerScaleView(pointsPerUnit: RulerMetrics.pointsPerCm(cal),
                                   subsPerUnit: 10, mediumEvery: 5, labelEvery: 10,
                                   colors: tool.colors)
                        .frame(height: 74)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.panel(scheme == .dark))
                        )
                    Divider().overlay(Theme.hairline(scheme == .dark))
                    BBSectionHeader("英寸刻度", icon: "ruler", colors: tool.colors)
                    RulerScaleView(pointsPerUnit: RulerMetrics.pointsPerInch(cal),
                                   subsPerUnit: 8, mediumEvery: 4, labelEvery: 8,
                                   colors: tool.colors)
                        .frame(height: 74)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.panel(scheme == .dark))
                        )
                    Text("把物体紧贴卡片左边缘摆放，即可直接读数")
                        .font(BBFont.cap(10))
                        .foregroundColor(.secondary)
                }
            }
            BBCard {
                HStack(spacing: 12) {
                    BBStat(label: "屏幕宽", value: String(format: "%.2f", screenWidthCM), unit: "cm",
                           icon: "arrow.left.and.right", colors: tool.colors)
                    BBStat(label: "屏幕宽", value: String(format: "%.2f", screenWidthIn), unit: "in",
                           icon: "arrow.left.and.right", colors: tool.colors)
                }
            }
            BBCard {
                VStack(alignment: .leading, spacing: 12) {
                    BBSectionHeader("校准", icon: "slider.horizontal.3", colors: tool.colors)
                    HStack {
                        Text("校准系数").font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(String(format: "%.1f%%", cal * 100))
                            .font(BBFont.mono)
                            .foregroundColor(tool.accent)
                    }
                    Slider(value: $cal, in: 0.75...1.25)
                        .tint(tool.accent)
                    HStack {
                        Text("与实物不符时左右微调，实时生效")
                            .font(BBFont.cap(11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            BBHaptic.tap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { cal = 1.0 }
                        } label: {
                            Text("重置")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(tool.accent)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(tool.accent.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            BBCard {
                VStack(alignment: .leading, spacing: 10) {
                    BBSectionHeader("校准参考", icon: "creditcard.fill", colors: tool.colors)
                    BBKV(key: "银行卡 / 身份证 标准宽", value: "8.56 cm")
                    Divider().overlay(Theme.hairline(scheme == .dark))
                    BBKV(key: "标准高", value: "5.40 cm")
                    Divider().overlay(Theme.hairline(scheme == .dark))
                    BBKV(key: "基准换算", value: String(format: "%.1f pt/cm", Double(RulerMetrics.pointsPerCm(cal))))
                    Divider().overlay(Theme.hairline(scheme == .dark))
                    BBKV(key: "屏幕 scale", value: "\(Int(RulerMetrics.screenScale))x")
                    Text("校准系数已保存到 bb.ruler.cal，下次打开自动沿用")
                        .font(BBFont.cap(10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    private var screenWidthCM: Double {
        RulerMetrics.cm(RulerMetrics.screenSize.width, cal: cal)
    }
    private var screenWidthIn: Double {
        RulerMetrics.inch(RulerMetrics.screenSize.width, cal: cal)
    }
    // MARK: 水平仪
    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            BBCard {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        BBPill(text: motion.isLevel ? "已水平" : "调整中",
                               color: motion.isLevel ? Theme.success : Theme.warning)
                        BBPill(text: String(format: "偏差 %.1f°", motion.total), color: tool.accent)
                        Spacer()
                        if motion.available {
                            BBPill(text: "实时", color: Theme.info)
                        } else {
                            BBPill(text: "不可用", color: Theme.danger)
                        }
                    }
                    LevelBubbleView(tiltX: motion.tiltX,
                                    tiltY: motion.tiltY,
                                    isLevel: motion.isLevel,
                                    active: motion.hasData,
                                    colors: tool.colors)
                        .frame(height: 270)
                    Text(motion.isLevel ? "已经水平，可以开工了 ✅" : "气泡偏向抬高的一侧，把它带回中心")
                        .font(BBFont.cap(12))
                        .foregroundColor(motion.isLevel ? Theme.success : .secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: motion.isLevel)
                }
            }
            BBCard {
                HStack(spacing: 12) {
                    BBStat(label: "X 轴倾角", value: String(format: "%.1f", motion.tiltX), unit: "°",
                           icon: "arrow.left.and.right",
                           colors: [Color(hex: 0x5B86E5), Color(hex: 0x36D1DC)])
                    BBStat(label: "Y 轴倾角", value: String(format: "%.1f", motion.tiltY), unit: "°",
                           icon: "arrow.up.and.down",
                           colors: [Color(hex: 0xFF9A5A), Color(hex: 0xB45309)])
                }
            }
            BBCard {
                VStack(alignment: .leading, spacing: 10) {
                    BBSectionHeader("读数说明", icon: "info.circle.fill", colors: tool.colors)
                    BBKV(key: "传感器", value: "加速度计（免权限）")
                    Divider().overlay(Theme.hairline(scheme == .dark))
                    BBKV(key: "采样频率", value: "60 Hz")
                    Divider().overlay(Theme.hairline(scheme == .dark))
                    BBKV(key: "水平判定", value: "|倾角| < 1°")
                    Divider().overlay(Theme.hairline(scheme == .dark))
                    BBKV(key: "X / Y 含义", value: "左右 / 前后 相对水平面")
                    Text("把手机平放在待测平面上读数；离开页面自动停止传感器")
                        .font(BBFont.cap(10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .onChange(of: motion.isLevel) { v in
            if v { BBHaptic.success() }
        }
    }
    // MARK: 逻辑
    private func switchTool(_ raw: Int) {
        toolRaw = raw
    }
}
