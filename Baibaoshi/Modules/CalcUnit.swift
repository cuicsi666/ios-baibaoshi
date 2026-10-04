import SwiftUI

// MARK: - 单位换算（纯本地 · iOS 16）

struct CalcUnitDef: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    /// 换算到基准单位的比例（温度分类不使用）
    let factor: Double
}

struct CalcUnitCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let isTemperature: Bool
    let units: [CalcUnitDef]

    /// 紧凑写法：id:名称:符号:系数，多单位用 | 分隔
    private static func mk(_ id: String, _ name: String, _ icon: String, _ temp: Bool, _ spec: String) -> CalcUnitCategory {
        let list = spec.split(separator: "|").map { part -> CalcUnitDef in
            let f = part.split(separator: ":").map(String.init)
            return CalcUnitDef(id: f.count > 0 ? f[0] : "u",
                               name: f.count > 1 ? f[1] : "单位",
                               symbol: f.count > 2 ? f[2] : "?",
                               factor: f.count > 3 ? (Double(f[3]) ?? 1) : 1)
        }
        return CalcUnitCategory(id: id, name: name, icon: icon, isTemperature: temp, units: list)
    }

    static let all: [CalcUnitCategory] = [
        mk("len", "长度", "ruler", false,
           "mm:毫米:mm:0.001|cm:厘米:cm:0.01|m:米:m:1|km:千米:km:1000|in:英寸:in:0.0254|ft:英尺:ft:0.3048|yd:码:yd:0.9144|mi:英里:mi:1609.344"),
        mk("wt", "重量", "scalemass", false,
           "mg:毫克:mg:0.000001|g:克:g:0.001|kg:千克:kg:1|t:吨:t:1000|lb:磅:lb:0.45359237|oz:盎司:oz:0.028349523125"),
        mk("temp", "温度", "thermometer", true,
           "c:摄氏度:°C:1|f:华氏度:°F:1|k:开尔文:K:1|r:兰氏度:°R:1"),
        mk("area", "面积", "square.on.square", false,
           "cm2:平方厘米:cm²:0.0001|m2:平方米:m²:1|km2:平方千米:km²:1000000|ha:公顷:ha:10000|mu:亩:亩:666.6666666667|ft2:平方英尺:ft²:0.09290304|acre:英亩:acre:4046.8564224"),
        mk("vol", "体积", "cube", false,
           "ml:毫升:mL:0.001|l:升:L:1|m3:立方米:m³:1000|cup:杯(美):cup:0.2365882365|pt:品脱(美):pt:0.473176473|gal:加仑(美):gal:3.785411784"),
        mk("spd", "速度", "speedometer", false,
           "mps:米/秒:m/s:1|kmh:千米/时:km/h:0.2777777778|mph:英里/时:mph:0.44704|kn:节:kn:0.5144444444|fps:英尺/秒:ft/s:0.3048"),
        mk("data", "数据存储", "internaldrive", false,
           "bit:比特:bit:0.125|b:字节:B:1|kb:千字节:KB:1024|mb:兆字节:MB:1048576|gb:吉字节:GB:1073741824|tb:太字节:TB:1099511627776"),
        mk("time", "时间", "clock", false,
           "ms:毫秒:ms:0.001|s:秒:s:1|min:分钟:min:60|h:小时:h:3600|d:天:d:86400|wk:周:周:604800")
    ]
}

// MARK: - 换算核心

enum CalcUnitMath {
    static func toBase(_ v: Double, _ unit: CalcUnitDef, _ cat: CalcUnitCategory) -> Double {
        guard cat.isTemperature else { return v * unit.factor }
        switch unit.symbol {
        case "°F": return (v - 32) * 5 / 9
        case "K": return v - 273.15
        case "°R": return (v - 491.67) * 5 / 9
        default: return v
        }
    }

    static func fromBase(_ b: Double, _ unit: CalcUnitDef, _ cat: CalcUnitCategory) -> Double {
        guard cat.isTemperature else { return b / unit.factor }
        switch unit.symbol {
        case "°F": return b * 9 / 5 + 32
        case "K": return b + 273.15
        case "°R": return b * 9 / 5 + 491.67
        default: return b
        }
    }

    /// 输出保留约 10 位有效数字并去掉多余 0
    static func fmt(_ v: Double) -> String {
        guard v.isFinite else { return "—" }
        if v == 0 { return "0" }
        let a = abs(v)
        if a >= 1e15 || a < 1e-9 { return String(format: "%.6e", v) }
        let digits = max(0, 9 - Int(floor(log10(a))) - 1)
        let raw = String(format: "%.\(min(digits, 10))f", v)
        guard raw.contains(".") else { return raw }
        var t = raw
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t
    }

    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix(".") { t += "0" }
        return t
    }
}

// MARK: - 主视图

