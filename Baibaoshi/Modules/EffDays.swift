import SwiftUI

// MARK: - 倒数日 / 纪念日（EffDaysView）
// 纯本地：Codable + JSON 存 UserDefaults（键 bb.days），不联网。
// 自定义类型统一 Days 前缀，避免与主工程符号冲突。

// MARK: 事件模型

struct DaysEvent: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var target: Date
    var emoji: String = "🎉"
    var colorHex: UInt32 = 0x2E5BFF
    var pinned: Bool = false
    var createdAt: Date = Date()
    var color: Color { Color(hex: colorHex) }
}

// MARK: 存储

enum DaysStore {
    static let key = "bb.days"
    static func load() -> [DaysEvent] {
        guard let data = UserDefaults.standard.data(forKey: key), !data.isEmpty,
              let list = try? JSONDecoder().decode([DaysEvent].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [DaysEvent]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: 计算与格式化

enum DaysCalc {
    /// 目标日与今天的天数差（正 = 未来，负 = 过去，0 = 今天）
    static func diff(_ target: Date, now: Date = Date()) -> Int {
        let cal = Calendar.current
        let from = cal.startOfDay(for: now)
        let to = cal.startOfDay(for: target)
        return cal.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// 「2026年10月5日 · 星期一」
    static func dateLine(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日 · EEEE"
        return fmt.string(from: date)
    }

    /// 「距今 N 天」/「已过 N 天」/ 今天
    static func statusText(_ d: Int) -> String {
        if d == 0 { return "就是今天 🎉" }
        return d > 0 ? "距今 \(d) 天" : "已过 \(abs(d)) 天"
    }

    static func unitText(_ d: Int) -> String {
        d == 0 ? "今天" : (d > 0 ? "天后" : "天前")
    }
}

// MARK: 调色板 / 表情

enum DaysPalette {
    static let hexes: [UInt32] = [0x2E5BFF, 0xFF4D6D, 0xF59E0B, 0x22C55E,
                                  0x06B6D4, 0x9E6BFF, 0xFF5EA8, 0x5B6478]
    static let emojis: [String] = ["🎉", "🎂", "💍", "✈️", "🎓", "❤️",
                                   "🏝️", "⏰", "🏆", "🎁", "🌟", "📅"]
}

/// 列表卡片外壳（圆角 + 描边 + 阴影，随深浅色自适应）
struct DaysCardModifier: ViewModifier {
    let scheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .padding(BBSpacing.m)
            .background(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                .fill(Theme.cardBg(scheme == .dark)))
            .overlay(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
            .bbShadow(scheme == .dark)
    }
}

// MARK: - 主视图

struct EffDaysView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var events: [DaysEvent] = DaysStore.load()
    @State private var draftTitle: String = ""
    @State private var draftDate: Date = Date()
    @State private var draftEmoji: String = DaysPalette.emojis.first ?? "🎉"
    @State private var draftHex: UInt32 = DaysPalette.hexes.first ?? 0x2E5BFF
    @State private var showComposer: Bool = false
    @FocusState private var inputFocused: Bool
    private var draftColor: Color { Color(hex: draftHex) }

    /// 排序：置顶优先 → 剩余天数升序（已过最久在前，今天随后，未来越近越前）
    private var sortedEvents: [DaysEvent] {
        events.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            let da = DaysCalc.diff(a.target), db = DaysCalc.diff(b.target)
            if da != db { return da < db }
            return a.createdAt < b.createdAt
        }
    }

    private var upcoming: DaysEvent? {
        events.filter { DaysCalc.diff($0.target) >= 0 }
            .min { DaysCalc.diff($0.target) < DaysCalc.diff($1.target) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "calendar.badge.clock", colors: Theme.accentColors(),
                           title: "倒数日", subtitle: "纪念日 · 倒计时 · 一目了然")
                summaryCard
                composerCard

                if events.isEmpty {
                    BBEmptyState(icon: "calendar", title: "还没有倒数日",
                                 message: "点开「新建倒数日」，记录值得期待的日子",
                                 colors: Theme.accentColors())
                } else {
                    BBSectionHeader(title: "我的日子", icon: "sparkles",
                                    colors: Theme.accentColors()) {
                        Text("共 \(events.count) 个").font(BBFont.cap(12)).foregroundColor(.secondary)
                    }
                    ForEach(sortedEvents) { ev in card(ev) }
                }
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("倒数日")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: events) { newValue in DaysStore.save(newValue) }
    }

    private var summaryCard: some View {
        BBCard {
            HStack(spacing: BBSpacing.m) {
                BBStat(label: "全部日子", value: "\(events.count)", unit: "个",
                       icon: "calendar", colors: Theme.accentColors())
                Divider().frame(height: 42)
                if let up = upcoming {
                    let d = DaysCalc.diff(up.target)
                    BBStat(label: "最近一个", value: d == 0 ? "今天" : "\(d)",
                           unit: d == 0 ? "" : "天", icon: "flag.fill",
                           colors: [up.color, up.color.opacity(0.6)])
                } else {
                    BBStat(label: "最近一个", value: "—", unit: "",
                           icon: "flag.fill", colors: [Color.gray, Color.gray])
                }
            }
        }
    }

    // MARK: 新建区
    private var composerCard: some View {
        VStack(alignment: .leading, spacing: BBSpacing.m) {
            Button {
                BBHaptic.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showComposer.toggle() }
                if showComposer { inputFocused = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showComposer ? "chevron.up.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(showComposer ? "收起" : "新建倒数日").font(BBFont.head(15))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)

            if showComposer {
                nameField
                dateField
                emojiPicker
                colorPicker
                BBPrimaryButton(title: "添加倒数日", icon: "plus",
                                colors: [draftColor, draftColor.opacity(0.7)]) { add() }
            }
        }
        .modifier(DaysCardModifier(scheme: scheme))
    }

    private var nameField: some View {
        HStack(spacing: BBSpacing.s) {
            Image(systemName: "pencil")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.accent)
            TextField("事件名称，如：结婚纪念日", text: $draftTitle)
                .font(BBFont.body(15)).focused($inputFocused)
                .submitLabel(.done).onSubmit { add() }
        }
        .padding(.horizontal, BBSpacing.m).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
            .fill(Theme.panel(scheme == .dark)))
    }

