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
