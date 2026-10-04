import SwiftUI
import Foundation

// MARK: - 文本工具箱
// 统计 / 大小写转换 / 行操作 / 文本处理，纯本地，iOS 16 兼容。

// MARK: 调色板（文件私有，避免与其它模块冲突）

private enum TxtPalette {
    static let main  = [Color(hex: 0x5B8CFF), Color(hex: 0x9B6BFF)]
    static let caseC = [Color(hex: 0xFF8A3D), Color(hex: 0xFF5E7A)]
    static let lineC = [Color(hex: 0x18B26B), Color(hex: 0x5BD1A0)]
    static let procC = [Color(hex: 0x2EC5D3), Color(hex: 0x3B82F6)]

    static let twoCols = [GridItem(.flexible(), spacing: 8),
                          GridItem(.flexible(), spacing: 8)]
    static let threeCols = [GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)]
    static let statCols = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]
}

// MARK: 多行输入框（去掉系统灰底）

private struct TxtEditorBox: View {
    @Binding var text: String
    var placeholder: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(BBFont.body(14))
                    .foregroundColor(.secondary.opacity(0.65))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            }
            TextEditor(text: $text)
                .font(BBFont.body(14))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 132)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                .fill(Theme.panel(scheme == .dark))
        )
    }
}

// MARK: 单行输入框

private struct TxtLineField: View {
    let placeholder: String
    var icon: String = "magnifyingglass"
    @Binding var text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .font(BBFont.body(14))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                .fill(Theme.panel(scheme == .dark))
        )
    }
}

// MARK: 操作按钮（小方块）

private struct TxtActionButton: View {
    let title: String
    let icon: String
    var colors: [Color] = TxtPalette.main
    let action: () -> Void

