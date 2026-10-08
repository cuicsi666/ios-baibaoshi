import SwiftUI

// MARK: - 哔哩Plus 入口卡片视图
// 点击百宝箱首页的「哔哩Plus」卡片后进入此页，自动尝试拉起已安装的哔哩Plus app
// （如未安装则提示）。返回本页顶栏有「返回百宝箱」。

struct BiliLauncherView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var opened = false
    @State private var launching = false

    var body: some View {
        ZStack {
            BBAuroraBackground(scheme: .light)
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(LinearGradient(colors: [.cyan, .blue, .pink],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 96, height: 96)
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("哔哩Plus")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(launching ? "正在打开哔哩Plus…" : (opened ? "已跳到哔哩Plus\n可返回百宝箱" : "未检测到哔哩Plus，请先安装"))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()

                Button {
                    launch()
                } label: {
                    Label(opened ? "再次打开" : "打开哔哩Plus", systemImage: "arrow.up.right.square.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .navigationTitle("哔哩Plus")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Label("返回", systemImage: "chevron.left") }
            }
        }
        .onAppear { launch() }
    }

    private func launch() {
        guard let url = URL(string: "bilibili://"), !launching else { return }
        launching = true
        UIApplication.shared.open(url) { ok in
            DispatchQueue.main.async {
                opened = ok
                launching = false
            }
        }
    }
}