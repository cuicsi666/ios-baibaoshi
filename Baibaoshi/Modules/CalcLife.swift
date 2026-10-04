import SwiftUI
import UIKit
import Foundation

// MARK: - 生活计算器（房贷 / 打折 / 小费 / BMI / 个税，纯本地）

private enum CalcLifeMode: String, CaseIterable, Hashable {
    case loan = "房贷", discount = "打折", tip = "小费", bmi = "BMI", tax = "个税"
    var title: String { rawValue }
    private static let metaTable: [CalcLifeMode: (String, [Color])] = [
        .loan: ("等额本息 · 月供与利息明细", [Color(hex: 0x2E5BFF), Color(hex: 0x00C2FF)]),
        .discount: ("折后价与优惠金额", [Color(hex: 0xFF7A18), Color(hex: 0xFF3D71)]),
        .tip: ("小费与 AA 分摊", [Color(hex: 0x18B26B), Color(hex: 0x9BD34A)]),
        .bmi: ("身体质量指数与分级", [Color(hex: 0x7B5CFF), Color(hex: 0xC86BFF)]),
        .tax: ("工资个税估算（5000 起征点）", [Color(hex: 0xF59E0B), Color(hex: 0xFF7A18)])
    ]
    var subtitle: String { Self.metaTable[self]?.0 ?? "" }
    var colors: [Color] { Self.metaTable[self]?.1 ?? Theme.accentColors() }
}

// MARK: 数据模型

private struct CalcKV: Identifiable {
    var id: String { key }
    let key: String, value: String
}

private struct CalcLoanRow: Identifiable {
    var id: Int { period }
    let period: Int, interest: Double, principal: Double, balance: Double
}

private struct CalcLoanResult {
    let monthly: Double, total: Double, interest: Double
    let months: Int
    let rows: [CalcLoanRow]
}

// MARK: 子组件

private struct CalcField: View {
    let label: String
    let placeholder: String
    var unit: String = ""
    @Binding var text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 14, weight: .medium)).frame(width: 76, alignment: .leading)
            TextField(placeholder, text: $text).keyboardType(.decimalPad)
                .font(BBFont.mono).multilineTextAlignment(.trailing)
            Text(unit).font(BBFont.cap(12)).foregroundColor(.secondary).frame(width: 34, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
            .fill(Theme.panel(scheme == .dark)))
    }
}

private struct CalcResultCard: View {
    let title: String
    let value: String
    let note: String
    var rows: [CalcKV] = []
    var colors: [Color] = Theme.accentColors()
    var body: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(BBFont.cap(12)).foregroundColor(.secondary)
                BBResult(text: value, colors: colors)
                if !rows.isEmpty {
                    VStack(spacing: 9) { ForEach(rows) { BBKV(key: $0.key, value: $0.value) } }
                }
                Text(note).font(BBFont.cap(11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: 工具

private func calcMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
}

private func calcFix(_ v: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", v) }

private func calcDismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - 主视图

struct CalcLifeView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var mode: CalcLifeMode = .loan
    @State private var loanAmount = "1000000"
    @State private var loanRate = "3.85"
    @State private var loanYears = "30"
    @State private var dPrice = ""
    @State private var dDiscount = ""
    @State private var tipAmount = ""
    @State private var tipPercent = "15"
    @State private var tipPeople = "2"
    @State private var bmiHeight = ""
    @State private var bmiWeight = ""
    @State private var taxIncome = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "percent", colors: mode.colors, title: "生活计算器", subtitle: mode.subtitle)
                BBSegmented(options: CalcLifeMode.allCases.map { ($0.title, $0) }, selection: $mode)
                content
            }
            .padding(.horizontal, BBSpacing.screen).padding(.top, 8).padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("生活计算器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { calcDismissKeyboard() } } }
    }
    @ViewBuilder private var content: some View {
        switch mode {
        case .loan: loanSection
        case .discount: discountSection
        case .tip: tipSection
        case .bmi: bmiSection
        case .tax: taxSection
        }
    }

    // MARK: 通用零件
    private func calcFields(_ items: [(String, String, String, Binding<String>)]) -> some View {
        BBCard {
            VStack(spacing: 10) {
                ForEach(items.indices, id: \.self) { i in
                    CalcField(label: items[i].0, placeholder: items[i].1, unit: items[i].2, text: items[i].3)
                }
            }
        }
    }
    private func calcEmpty(_ icon: String, _ title: String, _ message: String, _ colors: [Color]) -> some View {
        BBCard { BBEmptyState(icon: icon, title: title, message: message, colors: colors) }
    }

