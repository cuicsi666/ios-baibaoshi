import SwiftUI
import Foundation

// MARK: - 编码转换
// Base64 / URL / 表单 / HTML 实体 / Unicode 转义 / 二进制 / 十六进制，纯本地，iOS 16 兼容。

// MARK: 编码方式

private enum TxtEncMode: Hashable {
    case base64, url, html, unicode, radix

    static var selectable: [TxtEncMode] { [.base64, .url, .html, .unicode, .radix] }

    var title: String {
        switch self {
        case .base64: return "Base64"
        case .url: return "URL"
        case .html: return "HTML"
        case .unicode: return "Unicode"
        case .radix: return "进制"
        }
    }

    var icon: String {
        switch self {
        case .base64: return "square.stack.3d.up.fill"
        case .url: return "link"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .unicode: return "character"
        case .radix: return "number"
        }
    }

    var colors: [Color] {
        switch self {
        case .base64: return [Color(hex: 0x5B8CFF), Color(hex: 0x9B6BFF)]
        case .url: return [Color(hex: 0x2EC5D3), Color(hex: 0x3B82F6)]
        case .html: return [Color(hex: 0xFF8A3D), Color(hex: 0xFF5E7A)]
        case .unicode: return [Color(hex: 0x18B26B), Color(hex: 0x5BD1A0)]
        case .radix: return [Color(hex: 0xF7B733), Color(hex: 0xFC4A1A)]
        }
    }

    var hint: String {
        switch self {
        case .base64: return "Base64 文本编码，常用于传输二进制数据"
        case .url: return "百分号编码，可切换标准 / 表单（空格转 +）"
        case .html: return "HTML 实体，特殊字符与中文转 &#NNNN;"
        case .unicode: return "Unicode 转义 \\uXXXX，含代理对处理"
        case .radix: return "文本按 UTF-8 字节显示为二进制 / 十六进制"
        }
    }
}

// MARK: 编解码结果

private struct TxtEncOutcome {
    var text: String
    var error: String?
}

// MARK: 编解码核心

private enum TxtEncCodec {

    static func encode(_ s: String, mode: TxtEncMode, form: Bool, radix: Int) -> TxtEncOutcome {
        switch mode {
        case .base64:
            return TxtEncOutcome(text: Data(s.utf8).base64EncodedString(), error: nil)

        case .url:
            if form {
                var allowed = CharacterSet.alphanumerics
                allowed.insert(charactersIn: "-._*")
                guard let enc = s.addingPercentEncoding(withAllowedCharacters: allowed) else {
                    return TxtEncOutcome(text: "", error: "URL 表单编码失败：存在无法编码的字符")
                }
                return TxtEncOutcome(text: enc.replacingOccurrences(of: "%20", with: "+"), error: nil)
            }
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            guard let enc = s.addingPercentEncoding(withAllowedCharacters: allowed) else {
                return TxtEncOutcome(text: "", error: "URL 编码失败：存在无法编码的字符")
            }
            return TxtEncOutcome(text: enc, error: nil)

        case .html:
            return TxtEncOutcome(text: htmlEncode(s), error: nil)

        case .unicode:
            return TxtEncOutcome(text: unicodeEncode(s), error: nil)

        case .radix:
            let bytes = [UInt8](s.utf8)
            if radix == 2 {
                let parts = bytes.map { b -> String in
                    let raw = String(b, radix: 2)
                    return String(repeating: "0", count: max(0, 8 - raw.count)) + raw
                }
                return TxtEncOutcome(text: parts.joined(separator: " "), error: nil)
            }
            return TxtEncOutcome(text: bytes.map { String(format: "%02x", $0) }.joined(separator: " "), error: nil)
        }
    }

    static func decode(_ s: String, mode: TxtEncMode, form: Bool, radix: Int) -> TxtEncOutcome {
        guard !s.isEmpty else {
            return TxtEncOutcome(text: "", error: "请输入需要解码的内容")
        }
        switch mode {
        case .base64:
            let cleaned = s.components(separatedBy: .whitespacesAndNewlines).joined()
            guard let data = Data(base64Encoded: cleaned) else {
                return TxtEncOutcome(text: "", error: "Base64 解码失败：输入不是合法的 Base64 文本")
            }
            guard let str = String(data: data, encoding: .utf8) else {
                return TxtEncOutcome(text: "", error: "Base64 解码成功，但内容不是有效的 UTF-8 文本")
            }
            return TxtEncOutcome(text: str, error: nil)

        case .url:
            var src = s
            if form { src = src.replacingOccurrences(of: "+", with: " ") }
            guard let dec = src.removingPercentEncoding else {
                return TxtEncOutcome(text: "", error: "URL 解码失败：存在不完整的百分号转义（如 %ZZ）")
            }
            return TxtEncOutcome(text: dec, error: nil)

        case .html:
            return htmlDecode(s)

        case .unicode:
            return unicodeDecode(s)

        case .radix:
            return radixDecode(s, radix: radix)
        }
    }

