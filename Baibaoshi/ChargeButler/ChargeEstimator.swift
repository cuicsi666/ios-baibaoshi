import Foundation

// MARK: - 充电曲线模型（来自内置 JSON：公开评测数据）

struct CurveSegment: Codable {
    let from: Int
    let to: Int
    let rate: Double   // %/分钟
}

struct ChargeCurve: Codable {
    let id: String
    let name: String
    let match: [String]
    let segments: [CurveSegment]
}

struct ChargeReference: Codable {
    let updated: String
    let source: String
    let note: String?
    let curves: [ChargeCurve]
}

// MARK: - 预估结果

struct Estimate: Equatable {
    let minutesLeft: Double
    let doneAt: Date
    let blendedRate: Double      // 当前段混合速率 %/分钟
    let sourceNote: String       // 数据来源说明
    let curveName: String

    var timeText: String {
        let m = Int((minutesLeft).rounded())
        if m < 1 { return "不到 1 分钟" }
        if m < 60 { return "\(m) 分钟" }
        let h = m / 60, mm = m % 60
        return mm == 0 ? "\(h) 小时" : "\(h) 小时 \(mm) 分"
    }
    var doneAtText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: doneAt)
    }
    var rateText: String { String(format: "%.2f%%/分", blendedRate) }
}

// MARK: - 预估引擎：实时速率 × 历史统计 × 参考曲线 三源混合

final class ChargeEstimator {
    static let shared = ChargeEstimator()

    let reference: ChargeReference

    private static let fallback = ChargeReference(
        updated: "2026-09-15",
        source: "内置默认曲线",
        note: nil,
        curves: [ChargeCurve(id: "fast_20w", name: "默认 20W PD", match: [],
                             segments: [
                                CurveSegment(from: 0, to: 20, rate: 1.55),
                                CurveSegment(from: 20, to: 50, rate: 1.35),
                                CurveSegment(from: 50, to: 70, rate: 1.05),
                                CurveSegment(from: 70, to: 80, rate: 0.80),
                                CurveSegment(from: 80, to: 90, rate: 0.50),
                                CurveSegment(from: 90, to: 95, rate: 0.32),
                                CurveSegment(from: 95, to: 100, rate: 0.24)
                             ])]
    )

    init() {
        if let url = Bundle.main.url(forResource: "charge_reference", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let ref = try? JSONDecoder().decode(ChargeReference.self, from: data) {
            reference = ref
        } else {
            reference = Self.fallback
        }
    }

    /// 按机型选择最合适的参考曲线
    func bestCurve(for machine: String) -> ChargeCurve {
        for c in reference.curves where !c.match.isEmpty {
            for m in c.match where machine.hasPrefix(m) {
                return c
            }
        }
        return reference.curves.first { $0.match.isEmpty } ?? Self.fallback.curves[0]
    }

    private func curveRate(_ level: Int, curve: ChargeCurve) -> Double {
        curve.segments.first { level >= $0.from && level < $0.to }?.rate ?? 0.25
    }

    // 权重配置
    private static let liveNearWeight = 0.50    // 近段实时速率权重
    private static let histNearWeight = 0.35
    private static let curveNearWeight = 0.15
    private static let histFarWeight = 0.60     // 远段历史权重
    private static let curveFarWeight = 0.40
    private static let liveInfluenceRange = 15.0 // 实时速率影响范围（百分点）

    /// 三源混合速率
    private func blendedRate(level: Int, distFromNow: Double,
                             live: Double?, history: [Int: Double],
                             curve: ChargeCurve) -> Double {
        let cr = curveRate(level, curve: curve)
        let bucket = Int(Double(level) / 10) * 10
        let hist = history[bucket] ?? history[max(bucket - 10, 0)]

        if let live = live, live > 0.05, distFromNow < Self.liveInfluenceRange {
            let h = hist ?? cr
            return live * Self.liveNearWeight + h * Self.histNearWeight + cr * Self.curveNearWeight
        }
        if let h = hist {
            return h * Self.histFarWeight + cr * Self.curveFarWeight
        }
        return cr
    }

    /// 预估从 level 到 target 的剩余时间
    func estimate(level: Int, target: Int, liveRate: Double?,
                  history: [Int: Double], curve: ChargeCurve) -> Estimate? {
        guard level >= 0, level < target, target <= 100 else { return nil }

        var minutes = 0.0
        var cur = Double(level)
        var firstRate = 0.0
        var usedLive = false
        var usedHist = false

        while cur < Double(target) {
            let segLevel = Int(cur)
            let dist = cur - Double(level)
            let cr = curveRate(segLevel, curve: curve)
            let bucket = Int(Double(segLevel) / 10) * 10
            let hist = history[bucket] ?? history[max(bucket - 10, 0)]

            var r: Double
            if let live = liveRate, live > 0.05, dist < Self.liveInfluenceRange {
                let h = hist ?? cr
                r = live * Self.liveNearWeight + h * Self.histNearWeight + cr * Self.curveNearWeight
                usedLive = true
            } else if let h = hist {
                r = h * Self.histFarWeight + cr * Self.curveFarWeight
                usedHist = true
            } else {
                r = cr
            }
            r = max(r, 0.08)   // 防除零，最低 0.08%/min
            if firstRate == 0 { firstRate = r }
            minutes += 1.0 / r
            cur += 1
        }

        guard minutes > 0 else { return nil }

        var note = "参考曲线"
        if usedLive && usedHist { note = "实时 + 历史 + 曲线" }
        else if usedLive { note = "实时 + 曲线" }
        else if usedHist { note = "历史 + 曲线" }

        return Estimate(minutesLeft: minutes,
                        doneAt: Date().addingTimeInterval(minutes * 60),
                        blendedRate: firstRate,
                        sourceNote: note,
                        curveName: curve.name)
    }
}
