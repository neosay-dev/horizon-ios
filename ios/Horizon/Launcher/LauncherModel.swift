import Foundation
import SwiftUI

/// The launcher's settings, kept in Library/Horizon/launcher.json.
struct LauncherPrefs: Codable {
    var renderDistance: Double = 8
    var sensitivity: Double = 0.25
    var controlScale: Double = 1
    var controlOpacity: Double = 1
    var lastWorld: String = ""
}

@MainActor
final class LauncherSettings: ObservableObject {
    @Published var prefs: LauncherPrefs

    init(_ prefs: LauncherPrefs = LauncherPrefs()) { self.prefs = prefs }

    var renderDistance: Double { get { prefs.renderDistance } set { prefs.renderDistance = newValue } }
    var sensitivity: Double { get { prefs.sensitivity } set { prefs.sensitivity = newValue } }
    var controlScale: Double { get { prefs.controlScale } set { prefs.controlScale = newValue } }
    var controlOpacity: Double { get { prefs.controlOpacity } set { prefs.controlOpacity = newValue } }
    var lastWorld: String { get { prefs.lastWorld } set { prefs.lastWorld = newValue } }

    static func load() -> LauncherSettings {
        let data = try? Data(contentsOf: Paths.settings)
        let prefs = data.flatMap { try? JSONDecoder().decode(LauncherPrefs.self, from: $0) }
        return LauncherSettings(prefs ?? LauncherPrefs())
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.settings.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(prefs) { try? data.write(to: Paths.settings, options: .atomic) }
    }
}

/// The launcher's state and its Play.
@MainActor
final class LauncherModel: ObservableObject {
    let account = AccountStore()
    let controls = ControlLayout()
    let settings = LauncherSettings.load()

    @Published var resourcesReady = Paths.resourcesReady
    @Published var status: String?
    @Published var importing = false
    @Published var worlds: [String] = []

    init() { refreshWorlds() }

    func refreshWorlds() {
        let saves = Paths.gameDir.appendingPathComponent("saves")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: saves.path)) ?? []
        worlds = names.filter { !$0.hasPrefix(".") }.sorted()
        resourcesReady = Paths.resourcesReady
    }

    var canPlay: Bool {
        account.hasAccount && resourcesReady
    }

    /// Copies a prepared resources folder (`.local/horizon-client/26.3`) picked in Files.
    func importResources(from url: URL) {
        importing = true
        status = nil
        Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var source = url
            // The parent folder (horizon-client/) picked instead of 26.3 itself.
            let nested = url.appendingPathComponent("26.3")
            if !FileManager.default.fileExists(atPath: url.appendingPathComponent("horizon-resources.json").path),
               FileManager.default.fileExists(atPath: nested.appendingPathComponent("horizon-resources.json").path) {
                source = nested
            }
            let message: String?
            if !FileManager.default.fileExists(atPath: source.appendingPathComponent("horizon-resources.json").path) {
                message = String(localized: "В этой папке нет horizon-resources.json. Выбери папку .local/horizon-client/26.3, подготовленную horizon-prepare.")
            } else {
                do {
                    try? FileManager.default.removeItem(at: Paths.resources)
                    try FileManager.default.createDirectory(at: Paths.resources.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: source, to: Paths.resources)
                    message = nil
                } catch {
                    message = error.localizedDescription
                }
            }
            await MainActor.run {
                self.importing = false
                self.status = message
                self.refreshWorlds()
            }
        }
    }

    /// Play with a local name or a fresh Microsoft session.
    func play(world: String?) {
        status = nil
        settings.save()
        controls.save()
        Task {
            do {
                let accountArgs = try await account.launchArguments()
                var args = [
                    "--game-dir", Paths.gameDir.path,
                    "--home", Paths.home.path,
                    "--resources", Paths.resources.path,
                    "--render-distance", String(Int(settings.renderDistance)),
                    "--fullscreen",
                ] + accountArgs
                if let world, !world.isEmpty {
                    args += ["--quickPlaySingleplayer", world]
                    settings.lastWorld = world
                    settings.save()
                }
                let json = String(data: try JSONSerialization.data(withJSONObject: args), encoding: .utf8)!
                if !json.withCString({ hz_play($0) }) {
                    status = String(localized: "Не удалось передать параметры игре.")
                }
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
