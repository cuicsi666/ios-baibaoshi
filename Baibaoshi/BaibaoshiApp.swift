import SwiftUI

// V17 启动探针：逐项初始化，屏幕实时显示走到哪一步
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

    private let names = ["ThemeManager", "RouterPoller", "IdiomStore",
                         "BLEManager(蓝牙)", "BatteryMonitor", "ChargeHistory", "ModuleRegistry(36模块)"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if done, let r = router, let i = idioms, let b = ble,
               let m = monitor, let c = history, let t = theme {
                RootView()
                    .environmentObject(r)
                    .environmentObject(i)
                    .environmentObject(b)
                    .environmentObject(m)
                    .environmentObject(c)
                    .preferredColorScheme(t.preferredScheme)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("V17 启动探针 17.0")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                            .padding(.bottom, 8)
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, s in
                            Text(s)
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundColor(s.hasPrefix("✅") ? .green : (s.hasPrefix("▶︎") ? .white : .red))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
        }
        .onAppear { next(0) }
    }

    private func perform(_ i: Int) {
        switch i {
        case 0: theme = ThemeManager.shared
        case 1: router = RouterPoller()
        case 2: idioms = IdiomStore()
        case 3: ble = BLEManager.shared
        case 4: monitor = BatteryMonitor.shared
        case 5: history = ChargeHistory.shared
        default: _ = ModuleRegistry.all.count
        }
    }

    private func next(_ i: Int) {
        guard i < names.count else {
            lines.append("✅ 全部通过，加载首页")
            done = true
            return
        }
        lines.append("▶︎ \(names[i]) …")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            perform(i)
            lines.append("✅ \(names[i]) 完成")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { next(i + 1) }
        }
    }
}
