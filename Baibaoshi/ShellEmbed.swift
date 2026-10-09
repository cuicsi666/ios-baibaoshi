import SwiftUI
import UIKit
import Flutter

// MARK: - 通用内嵌引擎（Flutter add-to-app）
// 把任意 Flutter App（已编译为 xcframework 打进主包）在百宝箱内部打开。

struct EmbeddedApp {
    let id: String
    let title: String
    let icon: String
    let colors: [Color]
    let engineRoute: String  // Dart initialRoute，须与 Flutter 端 pushRouteName 对应
}

enum ShellEmbed {
    static var engine: FlutterEngine?
    static var ready = false

    /// 懒加载 / 复用引擎
    static func engine(for route: String) -> FlutterEngine {
        if let e = engine, ready { return e }
        AppLog.log("Embed", "创建引擎 route=\(route)")
        let project = FlutterDartProject()
        let e = FlutterEngine(name: "shell_embed_\(UUID().uuidString)",
                              project: project,
                              allowHeadlessExecution: true)
        let appRoute: String = route.isEmpty ? "/" : route
        let runOK = e.run(withEntrypoint: nil, initialRoute: appRoute)
        AppLog.log("Embed", "引擎 run: \(runOK)  route=\(appRoute)")
        registerDiagnosticHandler(engine: e)
        engine = e
        ready = runOK
        return e
    }

    /// 把远程关键词转发给 Flutter 哔哩（method channel）
    static func sendBiliKeyword(action: String, keyword: String) {
        guard let e = engine else { return }
        let channel = FlutterMethodChannel(name: "cuicsi/biliremote",
                                           binaryMessenger: e.binaryMessenger)
        channel.invokeMethod("remoteOpen", arguments: ["action": action, "keyword": keyword])
    }

    /// 注册哔哩→宿主的诊断日志接收（launchLog: 哔哩启动进度）
    static func registerDiagnosticHandler(engine e: FlutterEngine) {
        let channel = FlutterMethodChannel(name: "cuicsi/biliremote",
                                           binaryMessenger: e.binaryMessenger)
        channel.setMethodCallHandler { call, _ in
            if call.method == "launchLog" {
                let msg = call.arguments as? String ?? "?"
                AppLog.log("BiliLaunch", msg)
            }
        }
    }

    /// Swift → Flutter 消息通知（哔哩已进入）
    static func markEntered() {
        AppLog.log("Embed", "哔哩内嵌页面已呈现")
    }
}

/// SwiftUI 容器：承载 FlutterViewController
struct ShellEmbedView: UIViewControllerRepresentable {
    let route: String

    func makeUIViewController(context: Context) -> FlutterViewController {
        let engine = ShellEmbed.engine(for: route)
        let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        vc.view.backgroundColor = .systemBackground
        // add-to-app 白屏关键修复：确保控制器在窗口层级 + 触发首次布局
        vc.loadViewIfNeeded()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            ShellEmbed.markEntered()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: FlutterViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: FlutterViewController, coordinator: ()) {
        // 保留引擎（常驻），仅释放控制器视图
    }
}

/// 内嵌页面（导航容器 + 顶栏返回）
struct EmbeddedAppView: View {
    let app: EmbeddedApp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white.ignoresSafeArea()
            ShellEmbedView(route: app.engineRoute)
                .ignoresSafeArea(.container, edges: .bottom)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .clipShape(Circle())
                }
                .padding(.leading, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(true)
    }
}