import SwiftUI

struct ApiResult: Identifiable {
    let id = UUID()
    var name: String
    var status: Int?
    var ms: Int
    var body: String
    var ok: Bool { (status ?? 0) < 400 && status != nil }
}

struct ApiLabView: View {
    @State private var results: [ApiResult] = []
    @State private var customURL = "https://v1.hitokoto.cn"
    @State private var customMethod = "GET"
    @State private var customBody = ""
    @State private var busy = false
    @State private var expanded: Set<UUID> = []

    private let barkKey = "FWBhkLkmTb7opXqpfGaihJ"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(icon: "antenna.radiowaves.left.and.right", colors: Theme.api, title: "API 实验室", subtitle: "内置接口一键调用 · 支持自定义请求")

                builtIns
                custom
                history
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var builtIns: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("内置接口").font(.headline)
            Text("点一下发一次请求，响应与耗时直接展示").font(.caption).foregroundColor(.secondary)
            VStack(spacing: 10) {
                ApiRow(title: "一言 · 每日金句", desc: "v1.hitokoto.cn") { fire("一言", "https://v1.hitokoto.cn") }
                ApiRow(title: "我的公网 IP", desc: "ip-api.com") { fire("公网IP", "http://ip-api.com/json/?lang=zh-CN&fields=query,country,city,isp") }
                ApiRow(title: "Bing 每日壁纸", desc: "取今日壁纸直链") { fire("Bing壁纸", "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1") }
                ApiRow(title: "Bark 推送测试", desc: "发通知到崔老板 iPhone") { fire("Bark", "https://api.day.app/\(barkKey)/百宝匣/API测试成功🦞?group=CuiBox") }
            }
        }
        .padding(.horizontal, 4)
    }

    private var custom: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自定义请求").font(.headline)
            VStack(spacing: 10) {
                TextField("https://api.example.com/path", text: $customURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                Picker("", selection: $customMethod) {
                    ForEach(["GET", "POST", "PUT", "DELETE"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                if customMethod != "GET" {
                    TextField("{\"key\":\"value\"}", text: $customBody)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                }
                Button {
                    fire("自定义", customURL, method: customMethod, body: customBody)
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        else { Image(systemName: "paperplane.fill") }
                        Text(busy ? "请求中…" : "发送请求")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gradient(Theme.api)))
                }
                .buttonStyle(.plain)
                .disabled(busy || customURL.isEmpty)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
        }
        .padding(.horizontal, 4)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !results.isEmpty {
                HStack {
                    Text("响应记录").font(.headline)
                    Spacer()
                    Button("清空") { results.removeAll() }
                        .font(.caption).foregroundColor(.secondary)
                }
                ForEach(results) { r in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { toggle(r.id) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(r.ok ? .green : .red)
                                Text(r.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(r.status ?? 0) · \(r.ms)ms")
                                    .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                                Image(systemName: expanded.contains(r.id) ? "chevron.up" : "chevron.down")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        if expanded.contains(r.id) {
                            Text(pretty(r.body))
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.3)))
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func toggle(_ id: UUID) {
        withAnimation { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }
    }

    private func pretty(_ s: String) -> String {
        guard let d = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d),
              let dd = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let out = String(data: dd, encoding: .utf8) else { return s }
        return out
    }

    private func fire(_ name: String, _ urlString: String, method: String = "GET", body: String = "") {
        guard let url = URL(string: urlString) else {
            results.insert(ApiResult(name: name, status: nil, ms: 0, body: "URL 无效"), at: 0)
            return
        }
        busy = true
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        if method != "GET", !body.isEmpty { req.httpBody = body.data(using: .utf8) }
        let t0 = Date()
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let code = (resp as? HTTPURLResponse)?.statusCode
            let text = err?.localizedDescription ?? String(data: data ?? Data(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                busy = false
                results.insert(ApiResult(name: name, status: code, ms: ms, body: String(text.prefix(4000))), at: 0)
                if results.count > 10 { results.removeLast() }
            }
        }.resume()
    }
}

struct ApiRow: View {
    let title: String
    let desc: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            pressed = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pressed = false }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(desc).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.gradient(Theme.api))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
        }
        .buttonStyle(.plain)
    }
}
