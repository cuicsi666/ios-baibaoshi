import SwiftUI
import UIKit
import Foundation

// MARK: - 设备信息面板（DevInfoView）
// 纯本地：分区卡片展示设备 / 屏幕 / 处理器与内存 / 存储 / 运行时间 / 区域语言时区。
// 每项支持长按复制，底部可一键复制全部信息。
// 自定义类型统一 Dev 前缀，避免与主工程冲突。

// MARK: - 型号识别

enum DevHardware {

    /// utsname.machine，例如 iPhone15,2
    static var identifier: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        var result = ""
        for child in mirror.children {
            if let value = child.value as? Int8, value != 0 {
                result.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
            }
        }
        return result.isEmpty ? "unknown" : result
    }

    /// 机型标识 → 友好名（覆盖 iPhone 12 ~ 16 系列常见代号，另含部分旧机型）
    static func friendlyName(_ id: String) -> String {
        switch id {
        // iPhone 16 系列
        case "iPhone17,1": return "iPhone 16 Pro Max"
        case "iPhone17,2": return "iPhone 16 Pro"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone17,5": return "iPhone 16e"
        // iPhone 15 系列
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        // iPhone 14 系列
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        // iPhone 13 系列
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,4": return "iPhone 13 mini"
        // iPhone 12 系列
        case "iPhone13,1": return "iPhone 12 mini"
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"
        // 更早机型
        case "iPhone14,6": return "iPhone SE (第 3 代)"
        case "iPhone12,8": return "iPhone SE (第 2 代)"
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"
        case "iPhone11,2": return "iPhone XS"
        case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
        case "iPhone11,8": return "iPhone XR"
        case "iPhone10,3", "iPhone10,6": return "iPhone X"
        case "iPhone10,1", "iPhone10,4": return "iPhone 8"
        case "iPhone10,2", "iPhone10,5": return "iPhone 8 Plus"
        case "iPhone9,1", "iPhone9,3": return "iPhone 7"
        case "iPhone9,2", "iPhone9,4": return "iPhone 7 Plus"
        case "i386", "x86_64", "arm64": return "模拟器"
        default:
            if id.hasPrefix("iPhone") { return "iPhone（未知型号 \(id)）" }
            if id.hasPrefix("iPad") { return "iPad（\(id)）" }
            if id.hasPrefix("iPod") { return "iPod touch" }
            return id
        }
    }

    /// 机型 → 屏幕对角线英寸（用于估算 PPI）
    static func screenInches(_ id: String) -> Double? {
        switch id {
        case "iPhone17,1", "iPhone17,2", "iPhone16,2", "iPhone15,3", "iPhone14,3", "iPhone13,4": return 6.7
        case "iPhone17,3", "iPhone17,4", "iPhone17,5", "iPhone16,1", "iPhone15,4", "iPhone15,5",
             "iPhone15,2", "iPhone14,7", "iPhone14,8", "iPhone14,5", "iPhone14,2",
             "iPhone13,2", "iPhone13,3", "iPhone12,1", "iPhone12,3", "iPhone12,5",
             "iPhone11,2", "iPhone11,4", "iPhone11,6", "iPhone11,8": return 6.1
        case "iPhone14,4", "iPhone13,1": return 5.4
        case "iPhone14,6", "iPhone12,8", "iPhone10,1", "iPhone10,4", "iPhone9,1", "iPhone9,3": return 4.7
        case "iPhone10,2", "iPhone10,5", "iPhone9,2", "iPhone9,4": return 5.5
        case "iPhone10,3", "iPhone10,6": return 5.8
        default: return nil
        }
    }
}

// MARK: - 数据模型

struct DevItem: Identifiable {
    let id = UUID()
    let key: String
    let value: String
    let icon: String
}

struct DevSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let colors: [Color]
    let rows: [DevItem]
}

// MARK: - 信息采集

enum DevCollector {

