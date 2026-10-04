import SwiftUI
import UIKit
import CoreImage
// MARK: - 颜色工具（取色 + HEX/RGB/HSL/HSV 转换 + 调色板 + 渐变预览，纯本地）
// 自定义类型统一使用 ColorTool 前缀；转换算法全部手写，不使用 UIColor 私有 API。
/// 色卡模型（Codable，持久化到 UserDefaults 键 bb.colors）
struct ColorToolSwatch: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1
    var color: Color {
        Color(.sRGB, red: min(1, max(0, r)), green: min(1, max(0, g)), blue: min(1, max(0, b)), opacity: min(1, max(0, a)))
    }
    static func == (lhs: ColorToolSwatch, rhs: ColorToolSwatch) -> Bool {
        abs(lhs.r - rhs.r) < 0.004 && abs(lhs.g - rhs.g) < 0.004 && abs(lhs.b - rhs.b) < 0.004 && abs(lhs.a - rhs.a) < 0.004
    }
}
// MARK: - 颜色转换 / 明度算法
enum ColorToolConvert {
    static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
    /// #RRGGBB（带透明度时补 AA 两位）
    static func hex(_ s: ColorToolSwatch) -> String {
        let r = Int((clamp(s.r) * 255).rounded()), g = Int((clamp(s.g) * 255).rounded()), b = Int((clamp(s.b) * 255).rounded())
        if s.a < 0.999 { return String(format: "#%02X%02X%02X%02X", r, g, b, Int((clamp(s.a) * 255).rounded())) }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    static func rgb(_ s: ColorToolSwatch) -> String {
        let r = Int((clamp(s.r) * 255).rounded()), g = Int((clamp(s.g) * 255).rounded()), b = Int((clamp(s.b) * 255).rounded())
        if s.a < 0.999 { return String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, clamp(s.a)) }
        return String(format: "rgb(%d, %d, %d)", r, g, b)
    }
    /// RGB → HSL（手写）
    static func hsl(_ s: ColorToolSwatch) -> (Double, Double, Double) {
        let r = clamp(s.r), g = clamp(s.g), b = clamp(s.b)
        let maxV = max(r, g, b), minV = min(r, g, b), l = (max(r, g, b) + min(r, g, b)) / 2, d = maxV - minV
        if d < 0.000001 { return (0, 0, l * 100) }
        let sat = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double = 0
        if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) } else if maxV == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h *= 60
        if h >= 360 { h -= 360 }
        return (h, sat * 100, l * 100)
    }
    /// RGB → HSV（手写）
    static func hsv(_ s: ColorToolSwatch) -> (Double, Double, Double) {
        let r = clamp(s.r), g = clamp(s.g), b = clamp(s.b)
        let maxV = max(r, g, b), minV = min(r, g, b), d = maxV - minV
        let sat = maxV == 0 ? 0 : d / maxV
        var h: Double = 0
        if d > 0.000001 {
            if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) } else if maxV == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h *= 60
            if h >= 360 { h -= 360 }
        }
        return (h, sat * 100, maxV * 100)
    }
    static func hslString(_ s: ColorToolSwatch) -> String {
        let c = hsl(s)
        return String(format: "hsl(%d, %d%%, %d%%)", Int(c.0.rounded()), Int(c.1.rounded()), Int(c.2.rounded()))
    }
    static func hsvString(_ s: ColorToolSwatch) -> String {
        let c = hsv(s)
        return String(format: "hsv(%d, %d%%, %d%%)", Int(c.0.rounded()), Int(c.1.rounded()), Int(c.2.rounded()))
    }
    /// 相对亮度（WCAG 线性化）
    static func luminance(_ s: ColorToolSwatch) -> Double {
        func lin(_ c: Double) -> Double { let v = clamp(c); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(s.r) + 0.7152 * lin(s.g) + 0.0722 * lin(s.b)
    }
    /// 与黑 / 白的对比度
    static func contrast(_ s: ColorToolSwatch) -> (black: Double, white: Double) {
        let l = luminance(s)
        return ((l + 0.05) / 0.05, 1.05 / (l + 0.05))
    }
    /// 可读性建议：返回文案 / 建议文字色 / 图标
    static func readableText(_ s: ColorToolSwatch) -> (String, Color, String) {
        let c = contrast(s)
        return c.black >= c.white ? ("建议使用黑色文字", .black, "moon.fill") : ("建议使用白色文字", .white, "sun.max.fill")
    }
    /// 解析 #RGB / #RRGGBB
    static func parseHex(_ text: String) -> ColorToolSwatch? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return ColorToolSwatch(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255, a: 1)
    }
    /// 从 SwiftUI Color 读分量（UIColor 公有 API，失败回退 CIColor）
    static func swatch(from color: Color) -> ColorToolSwatch {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return ColorToolSwatch(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
        }
        let ci = CIColor(color: ui)
        return ColorToolSwatch(r: clamp(Double(ci.red)), g: clamp(Double(ci.green)), b: clamp(Double(ci.blue)), a: clamp(Double(ci.alpha)))
    }
}
// MARK: - 可点按复制的格式行
struct ColorToolCopyRow: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false
    var body: some View {
        Button {
            UIPasteboard.general.string = value
            BBHaptic.success()
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(spacing: 10) {
                Text(label).font(.system(size: 11, weight: .bold)).foregroundColor(.secondary).frame(width: 40, alignment: .leading)
                Text(value).font(.system(size: 15, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.55)
                Spacer(minLength: 6)
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(copied ? Theme.success : Theme.accent)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))
        }
        .buttonStyle(.plain)
    }
}
// MARK: - 主视图
struct ColorToolView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var swatch = ColorToolSwatch(r: 46.0 / 255, g: 91.0 / 255, b: 1.0, a: 1)
    @State private var hexInput = "#2E5BFF"
    @State private var palette: [ColorToolSwatch] = []
    @State private var loaded = false
    @State private var hint: String?
    private let storeKey = "bb.colors"
    private var pickerBinding: Binding<Color> {
        Binding(get: { swatch.color }, set: { newValue in
            swatch = ColorToolConvert.swatch(from: newValue)
            hexInput = ColorToolConvert.hex(swatch)
        })
    }
    /// 渐变预览：优先用最近两张色卡，其次当前色 + 最近色卡
    private var gradientPair: (ColorToolSwatch, ColorToolSwatch)? {
        if palette.count >= 2 { return (palette[1], palette[0]) }
        if let last = palette.first { return (swatch, last) }
        return nil
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BBSpacing.l) {
                PageHeader(icon: "paintpalette.fill", colors: [swatch.color, Theme.accent], title: "颜色工具", subtitle: "取色 · 转换 · 调色板")
                pickerCard
                convertCard
                readabilityCard
                paletteCard
                if let hint {
                    Text(hint).font(.system(size: 12)).foregroundColor(.secondary).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, BBSpacing.screen).padding(.top, 8).padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("颜色工具")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded { loaded = true; loadPalette() } }
    }
    // MARK: 取色
    private var pickerCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: BBSpacing.m) {
                BBSectionHeader("取色", icon: "eyedropper.halffull")
                RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                    .fill(swatch.color)
                    .frame(height: 96)
                    .overlay(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous).strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
                    .overlay(Text(ColorToolConvert.hex(swatch))
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundColor(ColorToolConvert.readableText(swatch).1.opacity(0.92)))
                    .animation(.easeInOut(duration: 0.2), value: swatch)
                HStack(spacing: BBSpacing.m) {
                    ColorPicker("选取颜色", selection: pickerBinding, supportsOpacity: true).font(.system(size: 14, weight: .medium))
                    TextField("#2E5BFF", text: $hexInput)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .autocapitalization(.allCharacters).disableAutocorrection(true)
                        .onSubmit { applyHexInput() }
                        .padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: 130)
                        .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))
                        .overlay(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
                }
                BBGhostButton(title: "应用 HEX 输入", icon: "arrow.down.circle") { applyHexInput() }
            }
        }
    }
    // MARK: 四种格式
    private var convertCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 8) {
                BBSectionHeader("颜色格式", icon: "number.square", colors: [.teal, .blue])
                ColorToolCopyRow(label: "HEX", value: ColorToolConvert.hex(swatch))
                ColorToolCopyRow(label: "RGB", value: ColorToolConvert.rgb(swatch))
                ColorToolCopyRow(label: "HSL", value: ColorToolConvert.hslString(swatch))
                ColorToolCopyRow(label: "HSV", value: ColorToolConvert.hsvString(swatch))
                Text("每行点按即可复制").font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }
    // MARK: 可读性建议
    private var readabilityCard: some View {
        let advice = ColorToolConvert.readableText(swatch)
        let c = ColorToolConvert.contrast(swatch)
        let lum = ColorToolConvert.luminance(swatch)
        let best = max(c.black, c.white)
        return BBCard {
            VStack(alignment: .leading, spacing: BBSpacing.m) {
                BBSectionHeader("可读性建议", icon: "textformat", colors: [.orange, .pink])
                RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                    .fill(swatch.color).frame(height: 58)
                    .overlay(Text("示例文字 Aa 123").font(.system(size: 16, weight: .semibold)).foregroundColor(advice.1))
                HStack(spacing: 8) {
                    Image(systemName: advice.2).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.gradient([.orange, .pink]))
                    Text(advice.0).font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 6)
                    BBPill(text: String(format: "亮度 %.2f", lum), color: Theme.info)
                }
                BBKV(key: "与黑色文字对比度", value: String(format: "%.2f : 1", c.black))
                BBKV(key: "与白色文字对比度", value: String(format: "%.2f : 1", c.white))
                BBKV(key: "WCAG AA 正文", value: best >= 4.5 ? "达标" : "偏低")
            }
        }
    }
    // MARK: 调色板
    private var paletteCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: BBSpacing.m) {
                BBSectionHeader("调色板", icon: "square.grid.2x2.fill", colors: [.purple, .pink])
                BBPrimaryButton(title: "保存当前颜色", icon: "plus.circle.fill", colors: [.purple, .pink]) { saveCurrent() }
                if let pair = gradientPair {
                    VStack(alignment: .leading, spacing: 8) {
                        LinearGradient(colors: [pair.0.color, pair.1.color], startPoint: .leading, endPoint: .trailing)
                            .frame(height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
                        HStack(spacing: 8) {
                            Text("\(ColorToolConvert.hex(pair.0)) → \(ColorToolConvert.hex(pair.1))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                            Spacer(minLength: 6)
                            Button {
                                UIPasteboard.general.string = "linear-gradient(90deg, \(ColorToolConvert.hex(pair.0)), \(ColorToolConvert.hex(pair.1)))"
                                BBHaptic.success()
                                withAnimation { hint = "已复制渐变 CSS" }
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))
                }
                if palette.isEmpty {
                    BBEmptyState(icon: "paintpalette", title: "还没有色卡",
                                 message: "保存当前颜色后会出现在这里\n点按套用 · 长按删除", colors: [.purple, .pink])
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                        ForEach(palette) { item in swatchCell(item) }
                    }
                    Text("共 \(palette.count) 张色卡 · 点按套用 · 长按删除").font(.system(size: 11)).foregroundColor(.secondary)
                    BBGhostButton(title: "清空调色板", icon: "trash") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { palette.removeAll() }
                        persist()
                    }
                }
            }
        }
    }
    private func swatchCell(_ item: ColorToolSwatch) -> some View {
        let isCurrent = item == swatch
        return RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
            .fill(item.color).frame(height: 58)
            .overlay(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                .strokeBorder(isCurrent ? Theme.accent : Theme.stroke(scheme == .dark), lineWidth: isCurrent ? 2 : 1))
            .overlay(Group {
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(ColorToolConvert.readableText(item).1)
                }
            })
            .contentShape(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous))
            .onTapGesture { applySwatch(item) }
            .onLongPressGesture(minimumDuration: 0.45) { deleteSwatch(item) }
    }
    // MARK: 逻辑
    private func applyHexInput() {
        guard let parsed = ColorToolConvert.parseHex(hexInput) else {
            withAnimation { hint = "HEX 格式不正确，示例：#2E5BFF" }
            BBHaptic.warn()
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) { swatch = parsed }
        hexInput = ColorToolConvert.hex(parsed)
        withAnimation { hint = "已应用 \(ColorToolConvert.hex(parsed))" }
        BBHaptic.success()
    }
    private func saveCurrent() {
        if let idx = palette.firstIndex(where: { $0 == swatch }) { palette.remove(at: idx) }
        palette.insert(swatch, at: 0)
        if palette.count > 24 { palette.removeLast() }
        persist()
        BBHaptic.success()
        withAnimation { hint = "已保存 \(ColorToolConvert.hex(swatch))" }
    }
    private func applySwatch(_ item: ColorToolSwatch) {
        withAnimation(.easeInOut(duration: 0.2)) { swatch = item }
        hexInput = ColorToolConvert.hex(item)
        BBHaptic.select()
        withAnimation { hint = "已套用 \(ColorToolConvert.hex(item))" }
    }
    private func deleteSwatch(_ item: ColorToolSwatch) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { palette.removeAll { $0 == item } }
        persist()
        BBHaptic.warn()
        withAnimation { hint = "已删除 \(ColorToolConvert.hex(item))" }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(palette) { UserDefaults.standard.set(data, forKey: storeKey) }
    }
    private func loadPalette() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let list = try? JSONDecoder().decode([ColorToolSwatch].self, from: data) else { return }
        palette = list
    }
}
