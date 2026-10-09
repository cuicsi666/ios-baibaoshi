import SwiftUI
import UIKit
import Flutter

// MARK: - 通用内嵌引擎（Flutter add-to-app）
// 把任意 Flutter App（已编译为 xcframework 打进主包）在百宝箱内部打开。
// module 名（Dart 入口）通过工程注册：每个内嵌 App 唯一 routeName。

/// 已注册的内嵌 Flutter 应用
struct EmbeddedApp {
    let id: String
    let title: String
    let icon: String
    let colors: [Color]
    let engineRoute: String  // Dart initialRoute，须与 Flutter 端 pushRouteName 对应
}

enum ShellEmbed {
    /// 全局单例引擎持有（保证后台常驻不重载，多卡片复用同一引擎）
    static var engine: FlutterEngine?   // 只保留一个活跃引擎（当前设计：单 Flutter 模块）

    /// 懒加载 / 复用引擎
    static func engine(for route: String) -> FlutterEngine {
        if let e = engine { return e }
        let e = FlutterEngine(name: "shell_embed", project: nil)
        e.run(withEntrypoint: nil, libraryURI: nil, initialRoute: route)
        engine = e
        return e
    }

    /// 释放引擎（内存回收）
    static func disposeEngine() {
        engine?.destroy()
        engine = nil
    }

    /// 把远程关键词转发给 Flutter 哔哩（通过 method channel）
    static func sendBiliKeyword(action: String, keyword: String) {
        guard let e = engine else { return }
        let channel = FlutterMethodChannel(name: "cuicsi/biliremote",
                                           binaryMessenger: e.binaryMessenger)
        channel.invokeMethod("remoteOpen", arguments: ["action": action, "keyword": keyword])
    }
}

/// SwiftUI 容器：承载一个 FlutterViewController
struct ShellEmbedView: UIViewControllerRepresentable {
    let route: String

    func makeUIViewController(context: Context) -> FlutterViewController {
        let engine = ShellEmbed.engine(for: route)
        let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        return vc
    }

    func updateUIViewController(_ uiViewController: FlutterViewController, context: Context) {}
}

/// 内嵌页面（导航容器 + 顶栏返回）
struct EmbeddedAppView: View {
    let app: EmbeddedApp
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShellEmbedView(route: app.engineRoute)
                .ignoresSafeArea(.container, edges: .bottom)

            // 顶栏返回浮层
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