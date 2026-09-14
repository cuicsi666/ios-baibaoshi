import SwiftUI
import WebKit

// MARK: - XVP 播放器（原 ObjC 壳的 SwiftUI 重制）
// WKWebView 全屏壳：15 分钟无操作回主页 · 进后台回主页 · 任务快照遮罩防偷看
// 时间密码等交互逻辑由前端 index.html 处理

final class XVPWebView: WKWebView {
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
}

struct XVPPlayerView: View {
    var body: some View {
        XVPWebViewWrapper()
            .ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                NotificationCenter.default.post(name: .xvpGoHome, object: nil)
            }
    }
}

extension Notification.Name {
    static let xvpGoHome = Notification.Name("xvpGoHome")
    static let xvpTouch = Notification.Name("xvpTouch")
}

struct XVPWebViewWrapper: UIViewControllerRepresentable {
    let reloadToken: Int

    func makeUIViewController(context: Context) -> XVPViewController { XVPViewController() }
    func updateUIViewController(_ vc: XVPViewController, context: Context) {}
}

/// 原 RootVC 移植：WebView + 15 分钟无操作锁定 + 后台回主页 + JS alert 桥接
class XVPViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private var idleTimer: Timer?

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsPictureInPictureMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view = webView

        loadHome()
        resetIdleTimer()

        NotificationCenter.default.addObserver(self, selector: #selector(goHome),
                                               name: .xvpGoHome, object: nil)
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTouch))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func loadHome() {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    @objc private func onTouch() { resetIdleTimer() }

    /// 15 分钟无操作 → 回主页（重新经过前端时间密码）
    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: false) { [weak self] _ in
            self?.loadHome()
        }
    }

    @objc private func goHome() { loadHome() }

    // JS alert 桥接
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let ac = UIAlertController(title: "XVP", message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(ac, animated: true)
    }

    deinit { idleTimer?.invalidate() }
}
