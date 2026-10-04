import SwiftUI
import UIKit

// MARK: - 时间戳转换（TimeStampView）
// 纯本地：① 当前时间戳 0.1s 实时刷新（秒 / 毫秒，可复制）
// ② 时间戳 → 日期（自动识别 10 位秒 / 13 位毫秒）③ 日期 → 时间戳
// ④ 两个时间戳差值（天 / 时 / 分 / 秒）⑤ 常用格式预设。
// 自定义类型统一使用 Stamp 前缀，避免与主工程冲突。

// MARK: - 模型

/// 时间戳单位（根据输入位数自动识别）
enum StampUnit: String {
    case seconds = "秒 · 10 位"
    case millis  = "毫秒 · 13 位"
}

/// 解析结果
struct StampParsed {
    let date: Date
    let unit: StampUnit
    let raw: String
}

// MARK: - 计算

enum StampTool {
    /// 支持 1~20 位纯数字：12 位及以上按毫秒处理；超出合理年份返回 nil
    static func parse(_ raw: String) -> StampParsed? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 20, t.allSatisfy({ $0.isNumber }), let v = Double(t) else { return nil }
        let isMillis = t.count > 11
        let secs = isMillis ? v / 1000 : v
        guard secs > -62_167_219_200, secs < 253_402_300_800 else { return nil }
        return StampParsed(date: Date(timeIntervalSince1970: secs), unit: isMillis ? .millis : .seconds, raw: t)
    }

    static func seconds(_ d: Date) -> Int { Int(d.timeIntervalSince1970.rounded(.down)) }

    static func millis(_ d: Date) -> Int { Int((d.timeIntervalSince1970 * 1000).rounded(.down)) }

    /// A、B 两个时间戳的差值（秒，A - B）
    static func diff(_ a: String, _ b: String) -> TimeInterval? {
        guard let x = parse(a), let y = parse(b) else { return nil }
        return x.date.timeIntervalSince(y.date)
    }

    /// 拆成 天 / 时 / 分 / 秒
    static func split(_ interval: TimeInterval) -> (d: Int, h: Int, m: Int, s: Int, negative: Bool) {
        let total = Int(abs(interval).rounded(.down))
        return (total / 86_400, (total % 86_400) / 3600, (total % 3600) / 60, total % 60, interval < 0)
    }
}

// MARK: - 格式化（带缓存，实时刷新时不重复创建 formatter）

final class StampFmt {
    static let shared = StampFmt()
    private var cache: [String: DateFormatter] = [:]
    private var isoCache: [Bool: ISO8601DateFormatter] = [:]

    private func formatter(_ pattern: String, _ tz: TimeZone) -> DateFormatter {
        let key = "\(tz.identifier)|\(pattern)"
        if let hit = cache[key] { return hit }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = tz
        f.dateFormat = pattern
        cache[key] = f
        return f
    }

    func local(_ d: Date, _ pattern: String = "yyyy-MM-dd HH:mm:ss") -> String {
        formatter(pattern, .current).string(from: d)
    }

    func utc(_ d: Date, _ pattern: String = "yyyy-MM-dd HH:mm:ss") -> String {
        formatter(pattern, TimeZone(identifier: "UTC") ?? .current).string(from: d)
    }

    func iso(_ d: Date, frac: Bool = false) -> String {
        if let hit = isoCache[frac] { return hit.string(from: d) }
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = frac ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        isoCache[frac] = f
        return f.string(from: d)
    }

    /// 相对现在的中文描述（几分钟前 / 几天后 …）
    func relative(_ d: Date) -> String {
        let delta = d.timeIntervalSince(Date())
        let s = abs(delta)
        if s < 2 { return "刚刚" }
        let text: String
        if s < 60 { text = "\(Int(s)) 秒" }
        else if s < 3_600 { text = "\(Int(s / 60)) 分钟" }
        else if s < 86_400 { text = "\(Int(s / 3600)) 小时" }
        else if s < 2_592_000 { text = "\(Int(s / 86_400)) 天" }
        else if s < 31_536_000 { text = "\(Int(s / 2_592_000)) 个月" }
        else { text = "\(Int(s / 31_536_000)) 年" }
        return delta >= 0 ? "\(text)后" : "\(text)前"
    }

