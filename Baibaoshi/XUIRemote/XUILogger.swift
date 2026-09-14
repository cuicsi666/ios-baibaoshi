import Foundation
import UIKit

// MARK: - XUI 全局日志（V3.14: 文件持久化）
// 连接/操作/转发全记录。V3.14 起同步写入 Documents/xui_log.txt,
// 闪退/杀进程后重开 APP 自动恢复上次日志 → 复制给我能看到崩溃前最后一刻现场。
final class XUILogger: ObservableObject {
    static let shared = XUILogger()
    @Published private(set) var entries: [String] = []
    private let maxMem = 300
    private let maxFile = 500
    private let df: DateFormatter
    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "xui.logger.io")

    private init() {
        df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("xui_log.txt")
        loadFromFile()
    }

    /// 启动时恢复上次会话日志（闪退现场）
    private func loadFromFile() {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = raw.split(separator: "\n").map(String.init)
        if !lines.isEmpty {
            entries.append("── 上次会话日志(\(lines.count)条) ──")
            entries.append(contentsOf: lines.suffix(maxMem))
        }
    }

    func log(_ msg: String) {
        let line = "[\(df.string(from: Date()))] \(msg)"
        // V3.16: 日志改为同步写内存(不再 async)——崩溃瞬间日志不丢, 精确定位崩溃点
        if Thread.isMainThread {
            appendAndTrim(line)
        } else {
            DispatchQueue.main.sync { self.appendAndTrim(line) }
        }
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let all = (self.loadCurrentLines() + [line]).suffix(self.maxFile)
            try? all.joined(separator: "\n").write(to: self.fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func appendAndTrim(_ line: String) {
        entries.append(line)
        if entries.count > maxMem {
            entries.removeFirst(entries.count - maxMem)
        }
    }

    /// 从文件读当前全部行(io线程用)
    private func loadCurrentLines() -> [String] {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return raw.split(separator: "\n").map(String.init)
    }

    var fullText: String {
        // 内存日志 + 文件兜底合并，去重；V3.15: 末尾附加崩溃报告(如有)
        var base: [String]
        let mem = entries
        let disk = loadCurrentLines()
        base = disk.count > mem.count ? disk : mem
        var text = base.joined(separator: "\n")
        if let c = CrashCatcher.readCrash(), !c.isEmpty {
            text += "\n\n========== 🧨 崩溃报告 ==========\n" + c
        }
        return text
    }

    /// 一键复制全部日志到剪贴板（返回复制的文本）
    @discardableResult
    func copyAll() -> String {
        let t = fullText
        UIPasteboard.general.string = t
        log("📋 已复制 \(t.split(separator: "\n").count) 条日志")
        return t
    }

    func clear() {
        DispatchQueue.main.async { self.entries.removeAll() }
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? "".write(to: self.fileURL, atomically: true, encoding: .utf8)
        }
    }
}
