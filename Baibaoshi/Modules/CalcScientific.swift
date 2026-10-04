import SwiftUI

// MARK: - 科学计算器（纯本地表达式求值 · iOS 16）

struct CalcScientificView: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("bb.calc.deg") private var isDeg: Bool = true

    @State private var expr: String = ""
    @State private var preview: String = ""
    @State private var result: String = ""
    @State private var errored: Bool = false
    @State private var done: Bool = false
    @State private var copied: Bool = false

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "function",
                           colors: Theme.accentColors(),
                           title: "科学计算器",
                           subtitle: "表达式求值 · 三角 / 对数 / 幂")

                displayCard
                BBSegmented(options: [("角度 DEG", true), ("弧度 RAD", false)], selection: $isDeg)
                keySection("函数", keys: fnKeys)
                keySection("键盘", keys: padKeys)

                Text("提示：支持连续表达式，例如 2×(3+4)²、sin(30)+ln(e)；点按结果区可复制。")
                    .font(BBFont.cap(11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("科学计算器")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 显示区

    private var bigText: String {
        if errored { return "错误" }
        if done { return result.isEmpty ? "0" : result }
        return preview.isEmpty ? "0" : preview
    }

    private var displayCard: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { Spacer(minLength: 0)
                    Text(expr.isEmpty ? "0" : expr)
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Text(bigText)
                .font(.system(size: 36, weight: .semibold, design: .monospaced))
                .foregroundColor(errored ? Theme.danger : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIPasteboard.general.string = bigText
                    BBHaptic.success()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }

            HStack(spacing: 8) {
                BBPill(text: isDeg ? "角度 DEG" : "弧度 RAD", color: Theme.accent)
                if done && !errored {
                    BBPill(text: copied ? "已复制" : "点按复制",
                           color: copied ? Theme.success : Theme.accent)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(BBSpacing.l)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: BBRadius.l, style: .continuous)
                .fill(Theme.cardBg(scheme == .dark))
                .overlay(RoundedRectangle(cornerRadius: BBRadius.l, style: .continuous)
                    .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
        )
        .bbShadow(scheme == .dark)
    }

    private func keySection(_ title: String, keys: [CalcKey]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BBSectionHeader(title, icon: "square.grid.3x3.fill", colors: Theme.accentColors())
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(keys) { k in
                    CalcKeyButton(key: k) { handle(k) }
                }
            }
        }
    }

    // MARK: 按键表

    private var fnKeys: [CalcKey] {
        [CalcKey("sin", .fn, .text("sin(")),
         CalcKey("cos", .fn, .text("cos(")),
         CalcKey("tan", .fn, .text("tan(")),
         CalcKey("π", .fn, .text("π")),
         CalcKey("ln", .fn, .text("ln(")),
         CalcKey("log₁₀", .fn, .text("log10(")),
         CalcKey("√", .fn, .text("√(")),
         CalcKey("e", .fn, .text("e")),
         CalcKey("x²", .fn, .text("^2")),
         CalcKey("1÷x", .fn, .recip),
         CalcKey("(", .fn, .text("(")),
         CalcKey(")", .fn, .text(")"))]
    }

    private var padKeys: [CalcKey] {
        [CalcKey("AC", .warn, .clear),
         CalcKey("⌫", .fn, .back),
         CalcKey("%", .fn, .text("%")),
         CalcKey("÷", .op, .text("÷")),
         CalcKey("7", .digit, .text("7")),
         CalcKey("8", .digit, .text("8")),
         CalcKey("9", .digit, .text("9")),
         CalcKey("×", .op, .text("×")),
         CalcKey("4", .digit, .text("4")),
         CalcKey("5", .digit, .text("5")),
         CalcKey("6", .digit, .text("6")),
         CalcKey("−", .op, .text("-")),
         CalcKey("1", .digit, .text("1")),
         CalcKey("2", .digit, .text("2")),
         CalcKey("3", .digit, .text("3")),
         CalcKey("+", .op, .text("+")),
         CalcKey("0", .digit, .text("0")),
         CalcKey(".", .digit, .text(".")),
         CalcKey("±", .fn, .sign),
         CalcKey("=", .eq, .equals)]
    }

    // MARK: 交互

    private func handle(_ k: CalcKey) {
        BBHaptic.tap()
        errored = false

        switch k.action {
        case .clear:
            expr = ""; preview = ""; result = ""; done = false
            return
        case .back:
            if done {
                expr = ""; result = ""; preview = ""; done = false
                return
            }
            if !expr.isEmpty { expr.removeLast() }
        case .equals:
            evaluate()
            return
        case .sign:
            toggleSign()
        case .recip:
            if done { done = false }
            if expr.isEmpty { expr = "1÷" } else { expr = "1÷(" + expr + ")" }
        case .text(let t):
            if done {
                let startsFresh = (t.first?.isNumber ?? false) || t == "π" || t == "e" || t == "(" || t == "√(" || t.hasSuffix("(")
                expr = startsFresh ? "" : result
                done = false
            }
            if t == "^2" && (expr.isEmpty || isLooseEnd(expr)) { expr += "0" }
            expr += t
        }
        updatePreview()
    }

    private func isLooseEnd(_ s: String) -> Bool {
        guard let c = s.last else { return true }
        return c == "+" || c == "-" || c == "×" || c == "÷" || c == "^" || c == "("
    }

    private func updatePreview() {
        let e = CalcEngine.balanced(expr)
        guard !e.isEmpty else { preview = ""; return }
        var eng = CalcEngine(e, degrees: isDeg)
        if let v = try? eng.run() {
            preview = CalcNum.fmt(v)
        }
    }

    private func evaluate() {
        let e = CalcEngine.balanced(expr)
        guard !e.isEmpty else {
            BBHaptic.warn()
            return
        }
        var eng = CalcEngine(e, degrees: isDeg)
        do {
            let v = try eng.run()
            result = CalcNum.fmt(v)
            preview = result
            done = true
            errored = false
            BBHaptic.success()
        } catch {
            errored = true
            done = false
            result = ""
            preview = ""
            BBHaptic.warn()
        }
    }

    private func toggleSign() {
        guard !expr.isEmpty else { expr = "-"; return }
        let chars = Array(expr)
        var start = chars.count
        while start > 0 {
            let c = chars[start - 1]
            if c.isNumber || c == "." { start -= 1 } else { break }
        }
        guard start < chars.count else { return }   // 结尾不是数字，忽略

        var s = expr
        let before = start > 0 ? chars[start - 1] : nil
        if before == "-" {
            let prev = start >= 2 ? chars[start - 2] : nil
            if prev == nil || prev == "+" || prev == "-" || prev == "×" || prev == "÷" || prev == "(" {
                let i = s.index(s.startIndex, offsetBy: start - 1)
                s.remove(at: i)
                expr = s
                return
            }
        }
        let i = s.index(s.startIndex, offsetBy: start)
        s.insert("-", at: i)
        expr = s
    }
}

