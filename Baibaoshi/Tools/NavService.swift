import Foundation

// MARK: - 导航站数据（g-navigation links.json）
struct NavCategory: Codable {
    let id: String
    let name: String
    let links: [NavLink]
}

struct NavLink: Codable {
    let title: String
    let url: String
}

final class NavService: ObservableObject {
    static let shared = NavService()
    @Published private(set) var categories: [NavCategory] = []

    var linksCount: Int { categories.reduce(0) { $0 + $1.links.count } }
    var allLinks: [NavLink] { categories.flatMap(\.links) }

    func load() {
        guard categories.isEmpty else { return }
        let url = URL(string: "http://6.6.6.130:8099/data/links.json")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data,
                  let cats = try? JSONDecoder().decode([NavCategory].self, from: data) else { return }
            DispatchQueue.main.async { self.categories = cats }
        }.resume()
    }

    func randomLink() -> NavLink? {
        let all = allLinks
        return all.isEmpty ? nil : all.randomElement()
    }
}
