import SwiftUI

// MARK: - 通用组件库（子代理可自由复用，务必保持 iOS 16 兼容）

/// 分区标题：图标 + 标题 + 可选右侧内容
struct BBSectionHeader<Accessory: View>: View {
    let title: String
    let icon: String
    var colors: [Color] = Theme.accentColors()
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gradient(colors))
            Text(title)
                .font(BBFont.head(17))
            Spacer(minLength: 6)
            accessory()
        }
    }
}

extension BBSectionHeader where Accessory == EmptyView {
    init(_ title: String, icon: String, colors: [Color] = Theme.accentColors()) {
        self.init(title: title, icon: icon, colors: colors) { EmptyView() }
    }
}

extension BBSectionHeader {
    /// 无标签标题 + 右侧内容的写法：`BBSectionHeader("标题", icon: "x") { 内容 }`
    init(_ title: String, icon: String, colors: [Color] = Theme.accentColors(),
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(title: title, icon: icon, colors: colors, accessory: accessory)
    }
}

/// 通用卡片容器
struct BBCard<Content: View>: View {
    var padding: CGFloat = BBSpacing.l
    var radius: CGFloat = BBRadius.l
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cardBg(scheme == .dark))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1)
                    )
            )
            .bbShadow(scheme == .dark)
    }
}

/// 大数字统计块
struct BBStat: View {
    let label: String
    let value: String
    var unit: String? = nil
    var icon: String? = nil
    var colors: [Color] = Theme.accentColors()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.gradient(colors))
                }
                Text(label)
                    .font(BBFont.cap(12))
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(BBFont.num(26))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit).font(BBFont.cap(12)).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 小胶囊标签
struct BBPill: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundColor(color)
    }
}

/// 主要操作按钮（渐变填充）
struct BBPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var colors: [Color] = Theme.accentColors()
    var action: () -> Void

    var body: some View {
        Button(action: {
            BBHaptic.tap()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                    .fill(Theme.gradient(colors))
                    .shadow(color: colors.last!.opacity(0.35), radius: 8, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 次级按钮（描边）
struct BBGhostButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: { BBHaptic.tap(); action() }) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                    .fill(Theme.accent.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

/// 设置行（图标 + 标题 + 右侧值）
struct BBRow: View {
    let title: String
    var icon: String? = nil
    var value: String? = nil
    var colors: [Color] = Theme.accentColors()
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.gradient(colors))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.system(size: 13)).foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
    }
}

/// 空状态
struct BBEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil
    var colors: [Color] = Theme.accentColors()

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.gradient(colors)).opacity(0.14).frame(width: 72, height: 72)
                Image(systemName: icon).font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.gradient(colors))
            }
            Text(title).font(BBFont.head(16))
            if let message {
                Text(message).font(.system(size: 12)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

/// 进度环
struct BBRing: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var colors: [Color] = Theme.accentColors()
    var label: String? = nil
    var caption: String? = nil

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(Theme.gradient(colors), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                if let label { Text(label).font(BBFont.num(20)) }
                if let caption { Text(caption).font(BBFont.cap(10)).foregroundColor(.secondary) }
            }
        }
        .frame(width: 92, height: 92)
    }
}

/// 水平进度条
struct BBMeter: View {
    var value: Double
    var colors: [Color] = Theme.accentColors()
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(Theme.gradient(colors))
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// 分段选择器（自定义，保证样式统一）
struct BBSegmented<T: Hashable>: View {
    let options: [(String, T)]
    @Binding var selection: T
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.1) { opt in
                Button {
                    BBHaptic.select()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = opt.1 }
                } label: {
                    Text(opt.0)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selection == opt.1 ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                if selection == opt.1 {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Theme.accentGradient)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Theme.panel(scheme == .dark))
        )
    }
}

/// 结果展示块（等宽字体，可复制）
struct BBResult: View {
    let text: String
    var colors: [Color] = Theme.accentColors()
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(text.isEmpty ? "—" : text)
                .font(BBFont.monoBig)
                .foregroundColor(text.isEmpty ? .secondary : .primary)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIPasteboard.general.string = text
                    BBHaptic.success()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
            if !text.isEmpty {
                BBPill(text: copied ? "已复制" : "点按复制", color: copied ? Theme.success : Theme.accent)
            }
        }
        .padding(BBSpacing.l)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                .fill(Theme.panel(scheme == .dark))
        )
    }
}

/// 芯片/标签，可选中
struct BBChip: View {
    let text: String
    var systemImage: String? = nil
    var selected: Bool = false
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: { BBHaptic.select(); action() }) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)) }
                Text(text).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.panel(scheme == .dark))))
            .foregroundColor(selected ? .white : .primary)
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(selected ? 0 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 键值行
struct BBKV: View {
    let key: String
    let value: String

    var body: some View {
        HStack {
            Text(key).font(.system(size: 13)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium)).lineLimit(1)
        }
    }
}

// MARK: - 触感反馈

enum BBHaptic {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warn() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