    static func bytes(_ count: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useTB, .useGB, .useMB]
        f.includesUnit = true
        f.isAdaptive = true
        return f.string(fromByteCount: max(0, count))
    }

    static func storage() -> (total: Int64, free: Int64) {
        var total: Int64 = 0
        var free: Int64 = 0
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]),
           let cap = values.volumeTotalCapacity {
            total = Int64(cap)
        }
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let avail = values.volumeAvailableCapacityForImportantUsage {
            free = avail
        }
        return (total, free)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let mins = (total % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时 \(mins) 分" }
        if hours > 0 { return "\(hours) 小时 \(mins) 分" }
        return "\(mins) 分 \(total % 60) 秒"
    }

    static func dateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    static func ppi() -> Double? {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        guard let inches = DevHardware.screenInches(DevHardware.identifier), inches > 0 else { return nil }
        let w = Double(bounds.width) * Double(scale)
        let h = Double(bounds.height) * Double(scale)
        return (w * w + h * h).squareRoot() / inches
    }

    static func sections() -> [DevSection] {
        let device = UIDevice.current
        let process = ProcessInfo.processInfo
        let screen = UIScreen.main
        let bounds = screen.bounds
        let pxW = Int(bounds.width * screen.scale)
        let pxH = Int(bounds.height * screen.scale)
        let memGB = Double(process.physicalMemory) / 1_073_741_824.0
        let store = storage()
        let used = max(0, store.total - store.free)
        let usedRatio = store.total > 0 ? Double(used) / Double(store.total) : 0
        let upSeconds = process.systemUptime
        let bootDate = Date().addingTimeInterval(-upSeconds)
        let locale = Locale.current
        let tz = TimeZone.current
        let offsetHours = Double(tz.secondsFromGMT()) / 3600.0
        let langCode = locale.language.languageCode?.identifier ?? locale.identifier
        let regionCode = locale.region?.identifier ?? "—"
        let preferred = Locale.preferredLanguages.first ?? "—"
        let hour12 = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("a") ?? true

        let deviceSection = DevSection(
            title: "设备", icon: "iphone.gen3", colors: [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)],
            rows: [
                DevItem(key: "设备名称", value: device.name, icon: "tag.fill"),
                DevItem(key: "机型", value: DevHardware.friendlyName(DevHardware.identifier), icon: "iphone"),
                DevItem(key: "型号标识", value: DevHardware.identifier, icon: "number"),
                DevItem(key: "设备类型", value: device.model, icon: "square.stack.3d.up.fill"),
                DevItem(key: "系统", value: "\(device.systemName) \(device.systemVersion)", icon: "gear"),
                DevItem(key: "名称/标识", value: "\(device.systemName)/\(DevHardware.identifier)", icon: "barcode")
            ])

        let screenSection = DevSection(
            title: "屏幕", icon: "rectangle.inset.filled", colors: [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)],
            rows: [
                DevItem(key: "分辨率", value: "\(pxW) × \(pxH) px", icon: "rectangle.on.rectangle"),
                DevItem(key: "逻辑尺寸", value: String(format: "%.0f × %.0f pt", bounds.width, bounds.height), icon: "ruler"),
                DevItem(key: "缩放倍数", value: String(format: "@%.0fx", screen.scale), icon: "magnifyingglass"),
                DevItem(key: "估算 PPI", value: ppiString(), icon: "dot.radiowaves.left.and.right"),
                DevItem(key: "屏幕亮度", value: String(format: "%.0f%%", screen.brightness * 100), icon: "sun.max.fill"),
                DevItem(key: "原生缩放", value: String(format: "%.2fx", screen.nativeScale), icon: "arrow.up.left.and.arrow.down.right")
            ])

        let cpuSection = DevSection(
            title: "处理器与内存", icon: "cpu", colors: [Color(hex: 0xFF7A18), Color(hex: 0xFF3D71)],
            rows: [
                DevItem(key: "核心总数", value: "\(process.processorCount) 核", icon: "cpu"),
                DevItem(key: "活跃核心", value: "\(process.activeProcessorCount) 核", icon: "bolt.fill"),
                DevItem(key: "物理内存", value: String(format: "%@（%.1f GB）", bytes(Int64(process.physicalMemory)), memGB), icon: "memorychip"),
                DevItem(key: "低电量模式", value: process.isLowPowerModeEnabled ? "已开启" : "未开启", icon: "battery.25"),
                DevItem(key: "运行环境", value: "iOS \(device.systemVersion)", icon: "apple.logo")
            ])

        let storageSection = DevSection(
            title: "存储", icon: "internaldrive", colors: [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)],
            rows: [
                DevItem(key: "总容量", value: bytes(store.total), icon: "externaldrive.fill"),
                DevItem(key: "可用容量", value: bytes(store.free), icon: "tray.and.arrow.down.fill"),
                DevItem(key: "已用容量", value: bytes(used), icon: "tray.full.fill"),
                DevItem(key: "使用率", value: String(format: "%.1f%%", usedRatio * 100), icon: "chart.pie.fill")
            ])

        let uptimeSection = DevSection(
            title: "系统运行", icon: "clock.arrow.circlepath", colors: [Color(hex: 0x43CBAF), Color(hex: 0x2E9CCA)],
            rows: [
                DevItem(key: "已运行", value: uptime(upSeconds), icon: "hourglass"),
                DevItem(key: "上次开机", value: dateTime(bootDate), icon: "power"),
                DevItem(key: "当前时间", value: dateTime(Date()), icon: "clock.fill")
            ])

        let localeSection = DevSection(
            title: "区域与语言", icon: "globe.asia.australia.fill", colors: [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)],
            rows: [
                DevItem(key: "区域", value: regionCode, icon: "map.fill"),
                DevItem(key: "语言代码", value: langCode, icon: "character.book.closed.fill"),
                DevItem(key: "首选语言", value: preferred, icon: "textformat"),
                DevItem(key: "时区", value: tz.identifier, icon: "globe"),
                DevItem(key: "时区偏移", value: String(format: "UTC%+.1f", offsetHours), icon: "clock.badge.checkmark"),
                DevItem(key: "时间制式", value: hour12 ? "12 小时制" : "24 小时制", icon: "calendar")
            ])

        return [deviceSection, screenSection, cpuSection, storageSection, uptimeSection, localeSection]
    }

    static func ppiString() -> String {
        guard let value = ppi() else { return "未知" }
        return String(format: "≈ %.0f", value)
    }

    /// 一键复制用的纯文本汇总
    static func plainText(_ sections: [DevSection]) -> String {
        var lines = ["【百宝箱 · 设备信息】", dateTime(Date()), ""]
        for section in sections {
            lines.append("◆ \(section.title)")
            for row in section.rows { lines.append("· \(row.key)：\(row.value)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 单行（长按复制）

struct DevRow: View {
    let item: DevItem
    var onCopy: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 18)
            Text(item.key)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            Spacer(minLength: 8)
            Text(item.value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.trailing)
            if copied {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.success)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onLongPressGesture {
            UIPasteboard.general.string = item.value
            BBHaptic.success()
            onCopy(item.key)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.easeOut(duration: 0.2)) { copied = false }
            }
        }
    }
}

