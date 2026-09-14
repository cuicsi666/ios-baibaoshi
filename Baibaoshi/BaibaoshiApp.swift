import SwiftUI
import UserNotifications

@main
struct BaibaoshiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var volume = VolumeMonitor()
    @StateObject private var router = RouterPoller()
    @StateObject private var idioms = IdiomStore()
    @StateObject private var ble = BLEManager.shared
    @StateObject private var monitor = BatteryMonitor.shared
    @StateObject private var chargeHistory = ChargeHistory.shared
    @StateObject private var theme = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(volume)
                .environmentObject(router)
                .environmentObject(idioms)
                .environmentObject(ble)
                .environmentObject(monitor)
                .environmentObject(chargeHistory)
                .preferredColorScheme(theme.scheme)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 充电监控
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.shared.requestAuthorization()
        BatteryMonitor.shared.start()
        // 后台保活（定位 + 充电音频）
        KeepAliveService.shared.applySettings()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
