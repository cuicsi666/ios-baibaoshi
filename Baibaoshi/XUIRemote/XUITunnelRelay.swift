import Foundation
import AVFoundation
import UserNotifications

// MARK: - BLE 透传 HTTP 中继（核心：板子 WiFi 断时借手机上网）
// 板子发 {"t":1,"id":N,"m":"POST|GET","url":"...","body":"...","h":{可选自定义请求头}}
// App 用自己的网络转发到 url，回 {"t":2,"id":N,"code":200,"b64":"<base64 body>"}
final class XUITunnelRelay: NSObject, ObservableObject {
    static let shared = XUITunnelRelay()

    @Published var relayCount = 0
    @Published var relayFailCount = 0    // V3.37: 转发失败累计(分测用)
    @Published var relayBytes = 0        // V3.37: 转发成功总字节
    @Published var relayFailBytes = 0    // V3.37: 失败尝试总字节
    @Published var lastRelay = ""
    @Published var lastError = ""   // V3.7: 转发失败详情(网络错/超时), 页面直显
    private var pending = [UInt8: (type: UInt8, payload: [UInt8])]()
    // V3.39: OTA 下载中检测 —— 最近 90s 内收到过 Range 分块请求 = 板子正在下载固件
    //   下载期间日志上报直接本地快速回 200(不转发服务器): 板子日志任务秒成功 → 不误判假死断开 → 下载不被掐断
    private var lastRangeAt = Date.distantPast

    override private init() {
        super.init()
        XUIManager.shared.delegate = self
    }

    /// 收到板子整条隧道消息（由 XUIManager 调）
    func handleIncoming(type: UInt8, payload: [UInt8]) {
        // V3.50: 音乐中转 —— 板子转发音乐命令到手机播放(手机网络无带宽限制)
        if type == TUNMsgType.appCmd.rawValue {
            let str = String(bytes: payload, encoding: .utf8) ?? ""
            XUILogger.shared.log("🎵 收到音乐命令: \(str.prefix(80))")
            MusicRelay.handle(cmdJson: str)
            return
        }
        guard type == TUNMsgType.httpReq.rawValue else {
            XUILogger.shared.log("⏭️ 忽略隧道消息 type=0x\(String(format:"%02X", type))")
            return
        }  // 语音/OTA后续
        let str = String(bytes: payload, encoding: .utf8) ?? ""

        // ---- 标准 JSON 解析 ----
        if let data = str.data(using: .utf8),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = j["id"] as? Int,
           let urlStr = j["url"] as? String {
            route(j: j, id: id, urlStr: urlStr)
            return
        }

        // ---- V3.10 容错解析 ----
        // 根因: V169 板子 tun_http_proxy 拼隧道JSON时 body 内层引号未转义
        // (OTA检查 body 是嵌套JSON如 {"board":...}) → 整条消息非法 → JSONSerialization 失败
        // → 之前直接丢弃 → 升级请求从未转发 → 板子 15s 超时 "网络错误"。
        // AI余量/监控正常是因为 body=空/{} 无内层引号。这里手动抠字段照样转发。
        XUILogger.shared.log("🛠️ JSON非法→容错解析: \(str.prefix(80))...")
        guard let to = tolerantParse(str) else {
            XUILogger.shared.log("❌ 容错解析失败, 丢弃")
            return
        }
        XUILogger.shared.log("🛠️ 容错OK: \(to.method) \(to.url) body=\(to.body.count)B")
        route(j: ["id": to.id, "m": to.method, "url": to.url, "body": to.body], id: to.id, urlStr: to.url)
    }

