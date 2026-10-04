import SwiftUI

// MARK: - 待办清单（EffTodoView）
// 纯本地：Codable + JSON 存 UserDefaults（键 bb.todos），不联网。
// 自定义类型统一 Todo 前缀，避免与主工程符号冲突。

// MARK: 优先级（高/中/低，彩色圆点）

enum TodoPriority: String, Codable, CaseIterable, Identifiable {
    case high, medium, low

    var id: String { rawValue }
    private var idx: Int { TodoPriority.allCases.firstIndex(of: self) ?? 1 }

    var title: String { ["高", "中", "低"][idx] }
    var icon: String { ["flame.fill", "bolt.fill", "leaf.fill"][idx] }
    var color: Color { [Theme.danger, Theme.warning, Theme.success][idx] }
}

// MARK: 分类

enum TodoCategory: String, Codable, CaseIterable, Identifiable {
    case work, life, other

    var id: String { rawValue }
    private var idx: Int { TodoCategory.allCases.firstIndex(of: self) ?? 2 }

    var title: String { ["工作", "生活", "其他"][idx] }
    var icon: String { ["briefcase.fill", "house.fill", "square.grid.2x2.fill"][idx] }
    var color: Color { [Theme.info, Color(hex: 0x18B26B), Color(hex: 0x9E6BFF)][idx] }
}

// MARK: 筛选项（全部/工作/生活/其他）

enum TodoFilter: String, CaseIterable, Identifiable {
    case all, work, life, other

    var id: String { rawValue }
    private var idx: Int { TodoFilter.allCases.firstIndex(of: self) ?? 0 }

    var title: String { ["全部", "工作", "生活", "其他"][idx] }
    var icon: String { ["tray.full.fill", "briefcase.fill", "house.fill", "square.grid.2x2.fill"][idx] }
    var category: TodoCategory? { idx == 0 ? nil : TodoCategory.allCases[idx - 1] }
}

// MARK: 模型与存储

struct TodoEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var priority: TodoPriority = .medium
    var category: TodoCategory = .work
    var done: Bool = false
    var createdAt: Date = Date()
}

enum TodoStore {
    static let key = "bb.todos"

    static func load() -> [TodoEntry] {
        guard let data = UserDefaults.standard.data(forKey: key), !data.isEmpty else { return [] }
        guard let list = try? JSONDecoder().decode([TodoEntry].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [TodoEntry]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum TodoFormat {
    static func short(_ date: Date) -> String {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(date) {
            fmt.dateFormat = "今天 HH:mm"
        } else if cal.isDateInYesterday(date) {
            fmt.dateFormat = "昨天 HH:mm"
        } else {
            fmt.dateFormat = "MM-dd"
        }
        return fmt.string(from: date)
    }
}

/// 统一卡片外壳（列表行内复用）
struct TodoCardModifier: ViewModifier {
    let scheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .padding(BBSpacing.m)
            .background(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous).fill(Theme.cardBg(scheme == .dark)))
            .overlay(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous).strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
            .bbShadow(scheme == .dark)
    }
}

// MARK: - 主视图

struct EffTodoView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var items: [TodoEntry] = TodoStore.load()
    @State private var draftTitle: String = ""
    @State private var draftPriority: TodoPriority = .medium
    @State private var draftCategory: TodoCategory = .work
    @State private var filter: TodoFilter = .all
    @FocusState private var inputFocused: Bool

    // 派生数据
    private var filtered: [TodoEntry] {
        guard let c = filter.category else { return items }
        return items.filter { $0.category == c }
    }
    private var pending: [TodoEntry] { filtered.filter { !$0.done } }
    private var finished: [TodoEntry] { filtered.filter { $0.done } }
    private var doneRatio: Double {
        guard !items.isEmpty else { return 0 }
        return Double(items.filter { $0.done }.count) / Double(items.count)
    }
    private var percentText: String { "\(Int((doneRatio * 100).rounded()))%" }
    private var subtitleText: String {
        "共 \(items.count) 项 · 已完成 \(items.filter { $0.done }.count) · 待办 \(items.filter { !$0.done }.count)"
    }
    private var rowInset: EdgeInsets {
        EdgeInsets(top: 5, leading: BBSpacing.screen, bottom: 5, trailing: BBSpacing.screen)
    }

    var body: some View {
        List {
            headerRow
            composerRow
            filterRow
            if !pending.isEmpty { groupSection("未完成", icon: "circle.dashed", list: pending) }
            if !finished.isEmpty { groupSection("已完成", icon: "checkmark.circle.fill", list: finished) }
            if filtered.isEmpty { emptyRow }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("待办清单")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: items) { newValue in TodoStore.save(newValue) }
    }