struct CalcUnitView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var catIndex = 0
    @State private var leftUnitIndex = 0
    @State private var rightUnitIndex = 1
    @State private var leftText = "1"
    @State private var rightText = ""
    @State private var base: Double = 1
    @State private var hasValue = true

    @FocusState private var focus: Int?

    private var cat: CalcUnitCategory { CalcUnitCategory.all[min(catIndex, CalcUnitCategory.all.count - 1)] }
    private var leftUnit: CalcUnitDef { cat.units[min(leftUnitIndex, cat.units.count - 1)] }
    private var rightUnit: CalcUnitDef { cat.units[min(rightUnitIndex, cat.units.count - 1)] }

    private func show(_ unit: CalcUnitDef) -> String {
        hasValue ? CalcUnitMath.fmt(CalcUnitMath.fromBase(base, unit, cat)) : "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "arrow.left.arrow.right",
                           colors: Theme.accentColors(),
                           title: "单位换算",
                           subtitle: "8 大类 · 双向实时换算")

                chipRow
                inputCard
                resultCard
                BBSectionHeader("换算为其它单位", icon: "list.bullet.rectangle")
                otherUnitsCard
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("单位换算")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if rightText.isEmpty { rightText = show(rightUnit) }
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(CalcUnitCategory.all.enumerated()), id: \.offset) { idx, c in
                    BBChip(text: c.name, systemImage: c.icon, selected: idx == catIndex) {
                        guard idx != catIndex else { return }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            catIndex = idx
                            switchCategory()
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var inputCard: some View {
        BBCard {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    unitField(side: 0)
                    swapButton
                    unitField(side: 1)
                }
                if !hasValue {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("输入的不是有效数字，请检查")
                            .font(BBFont.cap(11))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(Theme.warning)
                }
                HStack(spacing: 8) {
                    Text("两侧均可输入，另一侧实时换算")
                        .font(BBFont.cap(11))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                    negateButton
                }
            }
        }
    }

    private func unitField(side: Int) -> some View {
        let unit = side == 0 ? leftUnit : rightUnit
        let binding: Binding<String> = side == 0 ? $leftText : $rightText
        return VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(Array(cat.units.enumerated()), id: \.offset) { idx, u in
                    Button("\(u.name) (\(u.symbol))") { selectUnit(side: side, index: idx) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(unit.symbol).font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
            }
            TextField("0", text: binding)
                .focused($focus, equals: side)
                .keyboardType(.decimalPad)
                .font(BBFont.monoBig)
                .foregroundColor(hasValue ? .primary : Theme.warning)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .onChange(of: binding.wrappedValue) { v in
                    handleEdit(side: side, text: v)
                }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BBRadius.m, style: .continuous)
            .fill(Theme.panel(scheme == .dark)))
    }

    private var swapButton: some View {
        Button {
            BBHaptic.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                let tu = leftUnitIndex; leftUnitIndex = rightUnitIndex; rightUnitIndex = tu
                let tt = leftText; leftText = rightText; rightText = tt
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.accentGradient))
        }
        .buttonStyle(.plain)
    }

    private var negateButton: some View {
        Button {
            BBHaptic.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                base = -base
                hasValue = true
                leftText = show(leftUnit)
                rightText = show(rightUnit)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.slash.minus").font(.system(size: 10, weight: .bold))
                Text("取反").font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private var resultCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: cat.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accentGradient)
                    Text("换算结果").font(BBFont.head(15))
                    Spacer(minLength: 0)
                    BBPill(text: cat.name, color: Theme.accent)
                }
                Text(show(rightUnit))
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .foregroundColor(hasValue ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text("\(show(leftUnit)) \(leftUnit.symbol)")
                        .font(BBFont.mono).foregroundColor(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                    Text("\(show(rightUnit)) \(rightUnit.symbol)")
                        .font(BBFont.mono).foregroundColor(Theme.accent)
                }
                Divider().opacity(0.4)
                BBKV(key: "\(leftUnit.name)（\(leftUnit.symbol)）", value: show(leftUnit))
                BBKV(key: "\(rightUnit.name)（\(rightUnit.symbol)）", value: show(rightUnit))
            }
        }
    }

    private var otherUnitsCard: some View {
        BBCard(padding: BBSpacing.m) {
            VStack(spacing: 9) {
                ForEach(cat.units) { u in
                    BBKV(key: "\(u.name) (\(u.symbol))", value: show(u))
                }
            }
        }
    }

    // MARK: 逻辑

    private func switchCategory() {
        leftUnitIndex = 0
        rightUnitIndex = min(1, cat.units.count - 1)
        leftText = show(leftUnit)
        rightText = show(rightUnit)
    }

    private func selectUnit(side: Int, index: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if side == 0 { leftUnitIndex = index } else { rightUnitIndex = index }
            leftText = show(leftUnit)
            rightText = show(rightUnit)
        }
    }

    /// 只有获得焦点的输入框才是驱动方，避免双向联动死循环
    private func handleEdit(side: Int, text: String) {
        guard focus == side else { return }
        let t = CalcUnitMath.clean(text)
        let unit = side == 0 ? leftUnit : rightUnit
        guard !t.isEmpty, let d = Double(t), d.isFinite else {
            hasValue = false
            setOther(side, "")
            return
        }
        hasValue = true
        base = CalcUnitMath.toBase(d, unit, cat)
        setOther(side, CalcUnitMath.fmt(CalcUnitMath.fromBase(base, side == 0 ? rightUnit : leftUnit, cat)))
    }

    private func setOther(_ side: Int, _ value: String) {
        if side == 0 {
            if rightText != value { rightText = value }
        } else if leftText != value {
            leftText = value
        }
    }
}
