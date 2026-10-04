import SwiftUI
import UIKit
import AVFoundation

// MARK: - 摩斯电码（文本 ↔ 电码双向转换 + 正弦波播放，纯本地无网络）
// 自定义类型统一使用 Morse / Code 前缀。

/// 对照表条目
struct MorseEntry: Identifiable {
    let id: String
    let char: String
    let code: String
}

/// 转换方向
enum MorseDirection: String, CaseIterable, Identifiable {
    case toMorse, toText
    var id: String { rawValue }
    var label: String {
        switch self {
        case .toMorse: return "文本 → 摩斯"
        case .toText: return "摩斯 → 文本"
        }
    }
}

/// 播放速度
enum MorseSpeed: String, CaseIterable, Identifiable {
    case slow, normal, fast
    var id: String { rawValue }
    var label: String {
        switch self {
        case .slow: return "慢速"
        case .normal: return "标准"
        case .fast: return "快速"
        }
    }
    /// 一个"点"的时长（秒）
    var unit: Double {
        switch self {
        case .slow: return 0.14
        case .normal: return 0.09
        case .fast: return 0.065
        }
    }
}

/// 摩斯电码编解码
enum MorseCodec {
    static let entries: [MorseEntry] = [
        MorseEntry(id: "A", char: "A", code: ".-"),
        MorseEntry(id: "B", char: "B", code: "-..."),
        MorseEntry(id: "C", char: "C", code: "-.-."),
        MorseEntry(id: "D", char: "D", code: "-.."),
        MorseEntry(id: "E", char: "E", code: "."),
        MorseEntry(id: "F", char: "F", code: "..-."),
        MorseEntry(id: "G", char: "G", code: "--."),
        MorseEntry(id: "H", char: "H", code: "...."),
        MorseEntry(id: "I", char: "I", code: ".."),
        MorseEntry(id: "J", char: "J", code: ".---"),
        MorseEntry(id: "K", char: "K", code: "-.-"),
        MorseEntry(id: "L", char: "L", code: ".-.."),
        MorseEntry(id: "M", char: "M", code: "--"),
        MorseEntry(id: "N", char: "N", code: "-."),
        MorseEntry(id: "O", char: "O", code: "---"),
        MorseEntry(id: "P", char: "P", code: ".--."),
        MorseEntry(id: "Q", char: "Q", code: "--.-"),
        MorseEntry(id: "R", char: "R", code: ".-."),
        MorseEntry(id: "S", char: "S", code: "..."),
        MorseEntry(id: "T", char: "T", code: "-"),
        MorseEntry(id: "U", char: "U", code: "..-"),
        MorseEntry(id: "V", char: "V", code: "...-"),
        MorseEntry(id: "W", char: "W", code: ".--"),
        MorseEntry(id: "X", char: "X", code: "-..-"),
        MorseEntry(id: "Y", char: "Y", code: "-.--"),
        MorseEntry(id: "Z", char: "Z", code: "--.."),
        MorseEntry(id: "0", char: "0", code: "-----"),
        MorseEntry(id: "1", char: "1", code: ".----"),
        MorseEntry(id: "2", char: "2", code: "..---"),
        MorseEntry(id: "3", char: "3", code: "...--"),
        MorseEntry(id: "4", char: "4", code: "....-"),
        MorseEntry(id: "5", char: "5", code: "....."),
        MorseEntry(id: "6", char: "6", code: "-...."),
        MorseEntry(id: "7", char: "7", code: "--..."),
        MorseEntry(id: "8", char: "8", code: "---.."),
        MorseEntry(id: "9", char: "9", code: "----."),
        MorseEntry(id: ".", char: ".", code: ".-.-.-"),
        MorseEntry(id: ",", char: ",", code: "--..--"),
        MorseEntry(id: "?", char: "?", code: "..--.."),
        MorseEntry(id: "'", char: "'", code: ".----."),
        MorseEntry(id: "!", char: "!", code: "-.-.--"),
        MorseEntry(id: "(", char: "(", code: "-.--."),
        MorseEntry(id: ")", char: ")", code: "-.--.-"),
        MorseEntry(id: "&", char: "&", code: ".-..."),
        MorseEntry(id: ":", char: ":", code: "---..."),
        MorseEntry(id: ";", char: ";", code: "-.-.-."),
        MorseEntry(id: "=", char: "=", code: "-...-"),
        MorseEntry(id: "+", char: "+", code: ".-.-."),
        MorseEntry(id: "-", char: "-", code: "-....-"),
        MorseEntry(id: "_", char: "_", code: "..--.-"),
        MorseEntry(id: "\"", char: "\"", code: ".-..-."),
        MorseEntry(id: "$", char: "$", code: "...-..-"),
        MorseEntry(id: "@", char: "@", code: ".--.-.")
    ]

