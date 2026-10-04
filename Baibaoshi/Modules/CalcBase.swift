import SwiftUI

// MARK: - 进制转换 + 位运算（纯本地 · iOS 16）

enum CalcBaseKind: Int, CaseIterable, Identifiable {
    case bin = 2, oct = 8, dec = 10, hex = 16
    var id: Int { rawValue }
    private var i: Int { self == .bin ? 0 : (self == .oct ? 1 : (self == .dec ? 2 : 3)) }

    var label: String { ["二进制", "八进制", "十进制", "十六进制"][i] }
    var prefix: String { ["0b", "0o", "", "0x"][i] }
    var maxDigits: Int { [64, 22, 20, 16][i] }
    var allowed: String { ["01", "01234567", "0123456789", "0123456789abcdef"][i] }
    var keyboard: UIKeyboardType { self == .hex ? .asciiCapable : .asciiCapableNumberPad }

    func keeps(_ c: Character) -> Bool { allowed.contains(c.lowercased()) }

    func render(_ v: UInt64) -> String {
        String(String(v, radix: rawValue, uppercase: self == .hex).prefix(maxDigits))
    }

    func parse(_ raw: String) -> UInt64? {
        let t = raw.replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty else { return nil }
        return UInt64(t, radix: rawValue)
    }
}

enum CalcBaseMath {
    static let maxText = "18446744073709551615"

    /// 二进制（或任意进制）按每 size 位从低位起分组
    static func group(_ s: String, size: Int) -> String {
        guard !s.isEmpty else { return "0" }
        var out: [Character] = []
        for (i, c) in s.reversed().enumerated() {
            if i > 0 && i % size == 0 { out.append(" ") }
            out.append(c)
        }
        return String(out.reversed())
    }

    /// 位运算输入只保留十进制数字
    static func digits(_ s: String) -> String {
        String(s.filter { $0 >= "0" && $0 <= "9" }.prefix(20))
    }
}

// MARK: - 主视图

