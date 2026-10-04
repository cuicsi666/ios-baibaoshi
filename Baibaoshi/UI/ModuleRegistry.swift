import SwiftUI

// MARK: - 模块总注册表
// 新增功能：在 Modules/ 下实现 View，然后在此登记一条记录即可（XcodeGen 自动收录源码）。

enum ModuleRegistry {

    static let all: [ToolModule] = [

        // ───────────────────────── 核心应用 ─────────────────────────
        ToolModule("charge", "电管家", "充电监控 · 智能预估", icon: "bolt.fill",
                   colors: Theme.charge, category: .core, keywords: ["充电", "电量", "电池", "预估"]) {
            CBHomeView()
        },
        ToolModule("xvp", "XVP 播放器", "内置前端 · Face ID 解锁", icon: "play.rectangle.fill",
                   colors: [Color(hex: 0x654EA3), Color(hex: 0xEAAFC8)], category: .core, keywords: ["播放器", "视频", "影片"]) {
            XVPPlayerView()
        },
        ToolModule("vmon", "V监控", "ESXi + OpenWrt 直连", icon: "server.rack",
                   colors: [Color(hex: 0x2C3E50), Color(hex: 0x4CA1AF)], category: .core, keywords: ["esxi", "服务器", "虚拟机", "ssh"]) {
            VAppPlayerView()
        },
        ToolModule("router", "路由器监控", "OpenWrt 实时状态", icon: "wifi.router.fill",
                   colors: Theme.router, category: .core, keywords: ["路由器", "openwrt", "cpu", "温度"]) {
            RouterMonitorView()
        },
        ToolModule("aiusage", "AI 用量", "今日花销 · 历史记录", icon: "brain.head.profile",
                   colors: Theme.nav, category: .core, keywords: ["ai", "token", "花销", "api"]) {
            AIUsageView()
        },
        ToolModule("settings", "设置", "主题 · 保活 · 更新", icon: "gearshape.fill",
                   colors: [Color(hex: 0x8E9AAF), Color(hex: 0x5C6672)], category: .core, keywords: ["设置", "主题", "保活", "更新"]) {
            SettingsView()
        },

        // ───────────────────────── 趣味生活（原有） ─────────────────────────
        ToolModule("idiom", "励志成语", "每日正能量", icon: "text.book.closed.fill",
                   colors: Theme.idiom, category: .fun, keywords: ["成语", "励志", "名言"]) {
            IdiomView()
        },
    ]

    static func modules(in category: BBCategory) -> [ToolModule] {
        all.filter { $0.category == category }
    }

    static func search(_ query: String) -> [ToolModule] {
        all.filter { $0.matches(query) }
    }

    static func module(_ id: String) -> ToolModule? {
        all.first { $0.id == id }
    }
}
