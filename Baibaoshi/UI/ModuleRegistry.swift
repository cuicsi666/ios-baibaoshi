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
        ToolModule("biliplus", "哔哩Plus", "内嵌 · 跳过赞助", icon: "play.tv.fill",
                   colors: [Color(hex: 0x00A1D6), Color(hex: 0xF25D8E)], category: .core, keywords: ["哔哩", "bilibili", "视频", "哔哩哔哩", "b站", "pili"]) {
            EmbeddedAppView(app: EmbeddedApp(id: "biliplus", title: "哔哩Plus",
                                             icon: "play.tv.fill",
                                             colors: [Color(hex: 0x00A1D6), Color(hex: 0xF25D8E)],
                                             engineRoute: "biliplus"))
        },

        // ───────────────────────── 计算转换 ─────────────────────────
        ToolModule("calcSci", "科学计算器", "四则运算 · 函数 · 括号", icon: "function",
                   colors: [Color(hex: 0x34E0A1), Color(hex: 0x18B26B)], category: .calc, keywords: ["计算器", "sin", "对数", "开方"]) {
            CalcScientificView()
        },
        ToolModule("calcUnit", "单位换算", "长度 · 重量 · 温度 · 数据", icon: "ruler",
                   colors: [Color(hex: 0x3B9EFF), Color(hex: 0x2AD4C8)], category: .calc, keywords: ["单位", "换算", "长度", "重量", "温度"]) {
            CalcUnitView()
        },
        ToolModule("calcBase", "进制转换", "2 / 8 / 10 / 16 互转", icon: "number.square",
                   colors: [Color(hex: 0x7B5CFF), Color(hex: 0x4E54C8)], category: .calc, keywords: ["进制", "二进制", "十六进制", "位运算"]) {
            CalcBaseView()
        },
        ToolModule("calcLife", "生活计算", "房贷 · 折扣 · 小费 · BMI", icon: "percent",
                   colors: [Color(hex: 0xFF8C42), Color(hex: 0xFF3D68)], category: .calc, keywords: ["房贷", "月供", "折扣", "bmi", "个税"]) {
            CalcLifeView()
        },

        // ───────────────────────── 文本编码 ─────────────────────────
        ToolModule("qr", "二维码生成", "自定义颜色 · 纠错级别", icon: "qrcode",
                   colors: [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)], category: .text, keywords: ["二维码", "qr", "扫码", "分享"]) {
            CodeQRView()
        },
        ToolModule("barcode", "条码生成", "Code128 · Aztec · PDF417", icon: "barcode",
                   colors: [Color(hex: 0x5B6478), Color(hex: 0x9AA3B5)], category: .text, keywords: ["条码", "barcode", "code128"]) {
            CodeBarcodeView()
        },
        ToolModule("morse", "摩斯电码", "互转 · 音调播放 · 对照表", icon: "dot.radiowaves.left.and.right",
                   colors: [Color(hex: 0x11998E), Color(hex: 0x38EF7D)], category: .text, keywords: ["摩斯", "电报", "morse"]) {
            CodeMorseView()
        },
        ToolModule("textToolbox", "文本工具箱", "统计 · 大小写 · 行处理", icon: "text.alignleft",
                   colors: [Color(hex: 0x7B5CFF), Color(hex: 0xC86BFF)], category: .text, keywords: ["文本", "统计", "去重", "大小写"]) {
            TextToolboxView()
        },
        ToolModule("textEncode", "编码转换", "Base64 · URL · HTML", icon: "arrow.left.arrow.right.square",
                   colors: [Color(hex: 0xA86BFF), Color(hex: 0xFF6BB8)], category: .text, keywords: ["base64", "url", "编码", "解码"]) {
            TextEncodeView()
        },
        ToolModule("textJSON", "JSON 工具", "格式化 · 校验 · 压缩", icon: "curlybraces",
                   colors: [Color(hex: 0x4E54C8), Color(hex: 0x8F94FB)], category: .text, keywords: ["json", "格式化", "校验"]) {
            TextJSONView()
        },
        ToolModule("textHash", "哈希计算", "MD5 · SHA1 · SHA256", icon: "number",
                   colors: [Color(hex: 0x36D1DC), Color(hex: 0x5B86E5)], category: .text, keywords: ["哈希", "md5", "sha", "摘要"]) {
            TextHashView()
        },
        ToolModule("password", "密码生成器", "强度评估 · 批量生成", icon: "key.fill",
                   colors: [Color(hex: 0xFF9A5A), Color(hex: 0xFF5E62)], category: .text, keywords: ["密码", "随机", "安全", "强度"]) {
            SecPasswordView()
        },

        // ───────────────────────── 时间效率 ─────────────────────────
        ToolModule("worldClock", "世界时钟", "多城市 · 时差 · 昼夜", icon: "globe",
                   colors: [Color(hex: 0x3B9EFF), Color(hex: 0x00C2FF)], category: .time, keywords: ["世界时钟", "时区", "时差"]) {
            TimeWorldClockView()
        },
        ToolModule("stopwatch", "秒表", "分段计时 · 最快最慢", icon: "stopwatch.fill",
                   colors: [Color(hex: 0xFF7A18), Color(hex: 0xFFB020)], category: .time, keywords: ["秒表", "计时", "lap"]) {
            TimeStopwatchView()
        },
        ToolModule("countdown", "倒计时", "快捷预设 · 到时提醒", icon: "timer",
                   colors: [Color(hex: 0xF953C6), Color(hex: 0xB91D73)], category: .time, keywords: ["倒计时", "定时", "提醒"]) {
            TimeCountdownView()
        },
        ToolModule("pomodoro", "番茄钟", "25 / 5 循环 · 今日统计", icon: "clock.badge.checkmark",
                   colors: [Color(hex: 0xEF4444), Color(hex: 0xFF8C42)], category: .time, keywords: ["番茄钟", "专注", "pomodoro"]) {
            TimePomodoroView()
        },
        ToolModule("timestamp", "时间戳转换", "Unix ↔ 日期 · 多时区", icon: "calendar.badge.clock",
                   colors: [Color(hex: 0x11998E), Color(hex: 0x2AD4C8)], category: .time, keywords: ["时间戳", "unix", "日期", "转换"]) {
            TimeStampView()
        },
        ToolModule("days", "倒数日", "纪念日 · 正数倒数", icon: "calendar.badge.exclamationmark",
                   colors: [Color(hex: 0xEAAFC8), Color(hex: 0x654EA3)], category: .time, keywords: ["倒数日", "纪念日", "生日"]) {
            EffDaysView()
        },
        ToolModule("todo", "待办清单", "优先级 · 分类 · 进度", icon: "checklist",
                   colors: [Color(hex: 0x18B26B), Color(hex: 0x34E0A1)], category: .time, keywords: ["待办", "任务", "todo", "清单"]) {
            EffTodoView()
        },
        ToolModule("notes", "便签", "多便签 · 搜索 · 置顶", icon: "note.text",
                   colors: [Color(hex: 0xF7B733), Color(hex: 0xFF8C42)], category: .time, keywords: ["便签", "笔记", "备忘"]) {
            EffNotesView()
        },

        // ───────────────────────── 设备系统 ─────────────────────────
        ToolModule("devinfo", "设备信息", "机型 · 屏幕 · 内存 · 存储", icon: "iphone.gen3",
                   colors: [Color(hex: 0x2C3E50), Color(hex: 0x4CA1AF)], category: .device, keywords: ["设备", "机型", "参数", "内存"]) {
            DevInfoView()
        },
        ToolModule("battery", "电池面板", "实时电量 · 曲线 · 放电率", icon: "battery.100.bolt",
                   colors: [Color(hex: 0x22C55E), Color(hex: 0x9BD34A)], category: .device, keywords: ["电池", "电量", "充电"]) {
            DevBatteryView()
        },
        ToolModule("storage", "存储分析", "占用明细 · 一键清理", icon: "internaldrive.fill",
                   colors: [Color(hex: 0x5B6478), Color(hex: 0x2C3E50)], category: .device, keywords: ["存储", "空间", "清理", "缓存"]) {
            DevStorageView()
        },
        ToolModule("clipboard", "剪贴板历史", "捕获 · 置顶 · 一键回填", icon: "doc.on.clipboard",
                   colors: [Color(hex: 0x36D1DC), Color(hex: 0x3B9EFF)], category: .device, keywords: ["剪贴板", "复制", "历史", "粘贴"]) {
            DevClipboardView()
        },
        ToolModule("net", "网络工具", "公网IP · 延迟 · 状态码", icon: "network",
                   colors: [Color(hex: 0x4E54C8), Color(hex: 0x2E5BFF)], category: .device, keywords: ["网络", "ip", "ping", "延迟", "测速"]) {
            NetToolsView()
        },

        // ───────────────────────── 趣味生活 ─────────────────────────
        ToolModule("idiom", "励志成语", "每日正能量", icon: "text.book.closed.fill",
                   colors: Theme.idiom, category: .fun, keywords: ["成语", "励志", "名言"]) {
            IdiomView()
        },
        ToolModule("quote", "每日一言", "名言 · 冷知识 · 笑话", icon: "quote.bubble.fill",
                   colors: [Color(hex: 0xF953C6), Color(hex: 0xA86BFF)], category: .fun, keywords: ["一言", "名言", "冷知识", "笑话"]) {
            EffQuoteView()
        },
        ToolModule("random", "随机工具", "骰子 · 硬币 · 抽签", icon: "die.face.5.fill",
                   colors: [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)], category: .fun, keywords: ["随机", "骰子", "抽签", "硬币"]) {
            RandToolView()
        },
        ToolModule("color", "颜色工具", "取色 · 转换 · 调色板", icon: "paintpalette.fill",
                   colors: [Color(hex: 0xFF9A5A), Color(hex: 0xFF5EA8)], category: .fun, keywords: ["颜色", "取色", "hex", "rgb", "调色板"]) {
            ColorToolView()
        },
        ToolModule("noise", "白噪音", "白/粉/棕 · 定时关闭", icon: "waveform",
                   colors: [Color(hex: 0x654EA3), Color(hex: 0x36D1DC)], category: .fun, keywords: ["白噪音", "助眠", "噪音", "放松"]) {
            FunNoiseView()
        },
        ToolModule("ruler", "尺子水平仪", "屏幕标尺 · 气泡水平", icon: "ruler.fill",
                   colors: [Color(hex: 0x38EF7D), Color(hex: 0x11998E)], category: .fun, keywords: ["尺子", "水平仪", "测量", "角度"]) {
            FunRulerView()
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
