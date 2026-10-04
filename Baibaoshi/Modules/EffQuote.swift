import SwiftUI
import UIKit

// MARK: - 每日一言（EffQuoteView）
// 纯本地：内置三类中文内容（励志名言 / 冷知识 / 程序员笑话，各 22 条，共 66 条）。
// 「今日一言」以 yyyy-MM-dd 为种子，同一天固定同一条；支持换一条、复制、
// 系统分享（UIActivityViewController）与收藏（持久化 bb.quotes.fav）。
// 自定义类型统一 Quote 前缀，避免与主工程冲突。

// MARK: - 内容库（内置静态数据）

enum QuoteBank {

    static let motivation: [String] = [
        "路虽远，行则将至；事虽难，做则必成。",
        "你只管努力，剩下的交给时间。",
        "不为模糊不清的未来担忧，只为清清楚楚的现在努力。",
        "每一次低头，都是为了下一次更高地跃起。",
        "星光不问赶路人，时光不负有心人。",
        "你今天的努力，是明天幸运的伏笔。",
        "与其临渊羡鱼，不如退而结网。",
        "山高自有客行路，水深自有渡船人。",
        "熬过无人问津的日子，才有诗和远方。",
        "慢慢来，比较快。",
        "把每一个平凡的日子，都过成限量版。",
        "你要悄悄拔尖，然后惊艳所有人。",
        "世上无难事，只怕有心人。",
        "把眼泪收起来，把拳头握起来。",
        "越努力，越幸运。",
        "不怕慢，就怕站。",
        "心之所向，素履以往。",
        "别怕，你正在你最该奋斗的年纪。",
        "你若盛开，蝴蝶自来。",
        "种一棵树最好的时间是十年前，其次是现在。",
        "你现在的自律，藏着十年后的惊喜。",
        "向上的路其实并不拥挤，因为坚持的人不多。"
    ]

    static let trivia: [String] = [
        "蜂蜜是唯一不会腐坏的食物，考古学家在古埃及陵墓中发现了三千年仍可食用的蜂蜜。",
        "章鱼有三个心脏、九颗脑，血液是蓝色的。",
        "香蕉属于浆果，而草莓并不是浆果。",
        "人的胃酸强到可以溶解剃须刀片，只是胃黏膜更新得足够快。",
        "阳光从太阳到达地球大约需要 8 分 20 秒。",
        "北极熊的皮肤是黑色的，毛发其实是透明的。",
        "一只蜂鸟的心跳每分钟可达 1200 次。",
        "世界上最短的战争是 1896 年的英桑战争，只持续了 38 分钟。",
        "你每天吞下的鼻涕大约有 1 升之多。",
        "木头在真空中无法燃烧，因为没有氧气。",
        "闪电的温度可达 3 万摄氏度，比太阳表面还热。",
        "企鹅求婚时会送对方一块最漂亮的鹅卵石。",
        "人类和香蕉大约共享 60% 的基因。",
        "一茶匙中子星物质大约重 60 亿吨。",
        "打喷嚏时，你的心脏会短暂停跳一次。",
        "埃菲尔铁塔在夏天会因为金属膨胀而「长高」约 15 厘米。",
        "猫尝不出甜味，因为它们的甜味受体基因缺失。",
        "你的身体每秒产生约 250 万个新的红细胞。",
        "极纯净的深海水要到零下几十度才会结冰。",
        "蚊子更喜欢咬 O 型血、体温高和刚喝过酒的人。",
        "一张 A4 纸对折 42 次，厚度就能超过地球到月球的距离。",
        "地球上所有蚂蚁的总重量，可能与全人类的总重量大致相当。"
    ]

    static let joke: [String] = [
        "程序员的浪漫：我把你写进代码，因为我相信你永远不会报错。",
        "世界上最遥远的距离，是我在 if，你在 else。",
        "面试官：你最大的缺点是什么？我：不会撒谎。面试官：那说个优点。我：刚才那句是假的。",
        "为什么程序员分不清万圣节和圣诞节？因为 Oct 31 == Dec 25。",
        "生活不止眼前的苟且，还有改不完的 bug 和审不完的代码。",
        "我写的代码从不报错，报错的是编译器太矫情。",
        "程序员去菜市场：老板，来两斤洋葱。老板：要剥皮吗？程序员：不，我要保留现场。",
        "三种编程语言可以解决任何问题，只有一种会觉得你写得不好。",
        "调试：你以为是修 bug，其实是发现 bug 认识你，你也开始认识 bug。",
        "程序员最讨厌两件事：写注释，和别人不写注释。",
        "需求文档说「简单改一下」，一般意味着重写整个系统。",
        "世界上只有 10 种人：懂二进制的，和不懂的。",
        "我单身的原因很简单：变量名都不许见不得人，何况是对象。",
        "上线前一分钟改 bug，是程序员的极限运动。",
        "代码能跑就别动它——这是祖传代码的第一条家训。",
        "程序员加班到深夜，是因为白天都在开会讨论如何减少加班。",
        "程序员的口头禅：在我电脑上是好的啊。",
        "复制粘贴是最高效的复用，直到需要改的时候。",
        "有一种崩溃叫周五下午五点上线的版本。",
        "我写了个自动生成 bug 的程序，结果它写出了一个程序员。",
        "产品经理：这功能很简单吧？程序员：对，就像把大象放进冰箱一样简单。",
        "代码注释就像内衣，有比没有好，但别指望别人看得到。"
    ]
}

