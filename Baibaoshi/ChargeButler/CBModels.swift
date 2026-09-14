import Foundation
import UIKit
import SwiftUI

// MARK: - 充电数据点 / 会话

struct ChargePoint: Codable, Identifiable, Equatable {
    var id: Date { t }
    let t: Date
    let level: Int
}

struct ChargeSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date?
    var points: [ChargePoint] = []
    var startLevel: Int = 0
    var endLevel: Int = 0
    var reachedFull: Bool = false
    var device: String = ""

    /// 会话时长（分钟），未结束时按现在计算
    var durationMinutes: Double {
        let e = end ?? Date()
        return max(0, e.timeIntervalSince(start) / 60)
    }

    var gainedPercent: Int { max(0, endLevel - startLevel) }

    /// 平均速率 %/分钟
    var avgRate: Double {
        guard durationMinutes > 0.5 else { return 0 }
        return Double(gainedPercent) / durationMinutes
    }
}

// MARK: - 分段速率统计

struct RateBucket: Codable {
    var minutes: Double = 0
    var percents: Double = 0
    var samples: Int = 0
    var rate: Double { minutes > 0.2 ? percents / minutes : 0 }
}

// MARK: - 电量颜色分段工具

enum BatteryTheme {
    static func colors(for level: Int) -> [Color] {
        switch level {
        case ..<20:  return [Color(hex: 0xFF5F6D), Color(hex: 0xFF8A65)]
        case ..<50:  return [Color(hex: 0xFFB340), Color(hex: 0xFFD54F)]
        default:     return [Color(hex: 0x34E0A1), Color(hex: 0x2AD4C8)]
        }
    }

    static func stateText(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging:    return "充电中"
        case .full:        return "已充满"
        case .unplugged:   return "使用电池"
        default:           return "未知"
        }
    }
}
