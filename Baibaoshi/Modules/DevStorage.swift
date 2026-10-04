import SwiftUI
import Foundation
import UIKit
// MARK: - 存储分析（DevStorageView）
// 纯本地：沙箱各目录占用 / 文件数 / 设备容量环 / 一键清理缓存。
// 自定义类型统一 Stor 前缀，避免与主工程命名冲突。
// MARK: - 沙箱目录
enum StorLoc: String, CaseIterable, Identifiable {
    case documents, library, caches, tmp

    var id: String { rawValue }
    var title: String {
        switch self {
        case .documents: return "Documents"
        case .library:   return "Library（不含缓存）"
        case .caches:    return "Library/Caches"
        case .tmp:       return "tmp 临时目录"
        }
    }
    var note: String {
        switch self {
        case .documents: return "用户数据与导出文件"
        case .library:   return "偏好设置、数据库等"
        case .caches:    return "可安全清理的缓存"
        case .tmp:       return "系统临时文件"
        }
    }
    var icon: String {
        switch self {
        case .documents: return "folder.fill"
        case .library:   return "books.vertical.fill"
        case .caches:    return "shippingbox.fill"
        case .tmp:       return "clock.badge.exclamationmark.fill"
        }
    }
    var colors: [Color] {
        switch self {
        case .documents: return [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)]
        case .library:   return [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)]
        case .caches:    return [Color(hex: 0xF59E0B), Color(hex: 0xFF7A18)]
        case .tmp:       return [Color(hex: 0x5B6478), Color(hex: 0x9AA3B5)]
        }
    }
    var url: URL? {
        let fm = FileManager.default
        switch self {
        case .documents: return fm.urls(for: .documentDirectory, in: .userDomainMask).first
        case .library:   return fm.urls(for: .libraryDirectory, in: .userDomainMask).first
        case .caches:    return fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        case .tmp:       return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
    }
}
// MARK: - 占用模型
struct StorUsage: Identifiable {
    let id = UUID()
    let loc: StorLoc
    let bytes: Int64
    let files: Int
}
// MARK: - 统计器
enum StorAnalyzer {
    static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useAll]
        f.isAdaptive = true
        return f
    }()
    static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        return formatter.string(fromByteCount: bytes)
    }
    /// 统计单个位置（Library 排除 Caches，避免重复计入）
    static func measure(_ loc: StorLoc) -> StorUsage {
        guard let url = loc.url else { return StorUsage(loc: loc, bytes: 0, files: 0) }
        let exclude = loc == .library ? StorLoc.caches.url?.path : nil
        return measure(url, exclude: exclude, loc: loc)
    }
    static func measure(_ url: URL, exclude: String?, loc: StorLoc) -> StorUsage {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                     options: [], errorHandler: { _, _ in true }) else {
            return StorUsage(loc: loc, bytes: 0, files: 0)
        }
        var total: Int64 = 0
        var count = 0
        for case let f as URL in en {
            if let ex = exclude, f.path == ex || f.path.hasPrefix(ex + "/") {
                en.skipDescendants()
                continue
            }
            guard let v = try? f.resourceValues(forKeys: Set(keys)) else { continue }
            guard v.isRegularFile == true else { continue }
            total += max(0, Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0))
            count += 1
        }
        return StorUsage(loc: loc, bytes: total, files: count)
    }
    /// 设备容量（总量 / 可用，字节），失败返回 nil
    static func deviceSpace() -> (total: Int64, free: Int64)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        guard let t = v.volumeTotalCapacity, t > 0 else { return nil }
        let total = Int64(t)
        let free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
        return (total, max(0, min(total, free)))
    }
    /// 只清理 App 自己的 Caches 目录内容，返回（释放字节，删除条目数）
    static func clearCaches() -> (freed: Int64, removed: Int) {
        let fm = FileManager.default
        guard let dir = StorLoc.caches.url else { return (0, 0) }
        let before = measure(dir, exclude: nil, loc: .caches).bytes
        guard let items = try? fm.contentsOfDirectory(at: dir,
                                                      includingPropertiesForKeys: nil,
                                                      options: []) else { return (0, 0) }
        var removed = 0
        for item in items {
            do { try fm.removeItem(at: item); removed += 1 } catch { }
        }
        let after = measure(dir, exclude: nil, loc: .caches).bytes
        return (max(0, before - after), removed)
    }
}

