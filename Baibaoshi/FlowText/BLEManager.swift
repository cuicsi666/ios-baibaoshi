import Foundation
import CoreBluetooth

/// 流文 App BLE 中央管理：连接 XUI 板子（0xFFE0 服务），接收流文推流
/// 协议：0xFFE4 TUN 通道 NOTIFY，"FT|<utf8>" 前缀 = 流文文字；
///       "FT|\n" = 本句结束（下一次字符开始新会话）。
final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BLEManager()

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var pinChar: CBCharacteristic?
    private var tunChar: CBCharacteristic?

    // GATT UUID（与固件 1:1）
    private let svcFFE0 = CBUUID(string: "FFE0")
    private let chrFFE1 = CBUUID(string: "FFE1")   // PIN
    private let chrFFE4 = CBUUID(string: "FFE4")   // TUN 透传

    /// 会话累积文本（当前一句话）
    private var sessionText = ""
    /// App Group 共享（与键盘扩展通信）
    private var group: UserDefaults?
    private var rev: Int = 0

    @Published var state: String = "初始化蓝牙..."
    @Published var connected: Bool = false
    @Published var deviceName: String = ""
    @Published var lastLine: String = ""
    @Published var history: [String] = UserDefaults.standard.stringArray(forKey: "ft_history") ?? []

    static let ftTextKey = "ft_text"
    static let ftRevKey = "ft_rev"
    static let ftResetKey = "ft_reset"
    static let ftLastKey = "ft_last"

    override init() {
        super.init()
        group = UserDefaults(suiteName: "group.com.cuicsi.flowtext")
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - 公共操作
    func startScan() {
        guard central.state == .poweredOn else {
            state = "蓝牙未开启"
            return
        }
        state = "扫描 XUI 设备..."
        central.scanForPeripherals(withServices: [svcFFE0], options: nil)
    }

    func stopScan() { central.stopScan() }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            state = connected ? "已连接" : "蓝牙就绪"
        case .poweredOff: state = "蓝牙未开启"; connected = false
        case .unauthorized: state = "蓝牙未授权"
        default: state = "蓝牙不可用"; connected = false
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard name == "XUI" else { return }
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        state = "连接中..."
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = "发现服务..."
        peripheral.discoverServices([svcFFE0])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connected = false
        state = "已断开，重连中..."
        // 自动重连
        if let p = self.peripheral { central.connect(p, options: nil) }
    }

    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == svcFFE0 }) else { return }
        peripheral.discoverCharacteristics([chrFFE1, chrFFE4], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            if c.uuid == chrFFE1 {
                pinChar = c
                // 配对码 1234
                let pin = "1234".data(using: .utf8)!
                peripheral.writeValue(pin, for: c, type: .withResponse)
            }
            if c.uuid == chrFFE4 {
                tunChar = c
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == chrFFE4 && error == nil {
            connected = true
            deviceName = peripheral.name ?? "XUI"
            state = "已连接，等板子说话"
        }
    }

    // MARK: - 流文数据接收
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == chrFFE4,
              let raw = characteristic.value,
              let s = String(data: raw, encoding: .utf8) else { return }
        guard s.hasPrefix("FT|") else { return }   // 只处理流文帧

        var payload = String(s.dropFirst(3))
        let isEnd = (payload == "\n")
        if isEnd { payload = "" }

        if isEnd {
            // 一句结束：入历史 + 置新会话标记
            if !sessionText.isEmpty {
                lastLine = sessionText
                history.insert(sessionText, at: 0)
                if history.count > 20 { history.removeLast() }
                UserDefaults.standard.set(history, forKey: "ft_history")
            }
            sessionText = ""
        } else {
            sessionText += payload
        }

        // 写 App Group（键盘扩展轮询消费）
        guard let g = group else { return }
        if isEnd {
            g.set(true, forKey: Self.ftResetKey)
        } else {
            g.set(sessionText, forKey: Self.ftTextKey)
            g.set(sessionText, forKey: Self.ftLastKey)
        }
        rev += 1
        g.set(rev, forKey: Self.ftRevKey)
    }
}