    // MARK: HTML

    private static func htmlEncode(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 38: out += "&amp;"      // &
            case 60: out += "&lt;"       // <
            case 62: out += "&gt;"       // >
            case 34: out += "&quot;"     // "
            case 39: out += "&#39;"      // '
            default:
                if scalar.value > 126 {
                    out += "&#\(scalar.value);"
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    private static func htmlDecode(_ s: String) -> TxtEncOutcome {
        var text = s
        // 先处理数字实体
        if let re = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") {
            let ns = text as NSString
            let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            var built = ""
            var last = 0
            for m in matches {
                let range = m.range
                built += ns.substring(with: NSRange(location: last, length: range.location - last))
                let body = ns.substring(with: m.range(at: 1))
                var value: UInt32? = nil
                if body.hasPrefix("x") || body.hasPrefix("X") {
                    value = UInt32(body.dropFirst(), radix: 16)
                } else {
                    value = UInt32(body, radix: 10)
                }
                if let v = value, let scalar = Unicode.Scalar(v) {
                    built.unicodeScalars.append(scalar)
                } else {
                    built += ns.substring(with: range)
                }
                last = range.location + range.length
            }
            if last < ns.length {
                built += ns.substring(from: last)
            }
            text = built
        }
        // 再处理命名实体（必须在数字实体之后）
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")
        ]
        for pair in named {
            text = text.replacingOccurrences(of: pair.0, with: pair.1)
        }
        return TxtEncOutcome(text: text, error: nil)
    }

    // MARK: Unicode 转义

    private static func unicodeEncode(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v < 128 {
                out.unicodeScalars.append(scalar)
            } else if v <= 0xFFFF {
                out += String(format: "\\u%04x", v)
            } else {
                let n = v - 0x10000
                let hi = 0xD800 + (n >> 10)
                let lo = 0xDC00 + (n & 0x3FF)
                out += String(format: "\\u%04x\\u%04x", hi, lo)
            }
        }
        return out
    }

    private static func hexBlock(_ scalars: [Unicode.Scalar], _ start: Int, _ count: Int) -> String {
        var text = ""
        var k = start
        while k < start + count && k < scalars.count {
            text.unicodeScalars.append(scalars[k])
            k += 1
        }
        return text
    }

    private static func unicodeDecode(_ s: String) -> TxtEncOutcome {
        let scalars = Array(s.unicodeScalars)
        var out = ""
        var i = 0
        var bad = 0

        while i < scalars.count {
            let c = scalars[i]

            guard c.value == 92, i + 1 < scalars.count else {
                out.unicodeScalars.append(c)
                i += 1
                continue
            }

            let next = scalars[i + 1]
            if next.value == 117 {   // 'u'
                if i + 5 < scalars.count {
                    let hex = hexBlock(scalars, i + 2, 4)
                    if let v = UInt32(hex, radix: 16) {
                        var scalarValue = v
                        var consumed = 6
                        if v >= 0xD800 && v <= 0xDBFF, i + 11 < scalars.count,
                           scalars[i + 6].value == 92, scalars[i + 7].value == 117 {
                            let hex2 = hexBlock(scalars, i + 8, 4)
                            if let lo = UInt32(hex2, radix: 16), lo >= 0xDC00, lo <= 0xDFFF {
                                scalarValue = 0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00)
                                consumed = 12
                            }
                        }
                        if let us = Unicode.Scalar(scalarValue) {
                            out.unicodeScalars.append(us)
                            i += consumed
                            continue
                        }
                    }
                }
                // 非法 \u：原样保留
                bad += 1
                out += "\\u"
                i += 2
                continue
            }

            switch next.value {
            case 110: out += "\n"
            case 116: out += "\t"
            case 114: out += "\r"
            case 98:  out += "\u{8}"
            case 102: out += "\u{c}"
            case 34:  out += "\""
            case 39:  out += "'"
            case 47:  out += "/"
            case 92:  out += "\\"
            default:
                out += "\\"
                out.unicodeScalars.append(next)
            }
            i += 2
        }

        var warn: String? = nil
        if bad > 0 { warn = "有 \(bad) 处 \\u 转义不完整，已原样保留" }
        return TxtEncOutcome(text: out, error: warn)
    }

    // MARK: 进制

    private static func radixDecode(_ s: String, radix: Int) -> TxtEncOutcome {
        let unit = (radix == 2) ? 8 : 2
        var tokens = s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "," || $0 == ":" })
            .map { String($0) }

        if tokens.count == 1 {
            let single = tokens[0]
            if single.count > unit && single.count % unit == 0 {
                var chunks: [String] = []
                var idx = single.startIndex
                while idx < single.endIndex {
                    let nextIdx = single.index(idx, offsetBy: unit)
                    chunks.append(String(single[idx..<nextIdx]))
                    idx = nextIdx
                }
                tokens = chunks
            }
        }

        var bytes: [UInt8] = []
        for token in tokens {
            guard let v = UInt8(token, radix: radix) else {
                let name = (radix == 2) ? "二进制" : "十六进制"
                return TxtEncOutcome(text: "", error: "\(name)解码失败：无法识别「\(token)」")
            }
            bytes.append(v)
        }
        guard !bytes.isEmpty else {
            return TxtEncOutcome(text: "", error: "没有可解码的字节")
        }
        guard let str = String(bytes: bytes, encoding: .utf8) else {
            return TxtEncOutcome(text: "", error: "解码出的字节不是有效的 UTF-8 文本")
        }
        return TxtEncOutcome(text: str, error: nil)
    }
}

