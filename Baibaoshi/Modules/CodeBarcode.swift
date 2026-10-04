import SwiftUI
import UIKit
import CoreImage

// MARK: - 条码生成器（CoreImage：Code128 / Aztec / PDF417，纯本地无网络）
// 自定义类型统一使用 Barcode / Code 前缀。

/// 条码类型
enum BarcodeKind: String, CaseIterable, Identifiable {
    case code128, aztec, pdf417

    var id: String { rawValue }

    var label: String {
        switch self {
        case .code128: return "Code 128"
        case .aztec: return "Aztec"
        case .pdf417: return "PDF417"
        }
    }

    var shortLabel: String {
        switch self {
        case .code128: return "一维"
        case .aztec: return "二维"
        case .pdf417: return "二维"
        }
    }

    var filterName: String {
        switch self {
        case .code128: return "CICode128BarcodeGenerator"
        case .aztec: return "CIAztecCodeGenerator"
        case .pdf417: return "CIPDF417BarcodeGenerator"
        }
    }

    var tip: String {
        switch self {
        case .code128: return "仅支持 ASCII 字符（0-126），适合编号、单号"
        case .aztec: return "支持中英文，适合网址、名片、车票"
        case .pdf417: return "容量大、可纠错，适合证件与物流单据"
        }
    }

    var encodable: Bool { self == .code128 }

    var warningLimit: Int {
        switch self {
        case .code128: return 60
        case .aztec: return 800
        case .pdf417: return 900
        }
    }
}

/// 条码图像工厂
enum BarcodeImageFactory {
    private static let context = CIContext(options: nil)

    struct Result {
        var image: UIImage?
        var error: String?
    }

    static func make(text: String, kind: BarcodeKind) -> Result {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return Result(image: nil, error: nil) }

        if kind == .code128 {
            let ascii = value.unicodeScalars.allSatisfy { $0.isASCII && $0.value < 127 }
            if !ascii {
                return Result(image: nil,
                              error: "Code 128 仅支持英文字母、数字与常用符号，请删除中文或改用 Aztec / PDF417。")
            }
        }

        let payload: Data?
        switch kind {
        case .code128:
            payload = value.data(using: .isoLatin1) ?? value.data(using: .utf8)
        case .aztec:
            payload = value.data(using: .utf8)
        case .pdf417:
            payload = value.data(using: .isoLatin1) ?? value.data(using: .utf8)
        }
        guard let data = payload else {
            return Result(image: nil, error: "无法读取输入内容，请检查是否包含特殊字符。")
        }

        guard let filter = CIFilter(name: kind.filterName) else {
            return Result(image: nil, error: "当前系统不支持 \(kind.label) 条码类型。")
        }
        filter.setValue(data, forKey: "inputMessage")
        guard let output = filter.outputImage else {
            return Result(image: nil, error: "内容过长或格式不合法，\(kind.label) 无法编码。")
        }

        let extent = output.extent
        guard extent.width > 0, extent.height > 0 else {
            return Result(image: nil, error: "编码结果为空，请调整输入内容后重试。")
        }

        // 放大到足够清晰的分辨率，并限制总宽度
        var scale = max(1, 420 / max(extent.height, 1))
        if extent.width * scale > 2800 { scale = max(1, 2800 / extent.width) }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
            return Result(image: nil, error: "生成图片失败，请重试。")
        }
        return Result(image: renderOpaque(cg), error: nil)
    }

    /// 绘制到白色底（含留白区），去除透明通道，便于扫码 / 保存
    private static func renderOpaque(_ cg: CGImage) -> UIImage {
        let margin: CGFloat = 26
        let size = CGSize(width: CGFloat(cg.width) + margin * 2,
                          height: CGFloat(cg.height) + margin * 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: cg).draw(in: CGRect(x: margin, y: margin,
                                                 width: CGFloat(cg.width),
                                                 height: CGFloat(cg.height)))
        }
    }
}

/// 系统分享面板包装
struct BarcodeActivitySheet: UIViewControllerRepresentable {
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

/// 相册保存器（UIImageWriteToSavedPhotosAlbum + 失败回调）
final class BarcodePhotoSaver: NSObject {
    static let shared = BarcodePhotoSaver()
    private var completion: ((Error?) -> Void)?

    func save(_ image: UIImage, completion: @escaping (Error?) -> Void) {
        self.completion = completion
        UIImageWriteToSavedPhotosAlbum(image,
                                       self,
                                       #selector(BarcodePhotoSaver.finish(_:didFinishSavingWithError:contextInfo:)),
                                       nil)
    }

