import Foundation
import CoreBluetooth
import UIKit
import UserNotifications
import WidgetKit   // v3.47: 连接/断开本地通知

// MARK: - XUI 蓝牙遥控核心（v2.0 合体）
// 服务 FFE0 / PIN FFE1 / CTRL FFE2 / INFO FFE3 / TUNNEL FFE4
// 板子 V142+ 广播名 XUI，配对码 1234
// V3.9: 全链路日志埋点(连接/配对/命令/隧道收发) → XUILogger

protocol XUIManagerDelegate: AnyObject {
    func xuiStateChanged(_ state: XUIState)
    func xuiInfoUpdated(_ info: XUIInfo)
    func xuiLog(_ msg: String)
}

struct XUIInfo {
    var battery: Int = -1
    var version: String = "--"
    var wifi: Bool = false
    var mem: Int = -1          // V3.50: 内部RAM剩余KB
    var memExt: Int = -1       // V3.50: 外部PSRAM剩余KB
    var disk: Int = -1         // V3.50: Flash升级分区可用KB
    var alwaysOn: Bool = true  // v4.3: 板子常亮开关状态(默认开)
    var antiTouch: Bool = true // v4.3: 板子防误触开关状态(默认开)
}

struct XUIState {
    var scanned: Bool = false
    var connected: Bool = false
    var paired: Bool = false
}

final class XUIManager: NSObject, ObservableObject {
    static let shared = XUIManager()
    @Published var state = XUIState()
    @Published var info = XUIInfo()
    @Published var statusText = "未连接"

    weak var delegate: XUIManagerDelegate?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var pinChar: CBCharacteristic?
    private var ctrlChar: CBCharacteristic?
    private var infoChar: CBCharacteristic?
    private var tunChar: CBCharacteristic?

    private let pin: String = "1234"
    private var tunRx = TUNReceiver()

    // V3.17: 全自动连接 —— 无需手动扫描/配对, 断开自动重连
    private var autoScanning = false
    private var autoRetryTimer: DispatchWorkItem?
    private var hadXUI = false          // 曾经连上过 XUI(避免误连别的设备)
    private var pairedThisSession = false
    private var inBackground = false    // V3.42: 前后台感知——后台不杀连接, 前台恢复轻量探活
    private var connectedThisSession = false   // V3.43: 本次进程内是否主动连上过(杀进程恢复判定用)
    private var batteryReportTimer: DispatchSourceTimer?   // V3.45: iPhone 电量/充电 10s 周期上报
    private var lastReportedPct = -1        // V228: 去抖——变化<2%不上报, 防板子电量跳动
    private var lastBatteryState: UIDevice.BatteryState = .unknown  // V228: 拔电回桌面判定
    // V3.19: 记住板子 identifier + iOS 系统级后台恢复(APP 被系统回收后由系统代管重连)
    private let lastBoardKey = "xui_last_board_id"
    private var restoredPeripheral: CBPeripheral?

    // V3.40: 删除主动保活心跳(2s INFO 读) —— iOS 后台 Timer 被系统掐, 前台又打扰板子,
    //   改为"板子 15s 探活 → App 自动回 ACK"双向被动保活 + iOS RestoreIdentifier 系统代管
    // V3.37: 连接质量统计(供分测)
    private var connectCount = 0          // 累计成功连接次数
    private var disconnectCount = 0       // 累计断开次数
    private var lastConnectedAt: Date?    // 本次连接建立时刻
    private var rssiSamples: [Int] = []   // RSSI 采样(连接质量参考)
    private var lastDisconnectLog = ""

    // v3.47: 连接/断开本地通知（老板要求：连接提醒“设备已连接”，断开提醒“设备已断开”）
    private var wasPairedNotified = false
    private var wasDisconnectedNotified = false

    // v4.0: 充电事件推送（板子 chg:1 开始充电 / chg:2 充满 / chg:0 停止）
    @Published var rssi: Int = -100   // v4.0: RSSI 信号强度(负值, 越大越强)
    private var lastChgNotified = 0   // 0=无 1=充电中 2=充满

