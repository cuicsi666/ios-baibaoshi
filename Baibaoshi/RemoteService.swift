import Foundation
import UIKit
import Combine

/// 百宝箱远程操控引擎
/// - 心跳: 定时上报在线状态到上海云 bb-remote API
/// - 轮询: 定时拉取待执行命令, 收到后按 app/action 深链拉起对应应用(如哔哩Plus)
/// - 本地配置: bb.remoteToken / bb.remoteDevice(留空自动用机型)
final class RemoteService: ObservableObject {
    static let shared = RemoteService()

    @Published var enabled = false
    @Published var lastBeat: Date?
    @Published var lastPollError: String?
    @Published var lastCommand: String?

    private var beatTimer: Timer?
    private var pollTimer: Timer?
    private let base = "https://cuicsi.cn/remote/api"

    var token: String {
        get { UserDefaults.standard.string(forKey: "bb.remoteToken") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "bb.remoteToken") }
    }
    var device: String {
        get { UserDefaults.standard.string(forKey: "bb.remoteDevice") ?? Self.defaultDevice }
        set { UserDefaults.standard.set(newValue, forKey: "bb.remoteDevice") }
    }

    static var defaultDevice: String {
        // 简单机型标识
        UIDevice.current.name.hasPrefix("iPhone") ? "iPhone16e" : "Baibaoshi"
    }

    private init() {}

    // MARK: - 启停

    func applySettings() {
        let en = UserDefaults.standard.object(forKey: "bb.remoteEnabled") as? Bool ?? true
        enabled = en
        guard en else { stopAll(); return }
        start()
    }

    func start() {
        guard enabled, beatTimer == nil else { return }
        // 启动立即心跳一次（快速上线）
        beat { }
        // 心跳 60s
        beatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.beat { }
        }
        // 轮询 15s
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stopAll() {
        beatTimer?.invalidate(); beatTimer = nil
        pollTimer?.invalidate(); pollTimer = nil
    }

    // MARK: - 心跳

    func beat(completion: (() -> Void)? = nil) {
        guard enabled, !token.isEmpty else { completion?(); return }
        var req = URLRequest(url: URL(string: "\(base)/heartbeat")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "token": token,
            "device": device,
            "state": UIApplication.shared.applicationState == .background ? "background" : "foreground",
            "battery": Int(UIDevice.current.batteryLevel * 100)
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            if let resp = resp as? HTTPURLResponse, resp.statusCode == 200 {
                DispatchQueue.main.async { self?.lastBeat = Date() }
            }
            completion?()
        }.resume()
    }

    // MARK: - 轮询命令

    func poll() {
        guard enabled, !token.isEmpty, !device.isEmpty else { return }
        guard let url = URL(string: "\(base)/cmd/poll?token=\(token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")&device=\(device.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, resp, _ in
            guard let self = self else { return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["ok"] as? Bool) == true,
                  let cmd = json["cmd"] as? [String: Any] else { return }
            DispatchQueue.main.async {
                self.lastCommand = String(describing: cmd)
                self.handle(cmd)
            }
        }.resume()
    }

    /// 执行远程命令: 深链拉起目标应用
    private func handle(_ cmd: [String: Any]) {
        guard let app = cmd["app"] as? String else { return }
        let action = cmd["action"] as? String ?? "open"
        let keyword = cmd["keyword"] as? String ?? ""

        switch app.lowercased() {
        case "bilibili", "bilipius", "哔哩", "哔哩plus", "哔哩哔哩":
            openBili(action: action, keyword: keyword)
        default:
            break
        }
        // 回执
        if let id = cmd["id"] as? Int {
            ack(id: id, status: "ok")
        }
    }

    private func openBili(action: String, keyword: String) {
        var urlStr = "bilibili://"
        if action == "play" && !keyword.isEmpty {
            // 搜索 + 自动播放
            let kw = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            urlStr = "bilibili://search?keyword=\(kw)&autoplay=1"
        } else {
            urlStr = "bilibili://"
        }
        guard let url = URL(string: urlStr),
              UIApplication.shared.canOpenURL(url) else {
            // 未安装哔哩Plus, 提示
            NotificationManager.shared.send(title: "哔哩Plus", body: "未检测到哔哩Plus，请先安装", id: "remote-bili")
            return
        }
        UIApplication.shared.open(url) { ok in
            if !ok {
                NotificationManager.shared.send(title: "哔哩Plus", body: "打开失败", id: "remote-bili")
            }
        }
    }

    private func ack(id: Int, status: String) {
        var req = URLRequest(url: URL(string: "\(base)/cmd/\(id)/ack")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token, "status": status])
        URLSession.shared.dataTask(with: req).resume()
    }
}