// MARK: - 分类

enum QuoteCat: String, CaseIterable, Identifiable {
    case motivation
    case trivia
    case joke

    var id: String { rawValue }

    var title: String {
        switch self {
        case .motivation: return "励志名言"
        case .trivia: return "冷知识"
        case .joke: return "程序员笑话"
        }
    }

    var icon: String {
        switch self {
        case .motivation: return "sparkles"
        case .trivia: return "lightbulb.fill"
        case .joke: return "face.smiling"
        }
    }

    var colors: [Color] {
        switch self {
        case .motivation: return [Color(hex: 0xFF7A18), Color(hex: 0xFF3D71)]
        case .trivia: return [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)]
        case .joke: return [Color(hex: 0x7B5CFF), Color(hex: 0x18D3B0)]
        }
    }

    var accent: Color { colors[0] }

    var quotes: [String] {
        switch self {
        case .motivation: return QuoteBank.motivation
        case .trivia: return QuoteBank.trivia
        case .joke: return QuoteBank.joke
        }
    }
}

// MARK: - 数据模型

struct QuoteItem: Identifiable, Hashable {
    let cat: QuoteCat
    let index: Int
    let text: String

    var id: String { "\(cat.rawValue)-\(index)" }
}

// MARK: - 数据仓库

enum QuoteStore {

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 今日键（yyyy-MM-dd），作为「今日一言」的种子
    static func todayKey(_ date: Date = Date()) -> String { dayFormatter.string(from: date) }

    /// 稳定哈希（djb2 变体），保证同一天同一种是同一条
    static func seed(_ text: String) -> Int {
        var h = 5381
        for scalar in text.unicodeScalars { h = (h &* 33) &+ Int(scalar.value) }
        return abs(h % 1_000_003)
    }

    static func item(_ cat: QuoteCat, index: Int) -> QuoteItem {
        let list = cat.quotes
        let safe = list.isEmpty ? 0 : max(0, min(index, list.count - 1))
        return QuoteItem(cat: cat, index: safe, text: list.isEmpty ? "" : list[safe])
    }

    /// 今日一言：按日期固定
    static func today(_ cat: QuoteCat) -> QuoteItem {
        let count = cat.quotes.count
        guard count > 0 else { return QuoteItem(cat: cat, index: 0, text: "") }
        return item(cat, index: seed(todayKey()) % count)
    }

    /// 换一条：避开当前条目
    static func next(_ cat: QuoteCat, avoiding index: Int) -> QuoteItem {
        let count = cat.quotes.count
        guard count > 1 else { return item(cat, index: 0) }
        var pick = index
        var guardCount = 0
        while pick == index && guardCount < 40 {
            pick = Int.random(in: 0..<count)
            guardCount += 1
        }
        return item(cat, index: pick)
    }

    /// 由收藏 id 还原条目（形如 "motivation-3"）
    static func item(fromID id: String) -> QuoteItem? {
        let parts = id.split(separator: "-")
        guard parts.count == 2,
              let idx = Int(parts[1]),
              let cat = QuoteCat(rawValue: String(parts[0])),
              idx >= 0, idx < cat.quotes.count else { return nil }
        return item(cat, index: idx)
    }

    static let favKey = "bb.quotes.fav"

    static func loadFavorites() -> [String] {
        UserDefaults.standard.stringArray(forKey: favKey) ?? []
    }

    static func saveFavorites(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: favKey)
    }
}

// MARK: - 系统分享

enum QuoteShare {
    /// 从当前最上层控制器弹出 UIActivityViewController；iPad 上设置 popover 防崩溃
    static func present(_ text: String) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first,
              var host = window.rootViewController else { return }
        while let presented = host.presentedViewController { host = presented }
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = host.view
            pop.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        host.present(vc, animated: true)
    }
}

// MARK: - 主视图

