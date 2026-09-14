import Foundation
import AVFoundation

final class RecorderService: NSObject, ObservableObject {
    static let shared = RecorderService()
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    func startIfNeeded() {
        if isRecording { return }
        start()
    }

    func start() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(Int(Date().timeIntervalSince1970)).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.record()
            fileURL = url
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.elapsed = self?.recorder?.currentTime ?? 0
            }
        } catch {
            print("recorder start failed: \(error)")
        }
    }

    /// 停止录音并返回音频文件 URL；无录音时返回 nil
    func stop() -> URL? {
        timer?.invalidate()
        timer = nil
        guard let r = recorder, r.isRecording else {
            isRecording = false
            return nil
        }
        r.stop()
        isRecording = false
        let url = fileURL
        fileURL = nil
        return url
    }
}