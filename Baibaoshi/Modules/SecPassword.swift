import SwiftUI
import Foundation

// MARK: - 密码生成器
// 强随机密码（SystemRandomNumberGenerator），长度/字符集可调，纯本地，iOS 16 兼容。

// MARK: 强度等级

private enum SecLevel: String {
    case weak, medium, strong

    var title: String {
        switch self {
        case .weak: return "弱"
        case .medium: return "中"
        case .strong: return "强"
        }
    }

    var colors: [Color] {
        switch self {
        case .weak: return [Theme.danger, Color(hex: 0xFF7A7A)]
        case .medium: return [Theme.warning, Color(hex: 0xFFC24B)]
        case .strong: return [Theme.success, Color(hex: 0x5BD1A0)]
        }
    }
}

// MARK: 生成核心

private enum SecPasswordEngine {

    static let upperSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    static let lowerSet = "abcdefghijklmnopqrstuvwxyz"
    static let digitSet = "0123456789"
    static let symbolSet = "!@#$%^&*()-_=+[]{};:,.?/|"
    static let ambiguous = Set("0O1lI|")

    static func pools(upper: Bool, lower: Bool, digits: Bool, symbols: Bool, noMix: Bool) -> [String] {
        var pools: [String] = []
        if upper { pools.append(filter(upperSet, noMix)) }
        if lower { pools.append(filter(lowerSet, noMix)) }
        if digits { pools.append(filter(digitSet, noMix)) }
        if symbols { pools.append(filter(symbolSet, noMix)) }
        return pools.filter { !$0.isEmpty }
    }

    private static func filter(_ s: String, _ noMix: Bool) -> String {
        guard noMix else { return s }
        return String(s.filter { !ambiguous.contains($0) })
    }

    static func charsetSize(_ pools: [String]) -> Int {
        Set(pools.joined()).count
    }

    /// 熵（bit）= 长度 × log2(字符集大小)
    static func entropy(length: Int, pools: [String]) -> Double {
        let size = charsetSize(pools)
        guard size > 1 else { return 0 }
        return Double(length) * (log2(Double(size)))
    }

    static func level(_ bits: Double) -> SecLevel {
        if bits < 40 { return .weak }
        if bits < 70 { return .medium }
        return .strong
    }

    static func generate(length: Int, pools: [String]) -> String? {
        guard length > 0, !pools.isEmpty else { return nil }
        var rng = SystemRandomNumberGenerator()
        var chars: [Character] = []

        // 先保证每个启用的字符集至少出现一次
        for pool in pools where chars.count < length {
            let arr = Array(pool)
            chars.append(arr[Int.random(in: 0..<arr.count, using: &rng)])
        }
        let all = Array(pools.joined())
        while chars.count < length {
            chars.append(all[Int.random(in: 0..<all.count, using: &rng)])
        }
        chars.shuffle(using: &rng)
        return String(chars)
    }
}

// MARK: 开关行

private struct SecToggleRow: View {
    let title: String
    let icon: String
    let colors: [Color]
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gradient(colors))
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.accent)
        }
    }
}

// MARK: 密码行（批量列表用）

private struct SecPassRow: View {
    let text: String
    let copied: Bool
    var onCopy: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onCopy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(copied ? Theme.success : Theme.accent)
                    .padding(8)
                    .background(Circle().fill((copied ? Theme.success : Theme.accent).opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                .fill(Theme.panel(scheme == .dark))
        )
    }
}

// MARK: 主视图

struct SecPasswordView: View {
    @Environment(\.colorScheme) private var scheme

    @AppStorage("bb.pwd.len") private var length: Double = 16
    @AppStorage("bb.pwd.upper") private var useUpper: Bool = true
    @AppStorage("bb.pwd.lower") private var useLower: Bool = true
    @AppStorage("bb.pwd.digits") private var useDigits: Bool = true
    @AppStorage("bb.pwd.symbols") private var useSymbols: Bool = true
    @AppStorage("bb.pwd.nomix") private var noAmbiguous: Bool = true
    @AppStorage("bb.pwd.last") private var lastPassword: String = ""

    @State private var password: String = ""
    @State private var batch: [String] = []
    @State private var copiedIndex: Int? = nil
    @State private var copiedMain = false

    private var pools: [String] {
        SecPasswordEngine.pools(upper: useUpper, lower: useLower,
                                digits: useDigits, symbols: useSymbols,
                                noMix: noAmbiguous)
    }

    private var bits: Double {
        SecPasswordEngine.entropy(length: Int(length), pools: pools)
    }

    private var level: SecLevel {
        SecPasswordEngine.level(bits)
    }

    private var canGenerate: Bool { !pools.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "key.fill",
                           colors: [Color(hex: 0x18B26B), Color(hex: 0x2EC5D3)],
                           title: "密码生成器",
                           subtitle: "强随机 · 本地生成 · 不上传")