// MARK: - 视图
struct DevStorageView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var usages: [StorUsage] = []
    @State private var totalBytes: Int64 = 0
    @State private var freeBytes: Int64 = 0
    @State private var scanning = true
    @State private var toast: String?
    @State private var showConfirm = false

    private var usedBytes: Int64 { max(0, totalBytes - freeBytes) }
    private var sandboxBytes: Int64 { usages.reduce(0) { $0 + $1.bytes } }
    private var sandboxFiles: Int { usages.reduce(0) { $0 + $1.files } }
    private var maxBytes: Int64 { max(1, usages.map { $0.bytes }.max() ?? 1) }

    // MARK: Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BBSpacing.l) {
                PageHeader(icon: "internaldrive.fill",
                           colors: [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)],
                           title: "存储分析",
                           subtitle: "沙箱占用 · 设备容量 · 一键清理")
                if let toast { toastBar(toast) }
                capacityCard
                sandboxCard
                actionRow
                hintCard
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, BBSpacing.s)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("存储分析")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { scan() }
        .onAppear { if usages.isEmpty { scan() } }
        .alert("清理缓存", isPresented: $showConfirm) {
            Button("取消", role: .cancel) { }
            Button("立即清理", role: .destructive) { clean() }
        } message: {
            Text("将删除 App 自身 Caches 目录内的全部内容，不会影响您的数据文件。")
        }
    }

    // MARK: 提示条
    private func toastBar(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.success)
            Text(text).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BBSpacing.m).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
            .fill(Theme.success.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                .strokeBorder(Theme.success.opacity(0.30), lineWidth: 1)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: 设备容量
    private var capacityCard: some View {
        BBCard(padding: BBSpacing.l) {
            VStack(spacing: BBSpacing.l) {
                HStack {
                    Text("设备容量").font(BBFont.head(16))
                    Spacer()
                    BBPill(text: "本机磁盘", color: Theme.accent)
                }
                HStack(alignment: .center, spacing: 18) {
                    BBRing(progress: totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0,
                           lineWidth: 11,
                           colors: [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)],
                           label: totalBytes > 0
                                ? String(format: "%.0f%%", Double(usedBytes) / Double(totalBytes) * 100)
                                : "--",
                           caption: "已用")
                        .scaleEffect(1.35)
                        .frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: 11) {
                        capRow(title: "总容量", value: StorAnalyzer.format(totalBytes),
                               colors: [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)])
                        capRow(title: "已使用", value: StorAnalyzer.format(usedBytes),
                               colors: [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)])
                        capRow(title: "剩余可用", value: StorAnalyzer.format(freeBytes),
                               colors: [Color(hex: 0x22C55E), Color(hex: 0x34E0A1)])
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    private func capRow(title: String, value: String, colors: [Color]) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.gradient(colors)).frame(width: 8, height: 8)
            Text(title).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: 沙箱占用
    private var sandboxCard: some View {
        VStack(alignment: .leading, spacing: BBSpacing.m) {
            BBSectionHeader(title: "沙箱占用", icon: "folder.badge.gearshape",
                            colors: [Color(hex: 0xF59E0B), Color(hex: 0xFF7A18)]) {
                Text("共 \(StorAnalyzer.format(sandboxBytes))")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            BBCard(padding: BBSpacing.l, radius: BBRadius.m) {
                if scanning {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("正在统计目录…").font(.system(size: 12)).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if usages.isEmpty {
                    BBEmptyState(icon: "tray", title: "暂无数据", message: "未能读取沙箱目录")
                } else {
                    VStack(spacing: 16) {
                        ForEach(usages) { u in usageRow(u) }
                        Divider().opacity(0.3)
                        HStack {
                            Text("合计").font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(StorAnalyzer.format(sandboxBytes)) · \(sandboxFiles) 个文件")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
        }
    }
    private func usageRow(_ u: StorUsage) -> some View {
        let ratio = maxBytes > 0 ? Double(u.bytes) / Double(maxBytes) : 0
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.gradient(u.loc.colors)).frame(width: 28, height: 28)
                    Image(systemName: u.loc.icon)
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(u.loc.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(u.loc.note).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(StorAnalyzer.format(u.bytes))
                        .font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                    Text("\(u.files) 个文件").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            BBMeter(value: ratio, colors: u.loc.colors, height: 8)
        }
    }

    // MARK: 操作与说明
    private var actionRow: some View {
        HStack(spacing: BBSpacing.m) {
            BBGhostButton(title: "重新扫描", icon: "arrow.clockwise") { scan() }
            BBPrimaryButton(title: "清理缓存", icon: "trash.fill",
                            colors: [Color(hex: 0xF59E0B), Color(hex: 0xFF7A18)]) {
                showConfirm = true
            }
        }
    }
    private var hintCard: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gradient([Theme.info, Theme.accent2]))
            Text("仅统计并清理本 App 沙箱内的数据，无法访问其他 App 的存储；缓存清理后下次启动可能会重新生成少量文件。")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(BBSpacing.m)
        .background(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
            .fill(Theme.panel(scheme == .dark)))
    }

    // MARK: 逻辑
    private func scan() {
        scanning = true
        DispatchQueue.main.async {
            var result: [StorUsage] = []
            for loc in StorLoc.allCases { result.append(StorAnalyzer.measure(loc)) }
            result.sort { $0.bytes > $1.bytes }
            let space = StorAnalyzer.deviceSpace()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                usages = result
                totalBytes = space?.total ?? 0
                freeBytes = space?.free ?? 0
                scanning = false
            }
        }
    }
    private func clean() {
        let before = StorAnalyzer.measure(.caches).bytes
        let res = StorAnalyzer.clearCaches()
        scan()
        if res.removed == 0 && before == 0 {
            showToast("缓存目录本就是空的，无需清理")
        } else {
            showToast("已清理 \(res.removed) 项，释放 \(StorAnalyzer.format(res.freed))")
        }
        BBHaptic.success()
    }
    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = text }
        let shown = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if toast == shown { withAnimation(.easeOut(duration: 0.25)) { toast = nil } }
        }
    }
}
