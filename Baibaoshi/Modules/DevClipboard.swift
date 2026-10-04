import SwiftUI
import UIKit
import Foundation
import Combine

// MARK: - 剪贴板历史（DevClipboardView）
// iOS 不允许后台监听剪贴板：进入页面立即捕获一次，之后每 1.5 秒轮询 changeCount 记录变化。
// 支持类型标签 / 去重前置 / 置顶 / 删除 / 清空 / 搜索 / 空状态；最近 50 条 Codable+JSON 持久化（bb.clip）。

// MARK: 内容类型
enum ClipKind: String, Codable, CaseIterable {
    case text, url, number, long

    var label: String {
        switch self {
        case .text: return "文本"; case .url: return "网址"; case .number: return "数字"; case .long: return "长文本"
        }
    }
    var color: Color {
        switch self {
        case .text: return Theme.accent; case .url: return Theme.info; case .number: return Theme.warning
        case .long: return Color(hex: 0x7B5CFF)
        }
    }
    /// 启发式判断类型
    static func detect(_ raw: String) -> ClipKind {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 80 { return .long }
        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") { return .url }
        if !s.contains(" "), s.count >= 4 {
            let host = s.split(separator: "/").first.map(String.init) ?? ""
            let tlds = ["com", "cn", "net", "org", "io", "dev", "app", "xyz", "me", "co", "top", "info", "edu", "gov", "tv", "cc"]
            if host.contains("."), let tld = host.split(separator: ".").last.map(String.init), tlds.contains(tld) { return .url }
        }
        return Double(s) != nil ? .number : .text
    }
}

// MARK: 记录模型
struct ClipItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
    var date: Date = Date()
    var kind: ClipKind = .text
    var pinned: Bool = false
    init(id: UUID = UUID(), text: String, date: Date = Date(), kind: ClipKind = .text, pinned: Bool = false) {
        self.id = id; self.text = text; self.date = date; self.kind = kind; self.pinned = pinned
    }
    var preview: String { text.replacingOccurrences(of: "\n", with: " ") }
    var charCount: Int { text.count }
}

// MARK: 时间文案
enum ClipTime {
    static func text(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "刚刚" }
        if delta < 3600 { return "\(Int(delta / 60)) 分钟前" }
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        let cal = Calendar.current
        f.dateFormat = cal.isDateInToday(date) ? "今天 HH:mm"
            : (cal.isDateInYesterday(date) ? "昨天 HH:mm" : "MM-dd HH:mm")
        return f.string(from: date)
    }
}

// MARK: 数据仓库
final class ClipStore: ObservableObject {
    @Published var items: [ClipItem] = []
    let limit = 50
    let key = "bb.clip"
    private var lastChange: Int = -1
    init() { load() }

    // 持久化
    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = list
    }
    func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
    // 写入：重复内容去重并移到最前
    func capture(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 20000 else { return }
        if let idx = items.firstIndex(where: { $0.text == text }) {
            if idx == 0 { return }
            var it = items.remove(at: idx)
            it.date = Date()
            items.insert(it, at: 0)
        } else {
            items.insert(ClipItem(text: text, kind: ClipKind.detect(text)), at: 0)
        }
        trim(); save()
    }
    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var it = items.remove(at: idx)
        it.pinned.toggle()
        if it.pinned { items.insert(it, at: 0) }
        else { items.insert(it, at: items.firstIndex(where: { !$0.pinned }) ?? items.count) }
        trim(); save()
    }
    func remove(_ item: ClipItem) { items.removeAll { $0.id == item.id }; save() }
    func clearAll() { items.removeAll(); save() }

    /// 置顶优先，其余按新旧截断到 limit 条
    private func trim() {
        let pinned = items.filter { $0.pinned }
        let rest = items.filter { !$0.pinned }
        items = pinned + Array(rest.prefix(max(0, limit - pinned.count)))
    }

    // 剪贴板轮询
    func poll() {
        let cc = UIPasteboard.general.changeCount
        if lastChange < 0 { lastChange = cc; return }
        guard cc != lastChange else { return }
        lastChange = cc
        if let s = UIPasteboard.general.string { capture(s) }
    }
    /// 进入页面时立即同步一次
    func syncNow() {
        lastChange = UIPasteboard.general.changeCount
        if let s = UIPasteboard.general.string { capture(s) }
    }
    func copy(_ item: ClipItem) {
        UIPasteboard.general.string = item.text
        lastChange = UIPasteboard.general.changeCount
    }
}

// MARK: 单条记录卡片
struct ClipRowView: View {
    let item: ClipItem
    var onCopy: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        BBCard(padding: 12, radius: BBRadius.m) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    BBPill(text: item.kind.label, color: item.kind.color)
                    if item.pinned { BBPill(text: "已置顶", color: Theme.warning) }
                    Spacer(minLength: 4)
                    Text(ClipTime.text(item.date)).font(BBFont.cap(11)).foregroundColor(.secondary)
                }
                Text(item.preview)
                    .font(item.kind == .number || item.kind == .url ? BBFont.mono : BBFont.body(14))
                    .lineLimit(3).foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text("\(item.charCount) 字符").font(BBFont.cap(11)).foregroundColor(.secondary)
                    Spacer(minLength: 4)
                    iconButton(item.pinned ? "pin.slash.fill" : "pin.fill",
                               tint: item.pinned ? Theme.warning : Theme.accent, action: onPin)
                    iconButton("trash.fill", tint: Theme.danger, action: onDelete)
                    Text("点按复制").font(BBFont.cap(11)).foregroundColor(Theme.accent)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onCopy() }
    }

    private func iconButton(_ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold)).foregroundColor(tint)
                .frame(width: 30, height: 27)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: 页面