    /// 统一路由: 提取字段并计数转发
    private func route(j: [String: Any], id: Int, urlStr: String) {
        let method = (j["m"] as? String) ?? "GET"
        let bodyStr = (j["body"] as? String) ?? ""
        let rangeStr = (j["range"] as? String) ?? ""   // V166: 固件分块下载 bytes=start-end
        let hdrs = (j["h"] as? [String: Any]) ?? [:]     // V3.5: 板子要求的自定义请求头(OTA device-id 等)
        XUILogger.shared.log("🌐 收到HTTP请求: \(method) \(urlStr) body=\(bodyStr.count)B range=\(rangeStr) hdrs=\(hdrs.count)个")
        if !rangeStr.isEmpty {
            DispatchQueue.main.async {
                self.lastRangeAt = Date()   // V3.39: 检测到固件分块下载
                XUILogger.shared.log("📥⬇️ 固件下载中(Range \(rangeStr)) — 日志转本地快速回包模式")
            }
        }
        // V3.8: 请求一到就计数(不管转发成败) —— 这样"中继0次"=板子没发请求(配对/连接问题),
        // "次数涨但❌"=手机网络问题, 一眼分辨断在哪段
        DispatchQueue.main.async {
            self.relayCount += 1
            self.lastRelay = "收到 \(method) \(urlStr.prefix(42))"
        }
        Task {
            await forward(id: UInt8(id), method: method, url: urlStr, body: bodyStr, range: rangeStr, hdrs: hdrs)
        }
    }

