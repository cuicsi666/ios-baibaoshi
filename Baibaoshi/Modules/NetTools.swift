import SwiftUI
import UIKit
import Foundation
import Darwin
import Combine

// MARK: - 网络工具（NetToolsView）
// ① 本机 IP：getifaddrs 遍历网卡，取 en0(WiFi)/pdp_ip0(蜂窝) 的 IPv4（注意指针用法与 freeifaddrs 释放）
// ② 公网 IP/地区：https://ipapi.co/json/ 超时 8 秒，解析 IP/地区/运营商，失败友好降级不崩
// ③ 延迟测试：百度(HTTPS) 与 6.6.6.1(HTTP) 各发 10 次 URLSession 请求，统计平均/最小/最大/成功率
// ④ HTTP 状态码查询：输入网址返回状态码与耗时。结果卡片化（BBStat/BBKV），可一键重测与复制。

// MARK: 数据模型
struct NetLocalInfo {
    var wifi: String? = nil
    var cellular: String? = nil
    var hasAny: Bool { wifi != nil || cellular != nil }
}

struct NetPublicInfo {
    var ip = "", city = "", region = "", country = "", org = "", timezone = ""
    var place: String {
        let parts = [country, region, city].filter { !$0.isEmpty }
        return parts.isEmpty ? "未知地区" : parts.joined(separator: " · ")
    }
}

struct NetPingStat: Identifiable {
    var id: String { url }
    let host, url: String
    let avg, minV, maxV: Double
    let success, total: Int
    var rate: Double { total == 0 ? 0 : Double(success) / Double(total) }
    var ok: Bool { success > 0 }
    func msText(_ v: Double) -> String { ok ? String(format: "%.0f", v) : "—" }
}

struct NetStatusResult: Identifiable {
    var id: String { "\(url)#\(code)" }
    let url: String; let code: Int; let ms: Double; let bytes: Int; let server: String
    var msText: String { String(format: "%.0f", ms) }
    var meta: (String, Color) {
        switch code {
        case 200..<300: return ("请求成功", Theme.success)
        case 300..<400: return ("重定向", Theme.warning)
        case 400..<500: return ("客户端错误", Theme.danger)
        default: return ("服务端 / 其它", Color(hex: 0x7B5CFF))
        }
    }
}

// MARK: 本机网卡（getifaddrs C 互操作）
enum NetLocal {
    static func snapshot() -> NetLocalInfo {
        var info = NetLocalInfo()
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0 else { return info }
        defer { if ifaddr != nil { freeifaddrs(ifaddr) } }

        var cursor = ifaddr
        while let cur = cursor {
            defer { cursor = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            guard name == "en0" || name == "pdp_ip0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(addr.pointee.sa_len)
            guard getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            guard !ip.isEmpty, ip != "0.0.0.0" else { continue }
            if name == "en0" { info.wifi = ip } else { info.cellular = ip }
        }
        return info
    }
}

// MARK: 网络服务
final class NetService: ObservableObject {
    @Published var local = NetLocalInfo()
    @Published var publicInfo: NetPublicInfo? = nil
    @Published var publicError: String? = nil
    @Published var publicLoading = false
    @Published var pings: [NetPingStat] = []
    @Published var pingRunning = false
    @Published var pingProgress: Double = 0
    @Published var status: NetStatusResult? = nil
    @Published var statusError: String? = nil
    @Published var statusLoading = false
    private var pingDone = 0
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8; cfg.timeoutIntervalForResource = 24
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData; cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    // ① 本机 IP（回主线程更新）
    func refreshLocal() {
        let info = NetLocal.snapshot()
        DispatchQueue.main.async { self.local = info }
    }

