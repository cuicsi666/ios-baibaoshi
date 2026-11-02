import SwiftUI
import WebKit

/// 内嵌网页卡片：本地资源 + 顶部图标导航
struct WebCardView: View {
    let title: String
    let siteID: String
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var reloadToken = UUID()
    @Environment(\.colorScheme) private var scheme

    private func resolve(_ attempt: Int) {
        if let u = LocalSiteServer.shared.url(for: siteID) {
            url = u
            return
        }
        guard attempt < 20 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { resolve(attempt + 1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    BBHaptic.tap()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    BBHaptic.tap()
                    reloadToken = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.cardBg(scheme == .dark))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.stroke(scheme == .dark)).frame(height: 0.5)
            }

            if let url {
                SiteWebView(url: url, reloadToken: reloadToken)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在准备本地站点…").font(.system(size: 13)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cardBg(scheme == .dark))
            }
        }
        .background(Theme.cardBg(scheme == .dark))
        .onAppear { resolve(0) }
    }
}

struct SiteWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: UUID

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.allowsBackForwardNavigationGestures = false
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        if context.coordinator.lastToken != reloadToken {
            context.coordinator.lastToken = reloadToken
            wv.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastToken = UUID()
    }
}
