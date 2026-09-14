import SwiftUI
import WebKit

// MARK: - 龙虾帮：OpenClaw 控制台（原 ObjC 壳的 SwiftUI 重制）

struct ConsoleTarget: Identifiable {
    let id: Int
    let name: String
    let url: String
}

let consoleTargets: [ConsoleTarget] = [
    ConsoleTarget(id: 1, name: "主机控制台", url: "http://6.6.6.134:18789/#token=d5e77c013eb5cb13611c524e2e30936721db2ebe42c4a6f4"),
    ConsoleTarget(id: 2, name: "NAS 控制台", url: "http://6.6.6.130:18789/#token=2d2fe3cc314581f7600e37ca8e41532fc6cc8884eac648ac"),
    ConsoleTarget(id: 3, name: "备用控制台", url: "http://6.6.6.130:18791/#token=0454f6f5561707df502a5a3fa6328e14628562196f023f8c"),
]

struct WebAssistantView: View {
    @State private var selected = 0

    var body: some View {
        VStack(spacing: 0) {
            ConsoleWebView(url: consoleTargets[selected].url)
        }
        .navigationTitle("龙虾帮")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(Array(consoleTargets.enumerated()), id: \.offset) { i, t in
                        Button {
                            selected = i
                        } label: {
                            Label(t.name, systemImage: selected == i ? "checkmark" : "terminal")
                        }
                    }
                } label: {
                    Image(systemName: "terminal.fill")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("控制台", selection: $selected) {
                ForEach(Array(consoleTargets.enumerated()), id: \.offset) { i, t in
                    Text(t.name).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}

struct ConsoleWebView: UIViewRepresentable {
    let url: String

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsBackForwardNavigationGestures = true
        if let u = URL(string: url) {
            wv.load(URLRequest(url: u))
        }
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        if let u = URL(string: url), wv.url?.absoluteString.hasPrefix(url) != true {
            wv.load(URLRequest(url: u))
        }
    }
}
