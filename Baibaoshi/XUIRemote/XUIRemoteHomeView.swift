import SwiftUI

// XUI 遥控容器页（原独立 App 的遥控 + 手柄双 Tab）

struct XUIRemoteHomeView: View {
    var body: some View {
        TabView {
            XUIControlView()
                .tabItem { Label("遥控", systemImage: "cpu.fill") }
            GamepadView()
                .tabItem { Label("游戏", systemImage: "gamecontroller.fill") }
        }
    }
}