// MARK: - 按键模型

enum CalcKeyStyle {
    case digit, op, fn, eq, warn
}

enum CalcKeyAction {
    case text(String)
    case clear
    case back
    case sign
    case recip
    case equals
}

struct CalcKey: Identifiable {
    let id: String
    let label: String
    let style: CalcKeyStyle
    let action: CalcKeyAction

    init(_ label: String, _ style: CalcKeyStyle, _ action: CalcKeyAction) {
        self.id = label
        self.label = label
        self.style = style
        self.action = action
    }
}

struct CalcPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CalcKeyButton: View {
    let key: CalcKey
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
    }

    private var fgColor: Color {
        switch key.style {
        case .digit: return .primary
        case .fn:    return Theme.accent
        case .op, .eq: return .white
        case .warn:  return Theme.danger
        }
    }

    @ViewBuilder private var keyBackground: some View {
        switch key.style {
        case .op:
            shape.fill(Theme.accentGradient)
                .shadow(color: Theme.accent2.opacity(0.32), radius: 6, y: 3)
        case .eq:
            shape.fill(Theme.gradient([Theme.success, Color(hex: 0x9BD34A)]))
                .shadow(color: Theme.success.opacity(0.35), radius: 6, y: 3)
        case .fn:
            shape.fill(Theme.accent.opacity(0.12))
                .overlay(shape.strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1))
        case .warn:
            shape.fill(Theme.danger.opacity(0.13))
                .overlay(shape.strokeBorder(Theme.danger.opacity(0.20), lineWidth: 1))
        case .digit:
            shape.fill(Theme.panel(scheme == .dark))
                .overlay(shape.strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
        }
    }

    var body: some View {
        Button(action: action) {
            Text(key.label)
                .font(.system(size: key.style == .eq ? 22 : 17, weight: .semibold, design: .rounded))
                .foregroundColor(fgColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(keyBackground)
        }
        .buttonStyle(CalcPressStyle())
    }
}