struct CalcBaseView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var texts: [String] = ["0", "0", "0", "0"]
    @State private var hint = ""
    @State private var aText = "12"
    @State private var bText = "5"
    @State private var shiftText = "2"
    @FocusState private var focused: Int?

    private var kinds: [CalcBaseKind] { CalcBaseKind.allCases }
    private var decValue: UInt64? { CalcBaseKind.dec.parse(texts[2]) }
    private var aVal: UInt64? { UInt64(CalcBaseMath.digits(aText)) }
    private var bVal: UInt64? { UInt64(CalcBaseMath.digits(bText)) }
    private var shiftVal: UInt64 { min(63, UInt64(CalcBaseMath.digits(shiftText)) ?? 0) }

    private var bitCount: Int {
        guard let v = decValue else { return 0 }
        return v == 0 ? 1 : 64 - v.leadingZeroBitCount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "number.square", colors: Theme.accentColors(),
                           title: "进制转换", subtitle: "2 / 8 / 10 / 16 实时联动")
                convertCard
                groupedCard
                bitwiseCard
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("进制转换")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 四个进制输入框

    private var convertCard: some View {
        BBCard {
            VStack(spacing: 11) {
                ForEach(kinds.indices, id: \.self) { idx in
                    baseField(idx)
                    if idx < kinds.count - 1 { Divider().opacity(0.35) }
                }
                if !hint.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .bold))
                        Text(hint).font(BBFont.cap(11))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(Theme.warning)
                }
                HStack(spacing: 8) {
                    Text("改任一输入框，其余三个实时联动")
                        .font(BBFont.cap(11)).foregroundColor(.secondary)
                    Spacer(minLength: 0)
                    miniButton("清零", "arrow.counterclockwise") { setAll(0) }
                    miniButton("255", "flame") { setAll(255) }
                }
            }
        }
    }

    private func baseField(_ idx: Int) -> some View {
        let kind = kinds[idx]
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.gradient(Theme.accentColors())).frame(width: 30, height: 30)
                Text("\(kind.rawValue)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.label).font(BBFont.cap(11)).foregroundColor(.secondary)
                Text(kind.prefix.isEmpty ? "无前缀" : kind.prefix)
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.accent)
            }
            .frame(width: 58, alignment: .leading)
            TextField("0", text: $texts[idx])
                .focused($focused, equals: idx)
                .keyboardType(kind.keyboard)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.characters)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.5)
                .onChange(of: texts[idx]) { v in handleEdit(idx, v) }
        }
    }

    private func miniButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            BBHaptic.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Theme.accent).padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 二进制分组显示

    private var groupedCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3.middle.filled")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentGradient)
                    Text("二进制分组").font(BBFont.head(15))
                    Spacer(minLength: 0)
                    BBPill(text: decValue == nil ? "无效" : "\(bitCount) 位",
                           color: decValue == nil ? Theme.warning : Theme.accent)
                }
                Text(binText)
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .foregroundColor(decValue == nil ? .secondary : .primary)
                    .lineLimit(6).minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIPasteboard.general.string = binText
                        BBHaptic.success()
                    }
                if let v = decValue {
                    Divider().opacity(0.4)
                    BBKV(key: "十进制", value: String(v))
                    BBKV(key: "十六进制", value: "0x" + String(v, radix: 16, uppercase: true))
                    BBKV(key: "八进制", value: "0o" + String(v, radix: 8))
                    BBKV(key: "字节数", value: "\(max(1, (bitCount + 7) / 8)) B")
                }
                Text("点按分组文本可复制")
                    .font(BBFont.cap(10)).foregroundColor(.secondary)
            }
        }
    }

    private var binText: String {
        guard let v = decValue else { return "—" }
        return CalcBaseMath.group(String(v, radix: 2), size: 4)
    }

    // MARK: 位运算

    private var bitwiseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            BBSectionHeader("位运算", icon: "bitcoinsign.circle")
            BBCard {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        opInput("A", $aText, Theme.accent)
                        opInput("B", $bText, Theme.info)
                        opInput("移位", $shiftText, Theme.warning)
                    }
                    Divider().opacity(0.4)
                    if aVal == nil || bVal == nil {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .bold))
                            Text("请输入 0 ~ \(CalcBaseMath.maxText) 之间的十进制整数").font(BBFont.cap(11))
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(Theme.warning)
                    } else {
                        resultRows
                    }
                }
            }
        }
    }

    private func opInput(_ label: String, _ text: Binding<String>, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(BBFont.cap(11)).foregroundColor(.secondary)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.5)
                .onChange(of: text.wrappedValue) { v in
                    let fixed = CalcBaseMath.digits(v)
                    if fixed != v { text.wrappedValue = fixed }
                }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
            .strokeBorder(color.opacity(0.25), lineWidth: 1))
    }

    private var resultRows: some View {
        let a = aVal ?? 0
        let b = bVal ?? 0
        let n = shiftVal
        return VStack(spacing: 9) {
            opRow("AND 与", "ampersand", a & b, Theme.info)
            opRow("OR 或", "plus", a | b, Theme.success)
            opRow("XOR 异或", "xmark", a ^ b, Theme.accent)
            opRow("左移 << \(n)", "arrow.left", n >= 64 ? 0 : (a << n), Theme.warning)
            opRow("右移 >> \(n)", "arrow.right", n >= 64 ? 0 : (a >> n), Theme.accent2)
            opRow("NOT 取反", "personalhotspot.slash", ~a, Theme.danger)
            if a != 0 && n > 0 && (a >> (64 - n)) != 0 {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill").font(.system(size: 10, weight: .bold))
                    Text("左移结果超出 64 位，已截断为 0").font(BBFont.cap(11))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.warning)
            }
        }
    }

    private func opRow(_ name: String, _ icon: String, _ v: UInt64, _ color: Color) -> some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.opacity(0.16)).frame(width: 26, height: 26)
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundColor(color)
            }
            Text(name).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(v)).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("0x" + String(v, radix: 16, uppercase: true))
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: 联动逻辑

    private func setAll(_ v: UInt64) {
        for (i, k) in kinds.enumerated() {
            let s = k.render(v)
            if texts[i] != s { texts[i] = s }
        }
        hint = ""
    }

    /// 仅焦点所在的输入框驱动联动，避免 onChange 递归
    private func handleEdit(_ idx: Int, _ raw: String) {
        guard focused == idx else { return }
        let kind = kinds[idx]
        let cleaned = String(raw.filter { kind.keeps($0) }.prefix(kind.maxDigits))
        if cleaned != raw {
            texts[idx] = cleaned
            return
        }
        guard !cleaned.isEmpty else {
            hint = "请输入\(kind.label)数值"
            clearOthers(idx)
            return
        }
        guard let v = kind.parse(cleaned) else {
            hint = "数值超出 64 位范围（最大 \(CalcBaseMath.maxText)）"
            clearOthers(idx)
            return
        }
        hint = ""
        for (i, k) in kinds.enumerated() where i != idx {
            let s = k.render(v)
            if texts[i] != s { texts[i] = s }
        }
    }

    private func clearOthers(_ idx: Int) {
        for i in kinds.indices where i != idx {
            if !texts[i].isEmpty { texts[i] = "" }
        }
    }
}