    var body: some View {
        Button(action: {
            BBHaptic.tap()
            action()
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(colors.first ?? Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                    .fill((colors.first ?? Theme.accent).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                            .strokeBorder((colors.first ?? Theme.accent).opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 主视图

struct TextToolboxView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var input: String = ""
    @State private var output: String = ""
    @State private var actionTitle: String = "结果"
    @State private var copied = false
    @State private var findText: String = ""
    @State private var replaceText: String = ""

    // 实时统计
    private var charCount: Int { input.count }
    private var bareCount: Int { input.filter { !$0.isWhitespace }.count }
    private var wordCount: Int { input.split(whereSeparator: { $0.isWhitespace }).count }
    private var lineCount: Int { input.isEmpty ? 0 : input.components(separatedBy: .newlines).count }
    private var byteCount: Int { input.lengthOfBytes(using: .utf8) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "text.alignleft", colors: TxtPalette.main,
                           title: "文本工具箱", subtitle: "统计 · 转换 · 行操作 · 批量处理")

                // ── 输入 ──
                BBSectionHeader("输入文本", icon: "square.and.pencil")
                BBCard {
                    VStack(alignment: .leading, spacing: 10) {
                        TxtEditorBox(text: $input, placeholder: "在此输入或粘贴文本…")
                        HStack(spacing: 8) {
                            Text("\(charCount) 字符 · \(byteCount) 字节")
                                .font(BBFont.cap(11))
                                .foregroundColor(.secondary)
                            Spacer(minLength: 8)
                            Button {
                                clearAll()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("一键清空")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(Theme.danger)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Theme.danger.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // ── 统计 ──
                BBSectionHeader("文本统计", icon: "chart.bar.fill")
                BBCard {
                    LazyVGrid(columns: TxtPalette.statCols, spacing: 14) {
                        BBStat(label: "字符数", value: "\(charCount)", icon: "textformat.size")
                        BBStat(label: "去空格字符数", value: "\(bareCount)", icon: "textformat",
                               colors: TxtPalette.caseC)
                        BBStat(label: "词数", value: "\(wordCount)", icon: "text.word.spacing",
                               colors: TxtPalette.caseC)
                        BBStat(label: "行数", value: "\(lineCount)", icon: "list.number",
                               colors: TxtPalette.lineC)
                        BBStat(label: "字节数", value: "\(byteCount)", icon: "externaldrive",
                               colors: TxtPalette.lineC)
                    }
                }

                // ── 大小写转换 ──
                BBSectionHeader("大小写转换", icon: "textformat.abc", colors: TxtPalette.caseC)
                BBCard {
                    LazyVGrid(columns: TxtPalette.twoCols, spacing: 8) {
                        TxtActionButton(title: "全大写", icon: "arrow.up", colors: TxtPalette.caseC) {
                            apply("全大写") { $0.uppercased() }
                        }
                        TxtActionButton(title: "全小写", icon: "arrow.down", colors: TxtPalette.caseC) {
                            apply("全小写") { $0.lowercased() }
                        }
                        TxtActionButton(title: "首字母大写", icon: "textformat.size", colors: TxtPalette.caseC) {
                            apply("首字母大写") { titleCased($0) }
                        }
                        TxtActionButton(title: "句首大写", icon: "text.append", colors: TxtPalette.caseC) {
                            apply("句首大写") { sentenceCased($0) }
                        }
                    }
                }

                // ── 行操作 ──
                BBSectionHeader("行操作", icon: "list.bullet.rectangle", colors: TxtPalette.lineC)
                BBCard {
                    LazyVGrid(columns: TxtPalette.threeCols, spacing: 8) {
                        TxtActionButton(title: "去重行", icon: "square.on.square", colors: TxtPalette.lineC) {
                            apply("去重行") { uniqueLines($0) }
                        }
                        TxtActionButton(title: "去空行", icon: "rectangle.compress.vertical", colors: TxtPalette.lineC) {
                            apply("去空行") { dropEmptyLines($0) }
                        }
                        TxtActionButton(title: "倒序", icon: "arrow.up.arrow.down", colors: TxtPalette.lineC) {
                            apply("倒序") { reversedLines($0) }
                        }
                        TxtActionButton(title: "随机打乱", icon: "shuffle", colors: TxtPalette.lineC) {
                            apply("随机打乱") { shuffledLines($0) }
                        }
                        TxtActionButton(title: "行排序", icon: "arrow.up.to.line", colors: TxtPalette.lineC) {
                            apply("行排序") { sortedLines($0) }
                        }
                        TxtActionButton(title: "加行号", icon: "number", colors: TxtPalette.lineC) {
                            apply("加行号") { numberedLines($0) }
                        }
                    }
                }

                // ── 文本处理 ──
                BBSectionHeader("文本处理", icon: "wand.and.stars", colors: TxtPalette.procC)
                BBCard {
                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: TxtPalette.threeCols, spacing: 8) {
                            TxtActionButton(title: "去多余空格", icon: "space", colors: TxtPalette.procC) {
                                apply("去多余空格") { collapseSpaces($0) }
                            }
                            TxtActionButton(title: "去换行", icon: "arrow.left.and.right", colors: TxtPalette.procC) {
                                apply("去换行") { removeNewlines($0) }
                            }
                            TxtActionButton(title: "翻转字符串", icon: "arrow.uturn.left", colors: TxtPalette.procC) {
                                apply("翻转字符串") { String($0.reversed()) }
                            }
                        }
                        Divider().opacity(0.4)
                        TxtLineField(placeholder: "查找内容", icon: "magnifyingglass", text: $findText)
                        TxtLineField(placeholder: "替换为（留空则删除）", icon: "arrow.right.doc.on.clipboard",
                                     text: $replaceText)
                        BBPrimaryButton(title: "全部替换", icon: "arrow.triangle.2.circlepath",
                                        colors: TxtPalette.procC) {
                            doReplace()
                        }
                    }
                }

                // ── 结果 ──
                BBSectionHeader("处理结果", icon: "doc.text.magnifyingglass")
                BBCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            BBPill(text: actionTitle, color: TxtPalette.main[0])
                            Spacer(minLength: 6)
                            Text("\(output.count) 字符")
                                .font(BBFont.cap(11))
                                .foregroundColor(.secondary)
                        }
                        if output.isEmpty {
                            BBEmptyState(icon: "text.badge.xmark", title: "暂无结果",
                                         message: "在上方选择操作或执行替换，结果会显示在这里")
                        } else {
                            Text(output)
                                .font(BBFont.mono)
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 10) {
                                Button {
                                    copyOutput()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(copied ? "已复制" : "复制结果")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(copied ? Theme.success : Theme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(
                                        RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                                            .fill((copied ? Theme.success : Theme.accent).opacity(0.10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                                                    .strokeBorder((copied ? Theme.success : Theme.accent).opacity(0.25),
                                                                  lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)

                                BBGhostButton(title: "结果转输入", icon: "arrow.up.doc") {
                                    let t = output
                                    input = t
                                    BBHaptic.success()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("文本工具箱")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 动作

    private func apply(_ title: String, _ transform: (String) -> String) {
        guard !input.isEmpty else {
            BBHaptic.warn()
            return
        }
        let result = transform(input)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            output = result
            actionTitle = title
        }
        BBHaptic.success()
    }

    private func doReplace() {
        guard !input.isEmpty, !findText.isEmpty else {
            BBHaptic.warn()
            return
        }
        let result = input.replacingOccurrences(of: findText, with: replaceText)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            output = result
            actionTitle = "查找替换"
        }
        BBHaptic.success()
    }

    private func clearAll() {
        BBHaptic.warn()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            input = ""
            output = ""
            findText = ""
            replaceText = ""
            actionTitle = "结果"
        }
    }

    private func copyOutput() {
        guard !output.isEmpty else {
            BBHaptic.warn()
            return
        }
        UIPasteboard.general.string = output
        BBHaptic.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { copied = false }
        }
    }

    // MARK: - 文本变换

    private func titleCased(_ s: String) -> String {
        var result = ""
        var newWord = true
        for ch in s {
            if ch.isWhitespace || ch.isPunctuation {
                newWord = true
                result.append(ch)
            } else if newWord {
                result.append(contentsOf: ch.uppercased())
                newWord = false
            } else {
                result.append(ch)
            }
        }
        return result
    }

    private func sentenceCased(_ s: String) -> String {
        var result = ""
        var start = true
        let enders: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]
        for ch in s {
            if start && !ch.isWhitespace {
                result.append(contentsOf: ch.uppercased())
                start = false
            } else {
                result.append(ch)
                if enders.contains(ch) { start = true }
            }
        }
        return result
    }

    private func uniqueLines(_ s: String) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for line in s.components(separatedBy: "\n") {
            if seen.insert(line).inserted { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    private func dropEmptyLines(_ s: String) -> String {
        s.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    private func reversedLines(_ s: String) -> String {
        s.components(separatedBy: "\n").reversed().joined(separator: "\n")
    }

    private func shuffledLines(_ s: String) -> String {
        s.components(separatedBy: "\n").shuffled().joined(separator: "\n")
    }

    private func sortedLines(_ s: String) -> String {
        s.components(separatedBy: "\n")
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .joined(separator: "\n")
    }

    private func numberedLines(_ s: String) -> String {
        let lines = s.components(separatedBy: "\n")
        let width = String(lines.count).count
        var out: [String] = []
        for i in 0..<lines.count {
            let n = String(i + 1)
            let pad = String(repeating: " ", count: max(0, width - n.count))
            out.append(pad + n + ". " + lines[i])
        }
        return out.joined(separator: "\n")
    }

    private func collapseSpaces(_ s: String) -> String {
        s.components(separatedBy: .newlines).map { line -> String in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        }.joined(separator: "\n")
    }

    private func removeNewlines(_ s: String) -> String {
        let joined = s.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
    }
}