// MARK: - 数字格式化

enum CalcNum {
    static func fmt(_ v: Double) -> String {
        if v.isNaN { return "错误" }
        if v.isInfinite { return v > 0 ? "∞" : "-∞" }
        let a = abs(v)
        if a != 0 && (a >= 1e15 || a < 1e-9) {
            return String(format: "%.8g", v)
        }
        var x = (v * 1e10).rounded() / 1e10
        if abs(x) < 1e-10 { x = 0 }
        if x == x.rounded() && abs(x) < 1e15 {
            return String(format: "%.0f", x)
        }
        var s = String(format: "%.10f", x)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }
}

// MARK: - 简易表达式解析器

enum CalcEvalError: Error {
    case syntax
}

struct CalcEngine {
    private var chars: [Character]
    private var pos: Int = 0
    private var deg: Bool

    init(_ raw: String, degrees: Bool) {
        let rep: [Character: Character] = ["×": "*", "÷": "/", "−": "-", "–": "-", "✕": "*", "·": "*"]
        var t = String(raw.map { rep[$0] ?? $0 })
        t = t.replacingOccurrences(of: " ", with: "")
        t = t.replacingOccurrences(of: ",", with: "")
        t = t.replacingOccurrences(of: "，", with: "")
        chars = Array(t)
        deg = degrees
    }

    /// 补全缺失的右括号
    static func balanced(_ s: String) -> String {
        var open = 0
        for c in s {
            if c == "(" { open += 1 }
            else if c == ")" { open -= 1 }
        }
        if open <= 0 { return s }
        return s + String(repeating: ")", count: open)
    }

    mutating func run() throws -> Double {
        if chars.isEmpty { throw CalcEvalError.syntax }
        let v = try parseExpr()
        if pos < chars.count { throw CalcEvalError.syntax }
        if v.isNaN { throw CalcEvalError.syntax }
        return v
    }

    // MARK: 递归下降

    private mutating func parseExpr() throws -> Double {
        var v = try parseTerm()
        while pos < chars.count {
            let c = chars[pos]
            if c == "+" {
                pos += 1
                v += try parseTerm()
            } else if c == "-" {
                pos += 1
                v -= try parseTerm()
            } else {
                break
            }
        }
        return v
    }

    private mutating func parseTerm() throws -> Double {
        var v = try parseUnary()
        while pos < chars.count {
            let c = chars[pos]
            if c == "*" {
                pos += 1
                v *= try parseUnary()
            } else if c == "/" {
                pos += 1
                let d = try parseUnary()
                if d == 0 { throw CalcEvalError.syntax }
                v /= d
            } else if isPrimaryStart(c) {
                v *= try parseUnary()      // 隐式乘法：2π、3(4+1)
            } else {
                break
            }
        }
        return v
    }

    private mutating func parseUnary() throws -> Double {
        while pos < chars.count {
            let c = chars[pos]
            if c == "-" {
                pos += 1
                return -(try parseUnary())
            } else if c == "+" {
                pos += 1
                continue
            } else {
                break
            }
        }
        return try parsePower()
    }

