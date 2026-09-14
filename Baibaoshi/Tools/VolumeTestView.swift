import SwiftUI
import AVFoundation
import MediaPlayer

struct VolumeTestView: View {
    @EnvironmentObject var volume: VolumeMonitor
    @StateObject private var sine = SineEngine()
    @State private var playing: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PageHeader(icon: "speaker.wave.3.fill", colors: Theme.volume, title: "音量测试", subtitle: "实时监听系统音量 · 正弦波测试")

                ring
                controls
                wave
                tones
                tips
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onDisappear { sine.stop() }
    }

    // 大圆环音量表
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 22)
            Circle()
                .trim(from: 0, to: CGFloat(volume.volume))
                .stroke(Theme.gradient(Theme.volume), style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: volume.volume)
                .shadow(color: Theme.volume[0].opacity(0.6), radius: 10)
            VStack(spacing: 2) {
                Text("\(Int(volume.volume * 100))")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                Text("SYSTEM VOLUME").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 50)
        .padding(.top, 6)
    }

    // 音量调节按钮
    private var controls: some View {
        HStack(spacing: 14) {
            VolumeButton(icon: "speaker.slash.fill", label: "静音") { VolumeController.set(Float(0)) }
            VolumeButton(icon: "minus", label: "-10%") { VolumeController.set(max(0, volume.volume - 0.1)) }
            VolumeButton(icon: "plus", label: "+10%") { VolumeController.set(min(1, volume.volume + 0.1)) }
            VolumeButton(icon: "speaker.wave.3.fill", label: "最大") { VolumeController.set(Float(1)) }
        }
        .padding(.horizontal, 4)
    }

    // 实时波形
    private var wave: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("实时波形").font(.headline)
            WaveCanvas(active: playing != nil, amplitude: volume.volume)
                .frame(height: 90)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        }
        .padding(.horizontal, 4)
    }

    // 测试音
    private var tones: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("测试音").font(.headline)
            Text("左右声道独立播放，验证扬声器与音量档位").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 10) {
                ToneButton(title: "左声道", sub: "1kHz", active: playing == "L") { play("L") }
                ToneButton(title: "右声道", sub: "1kHz", active: playing == "R") { play("R") }
                ToneButton(title: "立体声", sub: "1kHz", active: playing == "ST") { play("ST") }
            }
            HStack(spacing: 10) {
                ToneButton(title: "扫频 20Hz→18kHz", sub: "全频段", active: playing == "SW") { play("SW") }
                ToneButton(title: "停止", sub: "", active: false) {
                    sine.stop(); playing = nil
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("也可以直接按手机物理音量键，圆环会实时跟随", systemImage: "lightbulb.fill")
            Label("扫频可听出扬声器各频段表现，发闷=高频缺失", systemImage: "waveform.path.ecg")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .padding(.horizontal, 4)
    }

    private func play(_ ch: String) {
        sine.stop()
        playing = ch
        switch ch {
        case "L": sine.play(freq: 1000, seconds: 1.6, channel: 0)
        case "R": sine.play(freq: 1000, seconds: 1.6, channel: 1)
        case "ST": sine.play(freq: 1000, seconds: 1.6, channel: -1)
        case "SW": sine.play(freq: 20, sweepTo: 18000, seconds: 2.5, channel: -1)
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if playing == ch { playing = nil }
        }
    }
}

// MARK: - 音量控制（MPVolumeView hack）
enum VolumeController {
    static func set(_ v: Float) {
        let mpv = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
            window.addSubview(mpv)
            let slider = mpv.subviews.first(where: { $0 is UISlider }) as? UISlider
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                slider?.setValue(v, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { mpv.removeFromSuperview() }
            }
        }
    }
}

// MARK: - 正弦波引擎
final class SineEngine: ObservableObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var ready = false

    private func setup() throws {
        guard !ready else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [])
        try session.setActive(true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        ready = true
    }

    func play(freq: Float, sweepTo: Float? = nil, seconds: Double, channel: Int) {
        do {
            try setup()
            try engine.start()
            player.stop()
            let sr: Double = 44100
            let frames = AVAudioFrameCount(sr * seconds)
            guard let buf = AVAudioPCMBuffer(pcmFormat: player.outputFormat(forBus: 0), frameCapacity: frames) else { return }
            buf.frameLength = frames
            let ch = Int(buf.format.channelCount)
            var phase: Double = 0
            for f in 0..<Int(frames) {
                let t = Double(f) / sr
                var fq = Double(freq)
                if let to = sweepTo { fq = Double(freq) * pow(Double(to) / Double(freq), t / seconds) }
                phase += 2 * .pi * fq / sr
                let v = Float(sin(phase)) * 0.85
                let data = buf.floatChannelData!
                for c in 0..<ch {
                    data[c][f] = (channel == -1 || channel == c) ? v : 0
                }
            }
            player.scheduleBuffer(buf, at: nil, options: .interrupts)
            player.play()
        } catch { }
    }

    func stop() { player.stop() }
}

// MARK: - 波形画布
struct WaveCanvas: View {
    var active: Bool
    var amplitude: Float

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                var path = Path()
                let amp = active ? CGFloat(amplitude) * size.height * 0.42 : size.height * 0.02
                for i in 0..<Int(size.width) {
                    let x = CGFloat(i)
                    let env = active ? (0.6 + 0.4 * sin(t * 3)) : 1
                    let y = size.height / 2
                        + CGFloat(sin(Double(i) * 0.045 + t * 6)) * amp * env
                        + CGFloat(sin(Double(i) * 0.011 - t * 2)) * amp * 0.35
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(path, with: .color(Theme.volume[0]), lineWidth: 2.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 小按钮
struct VolumeButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            pressed = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pressed = false }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.gradient(Theme.volume)))
            .scaleEffect(pressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: pressed)
        }
        .buttonStyle(.plain)
    }
}

struct ToneButton: View {
    let title: String
    let sub: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if !sub.isEmpty { Text(sub).font(.caption2).opacity(0.7) }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? AnyShapeStyle(Theme.gradient(Theme.music)) : AnyShapeStyle(.white.opacity(0.1)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
