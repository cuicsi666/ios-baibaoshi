import SwiftUI
import UIKit

// MARK: - 屏蔽系统更新

struct UpdateBlockerView: View {
    @AppStorage("bb.blockOTA") private var enabled = false
    @Environment(\.colorScheme) private var scheme

    private let profileURL = URL(string: "https://cuicsi666.github.io/ios-baibaoshi/disable_ota.mobileconfig")!

    private var sysVersion: String {
        UIDevice.current.systemVersion
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroCard
                switchCard
                stepsCard
                noteCard
            }
            .padding(.horizontal, BBSpacing.screen)
            .padding(.bottom, 30)
        }
        .background(BBAuroraBackground(scheme: scheme))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 顶部

    private var heroCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.gradient([Color(hex: 0x6366F1), Color(hex: 0x22D3EE)]))
                            .frame(width: 48, height: 48)
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("屏蔽系统更新").font(BBFont.title(20))
                        Text("装一个描述文件，让系统不再收到 OTA 推送")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Divider()

                HStack {
                    Label("当前系统", systemImage: "iphone.gen3")
                        .font(.system(size: 13))
                    Spacer()
                    Text("iOS \(sysVersion)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }

                HStack {
                    Label("屏蔽状态", systemImage: "lock.shield")
                        .font(.system(size: 13))
                    Spacer()
                    Text(enabled ? "已开启" : "未开启")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill((enabled ? Theme.success : Color.gray).opacity(0.16)))
                        .foregroundColor(enabled ? Theme.success : .secondary)
                }
            }
        }
    }

    // MARK: 开关

    private var switchCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                BBSectionHeader("屏蔽开关", icon: "switch.2")

                Toggle(isOn: Binding(
                    get: { enabled },
                    set: { v in
                        enabled = v
                        if v { installProfile() }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("屏蔽 iOS 更新").font(.system(size: 14, weight: .medium))
                        Text(enabled ? "已记录开启，如未安装请点下方按钮" : "打开后会跳转 Safari 安装描述文件")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .tint(Theme.accent)

                BBPrimaryButton(title: "安装屏蔽描述文件", icon: "arrow.down.doc.fill",
                                colors: [Color(hex: 0x6366F1), Color(hex: 0x22D3EE)]) {
                    installProfile()
                }

                Text("安装完成后，到「设置 → 通用 → VPN 与设备管理」确认出现 tvOS Beta Software Profile")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: 原理

    private var stepsCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                BBSectionHeader("原理与步骤", icon: "info.circle.fill")

                step("1", "点「安装屏蔽描述文件」，Safari 会提示下载配置描述文件")
                step("2", "点「允许」→ 打开「设置」，顶部出现「已下载描述文件」")
                step("3", "点进去 → 右上角「安装」→ 输入锁屏密码 → 安装")
                step("4", "回到「设置 → 通用 → 软件更新」，会显示当前已是最新版本")

                Divider()

                Text("原理：安装 tvOS 的 Beta 描述文件后，系统会被识别成 tvOS 测试设备，iOS 的 OTA 更新服务器就不会再推送更新包，从而达到「屏蔽更新」的效果。")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noteCard: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 10) {
                BBSectionHeader("注意事项", icon: "exclamationmark.triangle.fill",
                                colors: [Color(hex: 0xF59E0B), Color(hex: 0xEF4444)])

                bullet("想恢复更新：到「设置 → 通用 → VPN 与设备管理」删除该描述文件，重启后即可正常检测更新。")
                bullet("新系统（iOS 26/27）苹果可能封堵此方式；如果装完仍能检测到更新，说明该方法在你这版系统上已失效。")
                bullet("描述文件只改更新通道，不收集任何数据，可随时删除。")
                bullet("装完记得在「软件更新」里关掉「自动更新」，双保险。")
            }
        }
    }

    // MARK: 小组件

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(n)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.accent.opacity(0.6)).frame(width: 5, height: 5).padding(.top, 6)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func installProfile() {
        BBHaptic.tap()
        UIApplication.shared.open(profileURL)
    }
}
