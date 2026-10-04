import SwiftUI
import AVFoundation
// MARK: - 白噪音助眠（FunNoiseView）
// 纯本地：程序生成 PCM → 临时 WAV → AVAudioPlayer 循环播放（numberOfLoops = -1）。
// 白 / 粉 / 棕三音色 + 实时音量 + 定时关闭；任何音频失败一律优雅降级。类型统一 Noise 前缀。
enum NoiseTone: Int, CaseIterable {
    case white = 0, pink = 1, brown = 2
    private static let titles = ["白噪音", "粉噪音", "棕噪音"]
    private static let descs = ["全频段均匀能量，掩蔽环境杂音最直接",
                                "白噪音过一阶低通，低频更饱满，近似雨声",
                                "积分累积得到，低沉厚实，像海浪与瀑布"]
    private static let icons = ["waveform", "cloud.rain.fill", "drop.fill"]
    private static let palettes: [[Color]] = [[Color(hex: 0x5B86E5), Color(hex: 0x36D1DC)],
                                              [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)],
                                              [Color(hex: 0xFF9A5A), Color(hex: 0xB45309)]]
    var title: String { Self.titles[rawValue] }
    var desc: String { Self.descs[rawValue] }
    var icon: String { Self.icons[rawValue] }
    var colors: [Color] { Self.palettes[rawValue] }
    var accent: Color { colors[0] }
}
enum NoiseTimer {
    static let presets: [Int] = [0, 5, 10, 15, 30]
    static func label(_ m: Int) -> String { m <= 0 ? "关闭" : "\(m)分" }
    static func clock(_ s: TimeInterval) -> String {
        let t = max(0, Int(ceil(s)))
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}
enum NoiseGenerator {
    static let sampleRate: Double = 44100
    static let duration: Double = 6.0
    static func fileURL(for tone: NoiseTone) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bb_noise_\(tone.rawValue).wav")
    }
    /// 生成并写入本地临时 WAV（已存在则复用）；任何失败返回 nil
    static func prepare(tone: NoiseTone) -> URL? {
        let url = fileURL(for: tone)
        if let a = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = a[.size] as? Int, size > 44 { return url }
        let pcm = samples(tone)
        guard !pcm.isEmpty else { return nil }
        var data = Data(capacity: 44 + pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(contentsOf: le32(UInt32(36 + pcm.count * 2)))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(contentsOf: le32(16) + le16(1) + le16(1))
        data.append(contentsOf: le32(UInt32(sampleRate)) + le32(UInt32(sampleRate) * 2) + le16(2) + le16(16))
        data.append(contentsOf: Array("data".utf8))
        data.append(contentsOf: le32(UInt32(pcm.count * 2)))
        for s in pcm { data.append(contentsOf: le16(UInt16(bitPattern: s))) }
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
    /// 白 = 均匀随机；粉 = 一阶低通滤波；棕 = 泄漏积分累积
    private static func samples(_ tone: NoiseTone) -> [Int16] {
        let n = Int(sampleRate * duration)
        guard n > 0 else { return [] }
        var gen = SystemRandomNumberGenerator()
        var buf = [Double](repeating: 0, count: n)
        switch tone {
        case .white:
            for i in 0..<n { buf[i] = Double.random(in: -1...1, using: &gen) }
        case .pink:
            var y = 0.0
            for i in 0..<n {
                y += 0.10 * (Double.random(in: -1...1, using: &gen) - y)
                buf[i] = y
            }
        case .brown:
            var acc = 0.0
            for i in 0..<n {
                acc = (acc + Double.random(in: -1...1, using: &gen) * 0.02) * 0.998
                buf[i] = acc
            }
        }
        var mean = 0.0
        for v in buf { mean += v }
        mean /= Double(n)
        var peak = 0.0
        for i in 0..<n { buf[i] -= mean; peak = max(peak, abs(buf[i])) }
        let gain = peak > 1e-6 ? 0.8 / peak : 0
        var out = [Int16](repeating: 0, count: n)
        for i in 0..<n { out[i] = Int16(max(-1.0, min(1.0, buf[i] * gain)) * 32000) }
        let fade = min(n / 8, Int(sampleRate * 0.03))     // 首尾淡入淡出，消除循环爆音
        if fade > 1 {
            for i in 0..<fade {
                let k = Float(i) / Float(fade)
                out[i] = Int16(Float(out[i]) * k)
                out[n - 1 - i] = Int16(Float(out[n - 1 - i]) * k)
            }
        }
        return out
    }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
}
final class NoiseAudioEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var errorText: String?
    private var player: AVAudioPlayer?
    private var currentTone: NoiseTone?
    private var sessionOn = false
    private var token = 0
    /// 播放或切换音色；同音色直接续播，不重建播放器
    func play(tone: NoiseTone, volume: Float) {
        errorText = nil
        if let p = player, currentTone == tone {
            activateSession()
            p.numberOfLoops = -1
            p.volume = volume
            if p.play() { isPlaying = true } else { fail("播放未能启动，请检查音频输出或静音键") }
            return
        }
        player?.stop(); player = nil; currentTone = nil; isPlaying = false; isLoading = true
        token += 1
        let myToken = token
        DispatchQueue.global(qos: .userInitiated).async {
            let url = NoiseGenerator.prepare(tone: tone)
            DispatchQueue.main.async {
                guard myToken == self.token else { return }
                self.isLoading = false
                guard let url = url else { self.fail("音频生成失败，已静默降级（其他功能不受影响）"); return }
                do {
                    let p = try AVAudioPlayer(contentsOf: url)
                    p.numberOfLoops = -1; p.volume = volume; p.prepareToPlay()
                    self.activateSession()
                    if p.play() {
                        self.player = p; self.currentTone = tone; self.isPlaying = true
                    } else { self.fail("播放未能启动，请检查音频输出或静音键") }
                } catch { self.fail("音频初始化失败：\(error.localizedDescription)") }
            }
        }
    }
    func pause() {
        if isLoading { token += 1; isLoading = false }
        player?.pause()
        isPlaying = false
    }
    func setVolume(_ v: Float) { player?.volume = max(0, min(1, v)) }
    func stopAll() {
        token += 1; isLoading = false; isPlaying = false
        player?.stop(); player = nil; currentTone = nil
        deactivateSession()
    }
    private func fail(_ msg: String) { isPlaying = false; errorText = msg }
    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        do { try s.setCategory(.playback, mode: .default, options: []); try s.setActive(true); sessionOn = true }
        catch { }     // 激活失败也继续尝试播放（降级）
    }
    private func deactivateSession() {
        guard sessionOn else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        sessionOn = false
    }
}
struct FunNoiseView: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("bb.noise.tone") private var toneRaw = 0
    @AppStorage("bb.noise.volume") private var volume = 0.7
    @AppStorage("bb.noise.minutes") private var minutes = 0
    @StateObject private var engine = NoiseAudioEngine()
    @State private var remaining: TimeInterval = 0
    @State private var total: TimeInterval = 0
    @State private var endDate: Date?
    @State private var ticker: Timer?
    @State private var finished = false
    private var tone: NoiseTone { NoiseTone(rawValue: toneRaw) ?? .white }
    private var timerOn: Bool { minutes > 0 && total > 0 }
    private var countdownProgress: Double { total > 0 ? min(1, max(0, remaining / total)) : 0 }
    private var statusText: String {
        if engine.isLoading { return "正在生成音频…" }
        if engine.isPlaying { return "播放中 · 循环" }
        return remaining > 0 ? "已暂停" : "准备就绪"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "moon.zzz.fill", colors: tone.colors,
                           title: "白噪音助眠", subtitle: tone.desc)
                toneCard
                playerCard
                volumeCard
                timerCard
                if let msg = engine.errorText { errorCard(msg) }
                tipCard
            }
            .padding(.horizontal, BBSpacing.screen).padding(.top, 8).padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("白噪音")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if minutes > 0 { total = TimeInterval(minutes * 60); if remaining <= 0 { remaining = total } }
        }
        .onChange(of: volume) { v in engine.setVolume(Float(v)) }
        .onDisappear { stopTicker(); engine.stopAll() }
    }
    private var toneCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("音色", icon: tone.icon, colors: tone.colors)
                BBSegmented(options: [(NoiseTone.white.title, 0), (NoiseTone.pink.title, 1),
                                      (NoiseTone.brown.title, 2)],
                            selection: Binding(get: { toneRaw }, set: { pick($0) }))
                HStack(spacing: 8) {
                    BBPill(text: tone.title, color: tone.accent)
                    Text(tone.desc).font(BBFont.cap(11)).foregroundColor(.secondary).lineLimit(2)
                }
            }
        }
    }
    private var playerCard: some View {
        BBCard {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    BBPill(text: statusText, color: engine.isPlaying ? Theme.success : Theme.warning)
                    if timerOn { BBPill(text: "剩余 " + NoiseTimer.clock(remaining), color: tone.accent) }
                    Spacer()
                }
                ZStack {
                    if timerOn {
                        BBRing(progress: countdownProgress, lineWidth: 4, colors: tone.colors)
                            .scaleEffect(2.15).frame(width: 198, height: 198)
                    } else {
                        Circle().strokeBorder(Color.secondary.opacity(0.16), lineWidth: 9)
                            .frame(width: 198, height: 198)
                    }
                    Button(action: toggle) {
                        ZStack {
                            Circle().fill(Theme.gradient(tone.colors)).frame(width: 146, height: 146)
                                .shadow(color: tone.colors.last!.opacity(0.45), radius: 18, y: 8)
                            Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
                                .frame(width: 146, height: 146)
                            if engine.isLoading { ProgressView().tint(.white).scaleEffect(1.2) }
                            else {
                                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 50, weight: .bold)).foregroundColor(.white)
                                    .offset(x: engine.isPlaying ? 0 : 4)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                .frame(height: 214)
                if timerOn {
                    Text(NoiseTimer.clock(remaining))
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .monospacedDigit().foregroundStyle(Theme.gradient(tone.colors))
                }
                if finished {
                    Text("定时结束，已自动停止播放 🌙")
                        .font(BBFont.cap(12)).foregroundColor(Theme.success)
                }
                Text(engine.isPlaying ? "轻触按钮暂停 · 音频由本机实时生成"
                                      : "轻触按钮开始 · 白/粉/棕三档音色可选")
                    .font(BBFont.cap(11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
    private var volumeCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                BBSectionHeader("音量", icon: "speaker.wave.2.fill", colors: tone.colors)
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill").font(.system(size: 12)).foregroundColor(.secondary)
                    Slider(value: $volume, in: 0...1).tint(tone.accent)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 13)).foregroundColor(.secondary)
                }
                HStack {
                    Text("实时调整音量，不会打断播放").font(BBFont.cap(11)).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int((volume * 100).rounded()))%").font(BBFont.mono).foregroundColor(tone.accent)
                }
            }
        }
    }
    private var timerCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("定时关闭", icon: "timer", colors: tone.colors)
                HStack(spacing: 7) {
                    ForEach(NoiseTimer.presets, id: \.self) { m in
                        BBChip(text: NoiseTimer.label(m), selected: minutes == m) { selectMinutes(m) }
                    }
                }
                if timerOn {
                    BBMeter(value: countdownProgress, colors: tone.colors, height: 8)
                    BBKV(key: "剩余时间", value: NoiseTimer.clock(remaining))
                } else {
                    Text("倒计时结束后自动停止播放，适合入睡前使用")
                        .font(BBFont.cap(11)).foregroundColor(.secondary)
                }
            }
        }
    }
    private func errorCard(_ msg: String) -> some View {
        BBCard {
            VStack(alignment: .leading, spacing: 8) {
                BBSectionHeader("音频提示", icon: "exclamationmark.triangle.fill",
                                colors: [Theme.warning, Color(hex: 0xFF7A18)])
                Text(msg).font(BBFont.cap(12)).foregroundColor(.secondary)
                Text("已自动降级为静音模式，页面其余功能可正常使用")
                    .font(BBFont.cap(10)).foregroundColor(.secondary)
            }
        }
    }
    private var tipCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                BBSectionHeader("说明", icon: "lightbulb.fill", colors: tone.colors)
                BBRow(title: "音频来源", icon: "waveform.path", value: "本机实时生成", colors: tone.colors)
                Divider().overlay(Theme.hairline(scheme == .dark))
                BBRow(title: "循环方式", icon: "repeat", value: "首尾淡入淡出无缝循环", colors: tone.colors)
                Divider().overlay(Theme.hairline(scheme == .dark))
                BBRow(title: "退出页面", icon: "stop.circle.fill", value: "自动停止并释放会话",
                      colors: [Theme.danger, Color(hex: 0xFF3D71)])
            }
        }
    }
    // MARK: 逻辑
    private func pick(_ raw: Int) {
        let next = NoiseTone(rawValue: raw) ?? .white
        toneRaw = next.rawValue
        guard engine.isPlaying || engine.isLoading else { return }
        engine.play(tone: next, volume: Float(volume))
    }
    private func toggle() {
        if engine.isPlaying {
            BBHaptic.select(); syncRemaining(); engine.pause(); stopTicker()
        } else {
            BBHaptic.tap()
            finished = false
            engine.play(tone: tone, volume: Float(volume))
            if minutes > 0 {
                if remaining <= 0 { total = TimeInterval(minutes * 60); remaining = total }
                startTicker()
            }
        }
    }
    private func selectMinutes(_ m: Int) {
        minutes = m
        stopTicker()
        finished = false
        if m <= 0 { total = 0; remaining = 0; endDate = nil; return }
        total = TimeInterval(m * 60)
        remaining = total
        if engine.isPlaying { startTicker() }
    }
    private func startTicker() {
        stopTicker()
        guard remaining > 0 else { return }
        endDate = Date().addingTimeInterval(remaining)
        let t = Timer(timeInterval: 0.25, repeats: true) { _ in
            DispatchQueue.main.async { tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }
    private func tick() {
        guard let end = endDate else { return }
        if !engine.isPlaying && !engine.isLoading { stopTicker(); endDate = nil; return }
        let left = end.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0; endDate = nil; stopTicker(); finished = true
            engine.pause()
            BBHaptic.success()
        } else { remaining = left }
    }
    private func syncRemaining() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
    }
}