    static let alphanumeric: [MorseEntry] = entries.filter {
        guard let scalar = $0.char.unicodeScalars.first, $0.char.count == 1 else { return false }
        return scalar.value < 128
    }.filter { entry in
        if let c = entry.char.first { return c.isLetter || c.isNumber }
        return false
    }

    static let punctuation: [MorseEntry] = entries.filter { entry in
        if let c = entry.char.first { return !c.isLetter && !c.isNumber }
        return false
    }

    private static let charToMorse: [Character: String] = {
        var map: [Character: String] = [:]
        for entry in entries {
            if let c = entry.char.first { map[c] = entry.code }
        }
        return map
    }()

    private static let morseToChar: [String: Character] = {
        var map: [String: Character] = [:]
        for entry in entries {
            if let c = entry.char.first { map[entry.code] = c }
        }
        return map
    }()

    /// 文本 → 摩斯（字母间空格，单词间 / ）
    static func encode(_ text: String) -> String {
        var parts: [String] = []
        for ch in text.uppercased() {
            if ch == " " || ch == "\n" || ch == "\t" {
                if parts.last != "/" { parts.append("/") }
                continue
            }
            if let code = charToMorse[ch] { parts.append(code) }
        }
        while parts.last == "/" { parts.removeLast() }
        return parts.joined(separator: " ")
    }

    /// 摩斯 → 文本（支持 / 或 | 作为单词分隔）
    static func decode(_ morse: String) -> String {
        let normalized = morse.replacingOccurrences(of: "|", with: "/")
        var words: [String] = []
        for rawWord in normalized.components(separatedBy: "/") {
            let trimmedWord = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedWord.isEmpty { continue }
            var word = ""
            for token in trimmedWord.split(separator: " ") {
                if let ch = morseToChar[String(token)] { word.append(ch) }
                else { word.append("?") }
            }
            words.append(word)
        }
        return words.joined(separator: " ")
    }
}

// MARK: - 正弦波音频生成

enum MorseToneBuilder {
    static let sampleRate: Double = 44100

    /// 把摩斯字符串渲染成 WAV 数据（点=短音，划=长音）
    static func wavData(morse: String, frequency: Double, unit: Double) -> Data {
        let freq = max(300, min(1000, frequency))
        let unitLength = max(0.03, min(0.30, unit))
        let unitSamples = max(1, Int(unitLength * sampleRate))
        let ramp = max(1, Int(0.006 * sampleRate))
        var samples: [Float] = []

        func appendTone(_ units: Double) {
            let count = max(1, Int(Double(unitSamples) * units))
            for i in 0..<count {
                let t = Double(i) / sampleRate
                var env = 1.0
                if i < ramp { env = Double(i) / Double(ramp) }
                let tail = count - i
                if tail < ramp { env = min(env, Double(tail) / Double(ramp)) }
                env = max(0, min(1, env))
                samples.append(Float(sin(2 * Double.pi * freq * t) * 0.55 * env))
            }
        }

        func appendSilence(_ units: Double) {
            let count = max(1, Int(Double(unitSamples) * units))
            samples.append(contentsOf: repeatElement(Float(0), count: count))
        }

        let normalized = morse.replacingOccurrences(of: "|", with: "/")
        var isFirstWord = true
        for rawWord in normalized.components(separatedBy: "/") {
            let letters = rawWord.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if letters.isEmpty { continue }
            if !isFirstWord { appendSilence(7) }
            isFirstWord = false
            var isFirstLetter = true
            for letter in letters {
                if !isFirstLetter { appendSilence(3) }
                isFirstLetter = false
                var isFirstElement = true
                for element in letter {
                    if !isFirstElement { appendSilence(1) }
                    isFirstElement = false
                    if element == "." { appendTone(1) }
                    else if element == "-" { appendTone(3) }
                }
            }
        }
        if samples.isEmpty { appendSilence(1) }

        var ints: [Int16] = []
        ints.reserveCapacity(samples.count)
        for value in samples {
            let clamped = max(-1, min(1, value))
            ints.append(Int16(clamped * 32767))
        }
        return wav(from: ints, sampleRate: Int(sampleRate))
    }

