import SwiftUI

struct IdiomView: View {
    @EnvironmentObject var idioms: IdiomStore
    @State private var copied = false

    var body: some View {
        VStack(spacing: 22) {
            PageHeader(icon: "text.book.closed.fill", colors: Theme.idiom, title: "励志成语", subtitle: "每 60 秒自动轮换 · 与主页同步")

            Spacer(minLength: 4)

            // 主卡
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(Theme.idiom[0].opacity(0.4), lineWidth: 1.5)
                    )
                    .shadow(color: Theme.idiom[0].opacity(0.2), radius: 24, y: 10)

                VStack(spacing: 14) {
                    Text(idioms.current.text)
                        .font(.system(size: 54, weight: .heavy, design: .serif))
                        .foregroundStyle(Theme.gradient(Theme.idiom))
                        .id(idioms.index)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.7).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                    Text(idioms.current.pinyin)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundColor(.secondary)
                    Rectangle().fill(Theme.idiom[0].opacity(0.35)).frame(width: 44, height: 3).cornerRadius(2)
                    Text(idioms.current.meaning)
                        .font(.system(size: 15))
                        .foregroundColor(.primary.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                }
            }
            .frame(height: 330)
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: idioms.index)

            Spacer(minLength: 4)

            // 倒计时环 + 按钮
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(idioms.progress))
                        .stroke(Theme.gradient(Theme.idiom), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: idioms.tick)
                    Text("\(Int(IdiomStore.interval - Double(idioms.tick)))s")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(width: 52, height: 52)

                Button { idioms.next() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.2.squarepath")
                        Text("换一个")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.gradient(Theme.idiom)))
                    .shadow(color: Theme.idiom[0].opacity(0.45), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    UISelectionFeedbackGenerator().selectionChanged()
                })

                Button { copyIdiom() } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)

            Text("共 \(Idioms.list.count) 条 · 励志精选")
                .font(.caption2).foregroundColor(.secondary)
        }
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func copyIdiom() {
        let i = idioms.current
        UIPasteboard.general.string = "【\(i.text)】\(i.pinyin) —— \(i.meaning)"
        copied = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}