                // ── 结果展示 ──
                BBCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.rotation")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.gradient(level.colors))
                            Text(password.isEmpty ? "点击下方按钮生成" : "生成的密码")
                                .font(BBFont.cap(12))
                                .foregroundColor(.secondary)
                            Spacer()
                            BBPill(text: level.title, color: level.colors.first ?? Theme.accent)
                        }

                        Text(password.isEmpty ? "— — — — — —" : password)
                            .font(BBFont.monoBig)
                            .lineLimit(3)
                            .minimumScaleFactor(0.5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)

                        if canGenerate {
                            BBMeter(value: min(1, bits / 128), colors: level.colors, height: 10)
                            HStack {
                                Text("熵 ≈ \(Int(bits.rounded())) bit")
                                    .font(BBFont.cap(11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("字符集 \(SecPasswordEngine.charsetSize(pools)) 个")
                                    .font(BBFont.cap(11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 10) {
                            BBPrimaryButton(title: "生成", icon: "arrow.clockwise",
                                            colors: [Color(hex: 0x18B26B), Color(hex: 0x2EC5D3)]) {
                                generate()
                            }
                            BBGhostButton(title: copiedMain ? "已复制" : "复制",
                                          icon: copiedMain ? "checkmark" : "doc.on.doc") {
                                copyMain()
                            }
                        }
                        .disabled(!canGenerate)
                        .opacity(canGenerate ? 1 : 0.5)
                    }
                }

                // ── 长度 ──
                BBSectionHeader("密码长度", icon: "ruler.fill",
                                colors: [Color(hex: 0x18B26B), Color(hex: 0x2EC5D3)])
                BBCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("长度")
                                .font(BBFont.cap(12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(length))")
                                .font(BBFont.num(22))
                                .foregroundStyle(Theme.gradient(level.colors))
                            Text("位")
                                .font(BBFont.cap(12))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $length, in: 4...64, step: 1)
                            .tint(Theme.accent)
                        HStack {
                            Text("4").font(BBFont.cap(10)).foregroundColor(.secondary)
                            Spacer()
                            Text("64").font(BBFont.cap(10)).foregroundColor(.secondary)
                        }
                    }
                }

                // ── 字符集 ──
                BBSectionHeader("字符集", icon: "square.grid.3x3.fill",
                                colors: [Color(hex: 0x18B26B), Color(hex: 0x2EC5D3)])
                BBCard {
                    VStack(spacing: 12) {
                        SecToggleRow(title: "大写字母 A-Z", icon: "textformat",
                                     colors: [Color(hex: 0x5B8CFF), Color(hex: 0x9B6BFF)],
                                     isOn: $useUpper)
                        Divider().opacity(0.4)
                        SecToggleRow(title: "小写字母 a-z", icon: "textformat.abc",
                                     colors: [Color(hex: 0x18B26B), Color(hex: 0x5BD1A0)],
                                     isOn: $useLower)
                        Divider().opacity(0.4)
                        SecToggleRow(title: "数字 0-9", icon: "number",
                                     colors: [Color(hex: 0xF7B733), Color(hex: 0xFC4A1A)],
                                     isOn: $useDigits)
                        Divider().opacity(0.4)
                        SecToggleRow(title: "符号 !@#$", icon: "asterisk",
                                     colors: [Color(hex: 0xFF8A3D), Color(hex: 0xFF5E7A)],
                                     isOn: $useSymbols)
                        Divider().opacity(0.4)
                        SecToggleRow(title: "排除易混字符 0O1lI|", icon: "eye.slash.fill",
                                     colors: [Color(hex: 0x8E9AAF), Color(hex: 0x5C6672)],
                                     isOn: $noAmbiguous)
                    }
                }

                // ── 批量生成 ──
                BBSectionHeader("批量生成", icon: "list.bullet.rectangle.fill",
                                colors: [Color(hex: 0x18B26B), Color(hex: 0x2EC5D3)])
                BBCard {
                    VStack(alignment: .leading, spacing: 12) {
                        BBPrimaryButton(title: "批量生成 5 条", icon: "square.stack.3d.down.right.fill",
                                        colors: [Color(hex: 0x5B8CFF), Color(hex: 0x9B6BFF)]) {
                            generateBatch()
                        }
                        if batch.isEmpty {
                            BBEmptyState(icon: "square.stack.3d.down.right",
                                         title: "暂无批量结果",
                                         message: "按当前设置一次生成 5 条密码")
                        } else {
                            ForEach(Array(batch.enumerated()), id: \.offset) { idx, item in
                                SecPassRow(text: item, copied: copiedIndex == idx) {
                                    copyBatch(index: idx, text: item)
                                }
                            }
                        }
                    }
                }

                Text("密码仅在本机生成，不会上传或存储明文。")
                    .font(BBFont.cap(11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("密码生成器")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if password.isEmpty, !lastPassword.isEmpty {
                password = lastPassword
            } else if password.isEmpty {
                generate()
            }
        }
        .onChange(of: length) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                regenerateIfPossible()
            }
        }
        .onChange(of: useUpper) { _ in regenerateIfPossible() }
        .onChange(of: useLower) { _ in regenerateIfPossible() }
        .onChange(of: useDigits) { _ in regenerateIfPossible() }
        .onChange(of: useSymbols) { _ in regenerateIfPossible() }
        .onChange(of: noAmbiguous) { _ in regenerateIfPossible() }
    }

    // MARK: 操作

    private func regenerateIfPossible() {
        batch = []
        copiedIndex = nil
        guard canGenerate, !password.isEmpty else { return }
        password = SecPasswordEngine.generate(length: Int(length), pools: pools) ?? password
        lastPassword = password
    }

    private func generate() {
        guard let pwd = SecPasswordEngine.generate(length: Int(length), pools: pools) else {
            BBHaptic.warn()
            return
        }
        BBHaptic.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            password = pwd
            copiedMain = false
        }
        lastPassword = pwd
    }

    private func generateBatch() {
        guard canGenerate else {
            BBHaptic.warn()
            return
        }
        BBHaptic.tap()
        let items = (0..<5).compactMap {
            SecPasswordEngine.generate(length: Int(length), pools: pools)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            batch = items
            copiedIndex = nil
        }
    }

    private func copyMain() {
        guard !password.isEmpty else { return }
        UIPasteboard.general.string = password
        BBHaptic.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { copiedMain = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedMain = false }
    }

    private func copyBatch(index: Int, text: String) {
        UIPasteboard.general.string = text
        BBHaptic.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { copiedIndex = index }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedIndex == index { copiedIndex = nil }
        }
    }
}
