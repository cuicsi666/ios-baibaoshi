import SwiftUI
import UserNotifications

@main
struct BaibaoshiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var router = RouterPoller()
    @StateObject private var idioms = IdiomStore()
    @StateObject private var ble = BLEManager.shared
    @StateObject private var monitor = BatteryMonitor.shared
    @StateObject private var chargeHistory = ChargeHistory.shared
    @StateObject private var theme = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                Color(hex: 0xEEF2F8).ignoresSafeArea()
                RootView()
                    .environmentObject(router)
                    .environmentObject(idioms)
                    .environmentObject(ble)
                    .environmentObject(monitor)
                    .environmentObject(chargeHistory)
            }
            .preferredColorScheme(theme.preferredScheme)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AppLog.log("Launch", "didFinishLaunching begin")

        // 重活延后，先让首帧渲染出来（避免权限/蓝牙/定位初始化阻塞主线程导致白屏）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            AppLog.log("Launch", "post-launch init start")
            NotificationManager.shared.requestAuthorization()
            BatteryMonitor.shared.start()
            KeepAliveService.shared.applySettings()
            AppLog.log("Launch", "post-launch init done")
        }

        // 启动 6 秒后无条件尝试上报一次日志，便于远程排查白屏
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            AppLog.log("Launch", "6s heartbeat, auto upload")
            AppLog.maybeAutoUpload()
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
