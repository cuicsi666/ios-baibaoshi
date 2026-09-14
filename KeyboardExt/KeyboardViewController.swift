import UIKit
import Foundation

/// 流文键盘：轮询 App Group，把板子识别的文字逐字插入当前输入框
final class KeyboardViewController: UIInputViewController {

    // App Group keys（与宿主 App 约定一致，扩展内独立定义避免跨 target 引用）
    private static let kText = "ft_text"
    private static let kRev = "ft_rev"
    private static let kReset = "ft_reset"
    private static let kLast = "ft_last"

    private let group = UserDefaults(suiteName: "group.com.cuicsi.flowtext")
    private var lastRev = -1
    private var consumed = 0          // 本会话已插入的字符数
    private var timer: Timer?
    private var previewLabel: UILabel?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    private func setupUI() {
        view.backgroundColor = UIColor(white: 0.09, alpha: 1.0)

        // 预览条
        let preview = UILabel()
        preview.text = "流文 · 等待板子说话"
        preview.font = .systemFont(ofSize: 13)
        preview.textColor = UIColor(white: 0.75, alpha: 1)
        preview.numberOfLines = 2
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview)
        previewLabel = preview

        // 按键行
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        func key(_ title: String, _ action: Selector, _ bg: UIColor = UIColor(white: 0.22, alpha: 1)) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            b.setTitleColor(.white, for: .normal)
            b.backgroundColor = bg
            b.layer.cornerRadius = 10
            b.addTarget(self, action: action, for: .touchUpInside)
            return b
        }

        let newline = key("换行", #selector(newlineTapped))
        let back = key("⌫", #selector(backspaceTapped))
        let clear = key("丢弃", #selector(clearTapped), UIColor(white: 0.32, alpha: 1))
        let globe = key("🌐", #selector(globeTapped))

        for b in [newline, back, clear, globe] {
            b.heightAnchor.constraint(equalToConstant: 44).isActive = true
            stack.addArrangedSubview(b)
        }
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    /// 轮询 App Group：rev 变化 → 把新增文字插入输入框
    private func poll() {
        guard let g = group else { return }
        let rev = g.integer(forKey: Self.kRev)
        guard rev != lastRev else { return }
        lastRev = rev

        if g.bool(forKey: Self.kReset) {
            consumed = 0
            g.set(false, forKey: Self.kReset)
        }
        let text = g.string(forKey: Self.kText) ?? ""
        if consumed > text.count { consumed = 0 }
        if consumed < text.count {
            let idx = text.index(text.startIndex, offsetBy: consumed)
            let delta = String(text[idx...])
            textDocumentProxy.insertText(delta)
            consumed = text.count
        }
        if let last = g.string(forKey: Self.kLast) {
            previewLabel?.text = last.count > 60 ? "…" + last.suffix(60) : last
        }
    }

    // MARK: - 按键
    @objc private func newlineTapped() { textDocumentProxy.insertText("\n") }
    @objc private func backspaceTapped() { textDocumentProxy.deleteBackward() }
    @objc private func globeTapped() { advanceToNextInputMode() }
    /// "丢弃"：把未消费的会话文本标记为已消费（不再流入）
    @objc private func clearTapped() {
        let text = group?.string(forKey: Self.kText) ?? ""
        consumed = text.count
        previewLabel?.text = "已丢弃剩余文字"
    }
}