// MARK: 输入框

private struct TxtEncEditorBox: View {
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
                .font(BBFont.mono)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 120)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                .fill(Theme.panel(scheme == .dark))
        )
    }
}

// MARK: - 主视图

struct TextEncodeView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var mode: TxtEncMode = .base64
    @State private var formVariant = false
    @State private var radixBase = 16
    @State private var input: String = ""
    @State private var output: String = ""
    @State private var errorText: String? = nil
    @State private var lastAction: String = "等待操作"
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "arrow.left.arrow.right", colors: mode.colors,
                           title: "编码转换", subtitle: "Base64 · URL · HTML · Unicode · 进制")

                // ── 编码方式 ──
                BBSectionHeader("编码方式", icon: "square.grid.2x2.fill")
                BBCard {
                    VStack(alignment: .leading, spacing: 12) {
                        BBSegmented(options: TxtEncMode.selectable.map { ($0.title, $0) },
                                    selection: $mode)
                            .onChange(of: mode) { _ in
                                output = ""
                                errorText = nil
                                lastAction = "等待操作"
                            }

                        if mode == .url {
                            BBSegmented(options: [("标准 URL", false), ("表单（空格 → +）", true)],
                                        selection: $formVariant)
                                .onChange(of: formVariant) { _ in
                                    output = ""
                                    errorText = nil
                                }
                        }
                        if mode == .radix {
                            BBSegmented(options: [("二进制", 2), ("十六进制", 16)],
                                        selection: $radixBase)
                                .onChange(of: radixBase) { _ in
                                    output = ""
                                    errorText = nil
                                }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.gradient(mode.colors))
                            Text(mode.hint)
                                .font(BBFont.cap(11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // ── 输入 ──
                BBSectionHeader("输入内容", icon: "character.cursor.ibeam")
                BBCard {
                    VStack(alignment: .leading, spacing: 10) {
                        TxtEncEditorBox(text: $input,
                                        placeholder: mode == .radix
                                            ? "输入要转换的文本，或粘贴字节序列…"
                                            : "输入要编码 / 解码的内容…")
                        HStack(spacing: 10) {
                            Text("\(input.count) 字符")
                                .font(BBFont.cap(11))
                                .foregroundColor(.secondary)
                            Spacer(minLength: 8)
                            Button {
                                BBHaptic.warn()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    input = ""
                                    output = ""
                                    errorText = nil
                                    lastAction = "等待操作"
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("清空")
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

                // ── 双向按钮 ──
                HStack(spacing: 10) {
                    BBPrimaryButton(title: "编码", icon: "arrow.right.circle.fill", colors: mode.colors) {
                        run(encode: true)
                    }
                    BBPrimaryButton(title: "解码", icon: "arrow.left.circle.fill",
                                    colors: [mode.colors[1], mode.colors[0]]) {
                        run(encode: false)
                    }
                }

                // ── 错误提示 ──
                if let err = errorText, !err.isEmpty {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.warning)
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                            .fill(Theme.warning.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                                    .strokeBorder(Theme.warning.opacity(0.3), lineWidth: 1)
                            )
                    )
                }

                // ── 结果 ──
                BBSectionHeader("转换结果", icon: "doc.text.magnifyingglass")
                BBCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            BBPill(text: lastAction, color: mode.colors[0])
                            Spacer(minLength: 6)
                            Text("\(output.count) 字符")
                                .font(BBFont.cap(11))
                                .foregroundColor(.secondary)
                        }
                        if output.isEmpty {
                            BBEmptyState(icon: "arrow.left.arrow.right.square", title: "暂无结果",
                                         message: "选择编码方式后点「编码」或「解码」", colors: mode.colors)
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
        .navigationTitle("编码转换")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 动作

    private func run(encode: Bool) {
        guard !input.isEmpty else {
            BBHaptic.warn()
            errorText = "请先输入内容"
            return
        }
        let outcome = encode
            ? TxtEncCodec.encode(input, mode: mode, form: formVariant, radix: radixBase)
            : TxtEncCodec.decode(input, mode: mode, form: formVariant, radix: radixBase)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            output = outcome.text
            errorText = outcome.error
            lastAction = encode ? "\(mode.title) 编码" : "\(mode.title) 解码"
        }
        if outcome.error == nil && !outcome.text.isEmpty {
            BBHaptic.success()
        } else {
            BBHaptic.warn()
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
}
