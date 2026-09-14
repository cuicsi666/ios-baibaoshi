import Foundation
import UIKit

// MARK: - V3.14 崩溃现场捕获
// 捕获 NSException + 常见信号(SIGABRT/SIGSEGV/SIGBUS/SIGILL/SIGTRAP),
// 崩溃瞬间把原因和最近日志快照写入 Documents/xui_crash.txt,
// 重开 APP 后由 XUILogger 自动追加展示 → 复制给小龙虾即可看到崩溃现场。
enum CrashCatcher {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        // 1. Objective-C / 系统异常 (CoreBluetooth 异常走这里)
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "未知"
            let stack = exception.callStackSymbols.prefix(20).joined(separator: "\n")
            let text = "🧨 NSException 崩溃\n原因: \(reason)\n堆栈:\n\(stack)\n\n最近日志:\n\(XUILogger.shared.fullText)"
            CrashCatcher.write(text)
        }

        // 2. 信号崩溃 (EXC_BAD_ACCESS 等)
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP] {
            signal(sig, { s in
                let text = "🧨 信号崩溃 signal=\(s)\n最近日志:\n\(XUILogger.shared.fullText)"
                CrashCatcher.write(text)
                // 恢复默认处理后重新触发, 让系统正常收尸
                signal(s, SIG_DFL)
                raise(s)
            })
        }
    }

    private static func write(_ text: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("xui_crash.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 读取崩溃记录(供 UI 展示)
    static func readCrash() -> String? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("xui_crash.txt")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func clearCrash() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("xui_crash.txt")
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }
}