    // MARK: 顶部完成进度
    private var headerRow: some View {
        VStack(alignment: .leading, spacing: BBSpacing.m) {
            HStack(spacing: BBSpacing.m) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6).frame(width: 48, height: 48)
                    Circle()
                        .trim(from: 0, to: max(0.001, min(1, doneRatio)))
                        .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 48, height: 48)
                    Text(percentText).font(BBFont.num(12))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("完成进度").font(BBFont.head(16))
                    Text(subtitleText).font(BBFont.cap(12)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            BBMeter(value: doneRatio, colors: Theme.accentColors(), height: 10)
        }
        .modifier(TodoCardModifier(scheme: scheme))
        .listRowInsets(rowInset)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: 添加区（标题 + 优先级 + 分类）
    private var composerRow: some View {
        VStack(alignment: .leading, spacing: BBSpacing.m) {
            HStack(spacing: BBSpacing.s) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent)
                TextField("添加一个待办…", text: $draftTitle)
                    .font(BBFont.body(15)).focused($inputFocused)
                    .submitLabel(.done).onSubmit { addItem() }
            }
            .padding(.horizontal, BBSpacing.m).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))

            HStack(spacing: 8) {
                ForEach(TodoPriority.allCases) { p in
                    Button {
                        draftPriority = p
                        BBHaptic.select()
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(p.color).frame(width: 8, height: 8)
                            Text(p.title).font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(draftPriority == p
                            ? AnyShapeStyle(p.color.opacity(0.18))
                            : AnyShapeStyle(Theme.panel(scheme == .dark))))
                        .overlay(Capsule().strokeBorder(p.color.opacity(draftPriority == p ? 0.55 : 0.20), lineWidth: 1))
                        .foregroundColor(draftPriority == p ? p.color : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                ForEach(TodoCategory.allCases) { c in
                    BBChip(text: c.title, systemImage: c.icon, selected: draftCategory == c) { draftCategory = c }
                }
                Spacer(minLength: 0)
            }

            BBPrimaryButton(title: "添加待办", icon: "plus",
                            colors: [draftPriority.color, draftPriority.color.opacity(0.7)]) { addItem() }
        }
        .modifier(TodoCardModifier(scheme: scheme))
        .listRowInsets(rowInset)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: 分类筛选
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TodoFilter.allCases) { f in
                    BBChip(text: f.title, systemImage: f.icon, selected: filter == f) { filter = f }
                }
            }
            .padding(.horizontal, 2).padding(.vertical, 1)
        }
        .listRowInsets(rowInset)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: 分组与行
    private func groupSection(_ title: String, icon: String, list: [TodoEntry]) -> some View {
        Section {
            ForEach(list) { item in
                row(item)
                    .listRowInsets(rowInset)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { delete(item) } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button { toggle(item) } label: {
                            Label(item.done ? "取消完成" : "完成",
                                  systemImage: item.done ? "arrow.uturn.backward" : "checkmark")
                        }
                        .tint(Theme.success)
                    }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(BBFont.head(13))
                Text("\(list.count)").font(BBFont.cap(12)).foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .textCase(nil)
        }
    }

    private func row(_ item: TodoEntry) -> some View {
        HStack(spacing: BBSpacing.m) {
            Button { toggle(item) } label: {
                ZStack {
                    Circle()
                        .fill(item.done
                            ? AnyShapeStyle(Theme.gradient([item.priority.color, item.priority.color.opacity(0.6)]))
                            : AnyShapeStyle(Color.clear))
                        .frame(width: 24, height: 24)
                    Circle()
                        .strokeBorder(item.done ? Color.clear : item.priority.color.opacity(0.6), lineWidth: 1.8)
                        .frame(width: 24, height: 24)
                    if item.done {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(BBFont.body(15))
                    .strikethrough(item.done, color: Color.secondary)
                    .foregroundColor(item.done ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Circle().fill(item.priority.color).frame(width: 7, height: 7)
                    Text("\(item.priority.title)优先").font(BBFont.cap(11)).foregroundColor(item.priority.color)
                    Text("·").font(BBFont.cap(11)).foregroundColor(.secondary)
                    Image(systemName: item.category.icon)
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(item.category.color)
                    Text(item.category.title).font(BBFont.cap(11)).foregroundColor(item.category.color)
                    Spacer(minLength: 4)
                    Text(TodoFormat.short(item.createdAt)).font(BBFont.cap(11)).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .modifier(TodoCardModifier(scheme: scheme))
        .opacity(item.done ? 0.72 : 1)
    }

    private var emptyRow: some View {
        BBEmptyState(
            icon: "checklist",
            title: filter == .all ? "还没有待办" : "该分类暂无待办",
            message: filter == .all ? "在上方输入标题，选好优先级与分类即可添加" : "换个分类看看，或添加一条新的待办",
            colors: filter.category.map { [$0.color, $0.color.opacity(0.6)] } ?? Theme.accentColors()
        )
        .listRowInsets(rowInset)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: 操作
    private func addItem() {
        let text = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            BBHaptic.warn()
            return
        }
        let entry = TodoEntry(title: text, priority: draftPriority, category: draftCategory)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { items.insert(entry, at: 0) }
        draftTitle = ""
        BBHaptic.success()
    }

    private func toggle(_ item: TodoEntry) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { items[idx].done.toggle() }
        if items[idx].done { BBHaptic.success() } else { BBHaptic.tap() }
    }

    private func delete(_ item: TodoEntry) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { items.removeAll { $0.id == item.id } }
        BBHaptic.warn()
    }
}
