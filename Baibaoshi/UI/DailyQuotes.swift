import SwiftUI

// MARK: - 励志短句（点一下换一句）

struct DailyQuotes {
    struct Q {
        let text: String
        let colors: [Color]
    }

    static let all: [Q] = [
        .init(text: "星光不问赶路人，时光不负有心人", colors: [Color(hex: 0x4F8DFD), Color(hex: 0x8B5CF6)]),
        .init(text: "把每个平凡的日子，过成闪闪发光的样子", colors: [Color(hex: 0xFF9A62), Color(hex: 0xFF5F8F)]),
        .init(text: "慢一点没关系，方向对了就好", colors: [Color(hex: 0x2ED6C4), Color(hex: 0x38A3FF)]),
        .init(text: "你只管努力，剩下的交给时间", colors: [Color(hex: 0xB388FF), Color(hex: 0xFF8BCB)]),
        .init(text: "今天多学一点，明天就多一条路", colors: [Color(hex: 0xFFC24B), Color(hex: 0xFF8A3D)]),
        .init(text: "所有的热爱，都值得被认真对待", colors: [Color(hex: 0x0EA5E9), Color(hex: 0x22D3EE)]),
        .init(text: "不慌不忙，我们都在成为更好的自己", colors: [Color(hex: 0x34D399), Color(hex: 0x0D9488)]),
        .init(text: "山高路远，看世界，也找自己", colors: [Color(hex: 0x6366F1), Color(hex: 0xA855F7)]),
        .init(text: "把喜欢的事做到极致，就是天赋", colors: [Color(hex: 0xF472B6), Color(hex: 0xFB7185)]),
        .init(text: "日子是自己的，快乐也是", colors: [Color(hex: 0xFBBF24), Color(hex: 0xF97316)]),
        .init(text: "心之所向，素履以往", colors: [Color(hex: 0x38BDF8), Color(hex: 0x4F46E5)]),
        .init(text: "别急，最好的总会在不经意间出现", colors: [Color(hex: 0xE879F9), Color(hex: 0x818CF8)]),
        .init(text: "认真生活的人，运气都不会太差", colors: [Color(hex: 0x22D3EE), Color(hex: 0x10B981)]),
        .init(text: "每一点进步，都在悄悄改变未来", colors: [Color(hex: 0xFB923C), Color(hex: 0xEF4444)]),
        .init(text: "先成为自己的光，再照亮别人", colors: [Color(hex: 0xA78BFA), Color(hex: 0x60A5FA)]),
        .init(text: "熬过无人问津的日子，才有诗和远方", colors: [Color(hex: 0x14B8A6), Color(hex: 0x3B82F6)]),
        .init(text: "与其感慨路难行，不如马上出发", colors: [Color(hex: 0xF59E0B), Color(hex: 0xEC4899)]),
        .init(text: "愿你所行皆坦途，所求皆如愿", colors: [Color(hex: 0x8B5CF6), Color(hex: 0x06B6D4)]),
        .init(text: "生活明朗，万物可爱", colors: [Color(hex: 0xFB7185), Color(hex: 0xFBBF24)]),
        .init(text: "把今天过好，就是最好的答案", colors: [Color(hex: 0x10B981), Color(hex: 0x84CC16)]),
    ]
}