    // MARK: ① 房贷
    private var loanSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            BBSectionHeader("贷款信息", icon: "banknote.fill")
            calcFields([("贷款金额", "1000000", "元", $loanAmount),
                        ("年利率", "3.85", "%", $loanRate),
                        ("贷款年限", "30", "年", $loanYears)])
            BBSectionHeader("等额本息结果", icon: "chart.bar.xaxis")
            if let r = loanResult {
                CalcResultCard(
                    title: "每月月供", value: "¥" + calcMoney(r.monthly),
                    note: "月供 M = P·i·(1+i)ⁿ ÷ [(1+i)ⁿ−1]，i 为月利率、n 为月数；总利息 = 月供 × 期数 − 本金",
                    rows: [CalcKV(key: "贷款总额", value: "¥" + calcMoney(loanPrincipal)),
                           CalcKV(key: "支付总利息", value: "¥" + calcMoney(r.interest)),
                           CalcKV(key: "还款总额", value: "¥" + calcMoney(r.total)),
                           CalcKV(key: "还款期数", value: "\(r.months) 期")],
                    colors: CalcLifeMode.loan.colors)
                loanScheduleCard(r)
            } else {
                calcEmpty("banknote", "请输入贷款信息", "金额、年利率、年限均需有效", CalcLifeMode.loan.colors)
            }
        }
    }
    private func loanScheduleCard(_ r: CalcLoanResult) -> some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("前 6 期还款明细").font(BBFont.cap(12)).foregroundColor(.secondary)
                Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 7) {
                    GridRow {
                        Text("期数").gridColumnAlignment(.leading)
                        Text("本金"); Text("利息"); Text("剩余")
                    }
                    .font(BBFont.cap(10)).foregroundColor(.secondary)
                    ForEach(r.rows) { row in
                        GridRow {
                            Text("第\(row.period)期").gridColumnAlignment(.leading)
                            Text(calcMoney(row.principal)); Text(calcMoney(row.interest))
                            Text(calcMoney(row.balance))
                        }
                        .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }
    private var loanPrincipal: Double { Double(loanAmount) ?? 0 }
    private var loanResult: CalcLoanResult? {
        guard let p = Double(loanAmount), let rate = Double(loanRate), let years = Double(loanYears),
              p > 0, rate >= 0, years > 0 else { return nil }
        let months = Int((years * 12).rounded())
        guard months > 0 else { return nil }
        let i = rate / 100.0 / 12.0
        let f = i > 0 ? pow(1 + i, Double(months)) : 1
        let monthly = i > 0 ? p * i * f / (f - 1) : p / Double(months)
        var balance = p
        var rows: [CalcLoanRow] = []
        for k in 1...min(6, months) {
            let interest = balance * i
            let pay = monthly - interest
            rows.append(CalcLoanRow(period: k, interest: interest, principal: pay, balance: max(0, balance - pay)))
            balance = max(0, balance - pay)
        }
        let total = monthly * Double(months)
        return CalcLoanResult(monthly: monthly, total: total, interest: total - p, months: months, rows: rows)
    }

    // MARK: ② 打折
    private var discountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            BBSectionHeader("价格信息", icon: "tag.fill")
            calcFields([("商品原价", "199", "元", $dPrice), ("折扣", "8.5", "折", $dDiscount)])
            BBSectionHeader("计算结果", icon: "percent")
            if let r = discountResult {
                CalcResultCard(
                    title: "折后价", value: "¥" + calcMoney(r.final),
                    note: "折后价 = 原价 × 折扣 ÷ 10（如 8.5 折 = 原价 × 0.85）；实付比例 = 折扣 × 10",
                    rows: [CalcKV(key: "优惠金额", value: "省 ¥" + calcMoney(r.save)),
                           CalcKV(key: "实付比例", value: calcFix(r.percent) + " %")],
                    colors: CalcLifeMode.discount.colors)
            } else {
                calcEmpty("tag", "请输入原价与折扣", "例如原价 199 元、8.5 折", CalcLifeMode.discount.colors)
            }
        }
    }
    private var discountResult: (final: Double, save: Double, percent: Double)? {
        guard let p = Double(dPrice), let d = Double(dDiscount), p > 0, d > 0 else { return nil }
        let actual = p * d / 10.0
        return (actual, p - actual, d * 10.0)
    }

    // MARK: ③ 小费
    private var tipSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            BBSectionHeader("账单信息", icon: "creditcard.fill")
            calcFields([("消费金额", "300", "元", $tipAmount),
                        ("小费比例", "15", "%", $tipPercent),
                        ("分摊人数", "2", "人", $tipPeople)])
            BBSectionHeader("分摊结果", icon: "person.2.fill")
            if let r = tipResult {
                CalcResultCard(
                    title: "每人应付", value: "¥" + calcMoney(r.per),
                    note: "小费 = 消费金额 × 比例%；每人应付 = (消费金额 + 小费) ÷ 人数",
                    rows: [CalcKV(key: "小费金额", value: "¥" + calcMoney(r.tip)),
                           CalcKV(key: "账单合计", value: "¥" + calcMoney(r.total)),
                           CalcKV(key: "分摊人数", value: "\(r.people) 人")],
                    colors: CalcLifeMode.tip.colors)
            } else {
                calcEmpty("person.2", "请输入账单信息", "金额、比例与人数均需有效", CalcLifeMode.tip.colors)
            }
        }
    }
    private var tipResult: (tip: Double, total: Double, per: Double, people: Int)? {
        guard let a = Double(tipAmount), let percent = Double(tipPercent), let pn = Double(tipPeople),
              a > 0, percent >= 0, pn >= 1 else { return nil }
        let people = max(1, Int(pn.rounded()))
        let tip = a * percent / 100.0
        let total = a + tip
        return (tip, total, total / Double(people), people)
    }

    // MARK: ④ BMI
    private var bmiSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            BBSectionHeader("身体数据", icon: "figure.stand")
            calcFields([("身高", "170", "cm", $bmiHeight), ("体重", "65", "kg", $bmiWeight)])
            BBSectionHeader("BMI 结果", icon: "heart.fill")
            if let r = bmiResult {
                BBCard {
                    HStack(alignment: .center, spacing: 16) {
                        BBRing(progress: min(1, r.bmi / 40), colors: r.colors, label: calcFix(r.bmi), caption: "BMI")
                        VStack(alignment: .leading, spacing: 8) {
                            BBPill(text: "分级：\(r.level)", color: r.colors[0])
                            Text("BMI = 体重(kg) ÷ 身高²(m)").font(BBFont.cap(11)).foregroundColor(.secondary)
                            Text("中国标准：＜18.5 偏瘦 · 18.5–23.9 正常 · 24–27.9 超重 · ≥28 肥胖")
                                .font(BBFont.cap(11)).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                calcEmpty("figure.stand", "请输入身高体重", "身高单位 cm，体重单位 kg", CalcLifeMode.bmi.colors)
            }
        }
    }
    private var bmiResult: (bmi: Double, level: String, colors: [Color])? {
        guard let h = Double(bmiHeight), let w = Double(bmiWeight), h > 0, w > 0 else { return nil }
        let m = h / 100.0
        let bmi = w / (m * m)
        if bmi < 18.5 { return (bmi, "偏瘦", [Theme.info, Color(hex: 0x00C2FF)]) }
        if bmi < 24 { return (bmi, "正常", [Theme.success, Color(hex: 0x9BD34A)]) }
        if bmi < 28 { return (bmi, "超重", [Theme.warning, Color(hex: 0xFFB020)]) }
        return (bmi, "肥胖", [Theme.danger, Color(hex: 0xFF5EA8)])
    }

    // MARK: ⑤ 个税
    private var taxSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            BBSectionHeader("收入信息", icon: "yensign.circle.fill")
            calcFields([("月收入", "15000", "元", $taxIncome)])
            BBSectionHeader("个税估算", icon: "doc.text.fill")
            if let r = taxResult {
                CalcResultCard(
                    title: "应纳个税", value: "¥" + calcMoney(r.tax),
                    note: "应纳税所得额 = 月收入 − 5000 起征点；个税 = 应纳税所得额 × 税率 − 速算扣除数",
                    rows: [CalcKV(key: "应纳税所得额", value: "¥" + calcMoney(r.taxable)),
                           CalcKV(key: "适用税率", value: r.bracket),
                           CalcKV(key: "速算扣除数", value: "¥" + calcMoney(r.deduct)),
                           CalcKV(key: "税后到手", value: "¥" + calcMoney(r.after))],
                    colors: CalcLifeMode.tax.colors)
            } else {
                calcEmpty("yensign.circle", "请输入月收入", "按 5000 元起征点估算工资个税", CalcLifeMode.tax.colors)
            }
        }
    }
    private var taxResult: (taxable: Double, tax: Double, after: Double, bracket: String, deduct: Double)? {
        guard let income = Double(taxIncome), income > 0 else { return nil }
        let taxable = max(0, income - 5000)
        if taxable == 0 { return (0, 0, income, "免税（未达起征点）", 0) }
        let table: [(limit: Double, rate: Double, deduct: Double, name: String)] = [
            (3000, 0.03, 0, "3%"), (12000, 0.10, 210, "10%"), (25000, 0.20, 1410, "20%"),
            (35000, 0.25, 2660, "25%"), (55000, 0.30, 4410, "30%"), (80000, 0.35, 7160, "35%"),
            (Double.infinity, 0.45, 15160, "45%")]
        var tax = 0.0, deduct = 0.0, name = "45%"
        for b in table where taxable <= b.limit {
            tax = taxable * b.rate - b.deduct
            deduct = b.deduct
            name = b.name
            break
        }
        let finalTax = max(0, tax)
        return (taxable, finalTax, income - finalTax, name, deduct)
    }
}
