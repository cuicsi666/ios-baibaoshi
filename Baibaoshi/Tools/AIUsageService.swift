import Foundation

// MARK: - AI 用量数据模型

struct AIUsage: Codable {
    var credit: Double = 0        // 今日电耗
    var monthCredit: Double = 0   // 本月电耗
    var requests: Int = 0
    var tokens: Int = 0
    var promptTokens: Int = 0
    var completionTokens: Int = 0
    var cost: Double { credit / 30000 * 100 }   // 30000电 = 100元
    var date = ""
}

// 每日历史记录
struct AIUsageDay: Codable, Identifiable {
    var id: String { date }
    var date: String       // yyyy-MM-dd
    var credit: Double
    var requests: Int
    var tokens: Int
    var cost: Double

    var dateDisplay: String { date }
    var costDisplay: String { String(format: "¥%.2f", cost) }
}

// MARK: - AI 用量服务

final class AIUsageService: ObservableObject {
    static let shared = AIUsageService()

    @Published var today = AIUsage()
    @Published var history: [AIUsageDay] = []
    @Published var loading = false
    @Published var lastError: String?
    @Published var lastUpdated = ""

    // 通过 URLSession 拉取（解决 ATS：ipix 是 https，直接可用）
    private let endpoint = URL(string: "https://ai.ipix.ink/guest/dashboard")!
    private let apiToken = "UhZg04VXm89GtA4fpkutrw"
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var historyURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ai_usage_history.json")
    }

    private init() { loadHistory() }

    // MARK: 拉取当日用量

    func fetch(completion: (() -> Void)? = nil) {
        guard !loading else { return }
        loading = true
        lastError = nil
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["s": apiToken])
        req.timeoutInterval = 20

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading = false
                if let error = error {
                    self.lastError = "拉取失败：\(error.localizedDescription)"
                    completion?()
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.lastError = "解析失败"
                    completion?()
                    return
                }
                self.parse(json)
                completion?()
            }
        }.resume()
    }

    private func parse(_ json: [String: Any]) {
        let todayCredit = (json["today_credit"] as? NSNumber)?.doubleValue ?? 0
        let monthCredit = (json["month_credit"] as? NSNumber)?.doubleValue ?? 0
        let requests = (json["today_requests"] as? NSNumber)?.intValue ?? 0
        let tokens = (json["today_tokens"] as? NSNumber)?.intValue ?? 0
        let prompt = (json["today_prompt"] as? NSNumber)?.intValue ?? 0
        let completion = (json["today_completion"] as? NSNumber)?.intValue ?? 0

        let now = Date()
        today = AIUsage(credit: todayCredit,
                        monthCredit: monthCredit,
                        requests: requests,
                        tokens: tokens,
                        promptTokens: prompt,
                        completionTokens: completion,
                        date: dateFormatter.string(from: now))

        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
        lastUpdated = f.string(from: now)

        saveTodayIfNeeded()
    }

    // MARK: 本地历史（每日累积）

    private func saveTodayIfNeeded() {
        let key = today.date
        if let first = history.first, first.date == key {
            // 今天已存在 → 更新
            history[0] = AIUsageDay(date: key, credit: today.credit, requests: today.requests, tokens: today.tokens, cost: today.cost)
        } else {
            // 新的一天 → 插入
            history.insert(AIUsageDay(date: key, credit: today.credit, requests: today.requests, tokens: today.tokens, cost: today.cost), at: 0)
        }
        saveHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        if let list = try? JSONDecoder().decode([AIUsageDay].self, from: data) {
            history = list.sorted { $0.date > $1.date }
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    // 汇总
    var totalCost: Double { history.reduce(0) { $0 + $1.cost } }
    var totalCredit: Double { history.reduce(0) { $0 + $1.credit } }
}