    /// 组装 16bit 单声道 PCM 的 WAV 头
    private static func wav(from samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let byteRate = sampleRate * 2
        let dataSize = samples.count * 2

        func appendUInt32(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(byteRate))
        appendUInt16(2)
        appendUInt16(16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(dataSize))
        for sample in samples {
            var v = sample.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        return data
    }
}

/// 播放器
final class MorsePlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    private var player: AVAudioPlayer?

    func play(morse: String, frequency: Double, unit: Double) {
        stop()
        guard !morse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let data = MorseToneBuilder.wavData(morse: morse, frequency: frequency, unit: unit)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let audio = try AVAudioPlayer(data: data)
            audio.delegate = self
            audio.prepareToPlay()
            player = audio
            isPlaying = audio.play()
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        if isPlaying { isPlaying = false }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.isPlaying = false }
    }
}

// MARK: - 主视图

struct CodeMorseView: View {
    @Environment(\.colorScheme) private var scheme

    @AppStorage("bb.morse.input") private var input: String = "SOS"
    @AppStorage("bb.morse.direction") private var directionRaw: String = MorseDirection.toMorse.rawValue
    @AppStorage("bb.morse.freq") private var frequency: Double = 600
    @AppStorage("bb.morse.speed") private var speedRaw: String = MorseSpeed.normal.rawValue

    @StateObject private var player = MorsePlayerModel()
    @State private var copied = false

    private var direction: MorseDirection {
        MorseDirection(rawValue: directionRaw) ?? .toMorse
    }

    private var speed: MorseSpeed {
        MorseSpeed(rawValue: speedRaw) ?? .normal
    }

    private var directionBinding: Binding<MorseDirection> {
        Binding(get: { direction }, set: { directionRaw = $0.rawValue })
    }

    private var speedBinding: Binding<MorseSpeed> {
        Binding(get: { speed }, set: { speedRaw = $0.rawValue })
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 转换结果
    private var output: String {
        switch direction {
        case .toMorse: return MorseCodec.encode(input)
        case .toText: return MorseCodec.decode(input)
        }
    }

    /// 用于播放的电码
    private var playableMorse: String {
        direction == .toMorse ? output : trimmedInput
    }

    private var inputHint: String {
        direction == .toMorse
            ? "输入字母 / 数字 / 常用标点"
            : "字母间用空格，单词间用 / 分隔"
    }

    private var isOutputValid: Bool {
        !trimmedInput.isEmpty && !output.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "waveform.path",
                           colors: [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)],
                           title: "摩斯电码",
                           subtitle: "双向转换 · 正弦波播放")

                BBSectionHeader("转换方向", icon: "arrow.left.arrow.right")
                BBCard {
                    BBSegmented(options: MorseDirection.allCases.map { ($0.label, $0) },
                                selection: directionBinding)
                }