// MARK: - 主视图

struct DevInfoView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var sections: [DevSection] = DevCollector.sections()
    @State private var toast: String? = nil

    private var identifier: String { DevHardware.identifier }
    private var friendlyName: String { DevHardware.friendlyName(identifier) }

    private var usedRatio: Double {
        let store = DevCollector.storage()
        guard store.total > 0 else { return 0 }
        return Double(max(0, store.total - store.free)) / Double(store.total)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "iphone.gen3.radiowaves.left.and.right",
                           colors: [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)],
                           title: "设备信息",
                           subtitle: "长按任意一项即可复制该值")

                heroCard

                ForEach(sections) { section in
                    sectionCard(section)
                }

                BBPrimaryButton(title: "一键复制全部信息", icon: "doc.on.clipboard.fill",
                                colors: [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)]) {
                    copyAll()
                }

                Text("提示：长按每一行可复制该项数值；「估算 PPI」由机型屏幕对角线推算，仅供参考。")
                    .font(BBFont.cap(10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("设备信息")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { toastView }
        .onAppear { sections = DevCollector.sections() }
    }

    // MARK: 顶部概要卡

    private var heroCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.gradient([Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)]))
                            .frame(width: 46, height: 46)
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(friendlyName)
                            .font(BBFont.head(17))
                        Text("\(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · \(identifier)")
                            .font(BBFont.cap(11))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 6)
                    BBPill(text: "本机", color: Theme.accent)
                }
                Divider().overlay(Theme.hairline(scheme == .dark))
                HStack(spacing: 12) {
                    BBStat(label: "物理内存", value: String(format: "%.0f", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0),
                           unit: "GB", icon: "memorychip", colors: [Color(hex: 0xFF7A18), Color(hex: 0xFF3D71)])
                    BBStat(label: "核心数", value: "\(ProcessInfo.processInfo.activeProcessorCount)",
                           unit: "核", icon: "cpu", colors: [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)])
                }
                Divider().overlay(Theme.hairline(scheme == .dark))
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("存储使用率").font(BBFont.cap(12)).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", usedRatio * 100))
                            .font(BBFont.num(16))
                            .foregroundColor(Theme.accent)
                    }
                    BBMeter(value: usedRatio, colors: [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)], height: 9)
                }
            }
        }
    }

    // MARK: 分区卡片

    private func sectionCard(_ section: DevSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BBSectionHeader(section.title, icon: section.icon, colors: section.colors)
            BBCard {
                VStack(spacing: 0) {
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { pair in
                        DevRow(item: pair.element) { key in
                            showToast("已复制「\(key)」")
                        }
                        if pair.offset != section.rows.count - 1 {
                            Divider().overlay(Theme.hairline(scheme == .dark))
                        }
                    }
                }
            }
        }
    }

    // MARK: 轻提示

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.78)))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: 逻辑

    private func copyAll() {
        UIPasteboard.general.string = DevCollector.plainText(sections)
        BBHaptic.success()
        showToast("已复制全部设备信息")
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }
}