    @objc private func finish(_ image: UIImage,
                              didFinishSavingWithError error: Error?,
                              contextInfo: UnsafeRawPointer) {
        let callback = completion
        completion = nil
        DispatchQueue.main.async { callback?(error) }
    }
}

// MARK: - 主视图

struct CodeBarcodeView: View {
    @Environment(\.colorScheme) private var scheme

    @AppStorage("bb.barcode.text") private var text: String = "BB-2026-0001"
    @AppStorage("bb.barcode.kind") private var kindRaw: String = BarcodeKind.code128.rawValue

    @State private var image: UIImage?
    @State private var errorText: String?
    @State private var showShare = false
    @State private var notice: String?
    @State private var copied = false

    private let samples: [String] = ["BB-2026-0001", "https://example.com", "1234567890"]

    private var kind: BarcodeKind {
        BarcodeKind(rawValue: kindRaw) ?? .code128
    }

    private var kindBinding: Binding<BarcodeKind> {
        Binding(get: { kind }, set: { kindRaw = $0.rawValue })
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "barcode",
                           colors: [Color(hex: 0x7B5CFF), Color(hex: 0xC86BFF)],
                           title: "条码生成",
                           subtitle: "Code128 · Aztec · PDF417")

                BBSectionHeader("条码类型", icon: "square.grid.2x2.fill")
                BBCard {
                    VStack(alignment: .leading, spacing: 12) {
                        BBSegmented(options: BarcodeKind.allCases.map { ($0.label, $0) },
                                    selection: kindBinding)
                        HStack(spacing: 8) {
                            BBPill(text: kind.shortLabel, color: Theme.accent)
                            Text(kind.tip)
                                .font(BBFont.cap(11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                BBSectionHeader("输入内容", icon: "square.and.pencil")
                BBCard {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("输入要编码的内容…", text: $text, axis: .vertical)
                            .font(BBFont.body(15))
                            .lineLimit(2...5)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)

                        HStack(spacing: 8) {
                            Text("\(text.count) 字符")
                                .font(BBFont.cap(11))
                                .foregroundColor(text.count > kind.warningLimit ? Theme.warning : .secondary)
                            Spacer()
                            Button {
                                barcodeClear($text)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("清空").font(BBFont.cap(11))
                                }
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(samples, id: \.self) { sample in
                                    BBChip(text: sample, systemImage: "bolt.fill", selected: text == sample) {
                                        text = sample
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if let errorText {
                    BBCard {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.warning)
                            Text(errorText)
                                .font(BBFont.body(13))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                BBSectionHeader("预览", icon: "photo.on.rectangle.angled")

                if trimmed.isEmpty {
                    BBCard {
                        BBEmptyState(icon: "barcode.viewfinder",
                                     title: "暂无内容",
                                     message: "输入内容后自动生成条码")
                    }
                } else if let image {
                    BBCard {
                        VStack(spacing: 12) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 220)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                                        .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1)
                                )

                            VStack(spacing: 8) {
                                BBKV(key: "类型", value: kind.label)
                                BBKV(key: "数据长度", value: "\(text.count) 字符")
                                BBKV(key: "图像尺寸", value: "\(Int(image.size.width)) × \(Int(image.size.height)) px")
                            }
                        }
                    }
                } else {
                    BBCard {
                        BBEmptyState(icon: "exclamationmark.triangle",
                                     title: "无法生成",
                                     message: errorText ?? "请检查输入内容后重试",
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
                    BBGhostButton(title: "保存到相册", icon: "square.and.arrow.down") {
                        saveToAlbum()
                    }
                }

                Text("· 条码在本地生成，不上传任何数据")
                    .font(BBFont.cap(11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("条码")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .onChange(of: text) { _ in refresh() }
        .onChange(of: kindRaw) { _ in refresh() }
        .sheet(isPresented: $showShare) {
            if let image {
                BarcodeActivitySheet(items: [image])
            }
        }
        .alert("提示", isPresented: Binding(get: { notice != nil },
                                           set: { if !$0 { notice = nil } })) {
            Button("知道了", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: 逻辑

    private func refresh() {
        guard !trimmed.isEmpty else {
            image = nil
            errorText = nil
            return
        }
        let result = BarcodeImageFactory.make(text: text, kind: kind)
        image = result.image
        errorText = result.error
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

    private func saveToAlbum() {
        guard let image else { return }
        BarcodePhotoSaver.shared.save(image) { error in
            if let error {
                BBHaptic.warn()
                notice = "保存失败：\(error.localizedDescription)\n请在「设置 → 隐私与安全性 → 照片」中允许本 App 添加照片。"
            } else {
                BBHaptic.success()
                notice = "已保存到相册。"
            }
        }
    }
}

// MARK: - 小工具（清空按钮，带触感）

private func barcodeClear(_ text: Binding<String>) {
    BBHaptic.tap()
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { text.wrappedValue = "" }
}
