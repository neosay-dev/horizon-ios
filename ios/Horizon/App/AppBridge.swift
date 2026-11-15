import SwiftUI
import UIKit

/// The windows the Swift side owns above the game's: the launcher before Play, the touch
/// controls after. winit owns the app delegate and the game's own window.
@MainActor
final class AppBridge {
    static let shared = AppBridge()

    private var launcherWindow: UIWindow?
    private var controlsWindow: UIWindow?
    let launcher = LauncherModel()

    private func makeWindow(level: UIWindow.Level) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.windowLevel = level
        return window
    }

    func showLauncher() {
        Paths.ensure()
        controlsWindow?.isHidden = true
        if launcherWindow == nil {
            let window = makeWindow(level: .normal + 2)
            let host = UIHostingController(rootView: LauncherView().environmentObject(launcher)
                .environmentObject(launcher.account).environmentObject(launcher.controls))
            window.rootViewController = host
            launcherWindow = window
        }
        launcherWindow?.isHidden = false
        launcherWindow?.makeKeyAndVisible()
    }

    func gameStarted() {
        launcherWindow?.isHidden = true
        launcherWindow = nil
        // The game's window (winit's) comes next; the controls go above it and let every
        // touch that misses a control through to it.
        let window = PassthroughWindow(frame: UIScreen.main.bounds)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.windowLevel = .normal + 1
        let controller = TouchControlsController(layout: launcher.controls, settings: launcher.settings)
        window.rootViewController = controller
        window.isHidden = false
        controlsWindow = window
        watchHeat()
    }

    private var heatObserver: NSObjectProtocol?

    /// A hot phone slows its processor by itself, in jumps. Before that, the render distance comes down
    /// (6 chunks when the phone is hot, 4 when it is about to protect itself) and returns once it cools.
    private func watchHeat() {
        guard heatObserver == nil else { return }
        heatObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyHeat() }
        }
        applyHeat()
    }

    private var heatLimited = false

    private func applyHeat() {
        let settings = launcher.settings
        guard settings.thermalGuard else { return }
        let chosen = Int(settings.renderDistance)
        let limit: Int?
        switch ProcessInfo.processInfo.thermalState {
        case .serious: limit = 6
        case .critical: limit = 4
        default: limit = nil
        }
        if let limit, limit < chosen {
            gameInput("render-distance \(limit)")
            heatLimited = true
        } else if heatLimited {
            gameInput("render-distance \(chosen)")
            heatLimited = false
        }
    }

    func gameFailed() {
        let reason = hz_last_error().map { String(cString: $0) }
        launcher.status = reason.map { String(localized: "Игра не запустилась: \($0)") }
            ?? String(localized: "Игра не запустилась. Журнал: Файлы → Horizon → logs.")
        showLauncher()
    }
}

/// A window that takes only the touches its views claim.
final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self || hit === rootViewController?.view ? nil : hit
    }
}

// Called by Rust (crates/horizon-ios) on the main thread.

@_cdecl("hz_swift_show_launcher")
func hz_swift_show_launcher() {
    MainActor.assumeIsolated { AppBridge.shared.showLauncher() }
}

@_cdecl("hz_swift_game_started")
func hz_swift_game_started() {
    MainActor.assumeIsolated { AppBridge.shared.gameStarted() }
}

@_cdecl("hz_swift_game_failed")
func hz_swift_game_failed() {
    MainActor.assumeIsolated { AppBridge.shared.gameFailed() }
}

/// Sends a control line to the game.
func gameInput(_ line: String) {
    line.withCString { hz_input($0) }
}
