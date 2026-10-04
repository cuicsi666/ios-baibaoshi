import SwiftUI

// MARK: - 便签（EffNotesView）
// 纯本地：Codable + JSON 存 UserDefaults（键 bb.notes），不联网。
// 自定义类型统一 Note 前缀，避免与主工程符号冲突。

// MARK: 便签模型

struct NoteEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var body: String = ""
    var pinned: Bool = false
    var updatedAt: Date = Date()

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "无标题便签" : t
    }

    /// 摘要（前两行由 UI 的 lineLimit 控制）
    var summary: String {
        let raw = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "暂无内容" : raw
    }

    var charCount: Int { title.count + body.count }
}

// MARK: 存储

enum NoteStore {
    static let key = "bb.notes"

    static func load() -> [NoteEntry] {
        guard let data = UserDefaults.standard.data(forKey: key), !data.isEmpty,
              let list = try? JSONDecoder().decode([NoteEntry].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [NoteEntry]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: 时间格式化

enum NoteFormat {
    static func time(_ date: Date) -> String {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(date) {
            fmt.dateFormat = "今天 HH:mm"
        } else if cal.isDateInYesterday(date) {
            fmt.dateFormat = "昨天 HH:mm"
        } else if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
            fmt.dateFormat = "M月d日 HH:mm"
        } else {
            fmt.dateFormat = "yyyy年M月d日"
        }
        return fmt.string(from: date)
    }
}

/// 便签卡片外壳
struct NoteCardModifier: ViewModifier {
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

// MARK: - 列表主视图

struct EffNotesView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var notes: [NoteEntry] = NoteStore.load()
    @State private var query: String = ""
    @State private var editing: NoteEntry? = nil
    @FocusState private var searchFocused: Bool

    /// 置顶优先 → 更新时间倒序
    private var visibleNotes: [NoteEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = q.isEmpty ? notes : notes.filter {
            $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q)
        }
        return base.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updatedAt > b.updatedAt
        }
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "note.text", colors: Theme.accentColors(),
                           title: "便签", subtitle: "随手记录 · 自动保存 · 本地存储")

                searchBar
                BBPrimaryButton(title: "新建便签", icon: "square.and.pencil",
                                colors: Theme.accentColors()) { createNote() }
                summaryRow

                if visibleNotes.isEmpty {
                    BBEmptyState(icon: isSearching ? "magnifyingglass" : "note.text",
                                 title: isSearching ? "没有匹配的便签" : "还没有便签",
                                 message: isSearching ? "换个关键词试试，标题与正文都可搜索"
                                                      : "点击「新建便签」，记下此刻的灵感",
                                 colors: Theme.accentColors())
                } else {
                    ForEach(visibleNotes) { note in row(note) }
                }
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("便签")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: notes) { newValue in NoteStore.save(newValue) }
        .sheet(item: $editing) { note in
            NoteEditorView(noteId: note.id, notes: $notes)
        }
    }

    // MARK: 搜索框

    private var searchBar: some View {
        HStack(spacing: BBSpacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary)
            TextField("搜索标题或正文", text: $query)
                .font(BBFont.body(15)).focused($searchFocused).submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""; searchFocused = false; BBHaptic.tap()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, BBSpacing.m).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
            .fill(Theme.panel(scheme == .dark)))
        .overlay(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
            .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
    }

    private var summaryRow: some View {
        HStack(spacing: BBSpacing.s) {
            BBPill(text: "共 \(notes.count) 条", color: Theme.accent)
            if notes.contains(where: { $0.pinned }) {
                BBPill(text: "置顶 \(notes.filter { $0.pinned }.count)", color: Theme.warning)
            }
            Spacer(minLength: 0)
            if isSearching {
                Text("匹配 \(visibleNotes.count) 条").font(BBFont.cap(12)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: 列表行

    private func row(_ note: NoteEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.warning)
                }
                Text(note.displayTitle)
                    .font(BBFont.head(16))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
                Menu {
                    Button { togglePin(note) } label: {
                        Label(note.pinned ? "取消置顶" : "置顶",
                              systemImage: note.pinned ? "pin.slash" : "pin")
                    }
                    Button(role: .destructive) { delete(note) } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

            Text(note.summary)
                .font(BBFont.body(13))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
                Text(NoteFormat.time(note.updatedAt)).font(BBFont.cap(11))
                Text("·").font(BBFont.cap(11))
                Text("\(note.charCount) 字").font(BBFont.cap(11))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.secondary)
        }
        .modifier(NoteCardModifier(scheme: scheme))
        .contentShape(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous))
        .onTapGesture {
            editing = note
            BBHaptic.tap()
        }
    }

    // MARK: 操作

    private func createNote() {
        let note = NoteEntry(title: "")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            notes.insert(note, at: 0)
        }
        BBHaptic.success()
        editing = note
    }

    private func togglePin(_ note: NoteEntry) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            notes[i].pinned.toggle()
        }
        BBHaptic.tap()
    }

    private func delete(_ note: NoteEntry) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            notes.removeAll { $0.id == note.id }
        }
        BBHaptic.warn()
    }
}