    private mutating func parsePower() throws -> Double {
        let base = try parseSuffix()
        if pos < chars.count && chars[pos] == "^" {
            pos += 1
            let e = try parseUnary()
            return pow(base, e)
        }
        return base
    }

    private mutating func parseSuffix() throws -> Double {
        var v = try parsePrimary()
        while pos < chars.count {
            let c = chars[pos]
            if c == "%" {
                pos += 1
                v /= 100
            } else if c == "²" {
                pos += 1
                v = v * v
            } else {
                break
            }
        }
        return v
    }

    private func isPrimaryStart(_ c: Character) -> Bool {
        if c.isNumber || c == "." || c == "(" || c == "π" || c == "√" { return true }
        if c.isLetter && (c == "e" || c == "p") { return true }
        return false
    }

    private mutating func parsePrimary() throws -> Double {
        guard pos < chars.count else { throw CalcEvalError.syntax }
        let c = chars[pos]

        if c.isNumber || c == "." {
            return try readNumber()
        }
        if c == "(" {
            pos += 1
            let v = try parseExpr()
            guard pos < chars.count, chars[pos] == ")" else { throw CalcEvalError.syntax }
            pos += 1
            return v
        }
        if c == "π" {
            pos += 1
            return Double.pi
        }
        if c == "√" {
            pos += 1
            if pos < chars.count && chars[pos] == "(" {
                pos += 1
                let v = try parseExpr()
                guard pos < chars.count, chars[pos] == ")" else { throw CalcEvalError.syntax }
                pos += 1
                if v < 0 { throw CalcEvalError.syntax }
                return sqrt(v)
            }
            let v = try parsePower()
            if v < 0 { throw CalcEvalError.syntax }
            return sqrt(v)
        }
        if c.isLetter {
            let name = readIdentifier()
            if name == "e" { return Double(M_E) }
            if name == "pi" { return Double.pi }
            return try applyFunction(name)
        }
        throw CalcEvalError.syntax
    }

    private mutating func readIdentifier() -> String {
        var s = ""
        while pos < chars.count && chars[pos].isLetter {
            s.append(chars[pos])
            pos += 1
        }
        var name = s.lowercased()
        // 允许 log10 / lg10 这类带数字的函数名
        if name == "log" && pos + 1 < chars.count && chars[pos] == "1" && chars[pos + 1] == "0" {
            pos += 2
            name = "log10"
        }
        return name
    }

    private mutating func readNumber() throws -> Double {
        var s = ""
        var dot = false
        while pos < chars.count {
            let c = chars[pos]
            if c.isNumber {
                s.append(c)
                pos += 1
            } else if c == "." {
                if dot { break }
                dot = true
                s.append(c)
                pos += 1
            } else {
                break
            }
        }
        guard let d = Double(s) else { throw CalcEvalError.syntax }
        return d
    }

    private mutating func applyFunction(_ name: String) throws -> Double {
        var arg: Double
        if pos < chars.count && chars[pos] == "(" {
            pos += 1
            arg = try parseExpr()
            guard pos < chars.count, chars[pos] == ")" else { throw CalcEvalError.syntax }
            pos += 1
        } else {
            arg = try parsePower()
        }

        switch name {
        case "e":
            return Double(M_E)
        case "pi":
            return Double.pi
        case "sin":
            return trig(arg, sin)
        case "cos":
            return trig(arg, cos)
        case "tan":
            return trig(arg, tan)
        case "ln":
            if arg <= 0 { throw CalcEvalError.syntax }
            return log(arg)
        case "log", "log10", "lg":
            if arg <= 0 { throw CalcEvalError.syntax }
            return log10(arg)
        case "sqrt":
            if arg < 0 { throw CalcEvalError.syntax }
            return sqrt(arg)
        case "abs":
            return abs(arg)
        default:
            throw CalcEvalError.syntax
        }
    }

    private func trig(_ x: Double, _ f: (Double) -> Double) -> Double {
        let r = deg ? x * Double.pi / 180 : x
        return f(r)
    }
}
