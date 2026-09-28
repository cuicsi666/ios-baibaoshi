import SwiftUI

// MARK: - AI 用量视图：今日花销 + 历史记录

struct AIUsageView: View {
    @StateObject private var usage = AIUsageService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(icon: "brain.head.profile", colors: Theme.nav, title: "AI 用量", subtitle: "ipix 网关 · 每日花销")

                todayCard

                if let err = usage.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                }

                statusRow

                historySection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .refreshable { usage.fetch() }
        .onAppear { usage.fetch() }
    }

    // MARK: 今日花销

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline) {
                Text(usage.today.costDisplay)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gradient(Theme.nav))
                Text(usage.today.credit > 0 ? " 今日电耗 \(Int(usage.today.credit))" : "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Divider()
            HStack(spacing: 8) {
                statBox("请求", "\(usage.today.requests)")
                statBox("Token", "\(usage.today.tokens)")
                statBox("本月", "¥\(String(format: "%.2f", usage.today.monthCredit / 30000 * 100))")
            }
            if usage.today.promptTokens > 0 || usage.today.completionTokens > 0 {
                Text("输入 \(usage.today.promptTokens) · 输出 \(usage.today.completionTokens)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }

    private func statBox(_ k: String, _ v: String) -> some View {
        VStack(spacing: 4) {
            Text(v).font(.system(size: 18, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            Text(k).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private var statusRow: some View {
        HStack {
            Text(usage.lastUpdated.isEmpty ? "点按刷新 · 下拉刷新" : "更新于 \(usage.lastUpdated)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button { usage.fetch() } label: {
                Label("刷新", systemImage: "arrow.clockwise").font(.caption2)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: 历史花销

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("花销记录").font(.headline)
                Spacer()
                Text("累计 \(usage.totalCostDisplay)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(Theme.nav[0])
            }
            if usage.history.isEmpty {
                Text("暂无历史记录，拉取一次后自动累积")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(usage.history) { day in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.dateDisplay).font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(day.costDisplay)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(.primary)
                            Text("\(day.credit)电 · \(day.tokens)tok · \(day.requests)次")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
    }
}

extension AIUsageService {
    var totalCostDisplay: String {
        String(format: "¥%.2f", history.reduce(0) { $0 + $1.cost })
    }
}