    private var dateField: some View {
        DatePicker("目标日期", selection: $draftDate, displayedComponents: [.date])
            .datePickerStyle(.compact).font(BBFont.body(15))
            .padding(.horizontal, BBSpacing.m).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                .fill(Theme.panel(scheme == .dark)))
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("图标").font(BBFont.cap(12)).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DaysPalette.emojis, id: \.self) { e in
                        Button { draftEmoji = e; BBHaptic.select() } label: {
                            Text(e).font(.system(size: 20)).frame(width: 38, height: 38)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(draftEmoji == e ? AnyShapeStyle(draftColor.opacity(0.22))
                                                          : AnyShapeStyle(Theme.panel(scheme == .dark))))
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(draftEmoji == e ? draftColor.opacity(0.7) : Color.clear,
                                                  lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("颜色").font(BBFont.cap(12)).foregroundColor(.secondary)
            HStack(spacing: 10) {
                ForEach(DaysPalette.hexes, id: \.self) { hex in
                    Button { draftHex = hex; BBHaptic.select() } label: {
                        ZStack {
                            Circle().fill(Theme.gradient([Color(hex: hex), Color(hex: hex).opacity(0.55)]))
                                .frame(width: 30, height: 30)
                            if draftHex == hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .heavy)).foregroundColor(.white)
                            }
                        }
                        .overlay(Circle().strokeBorder(Color.white.opacity(draftHex == hex ? 0.9 : 0), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 事件卡片
    private func card(_ ev: DaysEvent) -> some View {
        let d = DaysCalc.diff(ev.target)
        return HStack(spacing: BBSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.gradient([ev.color, ev.color.opacity(0.6)]))
                    .frame(width: 54, height: 54)
                    .shadow(color: ev.color.opacity(0.45), radius: 8, y: 4)
                Text(ev.emoji).font(.system(size: 26))
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(ev.title).font(BBFont.head(16)).lineLimit(1)
                    if ev.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(Theme.warning)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button { togglePin(ev) } label: {
                            Label(ev.pinned ? "取消置顶" : "置顶",
                                  systemImage: ev.pinned ? "pin.slash" : "pin")
                        }
                        Button(role: .destructive) { delete(ev) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.secondary)
                    }
                }
                Text(DaysCalc.dateLine(ev.target))
                    .font(BBFont.cap(11)).foregroundColor(.secondary).lineLimit(1)
                BBPill(text: DaysCalc.statusText(d), color: ev.color)
            }

            VStack(spacing: 2) {
                if d == 0 {
                    Text("🎉").font(.system(size: 26))
                } else {
                    Text("\(abs(d))").font(BBFont.num(28))
                        .foregroundColor(ev.color).monospacedDigit()
                }
                Text(DaysCalc.unitText(d)).font(BBFont.cap(10)).foregroundColor(.secondary)
            }
            .frame(minWidth: 46)
        }
        .modifier(DaysCardModifier(scheme: scheme))
        .contextMenu {
            Button { togglePin(ev) } label: {
                Label(ev.pinned ? "取消置顶" : "置顶",
                      systemImage: ev.pinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) { delete(ev) } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: 操作
    private func add() {
        let text = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { BBHaptic.warn(); return }
        let ev = DaysEvent(title: text, target: draftDate, emoji: draftEmoji, colorHex: draftHex)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { events.append(ev) }
        draftTitle = ""
        draftDate = Date()
        showComposer = false
        inputFocused = false
        BBHaptic.success()
    }

    private func togglePin(_ ev: DaysEvent) {
        guard let i = events.firstIndex(where: { $0.id == ev.id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { events[i].pinned.toggle() }
        BBHaptic.tap()
    }

    private func delete(_ ev: DaysEvent) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { events.removeAll { $0.id == ev.id } }
        BBHaptic.warn()
    }
}
