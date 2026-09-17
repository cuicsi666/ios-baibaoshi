import SwiftUI
import UIKit

// MARK: - 应用内检查更新（Gitea Release）
// 检查最新版本 → 下载 IPA → 拉起分享面板 → 全能签签名安装

final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var checking = false
    @Published var hasUpdate = false
    @Published var newVersion = ""
    @Published var releaseNotes = ""
    @Published var downloadURL: URL?
    @Published var downloadProgress: Double = 0
    @Published var downloading = false
    @Published var downloadedIPA: URL?
    @Published var message = ""

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // 更新分发：飞牛导航站公开静态目录（无需认证）
    private let updateBase = "http://6.6.6.130:8099/updates/baibaoshi"
    private var manifestURL: URL? { URL(string: "\(updateBase)/update.json") }

    private var ipaURL: URL? {
        guard let file = ipaFile else { return nil }
        return URL(string: "\(updateBase)/\(file)")
    }
    private var ipaFile: String?

    /// 版本号比较：V4 > V3
    private func isNewer(_ latest: String) -> Bool {
        func nums(_ s: String) -> [Int] {
            s.filter { $0.isNumber || $0 == "." }.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = nums(latest), b = nums(currentVersion)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 静默检查（启动时）
    func silentCheck() {
        guard !checking else { return }
        check { _ in }
    }

    /// 手动检查（设置页按钮）：读 update.json {version, notes, ipa}
    func check(completion: @escaping (String) -> Void) {
        checking = true
        message = ""
        guard let url = manifestURL else { checking = false; return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            defer { DispatchQueue.main.async { self?.checking = false } }
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion("检查失败：无法连接更新服务器") }
                return
            }
            let ver = String(describing: json["version"] ?? "")
            let notes = json["notes"] as? String ?? ""
            let file = json["ipa"] as? String

            DispatchQueue.main.async {
                guard !ver.isEmpty, ver != "<null>" else { completion("未获取到版本信息"); return }
                self.newVersion = ver
                self.releaseNotes = notes
                self.ipaFile = file
                if self.isNewer("V\(ver)") {
                    self.hasUpdate = true
                    completion("发现新版本 V\(ver)")
                } else {
                    self.hasUpdate = false
                    completion("已是最新版本 V\(self.currentVersion)")
                }
            }
        }.resume()
    }

    /// 一键安装：调用 itms-services 链接，系统自动跳转 Safari 安装
    func installUpdate() {
        guard hasUpdate, let file = ipaFile else { return }
        let manifestURL = "https://cdn.jsdelivr.net/gh/cuicsi666/baibaoshi-ota@main/manifest.plist"
        let itmsURL = "itms-services://?action=download-manifest&url=\(manifestURL)"
        if let url = URL(string: itmsURL) {
            UIApplication.shared.open(url)
        }
    }

    /// 下载新版本 IPA
    func download() {
        guard let url = ipaURL, !downloading else { return }
        downloading = true
        downloadProgress = 0
        message = ""
        let task = URLSession.shared.downloadTask(with: url) { [weak self] location, resp, error in
            DispatchQueue.main.async {
                self?.downloading = false
                if let error = error {
                    self?.message = "下载失败：\(error.localizedDescription)"
                    return
                }
                guard let loc = location else { self?.message = "下载失败"; return }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("百宝箱_新版本.ipa")
                try? FileManager.default.removeItem(at: dest)
                do {
                    try FileManager.default.moveItem(at: loc, to: dest)
                    self?.downloadedIPA = dest
                    self?.message = "下载完成，选择「全能签」安装"
                } catch {
                    self?.message = "保存失败：\(error.localizedDescription)"
                }
            }
        }
        task.observe(\.progress.fractionCompleted) { [weak self] task, _ in
            DispatchQueue.main.async {
                self?.downloadProgress = task.progress.fractionCompleted
            }
        }
        task.resume()
    }

    /// 拉起分享面板（用户选全能签安装）
    func shareSheet() -> UIViewController? {
        guard let ipa = downloadedIPA else { return nil }
        let vc = UIActivityViewController(activityItems: [ipa], applicationActivities: nil)
        return vc
    }
}
