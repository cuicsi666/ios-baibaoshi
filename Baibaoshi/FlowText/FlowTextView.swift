import SwiftUI

struct FlowTextView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        Group {
            ScrollView {
                VStack(spacing: 14) {
                    // 连接状态卡
                    VStack(spacing: 10) {
                        HStack {
                            Circle()
                                .fill(ble.connected ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                            Text(ble.state)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        Text(ble.connected ? "设备：\(ble.deviceName) · 长按板子右侧键说话，文字会流入输入框" : "板子说话 → 文字直接流入手机任意输入框")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: {
                            if ble.connected { ble.disconnect() } else { ble.startScan() }
                        }) {
                            Text(ble.connected ? "断开连接" : "连接 XUI 设备")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))

                    // 最近文本卡
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近流向手机的文字")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                        if ble.history.isEmpty {
                            Text("还没有内容，去板子上说话吧")
                                .font(.system(size: 13))
                                .foregroundColor(.gray.opacity(0.6))
                        } else {
                            ForEach(ble.history, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 4)
                                Divider().overlay(Color.white.opacity(0.08))
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))

                    // 使用说明卡
                    VStack(alignment: .leading, spacing: 8) {
                        Text("首次使用（3 步）")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                        Text("① 连接上方按钮，与板子配对\n② 系统设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 选「流文」，并点开「允许完全访问」\n③ 任意输入框切到流文键盘，长按板子右侧键说话，文字自动流入")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
                }
                .padding(14)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("流文")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
