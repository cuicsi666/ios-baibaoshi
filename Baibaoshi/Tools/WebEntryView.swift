import SwiftUI
import WebKit

// MARK: - 通用 WebView 页（AI 音乐等固定入口）
enum WebEntry: String {
    case music
    var url: URL {
        switch self {
        case .music: return URL(string: "http://6.6.6.130:8007/music/")!
        }
    }
    var title: String { "AI 音乐" }
    var icon: String { "music.note.list" }
    var colors: [Color] { Theme.music }
}

struct WebEntryView: View {
    let config: WebEntry

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(icon: config.icon, colors: config.colors, title: config.title, subtitle: config.url.absoluteString)
            WebView(url: config.url)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Theme.bgBottom.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { WebViewCache.shared.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button { UIApplication.shared.open(config.url) } label: { Image(systemName: "safari") }
            }
        }
    }
}

// MARK: - 导航站（随机逛 + 全站 WebView）
struct NavStationView: View {
    @ObservedObject private var nav = NavService.shared
    @State private var randomURL: URL?
    @State private var showRandom = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Button {
                    if let link = nav.randomLink(), let u = URL(string: link.url) {
                        randomURL = u
                        showRandom = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } label: {
                    HStack {
                        Image(systemName: "dice.fill").font(.title3)
                        Text("随机逛一个").font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.gradient(Theme.nav)))
                    .shadow(color: Theme.nav[0].opacity(0.5), radius: 8, y: 4)
                }
                .buttonStyle(.plain)

                Text("全站 \(nav.linksCount) 个站点 · \(nav.categories.count) 个分类")                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            WebView(url: URL(string: "http://6.6.6.130:8099")!)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Theme.bgBottom.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { WebViewCache.shared.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button { UIApplication.shared.open(URL(string: "http://6.6.6.130:8099")!) } label: { Image(systemName: "safari") }
            }
        }
        .sheet(isPresented: $showRandom) {
            if let u = randomURL { RandomSiteSheet(url: u) }
        }
    }
}

struct RandomSiteSheet: View {
    let url: URL
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.host ?? "站点")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { UIApplication.shared.open(url) } label: { Image(systemName: "safari") }
                    }
                }
        }
    }
}

// MARK: - WKWebView 封装
final class WebViewCache {
    static let shared = WebViewCache()
    weak var current: WKWebView?
    func reload() { current?.reload() }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsBackForwardNavigationGestures = true
        WebViewCache.shared.current = wv
        wv.load(URLRequest(url: url, timeoutInterval: 12))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        WebViewCache.shared.current = uiView
    }
}
