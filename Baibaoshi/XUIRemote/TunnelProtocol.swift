import Foundation

// MARK: - BLE 透传分片协议（与固件 V142 xui_tunnel.cpp 对齐）
// chunk = [type(1) id(1) seq(1) flags(1) payload(0..176)]
// flags: 0x80=start 0x40=end | 收端回 ACK: type=0xFE flags=0x40

enum TUNMsgType: UInt8 {
    case httpReq = 0x01
    case httpResp = 0x02
    case audio = 0x03
    case tts = 0x04
    case otaBlock = 0x05
    case otaAck = 0x06
    case timeSet = 0x07
    case appCmd = 0x08
    case ack = 0xFE
}

struct TUNMessage {
    let type: UInt8
    let payload: [UInt8]
}

enum TUNChunker {
    // V3.22: 分片大小由 XUIManager 连上后按实际最大写长度(MTU)自适应:
    //   V169 收包截断 127B → 当时被迫 120B; V170 放宽到 511B → 可升到 ~245B(协商 MTU 256)
    //   默认 176(最小 MTU 185 也安全), 连接后读到更大上限自动上调 → 帧数减少 = 升级提速
    static var dataMax = 176
    static func chunk(type: UInt8, payload: [UInt8]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        if payload.isEmpty {
            out.append([type, 1, 0, 0xC0]) // start|end
            return out
        }
        var off = 0
        var seq: Int = 0   // V3.18: 改 Int 计数根治闪退——原 UInt8 在 365 帧(固件块44KB)时 seq=255 溢出
                           //   → Swift 整数溢出直接 SIGTRAP 崩溃(signal=5, 与崩溃报告完全吻合)。
                           //   写入帧头时截断为 UInt8(两端接收均不校验 seq, 仅作参考, 安全回绕)。
        while off < payload.count {
            let n = min(dataMax, payload.count - off)
            var h: [UInt8] = [type, 1, UInt8(truncatingIfNeeded: seq), 0]
            if off == 0 { h[3] |= 0x80 }
            if off + n >= payload.count { h[3] |= 0x40 }
            out.append(h + payload[off..<off+n])
            off += n; seq += 1
        }
        return out
    }
}

final class TUNReceiver {
    private var buf: [UInt8] = []
    private var active = false
    private var msgType: UInt8 = 0
    private var msgId: UInt8 = 0
    var onAck: (() -> Void)?

    /// 推入一帧，返回整条消息（组完时）
    func push(_ frame: [UInt8]) -> TUNMessage? {
        guard frame.count >= 4 else { return nil }
        let type = frame[0], id = frame[1], seq = frame[2], flags = frame[3]
        let body = frame.count > 4 ? Array(frame[4...]) : []

        if type == TUNMsgType.ack.rawValue {
            if flags & 0x40 != 0 { onAck?() }
            return nil
        }
        if flags & 0x80 != 0 {           // start
            active = true; buf = []; msgType = type; msgId = id
        }
        guard active, type == msgType, id == msgId else { return nil }
        buf += body
        if flags & 0x40 != 0 {           // end
            let msg = TUNMessage(type: msgType, payload: buf)
            active = false; buf = []
            return msg
        }
        return nil
    }
}
