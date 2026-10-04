import SwiftUI
import UIKit
import CoreImage

// MARK: - 二维码生成器（CoreImage CIQRCodeGenerator，纯本地无网络）
// 自定义类型统一使用 QR / Code 前缀，避免与其它模块命名冲突。

/// 二维码纠错级别
enum QRCorrectionLevel: String, CaseIterable, Identifiable {
    case low, medium, quartile, high

    var id: String { rawValue }

    /// CoreImage 的 inputCorrectionLevel 取值
    var ciValue: String {
        switch self {
        case .low: return "L"
        case .medium: return "M"
        case .quartile: return "Q"
        case .high: return "H"
        }
    }

    var label: String {
        switch self {
        case .low: return "低 L"
        case .medium: return "中 M"
        case .quartile: return "较高 Q"
        case .high: return "高 H"
        }
    }

    var desc: String {
        switch self {
        case .low: return "约 7% 容错，容量最大"
        case .medium: return "约 15% 容错，日常推荐"
        case .quartile: return "约 25% 容错，较抗污损"
        case .high: return "约 30% 容错，遮挡也能扫"
        }
    }
}

/// 二维码图像工厂：生成 ~1024px 高清位图，避免放大模糊
enum QRImageFactory {
    private static let context = CIContext(options: nil)

    static func make(text: String,
                     level: QRCorrectionLevel,
                     foreground: Color,
                     background: Color,
                     targetSize: CGFloat = 1024) -> UIImage? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(level.ciValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        // 前景 / 背景着色
        var base = output
        if let colorFilter = CIFilter(name: "CIFalseColor") {
            colorFilter.setValue(output, forKey: "inputImage")
            colorFilter.setValue(CIColor(color: UIColor(foreground)), forKey: "inputColor0")
            colorFilter.setValue(CIColor(color: UIColor(background)), forKey: "inputColor1")
            if let tinted = colorFilter.outputImage { base = tinted }
        }

        // 放大到目标尺寸（CoreImage 是矢量级放大，不会糊）
        let extent = base.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = max(1, targetSize / max(extent.width, extent.height))
        let scaled = base.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// 系统分享面板包装（iPhone 上设置 popover 锚点，防止 iPad / 弹出场景崩溃）
struct QRActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        attachPopover(vc)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        attachPopover(uiViewController)
    }

    private func attachPopover(_ vc: UIActivityViewController) {
        guard let pop = vc.popoverPresentationController else { return }
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        if let anchor = keyWindow?.rootViewController?.view ?? keyWindow {
            pop.sourceView = anchor
            pop.sourceRect = CGRect(x: anchor.bounds.midX, y: anchor.bounds.midY, width: 0, height: 0)
        }
        pop.permittedArrowDirections = []
    }
}

// MARK: - 主视图

struct CodeQRView: View {
    @Environment(\.colorScheme) private var scheme

    @AppStorage("bb.codeqr.text") private var text: String = ""
    @AppStorage("bb.codeqr.level") private var levelRaw: String = QRCorrectionLevel.medium.rawValue

    @State private var foreground: Color = .black
    @State private var background: Color = .white
    @State private var image: UIImage?
    @State private var showShare = false
    @State private var copied = false

    private var level: QRCorrectionLevel {
        QRCorrectionLevel(rawValue: levelRaw) ?? .medium
    }

    private var levelBinding: Binding<QRCorrectionLevel> {
        Binding(get: { level }, set: { levelRaw = $0.rawValue })
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var lengthHint: (String, Color) {
        if text.count > 2000 { return ("\(text.count) 字符 · 已超出常规容量，建议精简", Theme.danger) }
        if text.count > 1200 { return ("\(text.count) 字符 · 内容较长，识别率可能下降", Theme.warning) }
        return ("\(text.count) 字符", .secondary)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "qrcode",
                           colors: [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)],
                           title: "二维码生成",
                           subtitle: "文本 / 网址 → 高清二维码")

