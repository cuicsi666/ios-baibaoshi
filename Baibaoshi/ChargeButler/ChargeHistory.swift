import Foundation
import Combine

/// 历史充电数据存储（JSON 落盘），用于提升预估准确率
final class ChargeHistory: ObservableObject {
    static let shared = ChargeHistory()

    @Published private(set) var sessions: [ChargeSession] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("charge_history.json")
    }

    private init() { load() }

    // MARK: 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let list = try? dec.decode([ChargeSession].self, from: data) {
            sessions = list.sorted { $0.start > $1.start }
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(sessions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ s: ChargeSession) {
        sessions.insert(s, at: 0)
        if sessions.count > 60 { sessions = Array(sessions.prefix(60)) }
        save()
    }

    func clear() {
        sessions.removeAll()
        save()
    }

    // MARK: 分段速率（预估引擎用）

    /// 按电量段（10% 一桶）统计历史平均速率，最近会话权重更高
    /// - Returns: [电量段起点: %/分钟]
    func bucketRates() -> [Int: Double] {
        var buckets: [Int: RateBucket] = [:]
        for (i, s) in sessions.prefix(8).enumerated() {
            let w = 1.0 / Double(i + 1)   // 越新权重越高
            for (p, q) in zip(s.points, s.points.dropFirst()) {
                guard q.level > p.level else { continue }
                let mid = Double(p.level + q.level) / 2
                let key = Int(mid / 10) * 10
                let mins = q.t.timeIntervalSince(p.t) / 60
                guard mins > 0.02, mins < 30 else { continue }  // 过滤异常样本
                var b = buckets[key] ?? RateBucket()
                b.minutes += mins * w
                b.percents += Double(q.level - p.level) * w
                b.samples += 1
                buckets[key] = b
            }
        }
        var out: [Int: Double] = [:]
        for (k, b) in buckets where b.rate > 0.05 {
            out[k] = b.rate
        }
        return out
    }

    // MARK: 统计

    var averageFullDurationMinutes: Double? {
        let full = sessions.filter { $0.reachedFull }
        guard !full.isEmpty else { return nil }
        return full.map(\.durationMinutes).reduce(0, +) / Double(full.count)
    }

    var lastSession: ChargeSession? { sessions.first }
}