// MARK: - 编辑页

struct NoteEditorView: View {
    let noteId: UUID
    @Binding var notes: [NoteEntry]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var loaded: Bool = false
    private var index: Int? { notes.firstIndex { $0.id == noteId } }
    private var current: NoteEntry? { index.map { notes[$0] } }
    private var count: Int { title.count + bodyText.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BBSpacing.l) {
                    titleField
                    editorCard
                    footer
                }
                .padding(.horizontal, BBSpacing.screen)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(BBAuroraBackground(scheme: scheme))
            .navigationTitle("编辑便签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                        .font(BBFont.head(15))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button { togglePin() } label: {
                            Image(systemName: (current?.pinned ?? false) ? "pin.fill" : "pin")
                        }.tint(Theme.warning)
                        Button { deleteNote() } label: {
                            Image(systemName: "trash")
                        }.tint(Theme.danger)
                    }
                }
            }
        }
        .onAppear { loadIfNeeded() }
        .onChange(of: title) { _ in autosave() }
        .onChange(of: bodyText) { _ in autosave() }
    }

    // MARK: 子视图

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("标题").font(BBFont.cap(12)).foregroundColor(.secondary)
            TextField("给便签起个标题", text: $title).font(BBFont.title(22)).submitLabel(.next)
        }
        .modifier(NoteCardModifier(scheme: scheme))
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("正文").font(BBFont.cap(12)).foregroundColor(.secondary)
            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text("开始输入正文…").font(BBFont.body(15))
                        .foregroundColor(.secondary).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $bodyText)
                    .font(BBFont.body(15))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 340)
            }
        }
        .modifier(NoteCardModifier(scheme: scheme))
    }

    private var footer: some View {
        HStack(spacing: BBSpacing.s) {
            Label("\(count) 字", systemImage: "textformat.size")
            Spacer(minLength: 0)
            Label(NoteFormat.time(current?.updatedAt ?? Date()), systemImage: "clock")
            Circle().fill(Theme.success).frame(width: 6, height: 6)
            Text("自动保存")
        }
        .font(BBFont.cap(11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
    }

    // MARK: 逻辑

    private func loadIfNeeded() {
        guard !loaded, let i = index else { loaded = true; return }
        title = notes[i].title
        bodyText = notes[i].body
        loaded = true
    }

    private func autosave() {
        guard let i = index else { return }
        if notes[i].title == title && notes[i].body == bodyText { return }
        notes[i].title = title; notes[i].body = bodyText; notes[i].updatedAt = Date()
    }

    private func togglePin() {
        guard let i = index else { return }
        notes[i].pinned.toggle()
        BBHaptic.tap()
    }

    private func deleteNote() {
        notes.removeAll { $0.id == noteId }
        BBHaptic.warn()
        dismiss()
    }
}