                BBSectionHeader("输入内容", icon: "square.and.pencil")
                BBCard {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("输入文本或网址…", text: $text, axis: .vertical)
                            .font(BBFont.body(15))
                            .lineLimit(3...6)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)

                        HStack(spacing: 8) {
                            Text(lengthHint.0)
                                .font(BBFont.cap(11))
                                .foregroundColor(lengthHint.1)
                            Spacer()
                            if !text.isEmpty {
                                Button {
                                    text = ""
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle.fill")
                                        Text("清空").font(BBFont.cap(11))
                                    }
                                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                BBSectionHeader("纠错级别", icon: "shield.lefthalf.filled")
                BBCard {
                    VStack(alignment: .leading, spacing: 12) {
                        BBSegmented(options: QRCorrectionLevel.allCases.map { ($0.label, $0) },
                                    selection: levelBinding)
                        Text(level.desc)
                            .font(BBFont.cap(12))
                            .foregroundColor(.secondary)
                    }
                }

                BBSectionHeader("配色", icon: "paintpalette.fill")
                BBCard {
                    VStack(spacing: 12) {
                        colorRow(title: "前景色（码点）", icon: "circle.fill", color: $foreground)
                        Divider().opacity(0.4)
                        colorRow(title: "背景色", icon: "circle", color: $background)
                        HStack(spacing: 8) {
                            BBGhostButton(title: "黑 / 白", icon: "arrow.counterclockwise") {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    foreground = .black
                                    background = .white
                                }
                            }
                            BBGhostButton(title: "反色", icon: "circle.lefthalf.filled") {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    let f = foreground
                                    foreground = background
                                    background = f
                                }
                            }
                        }
                    }
                }

                BBSectionHeader("预览", icon: "photo.on.rectangle.angled")

                if trimmed.isEmpty {
                    BBCard {
                        BBEmptyState(icon: "qrcode.viewfinder",
                                     title: "暂无内容",
                                     message: "输入文本或网址后自动生成二维码")
                    }
                } else if let image {
                    BBCard {
                        VStack(spacing: 12) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 260, maxHeight: 260)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                                        .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1)
                                )

                            HStack(spacing: 8) {
                                BBPill(text: "1024 px", color: Theme.accent)
                                BBPill(text: level.label, color: Theme.success)
                                BBPill(text: "\(Int(image.size.width)) × \(Int(image.size.height))", color: Theme.info)
                                Spacer()
                            }
                        }
                    }
                } else {
                    BBCard {
                        BBEmptyState(icon: "exclamationmark.triangle",
                                     title: "生成失败",
                                     message: "内容过长或包含无法编码的字符，请精简后重试",
                                     colors: [Theme.warning, Theme.danger])
                    }
                }

                if image != nil {
                    HStack(spacing: 10) {
                        BBPrimaryButton(title: copied ? "已复制" : "复制图像",
                                        icon: copied ? "checkmark" : "doc.on.doc") {
                            copyImage()
                        }
                        BBGhostButton(title: "分享", icon: "square.and.arrow.up") {
                            showShare = true
                        }
                    }
                }

                Text("· 二维码在本地生成，不上传任何数据")
                    .font(BBFont.cap(11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("二维码")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .onChange(of: text) { _ in refresh() }
        .onChange(of: levelRaw) { _ in refresh() }
        .onChange(of: foreground) { _ in refresh() }
        .onChange(of: background) { _ in refresh() }
        .sheet(isPresented: $showShare) {
            if let image {
                QRActivitySheet(items: [image])
            }
        }
    }

    // MARK: 子视图

    @ViewBuilder
    private func colorRow(title: String, icon: String, color: Binding<Color>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gradient(Theme.accentColors()))
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer()
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
        }
    }

    // MARK: 逻辑

    private func refresh() {
        guard !trimmed.isEmpty else {
            image = nil
            return
        }
        image = QRImageFactory.make(text: text,
                                    level: level,
                                    foreground: foreground,
                                    background: background,
                                    targetSize: 1024)
    }

    private func copyImage() {
        guard let image else { return }
        UIPasteboard.general.image = image
        BBHaptic.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { copied = false }
        }
    }
}