    /// V3.10: 容错解析非法隧道JSON。板子 V169 拼包时 body 内层引号未转义
    /// → 整条非JSON。手动扫描: "id":后数字, "m":"/"url":"后到下一个引号, body花括号配平截取。
    private func tolerantParse(_ s: String) -> (id: Int, method: String, url: String, body: String)? {
        guard let id = Self.scanInt(s, after: "\"id\":"),
              let method = Self.scanQuoted(s, after: "\"m\":\""),
              let url = Self.scanQuoted(s, after: "\"url\":\"") else { return nil }
        guard let bmk = s.range(of: "\"body\":\""),
              bmk.upperBound < s.endIndex else { return (id, method, url, "") }
        var rest = s[bmk.upperBound...]
        guard rest.first == "{" else { return (id, method, url, "") }
        var depth = 0
        var i = rest.startIndex
        while i < rest.endIndex {
            let c = rest[i]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 {
                    let end = rest.index(after: i)
                    return (id, method, url, String(rest[..<end]))
                }
            }
            i = rest.index(after: i)
        }
        return nil
    }

    private static func scanInt(_ s: String, after marker: String) -> Int? {
        guard let r = s.range(of: marker) else { return nil }
        var v = 0
        var found = false
        for c in s[r.upperBound...] {
            if let d = c.wholeNumberValue { v = v * 10 + d; found = true }
            else if found { break }
        }
        return found ? v : nil
    }

    private static func scanQuoted(_ s: String, after marker: String) -> String? {
        guard let r = s.range(of: marker) else { return nil }
        var out = ""
        for c in s[r.upperBound...] {
            if c == "\"" { break }
            out.append(c)
        }
        return out.isEmpty ? nil : out
    }

    /// V3.8: 强制 IPv4 —— svip.cuicsi.cn 有 AAAA 记录但 8004 端口 IPv6 实测不通,
    /// iPhone 优先解析 IPv6 会连接超时 → 502 → 板子报网络错误。
    /// 纯 http:// 无 SNI/证书问题, 把域名解析成 IPv4 字面量重建 URL;
    /// 已实测 lucky 反代不挑 Host(直接 IP 访问 8004 正常返回), 解析失败则原样返回。
    private static func forceIPv4(_ urlString: String) -> String {
        guard let u = URL(string: urlString),
              let scheme = u.scheme?.lowercased(), scheme == "http",
              let host = u.host, !host.isEmpty else { return urlString }
        // 已是 IPv4 字面量就不折腾
        if !host.isEmpty && host.allSatisfy({ $0.isNumber || $0 == "." }) { return urlString }
        var hints = addrinfo()
        hints.ai_family = AF_INET          // 只要 A 记录
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return urlString }
        defer { freeaddrinfo(res) }
        guard let sa = first.pointee.ai_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else { return urlString }
        let sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var addr = sin.sin_addr
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return urlString }
        let ip = String(cString: buf)
        guard var comps = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return urlString }
        comps.host = ip
        guard let newURL = comps.url else { return urlString }
        return newURL.absoluteString
    }

    private func forward(id: UInt8, method: String, url: String, body: String, range: String = "", hdrs: [String: Any] = [:]) async {
        // V3.39: 固件下载中(90s 窗口) + 日志上报 → 本地秒回 200 不转发服务器
        //   板子 ota 下载占满隧道回包时, 日志转发排队/超时 → 板子误判假死断开下载; 本地回包让日志任务立即成功
        let dlWindow = Date().timeIntervalSince(lastRangeAt) < 90.0
        if dlWindow && url.contains("/api/xui/log") {
            XUILogger.shared.log("⚡ 下载中, 日志本地秒回(不占隧道): \(url.prefix(50))")
            sendReply(id: id, code: 200, data: Data("{\"ok\":true}".utf8), url: url)
            return
        }
        let actualURL = Self.forceIPv4(url)   // V3.8: 域名→IPv4, 绕开 IPv6 死路
        guard let reqURL = URL(string: actualURL) else {
            sendReply(id: id, code: 502, data: Data(), url: url)   // V3.5: URL 无效也别吞包，回 502 让板子快回退
            return
        }
        currentURL = url
        var req = URLRequest(url: reqURL)
        req.httpMethod = method
        req.timeoutInterval = 30    // V166: 固件分块可能较慢
        if !range.isEmpty {
            req.setValue(range, forHTTPHeaderField: "Range")
        }
        for (k, v) in hdrs {          // V3.5: 补上板子要求的请求头
            if let vs = v as? String { req.setValue(vs, forHTTPHeaderField: k) }
        }
        if method == "POST" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body.data(using: .utf8)
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            var code = (resp as? HTTPURLResponse)?.statusCode ?? 200
            var finalData = data
            // V3.13: 无 Range 却返回超大响应(>128KB) = 异常(如代理吞Range/服务器异常), 拒收回502防拖垮蓝牙
            if range.isEmpty && Self.oversized(data) {
                XUILogger.shared.log("⛔ 无Range超大响应 \(data.count)B, 拒收")
                sendReply(id: id, code: 502, data: Data(), url: url)
                DispatchQueue.main.async {
                    self.lastError = "超大响应拒绝: \(url.prefix(48)) \(data.count)B"
                }
                return
            }
            // V3.13: 强制 Range 切片 —— 代理/服务器可能忽略 Range 头返回全量(200),
            //   全量 4.77MB base64 后 6.3MB + 5 万帧塞蓝牙队列 → 内存爆炸闪退(点击升级闪退真凶)。
            //   手机按请求区间自行截取, 回传 ≤ 请求区间, 绝不把全量固件塞进蓝牙。
            if !range.isEmpty,
               let rangeParsed = Self.parseRange(range),
               (code == 200 || code == 206) {
                let total = data.count
                let start = min(rangeParsed.start, total)
                let end = min(rangeParsed.endExclusive, total)
                if start < end {
                    finalData = data.subdata(in: start..<end)
                    code = 206
                    XUILogger.shared.log("✂️ Range切片: \(range) 原始\(data.count)B→取\(finalData.count)B [206]")
                } else if code == 200 {
                    // 服务器给了全量但我们按区间切不到(区间超出)，回 502 让板子重试
                    XUILogger.shared.log("⚠️ Range区间无效: \(range) 全量\(data.count)B")
                    sendReply(id: id, code: 502, data: Data(), url: url)
                    DispatchQueue.main.async {
                        self.lastError = "Range切片失败: \(url.prefix(48))"
                    }
                    return
                }
            }
            XUILogger.shared.log("✅ 转发成功: \(actualURL) → \(finalData.count)B [\(code)]")
            DispatchQueue.main.async {
                self.relayBytes += finalData.count
            }
            sendReply(id: id, code: code, data: finalData, url: url)
            DispatchQueue.main.async {
                self.lastError = ""
                self.lastRelay = "转发 \(actualURL) → \(finalData.count)B [\(code)]"
            }
        } catch {
            // 转发失败：回 code 502 + 空 —— V3.7: 同时把错误详情上屏(NSError 带IPv4/IPv6/超时线索)
            XUILogger.shared.log("❌ 转发失败: \(actualURL) \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.lastError = "\(url.prefix(48)) \(error.localizedDescription)"
                self.relayFailCount += 1
                self.relayFailBytes += body.utf8.count + url.utf8.count
            }
            sendReply(id: id, code: 502, data: Data(), url: url)
        }
    }

    /// V3.13: 解析 Range 头 "bytes=start-end" → (start, endExclusive)
    private static func parseRange(_ s: String) -> (start: Int, endExclusive: Int)? {
        guard s.hasPrefix("bytes=") else { return nil }
        let body = s.dropFirst(6)
        let parts = body.split(separator: "-")
        guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) else { return nil }
        return (a, b + 1)   // 闭区间转半开
    }

    /// V3.13: 防御上限 —— 无 Range 请求响应超 128KB 拒收(防异常大响应拖垮蓝牙队列);
    /// 正常监控/余量/OTA检查都 <50KB, 超限必是异常(如代理吞Range返回全量固件)
    private static func oversized(_ data: Data) -> Bool {
        return data.count > 131072
    }

    /// V3.5: 统一出口 —— 大 JSON 响应(如 42KB dashboard)瘦身后再回板子，
    /// 蓝牙带宽仅 ~1KB/s，传全量 42KB 要 40 秒+还易丢包；只回板子 UI 需要的字段(<400B)
    private func sendReply(id: UInt8, code: Int, data: Data, url: String?) {
        let slim: Data
        if code == 200, let u = url, u.contains("/api/ipix/"),
           data.count > 1024, let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var out: [String: Any] = [:]
            out["today_credit"] = raw["today_credit"] ?? 0
            out["total_tokens"] = raw["total_tokens"] ?? 0
            var packs: [[String: Any]] = []
            for p in (raw["packs"] as? [[String: Any]]) ?? [] {
                packs.append(["status": p["status"] ?? "", "credit": p["credit"] ?? 0,
                              "used": p["used"] ?? 0, "left": p["left"] ?? 0])
            }
            out["packs"] = packs
            slim = (try? JSONSerialization.data(withJSONObject: out)) ?? data
        } else {
            slim = data
        }
        let b64 = slim.base64EncodedString()
        XUILogger.shared.log("↩️ 回包→板: code=\(code) 原\(data.count)B→瘦身\(slim.count)B")
        // V3.17: 大响应(固件块)手工拼JSON串 —— JSONSerialization 处理 44KB b64 曾触发 SIGTRAP,
        //   直接字符串拼接彻底绕开, 字符串本身即合法JSON(b64无特殊字符需转义)。
        let s = "{\"t\":2,\"id\":\(id),\"code\":\(code),\"b64\":\"" + b64 + "\"}"
        XUIManager.shared.tunnelSend(TUNMsgType.httpResp.rawValue, payload: Array(s.utf8))
    }

    private var currentURL: String?
}

