import SwiftUI

// MARK: - V应用嵌入（ESXi + OpenWrt + 工具箱 三 Tab，ObjC 混编）

struct VAppPlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        VAppEmbed.rootViewController()
    }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}
