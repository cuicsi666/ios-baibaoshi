import Foundation
import AVFoundation
import UIKit

// MARK: - NES 引擎（InfoNES core 桥 + 音频 + 游戏库）
// 帧渲染由 NESScreenUIView（CADisplayLink 直驱）负责

final class NESEngine: ObservableObject {
    static let shared = NESEngine()

    @Published var running = false
    @Published var soundOn = true
    @Published var currentGame = ""
    @Published var errorMessage = ""

    private var audioEngine: AVAudioEngine?

    private init() {}

    // MARK: 启动 / 停止

    func start(rom: URL) {
        stop()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        nes_set_sav_dir(docs.path)
        AppLog.log("NES", "启动游戏: \(rom.lastPathComponent)")
        guard nes_start(rom.path) == 0 else {
            let err = nes_last_error()
            AppLog.error("NES", "nes_start 失败 code=\(err) rom=\(rom.lastPathComponent)")
            errorMessage = "游戏加载失败（代码 \(err)），请重试或换一个游戏"
            return
        }
        currentGame = rom.deletingPathExtension().lastPathComponent
        running = true
        startAudioIfNeeded()
        AppLog.log("NES", "启动成功 rate=\(nes_sample_rate())")
    }

    func stop() {
        guard running else { return }
        AppLog.log("NES", "停止: \(currentGame)")
        nes_stop()
        running = false
        stopAudio()
    }

    // MARK: 音频（AVAudioSourceNode 拉环形缓冲，引擎自动重采样）

    private func startAudioIfNeeded() {
        guard audioEngine == nil, soundOn else { return }
        do {
            let engine = AVAudioEngine()
            let rate = Double(nes_sample_rate())
            guard let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                          sampleRate: rate, channels: 1, interleaved: true) else {
                AppLog.error("NES", "音频格式创建失败 rate=\(rate)")
                return
            }
            let src = AVAudioSourceNode(format: fmt) { [weak self] _, _, frameCount, ablPtr -> OSStatus in
                guard let self = self else { return noErr }
                let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
                guard let mData = abl[0].mData else { return noErr }
                let out = mData.assumingMemoryBound(to: Int16.self)
                let total = Int(frameCount)
                let got = Int(nes_audio_pull(out, Int32(total)))
                if got < total {
                    for i in got..<total { out[i] = 0 }
                }
                return noErr
            }
            engine.attach(src)
            engine.connect(src, to: engine.mainMixerNode, format: fmt)
            engine.prepare()
            try engine.start()
            audioEngine = engine
            AppLog.log("NES", "音频引擎启动 rate=\(rate)")
        } catch {
            AppLog.error("NES", "音频启动失败: \(error.localizedDescription)")
        }
    }

    private func stopAudio() {
        audioEngine?.stop()
        audioEngine = nil
    }

    func toggleSound() {
        soundOn.toggle()
        AppLog.log("NES", "声音切换: \(soundOn ? "开" : "关")")
        if soundOn, running { startAudioIfNeeded() } else { stopAudio() }
    }

    // MARK: 手柄

    func setPad(_ bits: UInt32) { nes_set_pad(bits) }

    // MARK: 游戏库

    static func romList() -> [(name: String, rom: URL, icon: URL?)] {
        guard let romDir = Bundle.main.url(forResource: "ROMs", withExtension: nil) else {
            AppLog.error("NES", "ROMs 目录缺失")
            return []
        }
        let icons = Bundle.main.url(forResource: "NESIcons", withExtension: nil)
        let files = (try? FileManager.default.contentsOfDirectory(at: romDir, includingPropertiesForKeys: nil)) ?? []
        let list = files
            .filter { $0.pathExtension.lowercased() == "nes" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { rom -> (name: String, rom: URL, icon: URL?) in
                let icon = icons?.appendingPathComponent(rom.deletingPathExtension().lastPathComponent + ".png")
                return (rom.deletingPathExtension().lastPathComponent, rom, icon)
            }
        AppLog.log("NES", "游戏库加载 \(list.count) 个")
        return list
    }
}
