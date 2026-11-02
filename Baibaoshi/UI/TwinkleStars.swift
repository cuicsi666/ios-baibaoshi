import SwiftUI

/// 顶部随机闪烁星星：颜色 / 亮度 / 大小 / 频率全部随机
struct TwinkleStars: View {
    struct Star {
        let x: CGFloat        // 0~1 横向比例
        let y: CGFloat        // 0~1 纵向比例
        let size: CGFloat
        let color: Color
        let phase: Double
        let speed: Double
    }

    @State private var stars: [Star] = {
        let palette: [Color] = [
            .white,
            Color(hex: 0xFFD54F),   // 金
            Color(hex: 0x80D8FF),   // 冰蓝
            Color(hex: 0xFF9ACE),   // 粉
            Color(hex: 0xB388FF),   // 紫
            Color(hex: 0x69F0AE),   // 薄荷
            Color(hex: 0xFFAB40)    // 橙
        ]
        var list: [Star] = []
        for _ in 0..<6 {
            list.append(Star(x: .random(in: 0.08...0.92),
                             y: .random(in: 0.05...0.85),
                             size: .random(in: 3...9),
                             color: palette.randomElement() ?? .white,
                             phase: .random(in: 0...(2 * .pi)),
                             speed: .random(in: 1.0...3.4)))
        }
        return list
    }()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(Array(stars.enumerated()), id: \.offset) { _, s in
                        let pulse = 0.30 + 0.70 * abs(sin(t * s.speed + s.phase))
                        let d = s.size * (0.65 + 0.55 * pulse)
                        Circle()
                            .fill(s.color)
                            .frame(width: d, height: d)
                            .opacity(pulse)
                            .shadow(color: s.color.opacity(pulse * 0.9), radius: 7)
                            .position(x: geo.size.width * s.x,
                                      y: geo.size.height * s.y)
                    }
                }
            }
        }
        .frame(height: 220)
        .allowsHitTesting(false)
    }
}
