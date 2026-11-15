import Foundation
import SwiftUI

/// The launcher's settings, kept in Library/Horizon/launcher.json.
struct LauncherPrefs: Codable {
    var renderDistance: Double = 8
    var sensitivity: Double = 0.25
    var controlScale: Double = 1
    var controlOpacity: Double = 1
    var lastWorld: String = ""
    /// Performance mode: the world renders at 75 % and rises to 100 % while the frame rate holds.
    var performanceMode: Bool = true
    /// FSR 3.1 frame interpolation: every second frame is made from its neighbours.
    var frameGeneration: Bool = false
    /// A hot phone gets a shorter render distance until it cools.
    var thermalGuard: Bool = true
    /// What `performanceMode` and `frameGeneration` were when horizon-graphics.txt was last written.
    var appliedGraphics: String = ""

    init() {}

    /// Keys a file from an older launcher lacks keep their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        renderDistance = try c.decodeIfPresent(Double.self, forKey: .renderDistance) ?? renderDistance
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? sensitivity
        controlScale = try c.decodeIfPresent(Double.self, forKey: .controlScale) ?? controlScale
        controlOpacity = try c.decodeIfPresent(Double.self, forKey: .controlOpacity) ?? controlOpacity
        lastWorld = try c.decodeIfPresent(String.self, forKey: .lastWorld) ?? lastWorld
        performanceMode = try c.decodeIfPresent(Bool.self, forKey: .performanceMode) ?? performanceMode
        frameGeneration = try c.decodeIfPresent(Bool.self, forKey: .frameGeneration) ?? frameGeneration
        thermalGuard = try c.decodeIfPresent(Bool.self, forKey: .thermalGuard) ?? thermalGuard
        appliedGraphics = try c.decodeIfPresent(String.self, forKey: .appliedGraphics) ?? appliedGraphics
    }
}

/// The game's graphics file, horizon-graphics.txt beside options.txt (`key:value` lines, graphics.rs).
enum GraphicsFile {
    static var url: URL { Paths.gameDir.appendingPathComponent("horizon-graphics.txt") }

    /// Sets `values`, keeping every other line as the game wrote it.
    static func set(_ values: [(String, String)]) {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        for (key, value) in values {
            lines.removeAll { $0.hasPrefix("\(key):") }
            lines.append("\(key):\(value)")
        }
        try? FileManager.default.createDirectory(at: Paths.gameDir, withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
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
    var performanceMode: Bool { get { prefs.performanceMode } set { prefs.performanceMode = newValue } }
    var frameGeneration: Bool { get { prefs.frameGeneration } set { prefs.frameGeneration = newValue } }
    var thermalGuard: Bool { get { prefs.thermalGuard } set { prefs.thermalGuard = newValue } }

    /// Writes the launcher's graphics switches into horizon-graphics.txt, once per change: what the player
    /// sets in the game's own Graphics screen afterwards stays until a switch here is flipped again.
    func applyGraphics() {
        let wanted = "performance:\(prefs.performanceMode) frames:\(prefs.frameGeneration)"
        guard wanted != prefs.appliedGraphics else { return }
        let fps = max(60, UIScreen.main.maximumFramesPerSecond)
        GraphicsFile.set([
            ("resolutionScale", prefs.performanceMode ? "75" : "100"),
            ("dynamicResolution", prefs.performanceMode ? "true" : "false"),
            ("targetFps", String(fps)),
            ("frameGeneration", prefs.frameGeneration ? "fsr3.1" : "off"),
        ])
        prefs.appliedGraphics = wanted
        save()
    }

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
        settings.applyGraphics()
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