                BBSectionHeader("输入", icon: "square.and.pencil")
                BBCard {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(inputHint, text: $input, axis: .vertical)
                            .font(BBFont.body(15))
                            .lineLimit(3...6)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)

                        HStack(spacing: 8) {
                            Text("\(input.count) 字符")
                                .font(BBFont.cap(11))
                                .foregroundColor(.secondary)
                            Spacer()
                            if !input.isEmpty {
                                Button {
                                    morseClear($input)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle.fill")
                                        Text("清空").font(BBFont.cap(11))
                                    }
                                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                BBSectionHeader("结果", icon: "text.alignleft")
                BBCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if trimmedInput.isEmpty {
                            BBEmptyState(icon: "waveform",
                                         title: "等待输入",
                                         message: "输入内容后自动转换")
                        } else if !isOutputValid {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Theme.warning)
                                Text(direction == .toMorse
                                     ? "没有可转换的字符，请使用字母、数字或常用标点。"
                                     : "没有识别到有效的摩斯电码，请检查空格与 / 分隔是否正确。")
                                    .font(BBFont.body(13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            BBResult(text: output)
                        }
                    }
                }

                if isOutputValid {
                    HStack(spacing: 10) {
                        if player.isPlaying {
                            BBPrimaryButton(title: "停止播放", icon: "stop.fill",
                                            colors: [Theme.danger, Color(hex: 0xFF7A18)]) {
                                player.stop()
                            }
                        } else {
                            BBPrimaryButton(title: "播放电码", icon: "play.fill") {
                                player.play(morse: playableMorse,
                                            frequency: frequency,
                                            unit: speed.unit)
                            }
                        }
                        BBGhostButton(title: copied ? "已复制" : "复制", icon: "doc.on.doc") {
                            copyOutput()
                        }
                    }
                }

                BBSectionHeader("播放设置", icon: "slider.horizontal.3")
                BBCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundStyle(Theme.gradient(Theme.accentColors()))
                            Text("音调频率").font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text("\(Int(frequency)) Hz")
                                .font(BBFont.mono)
                                .foregroundColor(Theme.accent)
                        }
                        Slider(value: $frequency, in: 400...800, step: 20)
                            .tint(Theme.accent)
                        Divider().opacity(0.4)
                        Text("速度").font(BBFont.cap(12)).foregroundColor(.secondary)
                        BBSegmented(options: MorseSpeed.allCases.map { ($0.label, $0) },
                                    selection: speedBinding)
                    }
                }

                BBSectionHeader("A-Z / 0-9 对照表", icon: "tablecells")
                BBCard {
                    VStack(alignment: .leading, spacing: 14) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                                  spacing: 8) {
                            ForEach(MorseCodec.alphanumeric) { entry in
                                morseCell(entry)
                            }
                        }
                        Divider().opacity(0.4)
                        Text("常用标点").font(BBFont.cap(12)).foregroundColor(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                                  spacing: 8) {
                            ForEach(MorseCodec.punctuation) { entry in
                                morseCell(entry)
                            }
                        }
                        Text("· 点按任意格子可复制该字符的电码")
                            .font(BBFont.cap(11))
                            .foregroundColor(.secondary)
                    }
                }

                Text("· 电码在本地生成与播放，不上传任何数据")
                    .font(BBFont.cap(11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("摩斯电码")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }

    // MARK: 子视图

    @ViewBuilder
    private func morseCell(_ entry: MorseEntry) -> some View {
        Button {
            UIPasteboard.general.string = entry.code
            BBHaptic.success()
        } label: {
            VStack(spacing: 3) {
                Text(entry.char)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(entry.code)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                    .fill(Theme.panel(scheme == .dark))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 逻辑

    private func copyOutput() {
        guard !output.isEmpty else { return }
        UIPasteboard.general.string = output
        BBHaptic.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { copied = false }
        }
    }
}

// MARK: - 小工具（清空输入，带触感）

private func morseClear(_ text: Binding<String>) {
    BBHaptic.tap()
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { text.wrappedValue = "" }
}
