import Foundation
import CryptoKit

// MARK: - BilibiliSponsorBlock 数据模型

struct BSBSegment: Codable, Identifiable {
    var id: UUID = UUID()
    var start: Double
    var end: Double
    var category: String
    var actionType: String
    var votes: Int?

    var startText: String { Self.timestamp(start) }
    var endText: String { Self.timestamp(end) }
    var durationText: String { String(format: "%.0f 秒", end - start) }

    static func timestamp(_ s: Double) -> String {
        let sec = Int(s)
        let m = sec / 60, ss = sec % 60
        return m > 0 ? String(format: "%d:%02d", m, ss) : "\(ss)"
    }
}

struct BSBSegmentGroup: Codable {
    var videoID: String
    var segments: [BSBSegment]
}

// MARK: - 视频空降助手服务

final class BilibiliSponsorService: ObservableObject {
    static let shared = BilibiliSponsorService()

    @Published var input = ""
    @Published var loading = false
    @Published var message = ""
    @Published var resolvedBvid = ""
    @Published var groups: [BSBSegmentGroup] = []

    private let baseURL = "https://www.bsbsb.top"

    // MARK: 解析 BV 号（支持完整 URL 或裸 BV）

    func parseBvid(from text: String) -> String? {
        let pattern = #"BV[0-9A-Za-z]{10}"#
        // 也支持 /video/ 路径后紧跟的 BV
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }

    // MARK: 查询跳过片段

    func fetch() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bvid = parseBvid(from: text) else {
            message = "无法识别视频，请输入 BV 号或 B站视频链接"
            return
        }
        resolvedBvid = bvid
        loading = true
        message = ""

        // hashPrefix = hex(SHA256(bvid)) 前 4 位
        let digest = SHA256.hash(data: Data(bvid.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let hashPrefix = String(hex.prefix(4))
        let endpoint = "\(baseURL)/api/skipSegments/\(hashPrefix)?categories=sponsor,selfpromo,intro,outro,interaction"

        guard let url = URL(string: endpoint) else {
            loading = false
            message = "URL 构造失败"
            return
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading = false
                if let error = error {
                    self.message = "请求失败：\(error.localizedDescription)"
                    return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 404 {
                    self.groups = []
                    self.message = "该视频暂无网友提交的跳过片段"
                    return
                }
                guard let data = data else {
                    self.message = "无数据返回"
                    return
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let groups = try? decoder.decode([BSBSegmentGroup].self, from: data) {
                    let filtered = groups.filter { $0.videoID == bvid }
                    if filtered.isEmpty {
                        // 可能 hash 前缀匹配但返回了别的视频 → 全返回
                        self.groups = groups
                        self.message = groups.isEmpty ? "暂无片段" : "返回 \(groups.count) 组数据"
                    } else {
                        self.groups = filtered
                        let total = filtered.reduce(0) { $0 + $1.segments.count }
                        self.message = "发现 \(total) 处跳过片段"
                    }
                } else {
                    self.message = "解析失败（HTTP \(code)）"
                }
            }
        }.resume()
    }

    // 清空
    func clear() {
        input = ""
        resolvedBvid = ""
        groups = []
        message = ""
    }
}