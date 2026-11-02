import Foundation
import Network

/// 内置静态站点服务器：把打包进 App 的网页从 127.0.0.1 提供出来，
/// 并把 /api 请求反向代理到真实服务器，保证与线上完全同源（无 CORS、POST body 完整）。
final class LocalSiteServer {
    static let shared = LocalSiteServer()

    struct Site {
        let id: String
        let folder: String
        let apiBase: String?
    }

    private var listener: NWListener?
    private var queue = DispatchQueue(label: "local.site.server", attributes: .concurrent)
    private(set) var port: UInt16 = 0
    private var sites: [String: Site] = [:]

    func register(_ site: Site) { sites[site.id] = site }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: .any)
            l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            l.stateUpdateHandler = { st in
                if case .ready = st, let p = l.port?.rawValue {
                    self.port = p
                    print("[site] listening on \(p)")
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            print("[site] start failed: \(error)")
        }
    }

    func url(for id: String) -> URL? {
        guard port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/\(id)/index.html")
    }

    // MARK: - 连接处理

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isDone, error in
            guard let self = self else { conn.cancel(); return }
            var buf = buffer
            if let data = data { buf.append(data) }

            guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
                if isDone || error != nil { conn.cancel() } else { self.receive(conn, buffer: buf) }
                return
            }

            let headData = buf.subdata(in: 0..<headerEnd.lowerBound)
            let bodyData = buf.subdata(in: headerEnd.upperBound..<buf.count)
            let head = String(data: headData, encoding: .utf8) ?? ""
            let lines = head.components(separatedBy: "\r\n")
            guard let first = lines.first else { conn.cancel(); return }
            let parts = first.split(separator: " ")
            guard parts.count >= 2 else { conn.cancel(); return }
            let method = String(parts[0])
            let rawPath = String(parts[1])

            var contentLength = 0
            for line in lines.dropFirst() {
                let kv = line.split(separator: ":", maxSplits: 1)
                if kv.count == 2, kv[0].lowercased() == "content-length" {
                    contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }

            if bodyData.count < contentLength {
                self.receive(conn, buffer: buf)
                return
            }

            self.route(method: method, rawPath: rawPath, body: bodyData) { status, ctype, payload in
                var header = "HTTP/1.1 \(status)\r\n"
                header += "Content-Type: \(ctype)\r\n"
                header += "Content-Length: \(payload.count)\r\n"
                header += "Cache-Control: no-store\r\n"
                header += "Connection: close\r\n\r\n"
                var out = Data(header.utf8)
                out.append(payload)
                conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
            }
        }
    }

    // MARK: - 路由

    private func route(method: String, rawPath: String, body: Data,
                       completion: @escaping (Int, String, Data) -> Void) {
        let comps = rawPath.split(separator: "?", maxSplits: 1)
        let path = String(comps[0])
        let query = comps.count > 1 ? "?" + String(comps[1]) : ""

        let segs = path.split(separator: "/").map(String.init)
        guard let siteID = segs.first, let site = sites[siteID] else {
            completion(404, "text/plain", Data("not found".utf8))
            return
        }

        // /<site>/api/... → 反向代理
        if segs.count >= 2, segs[1] == "api", let base = site.apiBase {
            let rest = "/" + segs.dropFirst().joined(separator: "/")
            proxy(method: method, url: base + rest + query, body: body, completion: completion)
            return
        }

        // 静态文件
        var rel = segs.dropFirst().joined(separator: "/")
        if rel.isEmpty { rel = "index.html" }
        guard let resDir = Bundle.main.resourceURL?
                .appendingPathComponent("sites")
                .appendingPathComponent(site.folder) else {
            completion(404, "text/plain", Data("no bundle".utf8)); return
        }
        var fileURL = resDir.appendingPathComponent(rel)
        if !FileManager.default.fileExists(atPath: fileURL.path),
           (rel as NSString).pathExtension.isEmpty {
            // SPA 路由回退到 index.html
            fileURL = resDir.appendingPathComponent("index.html")
        }
        guard fileURL.path.hasPrefix(resDir.path),
              let data = try? Data(contentsOf: fileURL) else {
            completion(404, "text/plain", Data("missing \(rel)".utf8))
            return
        }
        completion(200, Self.mime(fileURL.lastPathComponent), data)
    }

    private func proxy(method: String, url: String, body: Data,
                       completion: @escaping (Int, String, Data) -> Void) {
        guard let u = URL(string: url) else {
            completion(502, "text/plain", Data("bad upstream".utf8)); return
        }
        var req = URLRequest(url: u, timeoutInterval: 20)
        req.httpMethod = method
        if !body.isEmpty {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let sem = DispatchSemaphore(value: 0)
        var result: (Int, String, Data) = (502, "text/plain", Data("upstream error".utf8))
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let http = resp as? HTTPURLResponse {
                let ct = http.value(forHTTPHeaderField: "Content-Type") ?? "application/json"
                result = (http.statusCode, ct, data ?? Data())
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 22)
        completion(result.0, result.1, result.2)
    }

    static func mime(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        default: return "application/octet-stream"
        }
    }
}