extension XUITunnelRelay: XUIManagerDelegate {
    func xuiStateChanged(_ state: XUIState) {}
    func xuiInfoUpdated(_ info: XUIInfo) {}
    func xuiLog(_ msg: String) {}
}


// MARK: - V3.50 音乐手机中转
enum MusicRelay {
    static var player: AVPlayer?
    static var isPlaying = false

    static func handle(cmdJson: String) {
        guard let d = cmdJson.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        let cmd = j["cmd"] as? String ?? ""
        if cmd == "stop" {
            player?.pause()
            player = nil
            isPlaying = false
            XUILogger.shared.log("🎵 音乐已停止(手机端)")
            notifyStop()
            return
        }
        guard cmd == "play", let urlStr = j["url"] as? String, let u = URL(string: urlStr) else { return }
        DispatchQueue.main.async {
            let item = AVPlayerItem(url: u)
            if let p = player { p.replaceCurrentItem(with: item) } else {
                player = AVPlayer(playerItem: item)
            }
            player?.play()
            isPlaying = true
            XUILogger.shared.log("🎵 手机端播放: \(urlStr.prefix(60))")
            notifyPlaying()
            // 后台音频会话
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    private static func notifyPlaying() {
        let c = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "🎵 XUI 音乐"
        content.body = "正在手机端播放（无带宽限制）"
        let req = UNNotificationRequest(identifier: "xui-music", content: content, trigger: nil)
        c.add(req)
    }

    private static func notifyStop() {
        let c = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "⏹ XUI 音乐"
        content.body = "播放已停止"
        let req = UNNotificationRequest(identifier: "xui-music", content: content, trigger: nil)
        c.add(req)
    }
}