struct DevClipboardView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var store = ClipStore()
    @State private var query = ""
    @State private var filter: ClipKind? = nil
    @State private var toast: String? = nil
    @State private var timer: Timer? = nil
    @State private var showClear = false

    private let hero = [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)]
    private var filtered: [ClipItem] {
        var list = store.items
        if let f = filter { list = list.filter { $0.kind == f } }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { list = list.filter { $0.text.localizedCaseInsensitiveContains(q) } }
        return list
    }
    private var pinnedCount: Int { store.items.filter { $0.pinned }.count }
    private var isIdle: Bool { query.isEmpty && filter == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "doc.on.clipboard.fill", colors: hero,
                           title: "剪贴板历史", subtitle: "进入即捕获 · 每 1.5 秒自动记录")
                statCard
                searchCard
                filterBar

                if filtered.isEmpty {
                    BBCard {
                        BBEmptyState(icon: isIdle ? "tray" : "magnifyingglass",
                                     title: isIdle ? "暂无剪贴板记录" : "没有匹配的记录",
                                     message: isIdle ? "复制任意文字后再回到本页，即可自动记录"
                                                     : "试试换个关键词，或切换到「全部」类型",
                                     colors: hero)
                    }
                } else {
                    BBSectionHeader("历史记录", icon: "clock.arrow.circlepath", colors: hero)
                    ForEach(filtered) { item in
                        ClipRowView(item: item, onCopy: { copy(item) },
                                    onPin: { pin(item) }, onDelete: { delete(item) })
                    }
                }

                HStack(spacing: 10) {
                    BBPrimaryButton(title: "立即捕获", icon: "arrow.down.doc.fill", colors: hero) {
                        let before = store.items.count
                        store.syncNow()
                        showToast(store.items.count > before ? "已捕获新内容" : "已同步剪贴板")
                    }
                    BBGhostButton(title: "清空", icon: "trash") {
                        if store.items.isEmpty { showToast("暂无记录") } else { showClear = true }
                    }
                }

                Text("说明：iOS 不允许后台读取剪贴板，仅在本页停留时自动记录；最近 \(store.limit) 条保存在本机（键 bb.clip）。")
                    .font(BBFont.cap(10)).foregroundColor(.secondary).padding(.horizontal, 2)
            }
            .padding(.horizontal, BBSpacing.screen).padding(.top, 8).padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("剪贴板历史")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { toastView }
        .onAppear { store.syncNow(); startTimer() }
        .onDisappear { timer?.invalidate(); timer = nil }
        .alert("清空全部记录？", isPresented: $showClear) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.clearAll() }
                BBHaptic.warn(); showToast("已清空全部记录")
            }
        } message: { Text("此操作不可恢复，置顶记录也会一并删除。") }
    }

    // MARK: 顶部统计
    private var statCard: some View {
        BBCard {
            HStack(spacing: 8) {
                BBStat(label: "记录", value: "\(store.items.count)", unit: "条", icon: "clock.fill", colors: hero)
                Divider().frame(height: 36)
                BBStat(label: "置顶", value: "\(pinnedCount)", unit: "条", icon: "pin.fill", colors: [.orange, .pink])
                Divider().frame(height: 36)
                BBStat(label: "本页", value: "\(filtered.count)", unit: "条", icon: "eye.fill", colors: [.blue, .cyan])
            }
        }
    }

    // MARK: 搜索
    private var searchCard: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary)
            TextField("搜索剪贴板内容", text: $query)
                .font(BBFont.body(14)).textInputAutocapitalization(.never)
                .autocorrectionDisabled(true).submitLabel(.search)
            if !query.isEmpty {
                Button { withAnimation(.easeOut(duration: 0.2)) { query = "" } } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundColor(.secondary.opacity(0.7))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                .fill(Theme.cardBg(scheme == .dark))
                .overlay(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                    .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
        )
    }

    // MARK: 类型筛选
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                BBChip(text: "全部 \(store.items.count)", systemImage: "square.grid.2x2", selected: filter == nil) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { filter = nil }
                }
                ForEach(ClipKind.allCases, id: \.self) { kind in
                    let n = store.items.filter { $0.kind == kind }.count
                    if n > 0 {
                        BBChip(text: "\(kind.label) \(n)", selected: filter == kind) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { filter = (filter == kind ? nil : kind) }
                        }
                    }
                }
            }
            .padding(.horizontal, 2).padding(.vertical, 2)
        }
    }
    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Theme.accentGradient))
                .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 4)
                .padding(.bottom, 22).transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: 行为
    private func copy(_ item: ClipItem) {
        store.copy(item); BBHaptic.success(); showToast("已复制到剪贴板")
    }
    private func pin(_ item: ClipItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.togglePin(item) }
        BBHaptic.tap(); showToast(item.pinned ? "已取消置顶" : "已置顶")
    }
    private func delete(_ item: ClipItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.remove(item) }
        BBHaptic.warn(); showToast("已删除")
    }
    private func startTimer() {
        timer?.invalidate()
        let s = store
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in s.poll() }
    }
    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if toast == text { withAnimation(.easeOut(duration: 0.25)) { toast = nil } }
        }
    }
}
