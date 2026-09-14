import SwiftUI

// MARK: - 历史页

struct CBHistoryView: View {
    @EnvironmentObject var h: ChargeHistory
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    summaryHeader
                    if h.sessions.isEmpty {
                        emptyCard
                    } else {
                        ForEach(h.sessions) { s in
                            SessionCard(session: s)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .background(Theme.background(scheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.heroGradient)
                        Text("充电历史").font(.headline)
                    }
                }
            }
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            summaryCard(value: "\(h.sessions.count)", label: "累计记录次数",
                        icon: "list.bullet.clipboard", color: Theme.teal)
            summaryCard(value: avgFullText, label: "平均充满时长",
                        icon: "battery.100.bolt", color: Theme.mint)
        }
    }

    private var avgFullText: String {
        guard let mins = h.averageFullDurationMinutes else { return "待积累" }
        let m = Int(mins.rounded())
        return m >= 60 ? "\(m / 60)时\(m % 60)分" : "\(m)分钟"
    }

    private func summaryCard(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .cardStyle(scheme)
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundColor(.secondary.opacity(0.6))
            Text("还没有充电记录")
                .font(.system(size: 15, weight: .semibold))
            Text("完成一次充电后，历史数据会用于提升预估准确率")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .cardStyle(scheme)
    }
}

// MARK: - 会话卡片

struct SessionCard: View {
    @Environment(\.colorScheme) private var scheme
    let session: ChargeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // 充入电量徽章
                VStack(spacing: 2) {
                    Text("+\(session.gainedPercent)%")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("充入")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.7)
                }
                .foregroundColor(Theme.mint)
                .frame(width: 62, height: 62)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.mint.opacity(0.13)))

                VStack(alignment: .leading, spacing: 5) {
                    Text(dateText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("\(session.startLevel)% → \(session.endLevel)% · \(durText)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Label(String(format: "%.1f%%/分", session.avgRate), systemImage: "speedometer")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.teal.opacity(0.14)))
                            .foregroundColor(Theme.teal)
                        if session.reachedFull {
                            Label("已充满", systemImage: "checkmark.seal.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.mint.opacity(0.14)))
                                .foregroundColor(Theme.mint)
                        }
                    }
                }
                Spacer()
            }

            Sparkline(points: session.points)
                .frame(height: 42)
        }
        .cardStyle(scheme)
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(session.start) { f.dateFormat = "今天 HH:mm" }
        else if Calendar.current.isDateInYesterday(session.start) { f.dateFormat = "'昨天' HH:mm" }
        else { f.dateFormat = "M月d日 HH:mm" }
        return f.string(from: session.start)
    }

    private var durText: String {
        let m = Int(session.durationMinutes.rounded())
        return m >= 60 ? "\(m / 60)小时\(m % 60)分" : "\(m)分钟"
    }
}

// MARK: - 迷你曲线

struct Sparkline: View {
    let points: [ChargePoint]

    var body: some View {
        GeometryReader { geo in
            Path { p in
                guard points.count >= 2,
                      let first = points.first, let last = points.last else { return }
                let t0 = first.t.timeIntervalSince1970
                let t1 = max(last.t.timeIntervalSince1970, t0 + 1)
                for (i, pt) in points.enumerated() {
                    let x = CGFloat((pt.t.timeIntervalSince1970 - t0) / (t1 - t0)) * geo.size.width
                    let y = (1 - CGFloat(min(max(pt.level, 0), 100)) / 100) * geo.size.height
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Theme.lineGradient, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
