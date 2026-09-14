import Foundation
import UserNotifications

/// 本地通知封装：5% 步进播报 / 充满提醒
final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error { print("通知授权失败: \(error)") }
        }
    }

    func send(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(req)
    }

    func checkAuth(_ completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { s in
            DispatchQueue.main.async { completion(s.authorizationStatus == .authorized) }
        }
    }
}
