import SwiftUI
import UIKit
import Foundation

// MARK: - JSON 工具（格式化 / 压缩 / 校验 / 转义，纯本地 JSONSerialization）

private enum JsonStatus: Equatable { case idle, ok, fail }

private enum JsonColors {
    static let primary: [Color] = [Color(hex: 0x7B5CFF), Color(hex: 0xC86BFF)]
    static let green: [Color] = [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)]
}

private struct JsonEditorBox: View {
    @Binding var text: String
    var placeholder: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).font(BBFont.mono).foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 12).padding(.top, 12)
            }
            TextEditor(text: $text)
                .font(BBFont.mono).scrollContentBackground(.hidden).background(Color.clear)
                .frame(minHeight: 180).padding(.horizontal, 7).padding(.vertical, 6)
        }
        .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
            .fill(Theme.panel(scheme == .dark)))
    }
}

// MARK: - 主视图

struct TextJSONView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var input: String = ""
    @State private var output: String = ""
    @State private var status: JsonStatus = .idle
    @State private var message: String = ""
    @State private var indent: Int = 2
    @State private var copied = false

    private let sampleJSON = "{\"name\":\"百宝箱\",\"version\":\"9.0\",\"tags\":[\"工具\",\"本地\"],\"stats\":{\"count\":12,\"active\":true},\"note\":\"纯本地运行\"}"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "curlybraces", colors: JsonColors.primary,
                           title: "JSON 工具", subtitle: "格式化 · 压缩 · 校验 · 转义")

                BBSectionHeader("输入 JSON", icon: "square.and.pencil")
                BBCard {
                    VStack(alignment: .leading, spacing: 10) {
                        JsonEditorBox(text: $input, placeholder: "在此粘贴或输入 JSON 文本…")
                        HStack(spacing: 10) {
                            Text("\(input.count) 字符").font(BBFont.cap(11)).foregroundColor(.secondary)
                            Spacer(minLength: 8)
                            smallButton("填入示例", icon: "sparkles", color: Theme.accent) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    input = sampleJSON; output = ""; status = .idle; message = ""
                                }
                            }
                            smallButton("清空", icon: "trash", color: Theme.danger) { clearAll() }
                        }
                    }
                }

                BBSectionHeader("格式化缩进", icon: "text.alignleft")
                BBSegmented(options: [("2 空格", 2), ("4 空格", 4)], selection: $indent)

                HStack(spacing: 10) {
                    BBPrimaryButton(title: "格式化", icon: "text.alignleft", colors: JsonColors.primary) { jsonFormat(minify: false) }
                    BBPrimaryButton(title: "压缩", icon: "arrow.down.right.and.arrow.up.left", colors: JsonColors.green) { jsonFormat(minify: true) }
                }
                HStack(spacing: 10) {
                    BBGhostButton(title: "校验", icon: "checkmark.seal") { jsonValidate() }
                    BBGhostButton(title: "转义", icon: "arrow.right.to.line") { jsonEscape() }
                    BBGhostButton(title: "去转义", icon: "arrow.left.to.line") { jsonUnescape() }
                }
                if status != .idle { statusCard }

                BBSectionHeader("处理结果", icon: "doc.text.magnifyingglass")
                BBCard {
                    if output.isEmpty {
                        BBEmptyState(icon: "curlybraces", title: "暂无结果",
                                     message: "点「格式化 / 压缩 / 转义」后在此显示", colors: JsonColors.primary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                BBPill(text: "\(output.count) 字符", color: JsonColors.primary[0])
                                Spacer(minLength: 6)
                                Text("可长按选择文本").font(BBFont.cap(11)).foregroundColor(.secondary)
                            }
                            ScrollView {
                                Text(output).font(BBFont.mono).foregroundColor(.primary)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 340)
                            HStack(spacing: 10) {
                                BBGhostButton(title: copied ? "已复制" : "复制结果",
                                              icon: copied ? "checkmark" : "doc.on.doc") { copyOutput() }
                                BBGhostButton(title: "结果转输入", icon: "arrow.up.doc") { input = output; BBHaptic.success() }
                            }
                        }
                    }
                }
                Text("提示：解析与格式化均使用系统 JSONSerialization，纯本地处理，不上传任何数据。")
                    .font(BBFont.cap(11)).foregroundColor(.secondary).padding(.horizontal, 2)
            }
            .padding(.horizontal, BBSpacing.screen).padding(.top, 8).padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("JSON 工具")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 子视图

    private var statusCard: some View {
        let color = status == .ok ? Theme.success : Theme.danger
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: status == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(color)
            Text(message).font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
            .fill(color.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                .strokeBorder(color.opacity(0.3), lineWidth: 1)))
    }

    private func smallButton(_ title: String, icon: String, color: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: { BBHaptic.tap(); action() }) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(color).padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 动作

    private func jsonFormat(minify: Bool) {
        guard let data = cleanedInput() else { return }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            var opts: JSONSerialization.WritingOptions = minify ? [] : [.prettyPrinted]
            opts.insert(.withoutEscapingSlashes)
            let out = try JSONSerialization.data(withJSONObject: obj, options: opts)
            guard var text = String(data: out, encoding: .utf8) else { finish(false, "序列化结果无法转为文本"); return }
            if !minify && indent == 4 { text = jsonReindent(text, from: 2, to: 4) }
            finish(true, minify ? "压缩完成" : "格式化完成（\(indent) 空格缩进）")
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { output = text }
        } catch { finish(false, jsonErrorText(error)) }
    }

    private func jsonValidate() {
        guard let data = cleanedInput() else { return }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                output = ""
                status = .ok
                message = "校验通过 · 顶层类型：\(jsonKindName(obj)) · 共 \(data.count) 字节"
            }
            BBHaptic.success()
        } catch { finish(false, jsonErrorText(error)) }
    }

    private func jsonEscape() {
        guard !input.isEmpty else { finish(false, "请先输入内容"); return }
        guard let data = try? JSONSerialization.data(withJSONObject: [input], options: [.withoutEscapingSlashes]),
              var body = String(data: data, encoding: .utf8) else {
            finish(false, "转义失败：内容无法编码"); return
        }
        if body.hasPrefix("[") { body.removeFirst() }
        if body.hasSuffix("]") { body.removeLast() }
        output = body
        finish(true, "转义完成（JSON 字符串字面量）")
    }

    private func jsonUnescape() {
        var src = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { finish(false, "请先输入内容"); return }
        if !(src.hasPrefix("\"") && src.hasSuffix("\"")) {
            src = "\"" + src.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        guard let data = src.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let text = obj as? String else {
            finish(false, "去转义失败：内容不是合法的 JSON 字符串字面量"); return
        }
        output = text
        finish(true, "去转义完成")
    }

    private func copyOutput() {
        guard !output.isEmpty else { BBHaptic.warn(); return }
        UIPasteboard.general.string = output
        BBHaptic.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
    }

    private func clearAll() {
        BBHaptic.warn()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            input = ""; output = ""; status = .idle; message = ""
        }
    }

    // MARK: 工具

    private func cleanedInput() -> Data? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { finish(false, "请先输入 JSON 内容"); return nil }
        guard let data = trimmed.data(using: .utf8) else { finish(false, "无法读取输入内容"); return nil }
        return data
    }

    /// 统一更新状态条与触感（ok = true 成功，false 失败）
    private func finish(_ ok: Bool, _ note: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            status = ok ? .ok : .fail
            message = note
        }
        if ok { BBHaptic.success() } else { BBHaptic.warn() }
    }

    private func jsonKindName(_ obj: Any) -> String {
        if obj is [String: Any] { return "对象 {}" }
        if obj is [Any] { return "数组 []" }
        if obj is String { return "字符串" }
        if obj is NSNull { return "null" }
        if let num = obj as? NSNumber { return CFGetTypeID(num) == CFBooleanGetTypeID() ? "布尔" : "数字" }
        return "未知"
    }

    private func jsonErrorText(_ error: Error) -> String {
        let ns = error as NSError
        var desc = (ns.userInfo[NSDebugDescriptionErrorKey] as? String) ?? ns.localizedDescription
        desc = desc.replacingOccurrences(
            of: "JSON text did not start with array or object and option to allow fragments not set.",
            with: "JSON 顶层内容不合法")
        let nsc = desc as NSString
        let full = NSRange(location: 0, length: nsc.length)
        if let re = try? NSRegularExpression(pattern: "line (\\d+), column (\\d+)"),
           let m = re.firstMatch(in: desc, range: full), m.numberOfRanges == 3 {
            return "解析失败（第 \(nsc.substring(with: m.range(at: 1))) 行，第 \(nsc.substring(with: m.range(at: 2))) 列）：\(desc)"
        }
        if let re = try? NSRegularExpression(pattern: "character (\\d+)"),
           let m = re.firstMatch(in: desc, range: full), m.numberOfRanges == 2,
           let offset = Int(nsc.substring(with: m.range(at: 1))) {
            let pos = lineColumn(at: offset)
            return "解析失败（第 \(pos.0) 行，第 \(pos.1) 列）：\(desc)"
        }
        return "解析失败：\(desc)"
    }

    private func lineColumn(at offset: Int) -> (Int, Int) {
        var line = 1, col = 1, i = 0
        for scalar in input.unicodeScalars {
            if i >= offset { break }
            if scalar == "\n" { line += 1; col = 1 } else { col += 1 }
            i += 1
        }
        return (line, col)
    }

    /// 把 JSONSerialization 的 2 空格缩进改写为 to 空格
    private func jsonReindent(_ text: String, from: Int, to: Int) -> String {
        guard from > 0 else { return text }
        var lines = text.components(separatedBy: "\n")
        for idx in lines.indices {
            let line = lines[idx]
            var spaces = 0
            for ch in line { if ch == " " { spaces += 1 } else { break } }
            if spaces > 0 {
                let level = spaces / from
                lines[idx] = String(repeating: " ", count: level * to) + String(line.dropFirst(spaces))
            }
        }
        return lines.joined(separator: "\n")
    }
}