    /// 常用格式预设：(pattern, 中文名)
    static let presets: [(String, String)] = [
        ("yyyy-MM-dd HH:mm:ss", "标准"),
        ("yyyy-MM-dd HH:mm:ss.SSS", "带毫秒"),
        ("yyyy/MM/dd HH:mm", "斜杠"),
        ("yyyy年MM月dd日 HH:mm", "中文"),
        ("MM-dd HH:mm:ss", "简短"),
        ("HH:mm:ss", "仅时间"),
        ("EEEE", "星期"),
        ("yyyy-MM-dd'T'HH:mm:ssZ", "ISO 8601")
    ]
}

// MARK: - 主视图

struct TimeStampView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var now = Date()
    @State private var ticker: Timer?
    @State private var copied: String?

    @State private var toDateInput = ""
    @State private var fromDate = Date()
    @State private var diffA = ""
    @State private var diffB = ""
    @State private var presetRef = 0

    private let fmt = StampFmt.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "clock.badge.checkmark", colors: Theme.accentColors(),
                           title: "时间戳", subtitle: "Unix 时间戳 ⇄ 日期 · 实时刷新")
                liveCard
                toDateCard
                fromDateCard
                diffCard
                presetCard
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("时间戳")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startTicker() }
        .onDisappear { stopTicker() }
    }

    // MARK: ① 当前时间戳

    private var secText: String { "\(StampTool.seconds(now))" }

    private var msPartText: String { String(format: "%03d", StampTool.millis(now) % 1000) }

    private var liveCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                BBSectionHeader(title: "当前时间戳", icon: "bolt.fill") {
                    BBPill(text: "0.1s 刷新", color: Theme.success)
                }
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(secText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(".\(msPartText)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                .foregroundStyle(Theme.accentGradient)
                .contentShape(Rectangle())
                .onTapGesture { copy(secText, "sec") }

                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
                    Text(fmt.local(now) + " · 本地")
                }
                .font(BBFont.cap(12))
                .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    copyChip("秒", secText, "sec")
                    copyChip("毫秒", "\(StampTool.millis(now))", "ms")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: ② 时间戳 → 日期

    private var parsed: StampParsed? { StampTool.parse(toDateInput) }

    private var toDateCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("时间戳 → 日期", icon: "arrow.right.square")
                stampField(text: $toDateInput, placeholder: "输入 10 位秒或 13 位毫秒")
                HStack(spacing: 8) {
                    BBChip(text: "现在", systemImage: "clock") { toDateInput = "\(StampTool.seconds(Date()))" }
                    BBChip(text: "今天 0 点", systemImage: "sunrise") {
                        toDateInput = "\(StampTool.seconds(Calendar.current.startOfDay(for: Date())))"
                    }
                }
                if let p = parsed {
                    VStack(alignment: .leading, spacing: 8) {
                        resultLine("本地时间", fmt.local(p.date), strong: true)
                        resultLine("UTC", fmt.utc(p.date) + " UTC")
                        resultLine("ISO 8601", fmt.iso(p.date))
                        resultLine("相对现在", fmt.relative(p.date), mono: false)
                    }
                    HStack(spacing: 6) {
                        BBPill(text: p.unit.rawValue, color: Theme.info)
                        BBPill(text: fmt.local(p.date, "EEEE"), color: Theme.accent)
                        Spacer(minLength: 0)
                    }
                } else if toDateInput.isEmpty {
                    hint("支持 10 位秒 / 13 位毫秒，自动识别", color: .secondary)
                } else {
                    hint("无法识别，请输入纯数字（10 位或 13 位）", color: Theme.danger)
                }
            }
        }
    }

    // MARK: ③ 日期 → 时间戳

    private var fromDateCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("日期 → 时间戳", icon: "arrow.left.square")
                HStack {
                    Text("选择日期时间").font(BBFont.body(14))
                    Spacer()
                    DatePicker("", selection: $fromDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .tint(Theme.accent)
                }
                BBResult(text: "\(StampTool.seconds(fromDate))")
                resultLine("毫秒", "\(StampTool.millis(fromDate))")
                resultLine("本地时间", fmt.local(fromDate, "yyyy-MM-dd HH:mm:ss") )
                HStack(spacing: 8) {
                    BBGhostButton(title: "复制毫秒", icon: "doc.on.doc") { copy("\(StampTool.millis(fromDate))", "fromms") }
                    BBGhostButton(title: "设为现在", icon: "arrow.counterclockwise") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { fromDate = Date() }
                    }
                }
            }
        }
    }

    // MARK: ④ 时间戳差值

    private var diffCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("两个时间戳之差", icon: "plusminus.circle")
                stampField(text: $diffA, placeholder: "时间戳 A")
                stampField(text: $diffB, placeholder: "时间戳 B")
                HStack(spacing: 8) {
                    BBChip(text: "A = 现在", systemImage: "clock") { diffA = "\(StampTool.seconds(Date()))" }
                    BBChip(text: "交换", systemImage: "arrow.left.arrow.right") {
                        let t = diffA; diffA = diffB; diffB = t
                    }
                    BBChip(text: "清空", systemImage: "xmark") { diffA = ""; diffB = "" }
                }
                if let d = StampTool.diff(diffA, diffB) {
                    let sp = StampTool.split(d)
                    HStack(spacing: 8) {
                        miniStat("天", "\(sp.d)")
                        miniStat("时", "\(sp.h)")
                        miniStat("分", "\(sp.m)")
                        miniStat("秒", "\(sp.s)")
                    }
                    resultLine("总秒数", "\(Int(abs(d)))")
                    BBPill(text: sp.negative ? "A 比 B 早" : (d == 0 ? "两个时间相同" : "A 比 B 晚"),
                           color: sp.negative ? Theme.warning : Theme.success)
                } else {
                    hint("请填写两个时间戳，自动计算间隔", color: .secondary)
                }
            }
        }
    }

    // MARK: ⑤ 常用格式预设

    private var presetDate: Date {
        presetRef == 1 ? (parsed?.date ?? now) : now
    }

    private var presetCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                BBSectionHeader("常用格式预设", icon: "textformat")
                BBSegmented(options: [("当前时间", 0), ("输入的时间戳", 1)], selection: $presetRef)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(StampFmt.presets.indices, id: \.self) { i in
                        let item = StampFmt.presets[i]
                        Button {
                            copy(fmt.local(presetDate, item.0), "preset\(i)")
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(item.1) · \(item.0)")
                                        .font(BBFont.cap(10))
                                        .foregroundColor(.secondary)
                                    Text(fmt.local(presetDate, item.0))
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: copied == "preset\(i)" ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(copied == "preset\(i)" ? Theme.success : Theme.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i != StampFmt.presets.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 复用片段

    private func stampField(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))
        .overlay(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous)
            .strokeBorder(Theme.stroke(scheme == .dark), lineWidth: 1))
    }

    private func resultLine(_ key: String, _ value: String, mono: Bool = true, strong: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(BBFont.cap(12))
                .foregroundColor(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 13, weight: strong ? .semibold : .medium, design: .monospaced) : BBFont.body(13))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func hint(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 11, weight: .semibold))
            Text(text).font(BBFont.cap(12))
        }
        .foregroundColor(color)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(BBFont.num(20))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(BBFont.cap(11)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: BBRadius.s, style: .continuous).fill(Theme.panel(scheme == .dark)))
    }

    private func copyChip(_ title: String, _ value: String, _ key: String) -> some View {
        Button { copy(value, key) } label: {
            HStack(spacing: 5) {
                Image(systemName: copied == key ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                Text(copied == key ? "已复制\(title)" : "复制\(title)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(copied == key ? Theme.success : Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill((copied == key ? Theme.success : Theme.accent).opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func copy(_ value: String, _ key: String) {
        guard !value.isEmpty else { return }
        UIPasteboard.general.string = value
        BBHaptic.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { copied = key }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copied == key { withAnimation(.easeOut(duration: 0.2)) { copied = nil } }
        }
    }

    // MARK: - 计时器

    private func startTicker() {
        now = Date()
        stopTicker()
        let t = Timer(timeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async { now = Date() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
