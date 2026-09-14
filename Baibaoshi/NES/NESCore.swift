import Foundation
import AVFoundation
import CoreGraphics
import UIKit

// MARK: - NES 引擎（InfoNES core 桥 + 音频 + 帧渲染）

final class NESEngine: ObservableObject {
    static let shared = NESEngine()

    @Published var frameImage: CGImage?
    @Published var running = false
    @Published var soundOn = true
    @Published var currentGame = ""

    static let width = 256
    static let height = 240

    private var frameBuf: UnsafeMutablePointer<UInt16>!
    private var rgbaBuf: UnsafeMutablePointer<UInt8>!
    private var displayLink: CADisplayLink?
    private var audioEngine: AVAudioEngine?
    private var lastFrameTick = 0

    private init() {
        frameBuf = UnsafeMutablePointer<UInt16>.allocate(capacity: 256 * 240)
        rgbaBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 256 * 240 * 4)
    }

    deinit {
        frameBuf?.deallocate()
        rgbaBuf?.deallocate()
    }

    // MARK: 启动 / 停止

    func start(rom: URL) {
        stop()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        nes_set_sav_dir(docs.path)
        guard nes_start(rom.path) == 0 else { return }
        currentGame = rom.deletingPathExtension().lastPathComponent
        running = true
        startAudioIfNeeded()
        startDisplayLink()
    }

    func stop() {
        guard running else { return }
        nes_stop()
        running = false
        stopAudio()
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: 帧渲染（CADisplayLink 拉 WorkFrame → CGImage）

    private func startDisplayLink() {
        let dl = CADisplayLink(target: self, selector: #selector(renderTick))
        dl.preferredFramesPerSecond = 60
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    @objc private func renderTick() {
        guard running, nes_running() == 1 else { return }
        let _ = nes_frame_copy(frameBuf)

        let w = Self.width, h = Self.height
        for i in 0..<(w * h) {
            let px = frameBuf[i]
            let r = UInt8((px >> 11) & 0x1F), g = UInt8((px >> 5) & 0x3F), b = UInt8(px & 0x1F)
            rgbaBuf[i * 4] = UInt8((Int(r) * 255) / 31)
            rgbaBuf[i * 4 + 1] = UInt8((Int(g) * 255) / 63)
            rgbaBuf[i * 4 + 2] = UInt8((Int(b) * 255) / 31)
            rgbaBuf[i * 4 + 3] = 255
        }

        let ctx = CGContext(data: rgbaBuf, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        frameImage = ctx?.makeImage()
    }

    // MARK: 音频（AVAudioSourceNode 拉环形缓冲，引擎自动重采样）

    private func startAudioIfNeeded() {
        guard audioEngine == nil, soundOn else { return }
        do {
            let engine = AVAudioEngine()
            let rate = Double(nes_sample_rate())
            guard let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                          sampleRate: rate, channels: 1, interleaved: true) else { return }
            let src = AVAudioSourceNode(format: fmt) { [weak self] _, _, frameCount, ablPtr -> OSStatus in
                guard let self = self else { return noErr }
                let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
                guard let mData = abl[0].mData else { return noErr }
                let out = mData.assumingMemoryBound(to: Int16.self)
                let got = nes_audio_pull(out, Int32(frameCount))
                if got < Int(frameCount) {
                    for i in got..<Int(frameCount) { out[i] = 0 }
                }
                return noErr
            }
            engine.attach(src)
            engine.connect(src, to: engine.mainMixerNode, format: fmt)
            engine.prepare()
            try engine.start()
            audioEngine = engine
        } catch {
            print("NES 音频启动失败: \(error)")
        }
    }

    private func stopAudio() {
        audioEngine?.stop()
        audioEngine = nil
    }

    func toggleSound() {
        soundOn.toggle()
        if soundOn { startAudioIfNeeded() } else { stopAudio() }
    }

    // MARK: 手柄

    func setPad(_ bits: UInt32) { nes_set_pad(bits) }

    // MARK: 游戏库

    static func romList() -> [(name: String, rom: URL, icon: URL?)] {
        guard let romDir = Bundle.main.url(forResource: "ROMs", withExtension: nil) else { return [] }
        let icons = Bundle.main.url(forResource: "NESIcons", withExtension: nil)
        let files = (try? FileManager.default.contentsOfDirectory(at: romDir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "nes" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { rom in
                let icon = icons?.appendingPathComponent(rom.deletingPathExtension().lastPathComponent + ".png")
                return (rom.deletingPathExtension().lastPathComponent, rom, icon)
            }
    }
}