    private func requestNotifAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // v4.1: Widget 共享数据写入(App Group) —— 连接状态/电量/版本/RSSI 存 UserDefaults(suite)
    private var widgetDefaults: UserDefaults? {
        UserDefaults(suiteName: "group.com.cuicsi.xui")
    }
    private func updateWidgetData() {
        let d = widgetDefaults
        d?.set(state.paired, forKey: "xui_widget_connected")
        d?.set(info.battery, forKey: "xui_widget_battery")
        d?.set(info.version, forKey: "xui_widget_version")
        d?.set(rssi, forKey: "xui_widget_rssi")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // v4.1: 推送偏好(UserDefaults持久化, 设置页开关控制)
    enum NotifKey {
        static let charge = "xui_notif_charge"     // 充电/充满
        static let conn = "xui_notif_conn"         // 连接/断开
    }
    static func notifEnabled(_ key: String) -> Bool {
        let v = UserDefaults.standard.object(forKey: key) as? Bool
        return v ?? true   // 默认全开
    }
    static func setNotif(_ key: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
    }

    private func sendNotif(_ title: String, _ body: String) {
        // v4.1: 按标题分类过滤——充电类走 charge 开关, 连接类走 conn 开关
        if title.contains("充电") || title.contains("充满") {
            guard XUIManager.notifEnabled(NotifKey.charge) else { return }
        }
        if title == "XUI" {
            guard XUIManager.notifEnabled(NotifKey.conn) else { return }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    override init() {
        super.init()
        requestNotifAuth()   // v3.47: 启动请求通知权限
        // V3.19: RestoreIdentifier —— 系统后台代管: APP 退后台/被系统回收期间,
        // iOS 发现板子广播/连接事件会自动拉起 App 恢复连接(需 bluetooth-central 后台模式, 已配置)
        central = CBCentralManager(delegate: self, queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.cuicsi.xui.central"])
        // V3.42: 前后台生命周期监听 —— 返回桌面不杀连接, 回前台轻量探活
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        // V3.43: App 启动(含杀进程后重开)即自动连 —— 不等页面 onAppear, 后台也尽快拉回连接
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.startAutoConnect()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appDidEnterBackground() {
        inBackground = true
        zombieWork?.cancel()   // 后台不判僵尸: iOS 节能会延迟回调, 4s 必然误杀
        XUILogger.shared.log("📱 进入后台: 暂停僵尸检测, 保持连接")
    }

    @objc private func appWillEnterForeground() {
        inBackground = false
        XUILogger.shared.log("📱 回到前台: 恢复连接感知")
        if state.connected {
            refreshInfo()   // 连接还活着就轻量验活, 绝不先断开
        } else {
            startAutoConnect()
        }
    }

    // V3.45: iPhone 充电/电量上报 —— 开启电池监控, 每 10 秒发 ipct:NN 给板子;
    //       插拔充电瞬间额外立刻上报一次(板子侧首次上报自动打开电量监控App)
    // v4.3: 上报带充电状态 ipct:NN:S (S=1充/2满/3未充/0未知) —— 板子充电时左侧显示iPhone电量
    private func batteryStateCode(_ st: UIDevice.BatteryState) -> Int {
        switch st {
        case .charging: return 1
        case .full: return 2
        case .unplugged: return 3
        default: return 0
        }
    }
    private func startBatteryReport() {
        guard batteryReportTimer == nil else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let report = { [weak self] in
            guard let self = self, self.state.paired else { return }
            let pct = Int(UIDevice.current.batteryLevel * 100)
            let v = max(0, min(100, pct))
            let chg = self.batteryStateCode(UIDevice.current.batteryState)
            // V233: 每10秒必发(哪怕值不变)——板端已有3%容差防跳动, 不发反而让板子15s无上报显示"等待上报"
            self.lastReportedPct = v
            self.sendCtrl("ipct:\(v):\(chg)")
        }
        // 插拔电状态监听(立即上报一次触发板子跳电量)
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.state.paired else { return }
            let st = UIDevice.current.batteryState
            // V228: 去抖——状态没变(如电量浮点抖动)不处理
            if st == self.lastBatteryState { return }
            self.lastBatteryState = st
            self.reportNow(force: true)
            if st == .charging || st == .full {
                // V3.45: 插电/充满瞬间 → 直接命令板子打开电量监控(最可靠, 不依赖首次上报)  
                self.sendCtrl("app:电量")
                XUILogger.shared.log("🔌 检测到充电/满电 → 命令板子打开电量监控")
            } else if st == .unplugged {
                // V228: 拔电瞬间 → 命令板子回桌面(不再停留电量监控页)
                self.sendCtrl("app:表盘")
                XUILogger.shared.log("🔋 拔电 → 命令板子回桌面")
            }
        }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1, repeating: 2.0)   // V3.52: 10s->2s 电量更实时
        t.setEventHandler(handler: report)
        t.resume()
        batteryReportTimer = t
        XUILogger.shared.log("🔋 电量上报启动(10s周期 + 插拔电即报)")
    }

    private func stopBatteryReport() {
        batteryReportTimer?.cancel()
        batteryReportTimer = nil
    }

    // V3.45: 立即上报一次电量(插拔电事件调用)
    // V228: force=true 强制上报(拔插电瞬间, 跳过2%去抖)
    private func reportNow(force: Bool = false) {
        guard state.paired else { return }
        let pct = Int(UIDevice.current.batteryLevel * 100)
        let v = max(0, min(100, pct))
        let chg = batteryStateCode(UIDevice.current.batteryState)
        // V3.52: 去抖全删——报多少显多少, 实时无误差
        lastReportedPct = v
        sendCtrl("ipct:\(v):\(chg)")
    }

    /// 记住最近连上的板子 UUID
    private func rememberBoard(_ p: CBPeripheral) {
        UserDefaults.standard.set(p.identifier.uuidString, forKey: lastBoardKey)
    }

    /// V3.19: 入口 —— App 启动 / 重新进入页面时调用, 全自动连板子
    func startAutoConnect() {
        XUILogger.shared.log("🔄 自动连接启动")
        // V3.43: 杀进程后系统恢复的"已连接"外设 —— 本会话没主动连过, 板子端可能已把连接当僵尸
        //   （板子探活很保守, App 被杀后要 10 分钟才重广播 → 直接接管"已连接"永远扫不到!）
        //   正解: 强制断开让板子立刻重广播, 再走正常扫描/秒连。
        if let p = restoredPeripheral ?? peripheral, p.state == .connected, !connectedThisSession {
            XUILogger.shared.log("⚠️ 恢复连接未经本会话验证(可能僵尸), 强制断开让板子重广播")
            central.cancelPeripheralConnection(p)
            self.peripheral = nil
            self.pinChar = nil; self.ctrlChar = nil; self.infoChar = nil; self.tunChar = nil
            state = XUIState()
            scheduleReconnect(delay: 1.0)
            return
        }
        // V3.25: 系统恢复的外设若已是 connected → 直接接管, 绝不重复 connect!
        //   (对已连接设备调 connect 永不回调 → 卡死“连接中”; 板子还连着不广播 → 扫描也扫不到)
        if let p = restoredPeripheral ?? peripheral, p.state == .connected {
            XUILogger.shared.log("✅ 系统恢复的板子已连接, 直接接管")
            self.peripheral = p
            p.delegate = self
            state.connected = true
            if pinChar == nil {
                statusText = "已连接，发现服务..."
                p.discoverServices(nil)
                // V3.42: 特征未发现时绝不布防僵尸检测(此前 infoChar 为空时 refreshInfo 静默返回,
                //        infoPending 恒 true → 4s 后误判僵尸强制断开 = "返回桌面再进就未连接"真凶)
            } else {
                statusText = "已连接，探测中..."
                armZombieCheck()   // V3.42: 特征已就绪才验活, 且超时放宽到 12s + 后台豁免
            }
            return
        }
        // 1) 先尝试用记住的 identifier 直连(秒连, 不等扫描)
        if let saved = UserDefaults.standard.string(forKey: lastBoardKey),
           let uuid = UUID(uuidString: saved),
           let restored = restoredPeripheral {
            XUILogger.shared.log("⚡ 用记住的板子直连: \(saved.prefix(8))...")
            self.peripheral = restored
            restored.delegate = self
            central.connect(restored, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
            armConnectTimeout()
            return
        }
        // 2) retrievePeripherals 按 identifier 找回已配对设备(即使不在广播)
        if let saved = UserDefaults.standard.string(forKey: lastBoardKey),
           let uuid = UUID(uuidString: saved) {
            let known = central.retrievePeripherals(withIdentifiers: [uuid])
            if let kp = known.first {
                XUILogger.shared.log("⚡ retrieve 找回板子, 直连")
                self.peripheral = kp
                kp.delegate = self
                central.connect(kp, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                armConnectTimeout()
                return
            }
        }
        // 3) 兜底扫描
        autoScanIfNeeded()
    }

    /// V3.25: 直连超时兜底 —— 8s 内没连上, 取消转扫描(防卡死“连接中”)
    private var connectTimeoutWork: DispatchWorkItem?
    private func armConnectTimeout() {
        connectTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            XUILogger.shared.log("⚠️ 直连 8s 超时, 取消转扫描")
            if let p = self.peripheral, p.state != .connected {
                self.central.cancelPeripheralConnection(p)
            }
            self.peripheral = nil
            self.autoScanning = false
            self.autoScanIfNeeded()
        }
        connectTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: work)
    }

    // V3.26+V3.42: 僵尸连接检测 —— 仅特征就绪后才启动; 后台豁免; 超时 4s→12s
    private var zombieWork: DispatchWorkItem?
    private var infoPending = false
    private func armZombieCheck() {
        zombieWork?.cancel()
        guard infoChar != nil else { return }   // V3.42: 特征没发现完不判僵尸(修复误杀真凶)
        guard !inBackground else { return }     // V3.42: 后台不判(节能延迟回调易误杀)
        infoPending = true
        refreshInfo()   // 读 INFO 特征
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard !self.inBackground else { return }   // 超时期间进了后台也不杀
            if self.infoPending {
                XUILogger.shared.log("⚠️ 僵尸连接(INFO 12s 无回包), 断开让板子重广播")
                if let p = self.peripheral, p.state == .connected {
                    self.central.cancelPeripheralConnection(p)
                }
                self.peripheral = nil
                self.pinChar = nil; self.ctrlChar = nil; self.infoChar = nil; self.tunChar = nil
                self.autoScanning = false
                self.autoScanIfNeeded()
            }
        }
        zombieWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: work)
    }

    private func autoScanIfNeeded() {
        guard central.state == .poweredOn else {
            XUILogger.shared.log("⏳ 蓝牙未就绪, 等 poweredOn 后自动扫")
            return
        }
        if let p = peripheral, p.state == .connected {
            XUILogger.shared.log("✅ 已连接, 无需重扫")
            return
        }
        guard !autoScanning else { return }
        XUILogger.shared.log("🔍 自动扫描 XUI...")
        autoScanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    /// V3.17: 断开/失败后延迟重扫(板子不重启也能重连)
    /// V180: 改成每 3 秒无限循环重试 —— 只要没连上就一直尝试(板子侧 3 秒心跳广播兜底), 老板要求
    private func scheduleReconnect(delay: Double = 3.0) {
        autoRetryTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let p = self.peripheral, p.state == .connected {
                return
            }
            self.autoScanning = false
            self.autoScanIfNeeded()
            self.scheduleReconnect(delay: 3.0)   // 一直尝试直到连上
        }
        autoRetryTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: 扫描 / 连接
    func scan() {
        XUILogger.shared.log("🔍 扫描开始 (central=\(central.state.rawValue))")
        guard central.state == .poweredOn else {
            statusText = "请先打开 iPhone 蓝牙"; return
        }
        if let p = peripheral, p.state == .connected {
            XUILogger.shared.log("↩️ 断开旧连接再扫")
            central.cancelPeripheralConnection(p)
        }
        statusText = "扫描 XUI 板子..."
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func disconnect() {
        XUILogger.shared.log("🔌 主动断开")
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
    }

    // MARK: 配对 / 控制
    func pair() {
        guard let c = pinChar, let p = peripheral else {
            statusText = "请先连接板子"; return
        }
        XUILogger.shared.log("🔑 发送配对码 \(pin)")
        p.writeValue(pin.data(using: .utf8)!, for: c, type: .withResponse)
        statusText = "配对中..."
    }

    /// 发控制命令（未配对会收到 ERR:PAIR）
    /// V4.2: 无响应直发 —— 固件 V243+ FFE2 支持 WRITE_NO_RSP, 手柄按键/音量等不再等 ACK,
    ///   操控延迟 fromResponse 逐帧确认(~30ms+) 降到 ~5ms 直发; 旧固件(无 WRITE_NO_RSP)自动退避 withResponse
    func sendCtrl(_ cmd: String) {
        guard state.paired, let c = ctrlChar, let p = peripheral else {
            if !state.connected { statusText = "未连接板子" }
            else { statusText = "请先配对" }
            return
        }
        XUILogger.shared.log("🎮 CTRL→板: \(cmd)")
        if p.canSendWriteWithoutResponse {
            p.writeValue(cmd.data(using: .utf8)!, for: c, type: .withoutResponse)
        } else {
            p.writeValue(cmd.data(using: .utf8)!, for: c, type: .withResponse)
        }
    }

    func refreshInfo() {
        guard let c = infoChar, let p = peripheral else { return }
        XUILogger.shared.log("ℹ️ 请求 INFO 读取")
        p.readValue(for: c)
    }

    // MARK: 透传发送（隧道对外出口：App 侧构造消息发板子）
    // V3.5: CoreBluetooth 写操作必须在主线程；后台线程直接调会崩溃(大响应闪退真凶)
    // V3.11: 全部改 .withResponse —— V169 板子 TUN 特性(0xFFE4)只声明 WRITE(带响应) 没 WRITE_NO_RSP,
    //   iOS 用 .withoutResponse 写被 NimBLE 静默丢弃 → 板子永远等不到 ACK/响应 → 5s 超时重发 → 网络错误。
    // V3.12: 修复点击升级即闪退 —— 根因=同一时刻两笔 withResponse 写并发(双写)触发 CoreBluetooth 崩溃。
    //   旧实现每帧靠 asyncAfter 看门狗+回调都可能 drainSendQueue, 高速发帧时(固件下载 300+帧)会重叠双写。
    //   新实现: 每帧派发时取 writeSeq 快照, 看门狗 6s 后仅当 writeSeq 仍等于该快照(即这帧真卡住)才重置;
    //   后续帧会递增 writeSeq, 旧看门狗自动失效 → 全链路任意时刻最多 1 笔写。
    private var sendQueue: [[UInt8]] = []
    private var sending = false
    private var writeSeq = 0          // V3.12: 写序号, 每派发一帧 +1
    private var useWriteNoResp = false   // V3.24: 板子 >= V172 时 true(固件加了 WRITE_NO_RSP) → 流水线发送

    func tunnelSend(_ type: UInt8, payload: [UInt8]) {
        let chunks = TUNChunker.chunk(type: type, payload: payload)
        // 日志节流: 帧数>20 只记一次(防刷屏卡 UI)
        XUILogger.shared.log("📤 隧道发→板: type=0x\(String(format:"%02X", type)) \(payload.count)B → \(chunks.count)帧")
        DispatchQueue.main.async {
            // V3.13: 队列上限保护 —— 积压超 3000 帧(≈360KB)说明板子收不过来/连接异常, 清空防内存爆炸
            if self.sendQueue.count > 3000 {
                XUILogger.shared.log("⚠️ 发送队列积压 \(self.sendQueue.count) 帧, 清空防内存爆炸")
                self.sendQueue.removeAll()
            }
            self.sendQueue.append(contentsOf: chunks)
            self.drainSendQueue()
        }
    }

    /// V3.11: ACK 插队到最前优先发(板子在等 ACK 才返回)，且走 withResponse 保证送达
    private func sendAckFrame(_ ack: [UInt8]) {
        DispatchQueue.main.async {
            self.sendQueue.insert(contentsOf: [ack], at: 0)
            self.drainSendQueue()
        }
    }

    private func drainSendQueue() {
        guard !sendQueue.isEmpty else { return }
        guard state.paired, let c = tunChar, let p = peripheral else {
            sendQueue.removeAll()   // 断开/未配对时清空防积压
            return
        }
        // V3.16: 写前确认连接仍在线 —— 板子中途断连后继续写会触发 CoreBluetooth 断言崩溃(SIGTRAP)
        guard p.state == .connected else {
            XUILogger.shared.log("⚠️ 板子已断连, 清空发送队列")
            sendQueue.removeAll()
            sending = false
            return
        }

        // V3.24: V172+ 无响应写流水线 —— 不等每帧 ACK, canSendWriteWithoutResponse 门控批量连发,
        //   吞吐 5-10 倍(配合固件 7.5ms 快连接间隔, 4.7MB 固件 ~60 分钟 → 5-10 分钟)
        if useWriteNoResp {
            var burst = 0
            while burst < 40, !sendQueue.isEmpty, p.canSendWriteWithoutResponse {
                let ch = sendQueue.removeFirst()
                p.writeValue(Data(ch), for: c, type: .withoutResponse)
                burst += 1
            }
            if !sendQueue.isEmpty {
                // 每轮让出 3ms, 循环续发(不依赖回调, canSend 门控防溢出)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.003) { [weak self] in
                    self?.drainSendQueue()
                }
            }
            return
        }

        // ---- V170/V171 旧固件: withResponse 逐帧确认模式 ----
        sending = true
        writeSeq += 1
        let mySeq = writeSeq
        let ch = sendQueue.removeFirst()
        // V3.16: 进度日志(每50帧记一次)——精确定位崩溃在哪一帧
        if mySeq % 50 == 1 || sendQueue.isEmpty {
            XUILogger.shared.log("✉️ 发帧 \(mySeq) (剩 \(sendQueue.count))")
        }
        p.writeValue(Data(ch), for: c, type: .withResponse)
        // V3.14: 看门狗改为只清不续 —— 固件下载时板子 esp_ota_write 写 flash 会卡 BLE 响应,
        //   旧版(v3.12)6s 看门狗重置后与迟到的 didWriteValueFor 回调交错 → 两笔写并发 → CoreBluetooth 崩溃闪退。
        //   现在超时只放弃当前消息(清空队列+重置), 等板子侧超时重发请求即可, 绝不自动续发防双写。
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            if self.sending && self.writeSeq == mySeq {
                XUILogger.shared.log("⚠️ 写帧10s无回调(可能板子写flash中), 放弃本批防双写, 等板子重发")
                self.sending = false
                self.sendQueue.removeAll()
            }
        }
    }

    // V3.5: BLE 校时 —— 配对成功后把手机时间发给板子(纯蓝牙模式没 SNTP, 板子时钟停在 1970)
    private func sendTimeToBoard() {
        let ts = Int(Date().timeIntervalSince1970)
        let json = "{\"ts\":\(ts)}"
        if let data = json.data(using: .utf8) {
            tunnelSend(TUNMsgType.timeSet.rawValue, payload: [UInt8](data))
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension XUIManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        XUILogger.shared.log("📡 蓝牙状态: \(central.state.rawValue)")
        if central.state == .poweredOn {
            statusText = "蓝牙已就绪，自动连接中..."
            autoScanIfNeeded()   // V3.17: 蓝牙开启即自动扫
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "")
        XUILogger.shared.log("📡 扫描到设备: \(name) RSSI=\(RSSI)")
        DispatchQueue.main.async { self.rssi = RSSI.intValue }   // v4.0: RSSI 实时展示
        guard name.contains("XUI") else { return }
        hadXUI = true
        // V3.37: 采样 RSSI(连接质量参考)
        rssiSamples.append(RSSI.intValue)
        if rssiSamples.count > 20 { rssiSamples.removeFirst() }
        central.stopScan()
        autoScanning = false
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        statusText = "发现 XUI，连接中..."
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        XUILogger.shared.log("❌ 连接失败: \(error?.localizedDescription ?? "未知"), 2s后重试")
        self.peripheral = nil
        scheduleReconnect(delay: 2.0)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimeoutWork?.cancel()   // V3.25: 连上了就取消超时兑底
        XUILogger.shared.log("✅ 已连接，发现服务...")
        rememberBoard(peripheral)   // V3.19: 记住板子 identifier(下次秒连)
        connectedThisSession = true   // V3.43: 本会话已主动连接(恢复判定用)
        state.connected = true
        state.paired = false
        connectCount += 1
        lastConnectedAt = Date()
        statusText = "已连接，发现服务..."
        peripheral.discoverServices(nil)   // V3.40: 无主动心跳, 靠板子探活被动维持
    }

    // V3.19: 系统后台恢复 —— iOS 带着蓝牙状态拉起 App 时调用(需 central RestoreIdentifier)
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        XUILogger.shared.log("♻️ 系统恢复 \(restored.count) 个外设")
        if let p = restored.first {
            restoredPeripheral = p
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startAutoConnect()
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        disconnectCount += 1   // V3.40: 无心跳可停; 断开即尝试 retrieve 秒连
        wasPairedNotified = false   // v3.47: 重置, 下次配对成功再通知
        if !wasDisconnectedNotified {
            wasDisconnectedNotified = true
            sendNotif("XUI", "设备已断开")
        }
        let dur: String
        if let t0 = lastConnectedAt {
            let sec = Int(Date().timeIntervalSince(t0))
            dur = "连接时长\(sec)s"
        } else { dur = "时长未知" }
        let rssiNote = rssiSamples.isEmpty ? "" : " 平均RSSI=\(rssiSamples.reduce(0,+)/rssiSamples.count)"
        rssiSamples.removeAll()
        XUILogger.shared.log("❌ 已断开 #\(disconnectCount) error=\(error?.localizedDescription ?? "无") \(dur)\(rssiNote), 2s后自动重连")
        state = XUIState()
        connectedThisSession = false   // V3.43
        pairedThisSession = false
        stopBatteryReport()   // V3.45: 断开停上报
        updateWidgetData()   // v4.1: 断开刷新小组件
        statusText = "已断开，自动重连中..."
        self.peripheral = nil
        // V3.40: 断开后立即 retrieve 找回直连(秒连), 失败才转扫描重试
        if let saved = UserDefaults.standard.string(forKey: lastBoardKey),
           let uuid = UUID(uuidString: saved) {
            let known = central.retrievePeripherals(withIdentifiers: [uuid])
            if let kp = known.first {
                XUILogger.shared.log("⚡ 断开后 retrieve 找回板子, 秒连")
                self.peripheral = kp
                kp.delegate = self
                central.connect(kp, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                armConnectTimeout()
                return
            }
        }
        scheduleReconnect(delay: 1.0)   // retrieve 没找到 → 1s 后转扫描
    }

}

// MARK: - CBPeripheralDelegate
extension XUIManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        DispatchQueue.main.async { self.rssi = RSSI.intValue }   // v4.0: 连接中实时读 RSSI
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for svc in peripheral.services ?? [] where svc.uuid.uuidString.contains("FFE0") {
            peripheral.discoverCharacteristics(nil, for: svc)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        var found = ""
        for ch in service.characteristics ?? [] {
            let u = ch.uuid.uuidString
            if u.contains("FFE1") { pinChar = ch; peripheral.setNotifyValue(true, for: ch); found += " FFE1" }
            else if u.contains("FFE2") { ctrlChar = ch; peripheral.setNotifyValue(true, for: ch); found += " FFE2" }
            else if u.contains("FFE3") { infoChar = ch; peripheral.setNotifyValue(true, for: ch); found += " FFE3" }
            else if u.contains("FFE4") { tunChar = ch; peripheral.setNotifyValue(true, for: ch); found += " FFE4" }
        }
        XUILogger.shared.log("🔧 特征就绪:\(found)")
        // V3.23: 提速修复——只看 withResponse 模式最大写长度(我们发送用 withResponse):
        //   旧 v3.22 取 max(无响应,带响应) 可能设 500B → 超实际可写长度 → 写失败丢帧 → 整块收不齐 → 60s 超时重试卡块(下载慢元凶)
        let wr = peripheral.maximumWriteValueLength(for: .withResponse)
        if wr >= 244 { TUNChunker.dataMax = 240 }        // 协商 MTU≥247 时安全 (4+240=244)
        else if wr >= 180 { TUNChunker.dataMax = 176 }   // 最小 MTU 185 档
        else { TUNChunker.dataMax = 120 }                // 极保守兑底
        XUILogger.shared.log("⚡ withResponse写长 \(wr)B → 分片 \(TUNChunker.dataMax)B (提速)")
        statusText = "服务就绪，自动配对中..."
        // V3.17: 特征就绪后自动配对(无需点按钮), 稍等 notify 订阅建立
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pair()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        // V3.3 关键修复①: 隧道(FFE4)是二进制分片, 不能当 UTF8 字符串解析(含高字节帧会被挡掉丢消息)
        if characteristic == tunChar {
            let bytes = [UInt8](data)
            // V3.3 关键修复②: 收到完整数据消息的 end 帧时回 ACK ——
            //   板子 tun_send 发完分片会等 ACK(type 0xFE)才返回成功; 之前 App 端从不回 ACK,
            //   板子一直等到超时重发, AI余量/监控/OTA 借手机网络全部失败。
            // V3.11: ACK 必须主线程+门控发送, 否则 withoutResponse 写被系统丢弃 → 板子永远等不到 ACK
            if bytes.count >= 4 {
                let ftype = bytes[0], fid = bytes[1], fflags = bytes[3]
                if ftype != TUNMsgType.ack.rawValue && (fflags & 0x40) != 0 {
                    let ack: [UInt8] = [TUNMsgType.ack.rawValue, fid, 0, 0x40]
                    XUILogger.shared.log("📥 隧道收→\(bytes.count)B 回ACK id=\(fid)")
                    sendAckFrame(ack)
                }
            }
            if let msg = tunRx.push(bytes) {
                XUILogger.shared.log("📨 隧道完整消息 type=0x\(String(format:"%02X", msg.type)) \(msg.payload.count)B")
                XUITunnelRelay.shared.handleIncoming(type: msg.type, payload: msg.payload)
            }
            return
        }

        guard let val = String(data: data, encoding: .utf8) else { return }
        if characteristic == pinChar {
            if val.contains("PAIR:OK") {
                XUILogger.shared.log("✅ 配对成功！(发送校时)")
                state.paired = true
                if !wasPairedNotified {
                    wasPairedNotified = true
                    wasDisconnectedNotified = false   // v3.47: 重连后重置断开标记
                    sendNotif("XUI", "设备已连接")
                }
                statusText = "✅ 配对成功！可以遥控了"
                updateWidgetData()   // v4.1: 配对即刷新小组件
                sendTimeToBoard()   // V3.5: 配对即校时
                startBatteryReport()   // V3.45: 配对即开始电量/充电上报
            } else if val.contains("PAIR:FAIL") {
                XUILogger.shared.log("❌ 配对失败")
                statusText = "❌ 配对码错误"
            }
        } else if characteristic == ctrlChar {
            if val.contains("ERR:PAIR") { XUILogger.shared.log("⚠️ 收到 ERR:PAIR"); statusText = "未配对" }
            // v4.0: 板子充电事件推送 —— 充电中推当前电量, 充满推“已充满”
            else if val.contains("chg:1") {
                XUILogger.shared.log("🔌 板子开始充电")
                let pct = Int(UIDevice.current.batteryLevel * 100)
                sendNotif("XUI 充电中", "板子电量 \(max(0, min(100, pct)))%，正在充电 ⚡")
                lastChgNotified = 1
            }
            else if val.contains("chg:2") {
                XUILogger.shared.log("🔋 板子已充满")
                sendNotif("XUI 已充满", "板子电池已充满 💯")
                lastChgNotified = 2
            }
            else if val.contains("chg:0") {
                XUILogger.shared.log("🔌 板子停止充电")
                lastChgNotified = 0
            }
        } else if characteristic == infoChar {
            infoPending = false   // V3.26: INFO 有回包 = 连接真活, 取消僵尸检测
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                info.battery = j["bat"] as? Int ?? -1
                info.version = j["v"] as? String ?? "--"
                info.wifi = (j["wifi"] as? Int ?? 0) == 1
                info.mem = j["mem"] as? Int ?? -1
                info.memExt = j["mem_ext"] as? Int ?? -1
                info.disk = j["disk"] as? Int ?? -1
                // v4.3: 板子常亮/防误触开关状态(固件V244+ info 带 ao/at 字段)
                if let ao = j["ao"] as? Int { info.alwaysOn = (ao == 1) }
                if let at = j["at"] as? Int { info.antiTouch = (at == 1) }
                updateWidgetData()   // v4.1: 同步小组件数据
                XUILogger.shared.log("ℹ️ INFO: bat=\(info.battery) v=\(info.version) wifi=\(info.wifi)")
                // V3.24: 板子版本 >= V172 → 启用无响应写流水线(固件已加 WRITE_NO_RSP + 7.5ms 快间隔)
                let ver = info.version.replacingOccurrences(of: "V", with: "")
                let vnum = Int(ver) ?? 0
                if vnum >= 172 && !useWriteNoResp {
                    useWriteNoResp = true
                    XUILogger.shared.log("⚡ 板子 V\(vnum) 支持无响应写 → 流水线提速模式开启")
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic == tunChar, error == nil {
            XUILogger.shared.log("✅ 透传通道就绪(FFE4 notify 开)")
            statusText = "透传通道就绪"
        } else if error != nil {
            XUILogger.shared.log("⚠️ notify 设置失败: \(error!.localizedDescription)")
        }
    }

    // V3.6: 无响应写缓冲腾空回调 —— 继续排空发送队列
    // V3.24: 流水线模式下系统缓冲腾空时自动续发(不依赖 3ms 轮询, 更快)
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if useWriteNoResp {
            drainSendQueue()
        }
    }

    // V3.11: withResponse 写完成回调 —— 每帧确认送达后发下一帧(可靠+流控)
    // V3.12: 错误时退避 500ms 再续(防连续失败快速空转)；成功后立即发下一帧
    // V3.16: 帧间节流 8ms —— 固件下载 365 帧高速连发 + 板子写flash响应变慢时,
    //   iOS CoreBluetooth 连发触发 SIGTRAP 崩溃。改每帧确认后等 8ms 再发下一帧。
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic == tunChar else { return }
        sending = false
        if let e = error {
            XUILogger.shared.log("⚠️ 隧道写失败(退避500ms): \(e.localizedDescription)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.drainSendQueue()
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) { [weak self] in   // V3.23: 8ms→4ms, V170 已稳定提速
            self?.drainSendQueue()
        }
    }
}