struct EffQuoteView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var cat: QuoteCat = .motivation
    @State private var current: QuoteItem = QuoteStore.today(.motivation)
    @State private var favorites: [String] = QuoteStore.loadFavorites()
    @State private var toast: String? = nil

    private var isToday: Bool { current.id == QuoteStore.today(cat).id }
    private var isFav: Bool { favorites.contains(current.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "quote.bubble.fill",
                           colors: [Color(hex: 0x7B5CFF), Color(hex: 0xFF6BB8)],
                           title: "每日一言",
                           subtitle: "励志 · 冷知识 · 笑话，每天一句")

                BBSegmented(options: [(QuoteCat.motivation.title, QuoteCat.motivation),
                                      (QuoteCat.trivia.title, QuoteCat.trivia),
                                      (QuoteCat.joke.title, QuoteCat.joke)],
                            selection: $cat)

                mainCard
                actionRow
                favoritesSection
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("每日一言")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { toastView }
        .onAppear { current = QuoteStore.today(cat) }
        .onChange(of: cat) { newValue in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                current = QuoteStore.today(newValue)
            }
        }
    }

    // MARK: 主卡片（渐变 + 大号文字）

    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: cat.icon).font(.system(size: 12, weight: .bold))
                    Text(cat.title).font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.22)))
                .foregroundColor(.white)

                Spacer(minLength: 6)

                if isToday {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar").font(.system(size: 11, weight: .bold))
                        Text("今日一言").font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
                    .foregroundColor(.white)
                }
            }

            Image(systemName: "quote.opening")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white.opacity(0.45))

            Text(current.text)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineSpacing(9)
                .fixedSize(horizontal: false, vertical: true)
                .id(current.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))

            HStack {
                Spacer()
                Text("— 百宝箱 · 每日一言")
                    .font(BBFont.cap(11))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: BBRadius.l, style: .continuous))
        .shadow(color: cat.accent.opacity(scheme == .dark ? 0.45 : 0.30), radius: 14, y: 8)
    }

    private var cardBackground: some View {
        ZStack {
            Theme.gradient(cat.colors)
            GeometryReader { geo in
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: geo.size.width * 0.7)
                    .blur(radius: 40)
                    .offset(x: geo.size.width * 0.45, y: -geo.size.height * 0.45)
                Circle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: geo.size.width * 0.6)
                    .blur(radius: 40)
                    .offset(x: -geo.size.width * 0.25, y: geo.size.height * 0.55)
            }
        }
    }

    // MARK: 操作区

    private var actionRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                BBPrimaryButton(title: "换一条", icon: "shuffle", colors: cat.colors) { shuffle() }
                BBGhostButton(title: isFav ? "取消收藏" : "收藏",
                              icon: isFav ? "heart.slash" : "heart.fill") { toggleFav() }
            }
            HStack(spacing: 10) {
                BBGhostButton(title: "复制", icon: "doc.on.doc") { copyCurrent() }
                BBGhostButton(title: "分享", icon: "square.and.arrow.up") { shareCurrent() }
            }
        }
    }

    // MARK: 收藏夹

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BBSectionHeader("我的收藏", icon: "heart.fill", colors: [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)]) {
                BBPill(text: "\(favorites.count) 条", color: Color(hex: 0xFF5EA8))
            }

            BBCard {
                if favorites.isEmpty {
                    BBEmptyState(icon: "heart",
                                 title: "还没有收藏",
                                 message: "遇到喜欢的句子，点一下「收藏」吧",
                                 colors: [Color(hex: 0xFF5EA8), Color(hex: 0x9E6BFF)])
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(favorites.enumerated()), id: \.element) { pair in
                            if let item = QuoteStore.item(fromID: pair.element) {
                                favoriteRow(item)
                                if pair.offset != favorites.count - 1 {
                                    Divider().overlay(Theme.hairline(scheme == .dark))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func favoriteRow(_ item: QuoteItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.gradient(item.cat.colors))
                .frame(width: 4)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Image(systemName: item.cat.icon).font(.system(size: 9, weight: .bold))
                    Text(item.cat.title).font(BBFont.cap(10))
                    Spacer()
                    Text("长按取消收藏").font(BBFont.cap(9)).foregroundColor(.secondary.opacity(0.8))
                }
                .foregroundColor(item.cat.accent)
            }
            Button {
                removeFavorite(item.id)
            } label: {
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: 0xFF5EA8))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(hex: 0xFF5EA8).opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onLongPressGesture { removeFavorite(item.id) }
    }

    // MARK: 轻提示

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.78)))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: 逻辑

    private func shuffle() {
        BBHaptic.select()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            current = QuoteStore.next(cat, avoiding: current.index)
        }
    }

    private func toggleFav() {
        if isFav {
            removeFavorite(current.id)
        } else {
            favorites.append(current.id)
            QuoteStore.saveFavorites(favorites)
            BBHaptic.success()
            showToast("已加入收藏")
        }
    }

    private func removeFavorite(_ id: String) {
        guard favorites.contains(id) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            favorites.removeAll { $0 == id }
        }
        QuoteStore.saveFavorites(favorites)
        BBHaptic.warn()
        showToast("已取消收藏")
    }

    private func copyCurrent() {
        UIPasteboard.general.string = current.text
        BBHaptic.success()
        showToast("已复制到剪贴板")
    }

    private func shareCurrent() {
        BBHaptic.tap()
        QuoteShare.present("\(current.text)\n\n—— \(cat.title) · 百宝箱")
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }
}
