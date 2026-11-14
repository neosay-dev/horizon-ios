import Foundation

/// The port's releases on GitHub, for the What's new page (the original's Patch notes).
@MainActor
final class NewsStore: ObservableObject {
    struct Release: Identifiable {
        var id: Int
        var name: String
        var tag: String
        var date: Date?
        var body: String
        var url: URL?
    }

    static let api = URL(string: "https://api.github.com/repos/neosay-dev/horizon-ios/releases?per_page=20")!
    static let page = URL(string: "https://github.com/neosay-dev/horizon-ios/releases")!

    @Published var releases: [Release] = []
    @Published var error: String?
    @Published var loading = false

    func load() async {
        if loading { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            var request = URLRequest(url: Self.api)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue(ModsStore.agent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let list = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            let iso = ISO8601DateFormatter()
            releases = list.compactMap { r in
                guard let id = r["id"] as? Int, (r["draft"] as? Bool) != true else { return nil }
                let tag = r["tag_name"] as? String ?? ""
                return Release(
                    id: id,
                    name: (r["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag,
                    tag: tag,
                    date: (r["published_at"] as? String).flatMap { iso.date(from: $0) },
                    body: r["body"] as? String ?? "",
                    url: (r["html_url"] as? String).flatMap(URL.init(string:)))
            }
        } catch {
            self.error = "Не удалось загрузить релизы: \(error.localizedDescription)"
        }
    }
}
