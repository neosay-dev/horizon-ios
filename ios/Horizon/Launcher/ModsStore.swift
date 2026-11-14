import CryptoKit
import Foundation

/// What the Mods page installs, and the game folder each kind goes to (`--game-dir`): content
/// mods (`.hmod`, no code: iOS can't build native mods), resource packs and shader packs.
enum ModKind: String, CaseIterable, Codable {
    case mod, resourcepack, shader

    var folder: String {
        switch self {
        case .mod: return "horizon-mods"
        case .resourcepack: return "resourcepacks"
        case .shader: return "shaderpacks"
        }
    }

    var title: String {
        switch self {
        case .mod: return "Моды"
        case .resourcepack: return "Ресурспаки"
        case .shader: return "Шейдеры"
        }
    }

    var one: String {
        switch self {
        case .mod: return "мод"
        case .resourcepack: return "ресурспак"
        case .shader: return "шейдер"
        }
    }
}

enum ModSource: String, Codable { case horizon, modrinth }

/// One project of a list.
struct ModItem: Identifiable, Equatable {
    var source: ModSource
    var projectID: String
    var kind: ModKind
    var name: String
    var summary: String
    var author: String
    var downloads: Int
    var icon: URL?
    /// The registry's file (Modrinth's is asked for when installing).
    var file: RegistryFile?

    var id: String { "\(source.rawValue):\(projectID)" }
}

struct RegistryFile: Equatable {
    var name: String
    var url: URL
    var size: Int
    /// Lowercase hex; empty for Modrinth, which gives SHA-1.
    var sha256: String
    var sha1: String? = nil
}

/// A file the launcher put into the game folder.
struct InstalledMod: Codable, Identifiable, Equatable {
    var key: String
    var name: String
    var kind: ModKind
    var file: String
    var id: String { key }
}

/// Horizon's mod registry (the launcher's and the in-game browser's `index.json`), Modrinth's
/// resource packs and shaders, and what is installed.
@MainActor
final class ModsStore: ObservableObject {
    static let registryURL = URL(string: "https://horizon-rust.github.io/horizon-mods/index.json")!
    static let modrinth = "https://api.modrinth.com/v2"
    /// The Minecraft version of this game (horizon_core::version).
    static let game = "26.3"

    @Published var registry: [ModItem] = []
    @Published var registryError: String?
    @Published var loadingRegistry = false
    @Published var modrinthHits: [ModItem] = []
    @Published var modrinthError: String?
    @Published var searching = false
    @Published var installed: [InstalledMod] = []
    @Published var busy: Set<String> = []
    @Published var message: String?

    private var searchTask: Task<Void, Never>?
    private static let manifest = Paths.library.appendingPathComponent("Horizon/installed-mods.json")

    init() { loadInstalled() }

    // MARK: Installed

