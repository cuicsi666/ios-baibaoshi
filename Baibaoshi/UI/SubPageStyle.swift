import SwiftUI

/// 子页面统一表现：图标返回 + 左边缘滑动返回（去掉系统 "Back" 字样）
struct BBSubPage: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        BBHaptic.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 26)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { v in
                                if v.translation.width > 55 { dismiss() }
                            }
                    )
            }
    }
}

extension View {
    func bbSubPage() -> some View { modifier(BBSubPage()) }
}
