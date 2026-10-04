import SwiftUI
import UIKit

// MARK: - 励志成语 · 视觉层 V9 重构
//
// 数据来源：Idioms.list（Idiom = text / pinyin / meaning）
// 状态来源：IdiomStore（index / tick / current / next / progress / interval）—— 接口名全部原样保留。
// 本文件只重做视觉层：BB 设计系统组件 + 大号渐变成语卡（成语/拼音/释义三层排版）
// + 自动轮换进度条（progress）+「换一条」主按钮 + 一键复制 + 系统分享（iPad 安全）
// + 入场与切换动画（withAnimation / transition）。
// 未改动 Idioms.swift、Core.swift 及其他任何文件。
//
// 说明：Idiom 结构体没有「出处」字段，为避免伪造数据，卡片采用
//      「今日励志标签 → 大号成语 → 拼音 → 释义区块」的分层排版，
//      以带底色的「释义」区块承担出处行的视觉位置。

struct IdiomView: View {
    @EnvironmentObject var idioms: IdiomStore
    @Environment(\.colorScheme) private var scheme

    /// 复制成功态（驱动按钮与提示条）
    @State private var copied = false
    /// 入场动画开关
    @State private var entered = false

    /// 本页身份色（金橙）
    private var palette: [Color] { Theme.idiom }

    /// 距离自动轮换还剩多少秒
    private var remain: Int { max(0, Int(IdiomStore.interval) - idioms.tick) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BBSpacing.l) {
                PageHeader(icon: "text.book.closed.fill",
                           colors: palette,
                           title: "励志成语",
                           subtitle: "每 \(Int(IdiomStore.interval)) 秒自动轮换 · 与主页同步")

                idiomCard

                rotationCard

                actionArea

                footerRow
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 18)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .onAppear {
            guard !entered else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { entered = true }
        }
    }

    // MARK: - 大号成语卡（渐变底 + 圆角阴影 + 切换动画）

    private var idiomCard: some View {
        ZStack {
            // 渐变底
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Theme.gradient(palette))

            // 顶部高光
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.20), Color.white.opacity(0.0)],
                                     startPoint: .top, endPoint: .center))

            // 巨型水印字（装饰）
            Text("励")
                .font(.system(size: 150, weight: .black, design: .serif))
                .foregroundColor(.white.opacity(0.10))
                .rotationEffect(.degrees(-8))
                .offset(x: 80, y: 94)

            cardContent
        }
        .frame(height: 344)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: palette[1].opacity(0.38), radius: 26, y: 14)
        // 切换动画（定时轮换 / 手动换一条 都会走到这里）
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: idioms.index)
    }

    /// 卡片内容：成语 → 拼音 → 释义 三层排版，随 index 切换过渡
    private var cardContent: some View {
        let item = idioms.current
        return VStack(alignment: .leading, spacing: 12) {
            // 顶部：标签 + 序号
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                    Text("今日励志").font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.20)))

                Spacer(minLength: 6)

                Text("第 \(idioms.index + 1) / \(Idioms.list.count) 条")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer(minLength: 4)

            // 第一层：成语主体
            Text(item.text)
                .font(.system(size: 52, weight: .black, design: .serif))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
                .frame(maxWidth: .infinity, alignment: .center)

            // 第二层：拼音
            Text(item.pinyin)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .center)

            // 分层小分隔（印章线）
            HStack(spacing: 8) {
                Capsule().fill(Color.white.opacity(0.55)).frame(width: 26, height: 3)
                Circle().fill(Color.white.opacity(0.8)).frame(width: 5, height: 5)
                Capsule().fill(Color.white.opacity(0.55)).frame(width: 26, height: 3)
            }
            .frame(maxWidth: .infinity)

            // 第三层：释义区块
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "text.quote").font(.system(size: 11, weight: .bold))
                    Text("释义").font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.80))

                Text(item.meaning)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )

            Spacer(minLength: 4)
        }
        .padding(20)
        .id(idioms.index)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - 自动轮换进度卡（使用 IdiomStore.progress / tick）

    private var rotationCard: some View {
        BBCard(padding: 16, radius: BBRadius.l) {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader(title: "自动轮换", icon: "arrow.triangle.2.circlepath", colors: palette) {
                    Text(remain <= 3 ? "即将切换…" : "\(remain)s 后换下一条")
                        .font(BBFont.cap(12))
                        .foregroundColor(.secondary)
                }

                BBMeter(value: idioms.progress, colors: palette, height: 8)

                HStack(spacing: 10) {
                    ID9MiniStat(title: "本轮进度", value: "\(Int(idioms.progress * 100))%", colors: palette)
                    ID9MiniStat(title: "剩余", value: "\(remain)s", colors: palette)
                    ID9MiniStat(title: "词库", value: "\(Idioms.list.count) 条", colors: palette)
                }
            }
        }
    }

    // MARK: - 操作区（换一条主按钮 + 复制 + 分享）

    private var actionArea: some View {
        VStack(spacing: 10) {
            BBPrimaryButton(title: "换一条", icon: "arrow.2.squarepath", colors: palette) {
                idioms.next()
            }

            HStack(spacing: 10) {
                ID9ActionButton(icon: copied ? "checkmark" : "doc.on.doc",
                                title: copied ? "已复制" : "复制成语",
                                colors: palette,
                                active: copied) {
                    copyIdiom()
                }

                ID9ActionButton(icon: "square.and.arrow.up",
                                title: "分享",
                                colors: palette) {
                    shareIdiom()
                }
            }

            if copied {
                Text("已复制：成语 + 拼音 + 释义")
                    .font(BBFont.cap(12))
                    .foregroundColor(Theme.success)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: copied)
    }

    private var footerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "book.closed.fill").font(.system(size: 10, weight: .semibold))
            Text("共 \(Idioms.list.count) 条 · 励志精选 · 与主页同步轮换")
                .font(BBFont.cap(12))
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    // MARK: - 复制（成语 + 拼音 + 释义）

    private func copyIdiom() {
        let item = idioms.current
        UIPasteboard.general.string = "【\(item.text)】\(item.pinyin)\n释义：\(item.meaning)"
        BBHaptic.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { copied = false }
        }
    }

    // MARK: - 系统分享（UIActivityViewController，iPhone/iPad 均安全）

    private func shareIdiom() {
        let item = idioms.current
        let text = "【\(item.text)】\(item.pinyin)\n释义：\(item.meaning)"
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let top = id9TopViewController() else { return }
        // 关键：iPad / 大屏必须提供 sourceView + sourceRect，否则会崩
        if let pop = av.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX,
                                    y: top.view.bounds.midY,
                                    width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        BBHaptic.tap()
        top.present(av, animated: true)
    }

    /// 取最顶层的 UIViewController（分享弹出用）
    private func id9TopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - 文件内私有小组件（前缀 ID9 防冲突）

/// 描边式操作按钮（复制 / 分享）
fileprivate struct ID9ActionButton: View {
    let icon: String
    let title: String
    var colors: [Color] = Theme.idiom
    var active: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            BBHaptic.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(active ? .white : colors[0])
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                    .fill(active ? AnyShapeStyle(Theme.gradient(colors)) : AnyShapeStyle(colors[0].opacity(0.10)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
                    .strokeBorder(colors[0].opacity(active ? 0 : 0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 小统计块（进度 / 剩余 / 词库）
fileprivate struct ID9MiniStat: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let value: String
    var colors: [Color] = Theme.idiom

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(BBFont.cap(11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gradient(colors))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.panel(scheme == .dark))
        )
    }
}
