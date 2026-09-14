import Foundation
import AVFoundation
import Combine
import SwiftUI

// MARK: - sysmon 数据模型
struct Sysmon: Codable {
    let ok: Int
    let host: String
    let model: String
    let cpu: Double
    let load1: Double
    let load5: Double
    let load15: Double
    let memTotal: Int
    let memUsed: Int
    let memBuff: Int
    let memAvail: Int
    let temp: Double?
    let uptime: Int
    let leases: Int

    enum CodingKeys: String, CodingKey {
        case ok, host, model, cpu, temp, uptime, leases
        case load1 = "load1", load5 = "load5", load15 = "load15"
        case memTotal = "mem_total", memUsed = "mem_used"
        case memBuff = "mem_buff", memAvail = "mem_avail"
    }
}

// MARK: - 路由器轮询
final class RouterPoller: ObservableObject {
    @Published var sys: Sysmon?
    @Published var history: [Double] = []      // CPU 历史
    @Published var online = false
    @AppStorage("router.url") var urlString: String = "http://6.6.6.1:8080/cgi-bin/sysmon"

    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let s = try? JSONDecoder().decode(Sysmon.self, from: data) else {
                DispatchQueue.main.async { self?.online = false }
                return
            }
            DispatchQueue.main.async {
                self.sys = s
                self.online = true
                self.history.append(s.cpu)
                if self.history.count > 60 { self.history.removeFirst(self.history.count - 60) }
            }
        }.resume()
    }
}

// MARK: - 系统音量监听
final class VolumeMonitor: ObservableObject {
    @Published var volume: Float = AVAudioSession.sharedInstance().outputVolume
    private var obs: NSKeyValueObservation?

    init() {
        let session = AVAudioSession.sharedInstance()
        obs = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                if let v = change.newValue { self?.volume = v }
            }
        }
    }
    deinit { obs?.invalidate() }
}

// MARK: - 成语轮换（60 秒自动）
final class IdiomStore: ObservableObject {
    @Published var index = Int.random(in: 0..<100)
    @Published var tick = 0
    static let interval: Double = 60

    var current: Idiom { Idioms.list[index % Idioms.list.count] }
    var progress: Double { Double(tick) / IdiomStore.interval }

    private var timer: Timer?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            if self.tick >= Int(IdiomStore.interval) { self.next() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }

    func next() {
        tick = 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            index = (index + 1 + Int.random(in: 0..<3)) % Idioms.list.count
        }
    }
}
