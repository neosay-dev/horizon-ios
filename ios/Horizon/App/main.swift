import Foundation

// The app starts in Rust: winit runs UIApplicationMain and calls back
// hz_swift_show_launcher (AppBridge.swift) once the app is up.
exit(hz_run())