    // ② 公网 IP / 地区
    func loadPublic() {
        guard !publicLoading, let url = URL(string: "https://ipapi.co/json/") else { return }
        publicLoading = true; publicError = nil; publicInfo = nil
        var req = URLRequest(url: url); req.timeoutInterval = 8
        session.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                self.publicLoading = false
                if let err = err { self.publicError = "查询失败：\(err.localizedDescription)"; return }
                guard let data = data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let ip = obj["ip"] as? String, !ip.isEmpty else {
                    self.publicError = "返回数据解析失败，请稍后重试（可能已达服务限额）"; return
                }
                var info = NetPublicInfo()
                info.ip = ip
                info.city = obj["city"] as? String ?? ""; info.region = obj["region"] as? String ?? ""
                info.country = obj["country_name"] as? String ?? ""; info.org = obj["org"] as? String ?? ""
                info.timezone = obj["timezone"] as? String ?? ""
                self.publicInfo = info
            }
        }.resume()
    }

    // ③ 延迟测试（两目标并发，单目标串行 10 次）
    func runPing() {
        guard !pingRunning else { return }
        pingRunning = true; pingDone = 0; pingProgress = 0; pings = []
        let targets = [("百度", "https://www.baidu.com"), ("6.6.6.1", "http://6.6.6.1")]
        let group = DispatchGroup()
        var collected: [NetPingStat] = []
        for t in targets {
            group.enter()
            measure(host: t.0, url: t.1) { stat in
                DispatchQueue.main.async { collected.append(stat) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.pings = targets.compactMap { t in collected.first { $0.url == t.1 } }
            self.pingRunning = false; self.pingProgress = 1
        }
    }

    private func measure(host: String, url: String, completion: @escaping (NetPingStat) -> Void) {
        let total = 10
        var samples: [Double] = []; var ok = 0; var idx = 0
        func step() {
            if idx >= total {
                let avg = samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
                completion(NetPingStat(host: host, url: url, avg: avg, minV: samples.min() ?? 0,
                                       maxV: samples.max() ?? 0, success: ok, total: total))
                return
            }
            idx += 1
            let start = CFAbsoluteTimeGetCurrent()
            probe(url) { success in
                if success { ok += 1; samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000) }
                DispatchQueue.main.async { self.pingDone += 1; self.pingProgress = min(0.98, Double(self.pingDone) / Double(total * 2)) }
                step()
            }
        }
        step()
    }

    private func probe(_ urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else { completion(false); return }
        var req = URLRequest(url: url); req.httpMethod = "HEAD"; req.timeoutInterval = 4; req.cachePolicy = .reloadIgnoringLocalCacheData
        session.dataTask(with: req) { _, resp, err in completion(err == nil && resp != nil) }.resume()
    }

    // ④ HTTP 状态码
    func check(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { statusError = "请输入要查询的网址"; status = nil; return }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") { text = "https://" + text }
        guard let url = URL(string: text), url.host != nil else { statusError = "网址格式不正确"; status = nil; return }
        statusLoading = true; statusError = nil; status = nil
        var req = URLRequest(url: url); req.timeoutInterval = 8; req.cachePolicy = .reloadIgnoringLocalCacheData
        let start = CFAbsoluteTimeGetCurrent()
        session.dataTask(with: req) { data, resp, err in
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            DispatchQueue.main.async {
                self.statusLoading = false
                if let http = resp as? HTTPURLResponse {
                    self.status = NetStatusResult(url: text, code: http.statusCode, ms: ms, bytes: data?.count ?? 0,
                                                  server: http.value(forHTTPHeaderField: "Server") ?? "")
                } else { self.statusError = "请求失败：\(err?.localizedDescription ?? "无法建立连接")" }
            }
        }.resume()
    }
}

