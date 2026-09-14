import Foundation
import CoreLocation
import AVFoundation
import Combine

/// 后台保活服务：定位（始终授权·低功耗） + 充电时静音音频 双保险
/// 防止 iOS 冻结 App —— 电管家播报、XUI 蓝牙、流文连接全时段在线
final class KeepAliveService: NSObject, ObservableObject {
    static let shared = KeepAliveService()

    @Published var active = false
    @Published var locationAuth: CLAuthorizationStatus = .notDetermined
    @Published var audioOn = false

    private let lm = CLLocationManager()
    private var player: AVAudioPlayer?
    private var started = false

    var enabled: Bool { UserDefaults.standard.object(forKey: "bb.keepAlive") as? Bool ?? true }

    private override init() {
        super.init()
        lm.delegate = self
    }

    /// 应用启动 / 设置变更时调用
    func applySettings() {
        guard enabled else { stopAll(); return }
        startLocation()
        // 音频保活由 BatteryMonitor 按充电状态触发
    }

    // MARK: 定位保活（低功耗常驻）

    private func startLocation() {
        lm.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        lm.distanceFilter = CLLocationDistanceMax
        lm.pausesLocationUpdatesAutomatically = false
        lm.requestAlwaysAuthorization()
        guard CLLocationManager.locationServicesEnabled() else { return }
        lm.allowsBackgroundLocationUpdates = true
        lm.startUpdatingLocation()
        started = true
        refreshActive()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuth = manager.authorizationStatus
        refreshActive()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func refreshActive() {
        let ok = enabled && started &&
                 (locationAuth == .authorizedAlways || locationAuth == .authorizedWhenInUse)
        DispatchQueue.main.async { self.active = ok }
    }

    // MARK: 静音音频保活（充电时，BatteryMonitor 调用）

    func startAudioKeepAlive() {
        guard enabled, player == nil else { return }
        do {
            let ses = AVAudioSession.sharedInstance()
            try ses.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try ses.setActive(true)
            if let url = Bundle.main.url(forResource: "keepalive", withExtension: "wav") {
                let p = try AVAudioPlayer(contentsOf: url)
                p.numberOfLoops = -1
                p.volume = 1.0
                p.play()
                player = p
                audioOn = true
            }
        } catch { }
    }

    func stopAudioKeepAlive() {
        guard let p = player else { return }
        p.stop()
        player = nil
        audioOn = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func stopAll() {
        lm.stopUpdatingLocation()
        started = false
        stopAudioKeepAlive()
        active = false
    }
}
