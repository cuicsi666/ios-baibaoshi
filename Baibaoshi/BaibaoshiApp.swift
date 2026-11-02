import SwiftUI

// 极简启动测试：不含任何业务初始化，只验证「包能不能跑起来」
@main
struct BaibaoshiApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                LinearGradient(colors: [Color(red: 0.13, green: 0.75, blue: 0.45),
                                        Color(red: 0.05, green: 0.55, blue: 0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                VStack(spacing: 18) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.white)
                    Text("星辰 · 启动测试 OK")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text("BUILD 16 · 极简启动壳")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
    }
}
