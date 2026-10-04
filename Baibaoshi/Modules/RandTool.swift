import SwiftUI
import UIKit
// MARK: - 随机工具（骰子 / 硬币 / 随机数 / 抽签，纯本地无网络，自定义类型统一 Rand 前缀）
enum RandMode: Int, CaseIterable {
    case dice, coin, number, lot
    static let titles = ["骰子", "硬币", "随机数", "抽签"]
    static let icons = ["die.face.5", "circle.lefthalf.filled", "number", "list.bullet.rectangle"]
    static let palettes: [[Color]] = [[Color(hex: 0xFF8A18), Color(hex: 0xFF3D71)], [Color(hex: 0xF5C518), Color(hex: 0xFF8A18)], [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)], [Color(hex: 0x7B5CFF), Color(hex: 0x3B82F6)]]
    var title: String { Self.titles[rawValue] }
    var icon: String { Self.icons[rawValue] }
    var colors: [Color] { Self.palettes[rawValue] }
}
// MARK: - 骰子面（自绘点数，明暗两色都清晰）
struct RandDiceFace: View {
    let value: Int
    var size: CGFloat = 132
    @Environment(\.colorScheme) private var scheme
    /// 3x3 点位表：索引 = 点数 - 1
    private static let layouts: [Set<Int>] = [[4], [0, 8], [0, 4, 8], [0, 2, 6, 8], [0, 2, 4, 6, 8], [0, 2, 3, 5, 6, 8]]
    private var pips: Set<Int> { Self.layouts[max(0, min(5, value - 1))] }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(hex: 0xF7F7FB))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
            ForEach(0..<9, id: \.self) { i in
                if pips.contains(i) {
                    Circle().fill(Color(hex: 0x1A1A28)).frame(width: size * 0.185, height: size * 0.185)
                        .offset(x: CGFloat(i % 3 - 1) * size * 0.27, y: CGFloat(i / 3 - 1) * size * 0.27)
                }
            }
        }
        .frame(width: size, height: size)
        .bbShadow(scheme == .dark, strong: true)
    }
}
// MARK: - 整数输入框
struct RandField: View {
    let title: String
    @Binding var text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BBFont.cap(12)).foregroundColor(.secondary)
            TextField("", text: $text).keyboardType(.numbersAndPunctuation).font(BBFont.num(16))
                .multilineTextAlignment(.center).padding(.horizontal, 10).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))
                .overlay(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                    .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
        }
    }
}
// MARK: - 数量加减器
struct RandStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                stepButton(icon: "minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - 1) }
                Text("\(value)").font(BBFont.num(17)).frame(minWidth: 44)
                stepButton(icon: "plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + 1) }
            }
            .padding(3).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel(scheme == .dark)))
        }
    }
    private func stepButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { BBHaptic.select(); action() } label: {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
                .foregroundColor(enabled ? Theme.accent : Color.secondary.opacity(0.35))
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(enabled ? Theme.accent.opacity(0.12) : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
// MARK: - 主视图
struct RandToolView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var mode = 0
    @State private var diceValue = 6
    @State private var diceRolling = false
    @State private var diceHistory: [Int] = []
    @State private var coinHeads = true
    @State private var coinRotation = 0.0
    @State private var coinFlipping = false
    @State private var headCount = 0
    @State private var tailCount = 0
    @State private var numMin = "1"
    @State private var numMax = "100"
    @State private var numCount = 6
    @State private var numDedupe = false
    @State private var numResults: [Int] = []
    @State private var numError: String?
    @State private var lotText = "小明\n小红\n小刚\n小美\n老王"
    @State private var lotCount = 1
    @State private var lotPicked: [String] = []
    @State private var lotRolling = false
    private var currentMode: RandMode { RandMode(rawValue: mode) ?? .dice }
    private var coinRatio: Double { Double(headCount) / Double(max(1, headCount + tailCount)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BBSpacing.l) {
                PageHeader(icon: "shuffle", colors: currentMode.colors, title: "随机工具", subtitle: "骰子 · 硬币 · 随机数 · 抽签")
                BBSegmented(options: RandMode.allCases.map { ($0.title, $0.rawValue) }, selection: $mode)
                switch currentMode {
                case .dice: diceSection
                case .coin: coinSection
                case .number: numberSection
                case .lot: lotSection
                }
            }
            .padding(.horizontal, BBSpacing.screen).padding(.top, 8).padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("随机工具")
        .navigationBarTitleDisplayMode(.inline)
    }
    // MARK: ① 骰子
    @ViewBuilder private var diceSection: some View {
        BBCard {
            VStack(spacing: BBSpacing.l) {
                RandDiceFace(value: diceValue, size: 136)
                    .rotationEffect(.degrees(diceRolling ? 10 : 0)).scaleEffect(diceRolling ? 1.06 : 1)
                    .animation(.spring(response: 0.22, dampingFraction: 0.55), value: diceValue)
                HStack(spacing: BBSpacing.l) {
                    BBStat(label: "点数", value: "\(diceValue)", unit: "点", icon: "die.face.5", colors: currentMode.colors)
                    BBStat(label: "已掷", value: "\(diceHistory.count)", unit: "次", icon: "clock.arrow.circlepath", colors: [.gray, .blue])
                }
            }
        }
        BBPrimaryButton(title: diceRolling ? "掷骰中…" : "掷骰子", icon: "die.face.5", colors: currentMode.colors) { rollDice() }
    }
    private func rollDice() {
        guard !diceRolling else { return }
        diceRolling = true
        BBHaptic.tap()
        for step in 0..<10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.06) { diceValue = Int.random(in: 1...6) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) {
            let final = Int.random(in: 1...6)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { diceValue = final }
            diceHistory.insert(final, at: 0)
            if diceHistory.count > 24 { diceHistory.removeLast() }
            diceRolling = false
            BBHaptic.success()
        }
    }
    // MARK: ② 抛硬币
    @ViewBuilder private var coinSection: some View {
        BBCard {
            VStack(spacing: BBSpacing.l) {
                ZStack {
                    Circle()
                        .fill(coinHeads ? Theme.gradient([Color(hex: 0xF5C518), Color(hex: 0xFF8A18)])
                                        : Theme.gradient([Color(hex: 0x5B6478), Color(hex: 0x3B82F6)]))
                        .frame(width: 136, height: 136).shadow(color: (coinHeads ? Color.orange : Color.blue).opacity(0.35), radius: 12, y: 6)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 2).padding(7))
                    Text(coinHeads ? "正" : "反")
                        .font(.system(size: 48, weight: .heavy, design: .rounded)).foregroundColor(.white)
                }
                .rotation3DEffect(.degrees(coinRotation), axis: (x: 0, y: 1, z: 0))
                HStack(spacing: BBSpacing.l) {
                    BBStat(label: "正面", value: "\(headCount)", unit: "次", icon: "sun.max.fill", colors: [Color(hex: 0xF5C518), Color(hex: 0xFF8A18)])
                    BBStat(label: "反面", value: "\(tailCount)", unit: "次", icon: "moon.fill", colors: [.gray, .blue])
                }
                if headCount + tailCount > 0 {
                    BBMeter(value: coinRatio, colors: [Color(hex: 0xF5C518), Color(hex: 0xFF8A18)])
                    BBKV(key: "正面占比", value: String(format: "%.1f%%", coinRatio * 100))
                }
            }
        }
        BBPrimaryButton(title: coinFlipping ? "翻转中…" : "抛硬币", icon: "arrow.triangle.2.circlepath", colors: currentMode.colors) { flipCoin() }
    }
    private func flipCoin() {
        guard !coinFlipping else { return }
        coinFlipping = true
        BBHaptic.tap()
        let isHeads = Bool.random()
        withAnimation(.easeInOut(duration: 0.85)) { coinRotation += 1080 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { coinHeads = isHeads }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            coinFlipping = false
            if isHeads { headCount += 1 } else { tailCount += 1 }
            BBHaptic.success()
        }
    }
    // MARK: ③ 随机数
    @ViewBuilder private var numberSection: some View {
        BBCard {
            VStack(alignment: .leading, spacing: BBSpacing.m) {
                HStack(spacing: BBSpacing.m) {
                    RandField(title: "最小值", text: $numMin)
                    RandField(title: "最大值", text: $numMax)
                }
                RandStepper(title: "生成个数", value: $numCount, range: 1...100)
                Toggle(isOn: $numDedupe) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.gradient(currentMode.colors))
                        Text("结果不重复").font(.system(size: 14, weight: .medium))
                    }
                }.tint(Theme.accent)
                if let err = numError {
                    Label(err, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundColor(Theme.warning)
                }
            }
        }
        BBPrimaryButton(title: "生成随机数", icon: "sparkles", colors: currentMode.colors) { generateNumbers() }
        if !numResults.isEmpty {
            BBCard {
                VStack(alignment: .leading, spacing: BBSpacing.m) {
                    BBSectionHeader("结果", icon: "number", colors: currentMode.colors)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                        ForEach(Array(numResults.enumerated()), id: \.offset) { _, v in
                            Text("\(v)").font(BBFont.num(17)).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
                                .padding(.vertical, 10).background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))
                        }
                    }
                }
            }
        }
    }
    private func generateNumbers() {
        numError = nil
        let lo = Int(numMin.trimmingCharacters(in: .whitespaces)), hi = Int(numMax.trimmingCharacters(in: .whitespaces))
        guard let low = lo, let high = hi else { numError = "请输入合法的整数范围"; BBHaptic.warn(); return }
        guard low <= high else { numError = "最小值不能大于最大值"; BBHaptic.warn(); return }
        let span = high - low + 1
        guard span <= 200_000 else { numError = "范围过大，请缩小到 200000 以内"; BBHaptic.warn(); return }
        let n = max(1, min(100, numCount))
        if numDedupe {
            guard n <= span else { numError = "范围内只有 \(span) 个数，无法不重复生成 \(n) 个"; BBHaptic.warn(); return }
            var pool = Array(low...high)
            pool.shuffle()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { numResults = Array(pool.prefix(n)) }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { numResults = (0..<n).map { _ in Int.random(in: low...high) } }
        }
        BBHaptic.success()
    }
    // MARK: ④ 抽签
    private var lotNames: [String] {
        var seen = Set<String>(), out: [String] = []
        for line in lotText.split(separator: "\n") {
            let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && !seen.contains(name) { seen.insert(name); out.append(name) }
        }
        return out
    }
    @ViewBuilder private var lotSection: some View {
        BBCard {
            VStack(alignment: .leading, spacing: BBSpacing.m) {
                BBSectionHeader("名单", icon: "list.bullet.rectangle", colors: currentMode.colors)
                TextEditor(text: $lotText).font(.system(size: 14)).frame(minHeight: 112).scrollContentBackground(.hidden).padding(8)
                    .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))
                    .overlay(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
                HStack(spacing: 8) {
                    BBPill(text: "共 \(lotNames.count) 人", color: Theme.accent)
                    BBPill(text: "每行一个名字", color: .secondary)
                }
                RandStepper(title: "抽取个数", value: $lotCount, range: 1...max(1, lotNames.count))
                if !lotNames.isEmpty {
                    BBSectionHeader("抽取结果", icon: "checkmark.circle", colors: currentMode.colors)
                    ForEach(lotNames, id: \.self) { name in
                        HStack(spacing: 10) {
                            Image(systemName: lotPicked.contains(name) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(lotPicked.contains(name) ? Theme.success : Color.secondary.opacity(0.4))
                            Text(name).font(.system(size: 15, weight: lotPicked.contains(name) ? .semibold : .regular))
                            Spacer(minLength: 6)
                            if lotPicked.contains(name) { BBPill(text: "中签", color: Theme.success) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
                            .fill(lotPicked.contains(name) ? Theme.success.opacity(0.14) : Theme.panel(scheme == .dark)))
                    }
                }
            }
        }
        .onChange(of: lotText) { _ in if lotCount > max(1, lotNames.count) { lotCount = max(1, lotNames.count) } }
        BBPrimaryButton(title: lotRolling ? "抽取中…" : "开始抽签", icon: "hand.point.up.left.fill", colors: currentMode.colors) { drawLot() }
    }
    private func drawLot() {
        guard !lotNames.isEmpty else { BBHaptic.warn(); return }
        lotRolling = true
        BBHaptic.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            lotPicked = Array(lotNames.shuffled().prefix(max(1, min(lotNames.count, lotCount))))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { lotRolling = false; BBHaptic.success() }
    }
}
