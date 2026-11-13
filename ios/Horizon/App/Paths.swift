import Foundation

/// Where the app keeps the game's files. Documents is visible in the Files app and in Finder
/// (UIFileSharingEnabled), so the prepared resources can be copied there by hand too.
enum Paths {
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]

    /// Saves, options.txt, resource packs: the game's folder (`--game-dir`).
    static let gameDir = documents.appendingPathComponent("game", isDirectory: true)
    /// The prepared resources (`horizon-prepare`'s `.local/horizon-client/26.3`).
    static let resources = documents.appendingPathComponent("resources/26.3", isDirectory: true)
    /// Logs and crash reports (`--home`), in Documents so they can be read in the Files app.
    static let home = documents.appendingPathComponent("logs", isDirectory: true)
    /// The touch layout.
    static let controls = library.appendingPathComponent("Horizon/controls.json")
    /// The launcher's settings.
    static let settings = library.appendingPathComponent("Horizon/launcher.json")

    static func ensure() {
        for dir in [gameDir, resources.deletingLastPathComponent(), home] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static var resourcesReady: Bool {
        FileManager.default.fileExists(atPath: resources.appendingPathComponent("horizon-resources.json").path)
    }
}