// MARK: 页面
struct NetToolsView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var net = NetService()
    @State private var urlText = "https://www.apple.com"
    @State private var toast: String? = nil
    private let ipColors = [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)]
    private let pubColors = [Color(hex: 0xFF7A18), Color(hex: 0xFF3D71)]
    private let pingColors = [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)]
    private let httpColors = [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "antenna.radiowaves.left.and.right", colors: ipColors,
                           title: "网络工具", subtitle: "本机 IP · 公网信息 · 延迟 · 状态码")
                localCard
                publicCard
                pingCard
                statusCard
                Text("提示：6.6.6.1 为明文 HTTP，若被系统网络策略拦截会显示不可达；公网信息来自 ipapi.co，仅本机展示。")
                    .font(BBFont.cap(10)).foregroundColor(.secondary).padding(.horizontal, 2)
            }
            .padding(.horizontal, BBSpacing.screen).padding(.top, 8).padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("网络工具")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { toastView }
        .onAppear { net.refreshLocal(); net.loadPublic() }
    }
    private var localCard: some View {
        BBCard { VStack(alignment: .leading, spacing: 12) {
            BBSectionHeader("本机 IP", icon: "iphone", colors: ipColors)
            if net.local.hasAny {
                HStack(spacing: 8) {
                    BBStat(label: "WiFi en0", value: net.local.wifi ?? "未连接", icon: "wifi", colors: ipColors)
                    BBStat(label: "蜂窝 pdp_ip0", value: net.local.cellular ?? "未启用",
                           icon: "antenna.radiowaves.left.and.right", colors: pingColors)
                }
                BBGhostButton(title: "复制全部 IP", icon: "doc.on.doc") {
                    copy("WiFi: \(net.local.wifi ?? "-")\n蜂窝: \(net.local.cellular ?? "-")", note: "已复制本机 IP")
                }
            } else {
                errorRow("未检测到 IPv4 地址，请检查是否已联网") { net.refreshLocal() }
            }
        }}
    }
    private var publicCard: some View {
        BBCard { VStack(alignment: .leading, spacing: 12) {
            BBSectionHeader("公网 IP / 地区", icon: "globe.asia.australia.fill", colors: pubColors)
            if net.publicLoading {
                loadingRow("正在查询 ipapi.co …")
            } else if let p = net.publicInfo {
                BBStat(label: "公网 IP", value: p.ip, icon: "network", colors: pubColors)
                VStack(alignment: .leading, spacing: 8) {
                    BBKV(key: "地区", value: p.place)
                    BBKV(key: "运营商", value: p.org.isEmpty ? "未知" : p.org)
                    BBKV(key: "时区", value: p.timezone.isEmpty ? "—" : p.timezone)
                }
                .padding(11).background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))
                HStack(spacing: 10) {
                    BBGhostButton(title: "重新查询", icon: "arrow.clockwise") { net.loadPublic() }
                    BBGhostButton(title: "复制", icon: "doc.on.doc") { copy("\(p.ip) | \(p.place) | \(p.org)", note: "已复制公网信息") }
                }
            } else {
                errorRow(net.publicError ?? "暂无数据") { net.loadPublic() }
            }
        }}
    }
    private var pingCard: some View {
        BBCard { VStack(alignment: .leading, spacing: 12) {
            BBSectionHeader("延迟测试", icon: "speedometer", colors: pingColors)
            Text("对 百度 (HTTPS) 与 6.6.6.1 (HTTP) 各发送 10 次请求，统计平均 / 最小 / 最大耗时与成功率。")
                .font(BBFont.cap(11)).foregroundColor(.secondary)
            if net.pingRunning {
                BBMeter(value: net.pingProgress, colors: pingColors, height: 8)
            } else if net.pings.isEmpty {
                Text("尚未测试，点按下方按钮开始。").font(BBFont.cap(11)).foregroundColor(.secondary)
            }
            ForEach(net.pings) { stat in pingRow(stat) }
            BBPrimaryButton(title: net.pingRunning ? "测试中…" : "开始测试", icon: "bolt.fill", colors: pingColors) { net.runPing() }
        }}
    }
    private func pingRow(_ s: NetPingStat) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(s.host).font(BBFont.head(15))
                BBPill(text: "\(s.success)/\(s.total)", color: s.ok ? Theme.success : Theme.danger)
                Spacer(minLength: 4)
                Text(s.ok ? "\(s.msText(s.avg)) ms" : "不可达").font(BBFont.mono).foregroundColor(s.ok ? .primary : .secondary)
            }
            HStack(spacing: 8) {
                BBStat(label: "平均", value: s.msText(s.avg), unit: s.ok ? "ms" : nil, icon: "equal", colors: pingColors)
                BBStat(label: "最小", value: s.msText(s.minV), unit: s.ok ? "ms" : nil, icon: "arrow.down", colors: pingColors)
                BBStat(label: "最大", value: s.msText(s.maxV), unit: s.ok ? "ms" : nil, icon: "arrow.up", colors: pubColors)
            }
            BBMeter(value: s.rate, colors: s.ok ? pingColors : [Theme.danger, Theme.warning], height: 6)
            Text("成功率 \(Int(s.rate * 100))% · 共 \(s.total) 次").font(BBFont.cap(11)).foregroundColor(.secondary)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous).fill(Theme.panel(scheme == .dark)))
    }
    private var statusCard: some View {
        BBCard { VStack(alignment: .leading, spacing: 12) {
            BBSectionHeader("HTTP 状态码查询", icon: "number.square.fill", colors: httpColors)
            HStack(spacing: 8) {
                Image(systemName: "link").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                TextField("https://example.com", text: $urlText)
                    .font(BBFont.mono).keyboardType(.URL).textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true).submitLabel(.go)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))
            HStack(spacing: 10) {
                BBPrimaryButton(title: net.statusLoading ? "请求中…" : "查询", icon: "arrow.up.right.circle.fill", colors: httpColors) { net.check(urlText) }
                BBGhostButton(title: "粘贴", icon: "doc.on.clipboard") {
                    if let s = UIPasteboard.general.string, !s.isEmpty {
                        urlText = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else { showToast("剪贴板为空") }
                }
            }
            if net.statusLoading { loadingRow("正在请求 …") }
            else if let r = net.status { statusResult(r) }
            else if let e = net.statusError { errorRow(e) { net.check(urlText) } }
        }}
    }
    private func statusResult(_ r: NetStatusResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(r.code)").font(BBFont.num(34)).foregroundColor(r.meta.1)
                VStack(alignment: .leading, spacing: 3) {
                    BBPill(text: r.meta.0, color: r.meta.1)
                    Text(r.url).font(BBFont.cap(11)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            VStack(alignment: .leading, spacing: 8) {
                BBKV(key: "状态码", value: "\(r.code)")
                BBKV(key: "耗时", value: "\(r.msText) ms")
                BBKV(key: "响应大小", value: ByteCountFormatter.string(fromByteCount: Int64(r.bytes), countStyle: .binary))
                if !r.server.isEmpty { BBKV(key: "服务器", value: r.server) }
            }
            HStack(spacing: 10) {
                BBGhostButton(title: "重新查询", icon: "arrow.clockwise") { net.check(urlText) }
                BBGhostButton(title: "复制结果", icon: "doc.on.doc") { copy("\(r.url) → \(r.code) \(r.meta.0) · \(r.msText) ms", note: "已复制结果") }
            }
        }
        .padding(11).background(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous).fill(Theme.panel(scheme == .dark)))
    }
    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 9) { ProgressView().scaleEffect(0.75); Text(text).font(BBFont.cap(12)).foregroundColor(.secondary); Spacer() }
    }

    private func errorRow(_ text: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.warning)
                Text(text).font(BBFont.cap(12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            BBGhostButton(title: "重试", icon: "arrow.clockwise", action: retry)
        }
    }
    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 10).background(Capsule().fill(Theme.accentGradient))
                .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 4).padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    private func copy(_ text: String, note: String) {
        UIPasteboard.general.string = text; BBHaptic.success(); showToast(note)
    }
    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if toast == text { withAnimation(.easeOut(duration: 0.25)) { toast = nil } }
        }
    }
}
