import SwiftUI
import Foundation
import CryptoKit

// MARK: - 文本哈希
// MD5 / SHA1 / SHA256 / SHA512，纯本地 CryptoKit 计算，iOS 16 兼容。

// MARK: 哈希算法

private enum HashAlgo: String, CaseIterable, Identifiable {
    case md5, sha1, sha256, sha512

    var id: String { rawValue }

    var title: String {
        switch self {
        case .md5: return "MD5"
        case .sha1: return "SHA1"
        case .sha256: return "SHA256"
        case .sha512: return "SHA512"
        }
    }

    var icon: String {
        switch self {
        case .md5: return "number.square.fill"
        case .sha1: return "square.stack.3d.up.fill"
        case .sha256: return "lock.shield.fill"
        case .sha512: return "lock.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .md5: return [Color(hex: 0xFF8A3D), Color(hex: 0xFF5E7A)]
        case .sha1: return [Color(hex: 0xF7B733), Color(hex: 0xFC4A1A)]
        case .sha256: return [Color(hex: 0x2EC5D3), Color(hex: 0x3B82F6)]
        case .sha512: return [Color(hex: 0x5B8CFF), Color(hex: 0x9B6BFF)]
        }
    }

    var note: String {
        switch self {
        case .md5: return "128 位 · 校验用途"
        case .sha1: return "160 位 · 已不推荐"
        case .sha256: return "256 位 · 通用安全"
        case .sha512: return "512 位 · 抗碰撞强"
        }
    }

    var digestBits: Int {
        switch self {
        case .md5: return 128
        case .sha1: return 160
        case .sha256: return 256
        case .sha512: return 512
        }
    }
}

// MARK: 摘要计算

private enum HashDigest {

    static func hex(_ text: String, algo: HashAlgo) -> String {
        let data = Data(text.utf8)
        switch algo {
        case .md5:
            return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha1:
            return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha256:
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha512:
            return SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    static func computeAll(_ text: String) -> [HashAlgo: String] {
        var out: [HashAlgo: String] = [:]
        guard !text.isEmpty else { return out }
        for algo in HashAlgo.allCases {
            out[algo] = hex(text, algo: algo)
        }
        return out
    }
}

// MARK: 结果卡片

private struct HashAlgoCard: View {
    let algo: HashAlgo
    let digest: String
    let upper: Bool
    let copied: Bool
    var onCopy: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var shown: String {
        upper ? digest.uppercased() : digest
    }

    var body: some View {
        BBCard(padding: 14, radius: BBRadius.m) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: algo.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.gradient(algo.colors))
                    Text(algo.title)
                        .font(BBFont.head(15))
                    BBPill(text: "\(algo.digestBits) bit", color: algo.colors.first ?? Theme.accent)
                    Spacer(minLength: 4)
                    Button {
                        onCopy()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .bold))
                            Text(copied ? "已复制" : "复制")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill((copied ? Theme.success : Theme.accent).opacity(0.16))
                        )
                        .foregroundColor(copied ? Theme.success : Theme.accent)
                    }
                    .buttonStyle(.plain)
                }

                Text(shown.isEmpty ? "—" : shown)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(shown.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(algo.note)
                    .font(BBFont.cap(10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: 主视图

struct TextHashView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var input: String = ""
    @State private var digests: [HashAlgo: String] = [:]
    @State private var uppercase: Bool = false
    @State private var copiedAlgo: HashAlgo? = nil
    @State private var copiedAll = false

    private var isEmpty: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "lock.shield.fill",
                           colors: [Color(hex: 0x2EC5D3), Color(hex: 0x5B8CFF)],
                           title: "文本哈希",
                           subtitle: "MD5 · SHA1 · SHA256 · SHA512")

                // ── 输入 ──
                BBSectionHeader("输入文本", icon: "character.cursor.ibeam")

                BBCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack(alignment: .topLeading) {
                            if input.isEmpty {
                                Text("输入要计算哈希的文本…")
                                    .font(BBFont.body(15))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $input)
                                .font(.system(size: 15, design: .monospaced))
                                .frame(minHeight: 96, maxHeight: 150)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                                .fill(Theme.panel(scheme == .dark))
                        )

                        HStack(spacing: 10) {
                            Image(systemName: "textformat.size")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.gradient(Theme.accentColors()))
                            Text("大小写")
                                .font(BBFont.cap(12))
                                .foregroundColor(.secondary)
                            Spacer(minLength: 8)
                            Text("\(input.count) 字符")
                                .font(BBFont.cap(11))
                                .foregroundColor(.secondary)
                        }

                        BBSegmented(options: [("小写", false), ("大写", true)],
                                    selection: $uppercase)

                        HStack(spacing: 10) {
                            BBPrimaryButton(title: copiedAll ? "已全部复制" : "全部复制",
                                            icon: copiedAll ? "checkmark" : "doc.on.doc",
                                            colors: copiedAll ? [Theme.success, Theme.success] : [Color(hex: 0x2EC5D3), Color(hex: 0x5B8CFF)]) {
                                copyAll()
                            }
                            BBGhostButton(title: "清空", icon: "trash") {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    input = ""
                                    digests = [:]
                                }
                            }
                        }
                    }
                }

                // ── 结果 ──
                BBSectionHeader("哈希结果", icon: "lock.doc.fill",
                                colors: [Color(hex: 0x2EC5D3), Color(hex: 0x5B8CFF)])

                if isEmpty {
                    BBCard {
                        BBEmptyState(icon: "text.magnifyingglass",
                                     title: "等待输入",
                                     message: "输入文本后将自动计算四种哈希摘要")
                    }
                } else {
                    ForEach(HashAlgo.allCases) { algo in
                        HashAlgoCard(algo: algo,
                                     digest: digests[algo] ?? "",
                                     upper: uppercase,
                                     copied: copiedAlgo == algo) {
                            copy(algo)
                        }
                    }
                }
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("文本哈希")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: input) { newValue in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                digests = HashDigest.computeAll(newValue)
            }
        }
    }

    // MARK: 操作

    private func copy(_ algo: HashAlgo) {
        let raw = digests[algo] ?? ""
        guard !raw.isEmpty else { return }
        UIPasteboard.general.string = uppercase ? raw.uppercased() : raw
        BBHaptic.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { copiedAlgo = algo }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedAlgo == algo { copiedAlgo = nil }
        }
    }

    private func copyAll() {
        guard !isEmpty else { return }
        let lines = HashAlgo.allCases.compactMap { algo -> String? in
            guard let raw = digests[algo], !raw.isEmpty else { return nil }
            return "\(algo.title): \(uppercase ? raw.uppercased() : raw)"
        }
        guard !lines.isEmpty else { return }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        BBHaptic.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { copiedAll = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copiedAll = false
        }
    }
}
