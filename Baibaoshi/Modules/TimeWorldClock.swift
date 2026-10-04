import SwiftUI

// MARK: - 世界时钟 TimeWorldClockView：内置城市时区表 + 每秒刷新 + Canvas 表盘，纯本地
// 自定义类型统一使用 Clock 前缀，避免与主工程冲突。

struct ClockCity: Identifiable, Equatable {
    let zoneID: String, name: String, region: String, emoji: String
    var id: String { "\(zoneID)#\(name)" }
    var zone: TimeZone { TimeZone(identifier: zoneID) ?? TimeZone.current }
}

// MARK: 内置城市表 + 持久化

enum ClockCatalog {
    static let all: [ClockCity] = [
        ClockCity(zoneID: "Asia/Shanghai", name: "北京", region: "中国", emoji: "🇨🇳"), ClockCity(zoneID: "Asia/Shanghai", name: "上海", region: "中国", emoji: "🇨🇳"),
        ClockCity(zoneID: "Asia/Hong_Kong", name: "香港", region: "中国香港", emoji: "🇭🇰"), ClockCity(zoneID: "Asia/Taipei", name: "台北", region: "中国台湾", emoji: "🇨🇳"),
        ClockCity(zoneID: "Asia/Tokyo", name: "东京", region: "日本", emoji: "🇯🇵"), ClockCity(zoneID: "Asia/Seoul", name: "首尔", region: "韩国", emoji: "🇰🇷"),
        ClockCity(zoneID: "Asia/Singapore", name: "新加坡", region: "新加坡", emoji: "🇸🇬"), ClockCity(zoneID: "Asia/Bangkok", name: "曼谷", region: "泰国", emoji: "🇹🇭"),
        ClockCity(zoneID: "Asia/Kolkata", name: "新德里", region: "印度", emoji: "🇮🇳"), ClockCity(zoneID: "Asia/Dubai", name: "迪拜", region: "阿联酋", emoji: "🇦🇪"),
        ClockCity(zoneID: "Europe/Moscow", name: "莫斯科", region: "俄罗斯", emoji: "🇷🇺"), ClockCity(zoneID: "Europe/Berlin", name: "柏林", region: "德国", emoji: "🇩🇪"),
        ClockCity(zoneID: "Europe/Paris", name: "巴黎", region: "法国", emoji: "🇫🇷"), ClockCity(zoneID: "Europe/London", name: "伦敦", region: "英国", emoji: "🇬🇧"),
        ClockCity(zoneID: "Africa/Cairo", name: "开罗", region: "埃及", emoji: "🇪🇬"), ClockCity(zoneID: "Africa/Johannesburg", name: "约翰内斯堡", region: "南非", emoji: "🇿🇦"),
        ClockCity(zoneID: "America/New_York", name: "纽约", region: "美国东部", emoji: "🇺🇸"), ClockCity(zoneID: "America/Chicago", name: "芝加哥", region: "美国中部", emoji: "🇺🇸"),
        ClockCity(zoneID: "America/Los_Angeles", name: "洛杉矶", region: "美国西部", emoji: "🇺🇸"), ClockCity(zoneID: "America/Sao_Paulo", name: "圣保罗", region: "巴西", emoji: "🇧🇷"),
        ClockCity(zoneID: "Australia/Sydney", name: "悉尼", region: "澳大利亚", emoji: "🇦🇺"), ClockCity(zoneID: "Australia/Perth", name: "珀斯", region: "澳大利亚", emoji: "🇦🇺"),
        ClockCity(zoneID: "Pacific/Auckland", name: "奥克兰", region: "新西兰", emoji: "🇳🇿"),
        ClockCity(zoneID: "UTC", name: "协调世界时", region: "UTC", emoji: "🌐")
    ]
    static var defaultKeys: [String] {
        ["Asia/Shanghai#北京", "Asia/Tokyo#东京", "Europe/London#伦敦", "America/New_York#纽约"]
    }
    static var defaultStore: String { encode(defaultKeys) }
    static func encode(_ keys: [String]) -> String {
        (try? JSONEncoder().encode(keys)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
    static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let keys = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return keys
    }
    /// 由持久化键还原城市（未知标识符兜底命名，保证不崩）
    static func resolve(_ key: String) -> ClockCity {
        if let hit = all.first(where: { $0.id == key }) { return hit }
        let parts = key.split(separator: "#", maxSplits: 1).map(String.init)
        let zoneID = parts.first ?? key
        let fallback = zoneID.split(separator: "/").last.map(String.init) ?? zoneID
        return ClockCity(zoneID: zoneID, name: parts.count > 1 ? parts[1] : fallback,
                         region: "自定义", emoji: "🌐")
    }
}

// MARK: 计算 / 文案

enum ClockMath {
    static func components(_ date: Date, _ zone: TimeZone) -> (h: Int, m: Int, s: Int) {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
    /// 与本地时差，如 +8h / -5h / +5.5h
    static func offsetText(_ seconds: Int) -> String {
        if seconds == 0 { return "与本地同步" }
        let hours = Double(seconds) / 3600
        return (hours > 0 ? "+" : "-") + hourText(abs(hours)) + "h"
    }
    /// UTC 偏移，如 UTC+8
    static func utcText(_ zone: TimeZone) -> String {
        let hours = Double(zone.secondsFromGMT()) / 3600
        return "UTC\(hours >= 0 ? "+" : "-")\(hourText(abs(hours)))"
    }
    /// 整数小时去掉小数位，半点保留 .5
    private static func hourText(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
    /// 0 今天 / 1 明天 / -1 昨天
    static func dayDelta(_ date: Date, zone: TimeZone) -> Int {
        let city = stamp(date, zone), local = stamp(date, TimeZone.current)
        return city == local ? 0 : (city > local ? 1 : -1)
    }
    private static func stamp(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = zone
        return f.string(from: date)
    }
    static func isDaytime(hour: Int) -> Bool { hour >= 6 && hour < 18 }   // 6-18 点算白天
    static func timeText(_ date: Date, _ zone: TimeZone) -> String { formatter("HH:mm:ss", zone).string(from: date) }
    static func dateText(_ date: Date, _ zone: TimeZone) -> String { formatter("M月d日 EEEE", zone).string(from: date) }
    private static var cache: [String: DateFormatter] = [:]
    /// 按「格式 + 时区」缓存 DateFormatter，避免每秒重复创建
    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let key = "\(format)|\(zone.identifier)"
        if let hit = cache[key] { return hit }
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "zh_CN")
        fmt.timeZone = zone; fmt.dateFormat = format
        cache[key] = fmt
        return fmt
    }
}


// MARK: 表盘（Canvas 画时针 / 分针 / 秒针）

struct ClockDial: View {
    var date: Date
    var zone: TimeZone
    var size: CGFloat = 66
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = ClockMath.components(date, zone)
        let hour: CGFloat = CGFloat(c.h)
        let minute: CGFloat = CGFloat(c.m)
        let second: CGFloat = CGFloat(c.s)
        return Canvas { ctx, canvas in
            let center: CGPoint = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let radius: CGFloat = min(canvas.width, canvas.height) / 2 - 1.5
            let face = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ctx.fill(face, with: .color(Theme.panel(scheme == .dark)))
            ctx.stroke(face, with: .color(Theme.accent.opacity(0.22)), lineWidth: 1)
            for tick in 0..<12 {
                let a: CGFloat = CGFloat(tick) / 12 * 2 * CGFloat.pi - CGFloat.pi / 2
                let ca: CGFloat = CGFloat(Foundation.cos(Double(a)))
                let sa: CGFloat = CGFloat(Foundation.sin(Double(a)))
                var m = Path(CGPoint(x: center.x + ca * (radius - 5.5), y: center.y + sa * (radius - 5.5)))
                m.addLine(to: CGPoint(x: center.x + ca * (radius - 2), y: center.y + sa * (radius - 2)))
                ctx.stroke(m, with: .color(Theme.accent.opacity(0.4)), lineWidth: 1)
            }
            hand(&ctx, center: center, degrees: Double((hour.truncatingRemainder(dividingBy: 12) + minute / 60) * 30), length: radius * 0.46, width: 2.6, color: Color.primary)
            hand(&ctx, center: center, degrees: Double((minute + second / 60) * 6), length: radius * 0.68, width: 2, color: Color.primary.opacity(0.85))
            hand(&ctx, center: center, degrees: Double(second * 6), length: radius * 0.82, width: 1.2, color: Theme.accent)
            let hub = CGRect(x: center.x - 2.2, y: center.y - 2.2, width: 4.4, height: 4.4)
            ctx.fill(Path(ellipseIn: hub), with: .color(Theme.accent))
        }
        .frame(width: size, height: size)
    }
    private func hand(_ ctx: inout GraphicsContext, center: CGPoint, degrees: Double, length: CGFloat, width: CGFloat, color: Color) {
        let radians: Double = (degrees - 90) * Double.pi / 180
        let cr: CGFloat = CGFloat(Foundation.cos(radians))
        let sr: CGFloat = CGFloat(Foundation.sin(radians))
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + cr * length, y: center.y + sr * length))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
/// 秒进度弧（Shape 版，叠在表盘外圈）
struct ClockSweepShape: Shape {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2 - 1,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * max(0.001, min(1, progress))), clockwise: false)
        return path
    }
}

