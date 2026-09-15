import Foundation
import UIKit

// MARK: - 全 App 诊断日志
// 落盘 Documents/app.log（512KB 轮转），崩溃自动留现场，设置页一键上传服务器

final class AppLog {
    static let shared = AppLog()
    private static let maxBytes = 512 * 1024
    private let queue = DispatchQueue(label: "applog.writer")

    private var logURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("app.log")
    }

    private init() { installCrashHooks() }

    static func log(_ module: String, _ msg: String) {
        shared.write("INFO", module, msg)
    }

    static func error(_ module: String, _ msg: String) {
        shared.write("ERR ", module, msg)
    }

    private func write(_ level: String, _ module: String, _ msg: String) {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        let line = "[\(f.string(from: Date()))] \(level) [\(module)] \(msg)\n"
        queue.async { [self] in
            append(line)
        }
    }

    private func append(_ line: String) {
        let fm = FileManager.default
        if let data = line.data(using: .utf8) {
            if let size = (try? fm.attributesOfItem(atPath: logURL.path)[.size]) as? Int, size > Self.maxBytes {
                let old = logURL.deletingPathExtension().appendingPathExtension("log.1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: logURL, to: old)
            }
            if let fh = FileHandle(forWritingAtPath: logURL.path) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    /// 上传到服务器（POST 文件），回调结果消息
    static func upload(completion: @escaping (String) -> Void) {
        let url = URL(string: "http://6.6.6.130:8099/updates/baibaoshi/upload.php")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let device = "\(UIDevice.current.model)-\(UIDevice.current.systemVersion)"
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"device\"\r\n\r\n\(device)\r\n".data(using: .utf8)!)
        if let logData = try? Data(contentsOf: shared.logURL) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"log\"; filename=\"app.log\"\r\nContent-Type: text/plain\r\n\r\n".data(using: .utf8)!)
            body.append(logData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, resp, error in
            DispatchQueue.main.async {
                if let error = error { completion("上传失败：\(error.localizedDescription)"); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
                completion(code == 200 ? "上传成功 \(text)" : "上传失败 HTTP \(code)")
            }
        }.resume()
    }

    // MARK: 崩溃捕获

    private func installCrashHooks() {
        NSSetUncaughtExceptionHandler { ex in
            let text = "[CRASH] NSException \(ex.name.rawValue)\nreason: \(ex.reason ?? "?")\n" +
                       ex.callStackSymbols.prefix(15).joined(separator: "\n")
            AppLog.shared.appendSync(text)
        }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE] {
            signal(sig) { s in
                AppLog.shared.appendSync("[CRASH] signal=\(s)")
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }

    /// 同步写（崩溃现场用）
    private func appendSync(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(text)\n"
        try? line.data(using: .utf8)?.appendTo(fileURL: logURL)
    }
}

extension Data {
    func appendTo(fileURL: URL) {
        if let fh = FileHandle(forWritingAtPath: fileURL.path) {
            fh.seekToEndOfFile()
            fh.write(self)
            fh.closeFile()
        } else {
            try? self.write(to: fileURL)
        }
    }
}