    func loadInstalled() {
        let data = try? Data(contentsOf: Self.manifest)
        var list = data.flatMap { try? JSONDecoder().decode([InstalledMod].self, from: $0) } ?? []
        // A file removed in the Files app is gone from the list too.
        list.removeAll { !FileManager.default.fileExists(atPath: path(of: $0).path) }
        // Files put into the folders by hand are listed as well.
        for kind in ModKind.allCases {
            let dir = Paths.gameDir.appendingPathComponent(kind.folder)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names where !name.hasPrefix(".") && !name.hasSuffix(".txt") {
                if !list.contains(where: { $0.kind == kind && $0.file == name }) {
                    list.append(InstalledMod(key: "file:\(kind.rawValue):\(name)", name: name, kind: kind, file: name))
                }
            }
        }
        installed = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func saveInstalled() {
        try? FileManager.default.createDirectory(at: Self.manifest.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(installed) { try? data.write(to: Self.manifest, options: .atomic) }
    }

    private func path(of mod: InstalledMod) -> URL {
        Paths.gameDir.appendingPathComponent(mod.kind.folder).appendingPathComponent(mod.file)
    }

    func isInstalled(_ item: ModItem) -> Bool { installed.contains { $0.key == item.id } }

    func count(_ kind: ModKind) -> Int { installed.filter { $0.kind == kind }.count }

    func remove(_ mod: InstalledMod) {
        try? FileManager.default.removeItem(at: path(of: mod))
        installed.removeAll { $0.key == mod.key }
        saveInstalled()
    }

    // MARK: Horizon's registry

    func loadRegistry() async {
        if loadingRegistry { return }
        loadingRegistry = true
        registryError = nil
        defer { loadingRegistry = false }
        do {
            var request = URLRequest(url: Self.registryURL)
            request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            registry = try Self.parseRegistry(data)
        } catch {
            registryError = "Реестр Horizon недоступен: \(error.localizedDescription)"
        }
    }

    /// The projects this build can use: content mods without code for 26.3, resource packs and
    /// shader packs; the newest version of each that wasn't taken down.
    static func parseRegistry(_ data: Data) throws -> [ModItem] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let revoked = (root["revoked"] as? [[String: Any]]) ?? []
        let revokedIDs = Set(revoked.filter { $0["sha256"] == nil }.compactMap { $0["id"] as? String })
        let revokedFiles = Set(revoked.compactMap { $0["sha256"] as? String })
        let base = URL(string: "https://horizon-rust.github.io/horizon-mods/")!
        var out: [ModItem] = []
        for p in (root["projects"] as? [[String: Any]]) ?? [] {
            guard let id = p["id"] as? String, !revokedIDs.contains(id),
                  let kindName = p["kind"] as? String else { continue }
            let kind: ModKind
            switch kindName {
            case "mod": kind = .mod
            case "resourcepack": kind = .resourcepack
            case "shader", "shaderpack": kind = .shader
            default: continue
            }
            let versions = ((p["versions"] as? [[String: Any]]) ?? []).filter { v in
                guard let file = v["file"] as? [String: Any],
                      let sha = file["sha256"] as? String, !revokedFiles.contains(sha) else { return false }
                if kind == .mod {
                    // Content only: a mod with code doesn't run in this game.
                    let caps = (v["capabilities"] as? [String]) ?? []
                    guard (file["name"] as? String)?.hasSuffix(".hmod") == true,
                          caps.allSatisfy({ $0 == "registries" }),
                          (v["game"] as? String) == game else { return false }
                }
                return true
            }
            guard let v = versions.max(by: { ($0["published"] as? String ?? "") < ($1["published"] as? String ?? "") }),
                  let file = v["file"] as? [String: Any],
                  let name = file["name"] as? String, let urlText = file["url"] as? String,
                  let url = URL(string: urlText, relativeTo: base)?.absoluteURL,
                  let sha = file["sha256"] as? String else { continue }
            let icon = (p["icon"] as? String).flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
            out.append(ModItem(
                source: .horizon, projectID: id, kind: kind,
                name: p["name"] as? String ?? id,
                summary: p["summary"] as? String ?? "",
                author: ((p["authors"] as? [String]) ?? []).joined(separator: ", "),
                downloads: (p["downloads"] as? Int) ?? 0,
                icon: icon,
                file: RegistryFile(name: name, url: url, size: (file["size"] as? Int) ?? 0, sha256: sha.lowercased())))
        }
        return out.sorted { $0.downloads > $1.downloads }
    }

    // MARK: Modrinth

    func search(_ query: String, kind: ModKind) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            // Typing: wait for a pause before asking.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.runSearch(query, kind: kind)
        }
    }

    private func runSearch(_ query: String, kind: ModKind) async {
        searching = true
        modrinthError = nil
        defer { searching = false }
        let type = kind == .shader ? "shader" : "resourcepack"
        var parts = URLComponents(string: "\(Self.modrinth)/search")!
        parts.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "index", value: query.isEmpty ? "downloads" : "relevance"),
            URLQueryItem(name: "facets", value: "[[\"project_type:\(type)\"]]"),
        ]
        do {
            var request = URLRequest(url: parts.url!)
            request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            if Task.isCancelled { return }
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let hits = (root?["hits"] as? [[String: Any]]) ?? []
            modrinthHits = hits.compactMap { h in
                guard let id = h["project_id"] as? String else { return nil }
                return ModItem(
                    source: .modrinth, projectID: id, kind: kind,
                    name: h["title"] as? String ?? id,
                    summary: h["description"] as? String ?? "",
                    author: h["author"] as? String ?? "",
                    downloads: (h["downloads"] as? Int) ?? 0,
                    icon: (h["icon_url"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
                    file: nil)
            }
        } catch {
            if !Task.isCancelled { modrinthError = "Modrinth недоступен: \(error.localizedDescription)" }
        }
    }

    /// The newest version's primary file; for shaders the one made for Iris or OptiFine (the
    /// `shaders/` format Horizon reads).
    private func modrinthFile(_ item: ModItem) async throws -> RegistryFile {
        let url = URL(string: "\(Self.modrinth)/project/\(item.projectID)/version")!
        var request = URLRequest(url: url)
        request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let versions = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let usable = versions.filter { v in
            guard item.kind == .shader else { return true }
            let loaders = (v["loaders"] as? [String]) ?? []
            return loaders.contains("iris") || loaders.contains("optifine")
        }
        for v in usable {
            let files = (v["files"] as? [[String: Any]]) ?? []
            let file = files.first { ($0["primary"] as? Bool) == true } ?? files.first
            if let file, let name = file["filename"] as? String, let urlText = file["url"] as? String,
               let url = URL(string: urlText) {
                let hashes = file["hashes"] as? [String: Any]
                return RegistryFile(name: name, url: url, size: (file["size"] as? Int) ?? 0,
                                    sha256: "", sha1: hashes?["sha1"] as? String)
            }
        }
        throw ModError.noFile
    }

    // MARK: Install

    enum ModError: LocalizedError {
        case noFile, size, hash
        var errorDescription: String? {
            switch self {
            case .noFile: return "У проекта нет файла для этой игры."
            case .size: return "Файл скачался не целиком."
            case .hash: return "Файл не совпал с контрольной суммой."
            }
        }
    }

    func install(_ item: ModItem) {
        guard !busy.contains(item.id) else { return }
        busy.insert(item.id)
        message = nil
        Task {
            defer { busy.remove(item.id) }
            do {
                let file: RegistryFile
                if let f = item.file { file = f } else { file = try await modrinthFile(item) }
                var request = URLRequest(url: file.url)
                request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
                let (temp, _) = try await URLSession.shared.download(for: request)
                let data = try Data(contentsOf: temp)
                if file.size > 0 && data.count != file.size { throw ModError.size }
                if !file.sha256.isEmpty {
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    if digest != file.sha256 { throw ModError.hash }
                } else if let sha1 = file.sha1 {
                    let digest = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    if digest != sha1.lowercased() { throw ModError.hash }
                }
                let dir = Paths.gameDir.appendingPathComponent(item.kind.folder, isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let safeName = file.name.replacingOccurrences(of: "/", with: "_")
                let target = dir.appendingPathComponent(safeName)
                try? FileManager.default.removeItem(at: target)
                try data.write(to: target, options: .atomic)
                installed.removeAll { $0.key == item.id || ($0.kind == item.kind && $0.file == safeName) }
                installed.append(InstalledMod(key: item.id, name: item.name, kind: item.kind, file: safeName))
                installed.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                saveInstalled()
                message = "Установлено: \(item.name). Включи в игре: Настройки → \(item.kind == .mod ? "Моды" : item.kind == .shader ? "Шейдеры" : "Пакеты ресурсов")."
            } catch {
                message = "\(item.name): \(error.localizedDescription)"
            }
        }
    }

    nonisolated static let agent = "neosay-dev/horizon-ios/0.1.0 (iOS launcher)"
}