// MARK: 城市卡片

struct ClockCityCard: View {
    let city: ClockCity
    let now: Date
    let localOffset: Int
    let showDial: Bool
    let editing: Bool
    let onDelete: () -> Void
    var body: some View {
        let zone = city.zone, c = ClockMath.components(now, zone)
        let isDay = ClockMath.isDaytime(hour: c.h)
        let delta = ClockMath.offsetText(zone.secondsFromGMT(for: now) - localOffset)
        let dayDelta = ClockMath.dayDelta(now, zone: zone)
        return BBCard(padding: 14, radius: BBRadius.m) {
            HStack(spacing: 14) {
                if showDial {
                    ZStack {
                        ClockDial(date: now, zone: zone, size: 66)
                        ClockSweepShape(progress: Double(c.s) / 60.0)
                            .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 66, height: 66)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(city.emoji).font(.system(size: 14))
                        Text(city.name).font(BBFont.head(16)).lineLimit(1)
                        if dayDelta != 0 {
                            BBPill(text: dayDelta > 0 ? "明天" : "昨天", color: dayDelta > 0 ? Theme.info : Theme.warning)
                        }
                    }
                    Text(city.region).font(BBFont.cap(11)).foregroundColor(.secondary)
                    Text(ClockMath.dateText(now, zone)).font(BBFont.cap(11)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: isDay ? "sun.max.fill" : "moon.stars.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isDay ? .orange : .indigo)
                        Text(ClockMath.timeText(now, zone))
                            .font(.system(size: 19, weight: .bold, design: .monospaced))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Text(delta).font(BBFont.cap(11)).foregroundColor(.secondary)
                    BBPill(text: ClockMath.utcText(zone), color: Theme.accent)
                }
                if editing {
                    Button { BBHaptic.warn(); onDelete() } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundColor(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: 主视图

struct TimeWorldClockView: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("bb.clock.cities") private var cityStore: String = ClockCatalog.defaultStore
    @AppStorage("bb.clock.dials") private var showDials: Bool = true
    @State private var now = Date()
    @State private var timer: Timer?
    @State private var showAdd = false
    @State private var editing = false
    private var cities: [ClockCity] { ClockCatalog.decode(cityStore).map { ClockCatalog.resolve($0) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "globe.asia.australia.fill", colors: Theme.accentColors(),
                           title: "世界时钟", subtitle: "本地即时换算 · 共 \(cities.count) 座城市")
                localCard
                BBSectionHeader("世界时间", icon: "clock.badge.checkmark") {
                    HStack(spacing: 8) {
                        BBChip(text: "表盘", systemImage: "clock", selected: showDials) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showDials.toggle() }
                        }
                        Button {
                            BBHaptic.tap()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { editing.toggle() }
                        } label: {
                            Image(systemName: editing ? "checkmark.circle.fill" : "slider.horizontal.3").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.accent)
                        }.buttonStyle(.plain)
                    }
                }
                if cities.isEmpty {
                    BBCard { BBEmptyState(icon: "globe", title: "还没有城市", message: "点下面的按钮添加你关心的时区") }
                } else {
                    ForEach(cities) { city in
                        ClockCityCard(city: city, now: now,
                                      localOffset: TimeZone.current.secondsFromGMT(for: now),
                                      showDial: showDials, editing: editing,
                                      onDelete: { removeCity(city.id) })
                    }
                }
                HStack(spacing: 10) {
                    BBPrimaryButton(title: showAdd ? "收起城市表" : "添加城市",
                                    icon: showAdd ? "chevron.up" : "plus") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showAdd.toggle() }
                    }
                    BBGhostButton(title: "恢复默认", icon: "arrow.counterclockwise") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { resetCities() }
                    }
                }
                if showAdd { addCityCard }
            }
            .padding(.horizontal, BBSpacing.screen).padding(.top, 8).padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationTitle("世界时钟")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }
    /// 从内置表点选添加城市
    private var addCityCard: some View {
        let added = ClockCatalog.decode(cityStore)
        let remain = ClockCatalog.all.filter { !added.contains($0.id) }
        return BBCard(padding: 12, radius: BBRadius.m) {
            VStack(alignment: .leading, spacing: 8) {
                if remain.isEmpty {
                    Text("内置城市已全部添加").font(BBFont.cap(12)).foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(remain) { city in
                                BBChip(text: city.name, systemImage: "plus") { addCity(city.id) }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
    /// 本地时间总览
    private var localCard: some View {
        let zone = TimeZone.current, c = ClockMath.components(now, zone)
        let fraction = (Double(c.h) * 3600 + Double(c.m) * 60 + Double(c.s)) / 86400
        let isDay = ClockMath.isDaytime(hour: c.h)
        return BBCard {
            HStack(spacing: 16) {
                BBRing(progress: Double(c.s) / 60.0, lineWidth: 9, label: String(format: "%02d", c.s), caption: "秒")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("本地时间").font(BBFont.cap(12)).foregroundColor(.secondary)
                        BBPill(text: ClockMath.utcText(zone), color: Theme.info)
                        BBPill(text: isDay ? "白天" : "夜间", color: isDay ? Theme.warning : Theme.accent)
                    }
                    Text(ClockMath.timeText(now, zone))
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(ClockMath.dateText(now, zone)).font(BBFont.cap(12)).foregroundColor(.secondary)
                    BBMeter(value: fraction, colors: [.orange, .purple], height: 6)
                    Text("今日已过 \(Int(fraction * 100))%").font(BBFont.cap(10)).foregroundColor(.secondary)
                }
            }
        }
    }
    // MARK: 每秒刷新（Timer，onDisappear 失效）
    private func startTimer() {
        stopTimer()
        now = Date()
        let ticker = Timer(timeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async { now = Date() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    // MARK: 持久化（键 bb.clock.cities）
    private func addCity(_ key: String) {
        var keys = ClockCatalog.decode(cityStore)
        guard !keys.contains(key) else { return }
        keys.append(key)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { cityStore = ClockCatalog.encode(keys) }
        BBHaptic.success()
    }
    private func removeCity(_ key: String) {
        var keys = ClockCatalog.decode(cityStore)
        keys.removeAll { $0 == key }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { cityStore = ClockCatalog.encode(keys) }
    }
    private func resetCities() {
        cityStore = ClockCatalog.defaultStore
        BBHaptic.success()
    }
}