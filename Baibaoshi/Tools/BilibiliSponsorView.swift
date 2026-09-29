import SwiftUI

// MARK: - 视频空降助手视图

struct BilibiliSponsorView: View {
    @StateObject private var svc = BilibiliSponsorService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(icon: "video.badge.checkmark", colors: Theme.superkey, title: "视频空降助手", subtitle: "BilibiliSponsorBlock · 跳过赞助/恰饭")

                inputCard
                if !svc.message.isEmpty { messageRow }
                resultSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onDisappear { svc.clear() }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundColor(Theme.superkey[0])
                TextField("粘贴 B站视频链接 或 BV 号", text: $svc.input)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))

            HStack {
                Button {
                    svc.fetch()
                } label: {
                    Label(svc.loading ? "查询中…" : "查询跳过片段", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.superkey[0])
                .disabled(svc.input.trimmingCharacters(in: .whitespaces).isEmpty || svc.loading)

                if !svc.input.isEmpty {
                    Button {
                        svc.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
    }

    private var messageRow: some View {
        HStack(spacing: 6) {
            Image(systemName: svc.message.contains("暂无") || svc.message.contains("失败") ? "info.circle" : "checkmark.circle.fill")
                .foregroundColor(svc.message.contains("暂无") || svc.message.contains("失败") ? .orange : Theme.superkey[0])
            Text(svc.message).font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !svc.groups.isEmpty {
                HStack {
                    Text("片段列表").font(.headline)
                    Spacer()
                    if !svc.resolvedBvid.isEmpty {
                        Text(svc.resolvedBvid).font(.caption2.monospaced()).foregroundColor(.secondary)
                    }
                }
                let segs = svc.groups.flatMap { $0.segments }
                ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                    segmentRow(seg)
                }
                openButton
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
    }

    private func segmentRow(_ seg: BSBSegment) -> some View {
        return HStack(spacing: 12) {
            Text(categoryText(seg.category))
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(categoryColor(seg.category).opacity(0.18)))
                .foregroundColor(categoryColor(seg.category))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(seg.startText) → \(seg.endText)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                Text(seg.durationText + (seg.votes.map { " · \($0)票" } ?? ""))
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button {
                openAt(seg.start)
            } label: {
                Image(systemName: "arrow.down.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.superkey[0])
            }
        }
        .padding(.vertical, 6)
        Divider().overlay(Color.white.opacity(0.05))
    }

    private var openButton: some View {
        Button {
            openAt(nil)
        } label: {
            Label("在 B站 打开该视频", systemImage: "arrow.up.right.square")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.superkey[0])
    }

    // 分类中文映射
    private func categoryText(_ c: String) -> String {
        switch c {
        case "sponsor": return "赞助"
        case "selfpromo": return "恰饭"
        case "intro": return "开场"
        case "outro": return "片尾"
        case "interaction": return "互动"
        case "preview": return "预告"
        case "music_offtopic": return "音乐"
        case "filler": return "拖沓"
        default: return c
        }
    }
    private func categoryColor(_ c: String) -> Color {
        switch c {
        case "sponsor": return Color(hex: 0xFC4A1A)
        case "selfpromo": return Color(hex: 0xF7B733)
        case "intro": return Color(hex: 0x34A853)
        case "outro": return Color(hex: 0x3B9EFF)
        default: return Color(hex: 0x8E9AAF)
        }
    }
    // 打开 B站（网页版带 t 参数定位时间，兼容 App）
    private func openAt(_ seconds: Double?) {
        guard !svc.resolvedBvid.isEmpty else { return }
        var urlStr = "https://www.bilibili.com/video/\(svc.resolvedBvid)"
        if let s = seconds { urlStr += "?t=\(Int(s))" }
        if let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }
}