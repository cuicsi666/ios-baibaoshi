import SwiftUI

// V18 分层渲染探针：逐层测试 SwiftUI 组件，定位首页白屏
@main
struct BaibaoshiApp: App {
    var body: some Scene {
        WindowGroup { BootProbe() }
    }
}

struct BootProbe: View {
    @State private var lines: [String] = []
    @State private var done = false
    @State private var router: RouterPoller?
    @State private var idioms: IdiomStore?
    @State private var ble: BLEManager?
    @State private var monitor: BatteryMonitor?
    @State private var history: ChargeHistory?
    @State private var theme: ThemeManager?

    var body: some View {
        Group {
            if done, let r = router, let i = idioms, let b = ble,
               let m = monitor, let c = history, let t = theme {
                SectionProbe(router: r, idioms: i, ble: b, monitor: m, history: c, theme: t)
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("V18 启动探针").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(.yellow)
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, s in
                                Text(s).font(.system(size: 15, design: .monospaced)).foregroundColor(.green)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    }
                }
            }
        }
        .onAppear { boot() }
    }

    private func boot() {
        theme = ThemeManager.shared
        router = RouterPoller()
        idioms = IdiomStore()
        ble = BLEManager.shared
        monitor = BatteryMonitor.shared
        history = ChargeHistory.shared
        _ = ModuleRegistry.all.count
        lines.append("✅ 全部初始化完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { done = true }
    }
}

struct SectionProbe: View {
    let router: RouterPoller
    let idioms: IdiomStore
    let ble: BLEManager
    let monitor: BatteryMonitor
    let history: ChargeHistory
    let theme: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                title("1 · 基础 Text")
                ProbeBox { Text("基础渲染 OK").foregroundColor(.white) }

                title("2 · ScrollView")
                ProbeBox { ScrollView { Text("滚动 OK").foregroundColor(.white) } .frame(height: 44) }

                title("3 · NavigationStack")
                ProbeBox { NavigationStack { Text("导航容器 OK").foregroundColor(.white) } .frame(height: 60) }

                title("4 · Nav + principal toolbar")
                Section {
                    NavigationStack {
                        Text("principal OK").foregroundColor(.white)
                            .toolbar { ToolbarItem(placement: .principal) { Text("标题").foregroundColor(.white) } }
                    }
                    .frame(height: 80)
                }

                title("5 · Nav + topBarTrailing")
                Section {
                    NavigationStack {
                        Text("trailing OK").foregroundColor(.white)
                            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("B") {} } }
                    }
                    .frame(height: 80)
                }

                title("6 · BBAuroraBackground")
                ProbeBox { BBAuroraBackground(scheme: .light).frame(height: 60) }

                title("7 · 简化首页（无 NavigationStack）")
                ProbeBox {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("星辰 · 简化首页").font(.system(size: 24, weight: .bold)).foregroundColor(.black)
                            ForEach(Array(ModuleRegistry.all.prefix(6))) { m in
                                HStack(spacing: 8) {
                                    Image(systemName: m.icon).foregroundColor(.white)
                                        .frame(width: 30, height: 30)
                                        .background(Circle().fill(Color.blue))
                                    Text(m.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.black)
                                    Spacer()
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 320)
                    .background(Color(hex: 0xF4F6FB))
                }

                title("8 · 完整 RootView")
                Section {
                    RootView()
                        .environmentObject(router)
                        .environmentObject(idioms)
                        .environmentObject(ble)
                        .environmentObject(monitor)
                        .environmentObject(history)
                        .preferredColorScheme(theme.preferredScheme)
                        .frame(height: 420)
                }
            }
            .padding(14)
        }
        .background(Color.black)
    }

    private func title(_ s: String) -> some View {
        Text(s).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.yellow)
    }

    private struct ProbeBox<C: View>: View {
        let content: C
        init(@ViewBuilder content: () -> C) { self.content = content() }
        var body: some View {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
    }
}
