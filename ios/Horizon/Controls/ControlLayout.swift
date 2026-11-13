import Foundation
import SwiftUI

/// What a touch control does. Keys and buttons are the control protocol's names
/// (docs/horizon-ctl-commands.md): `w`, `space`, `shift`, `e`, `esc`, `f5`, `1`…
enum ControlAction: Codable, Hashable {
    /// The movement stick: W, A, S, D, and sprint when pushed to the rim.
    case joystick
    /// The nine hotbar slots, `hotbar N`.
    case hotbar
    /// A key: held while the finger is down, or toggled by each tap.
    case key(String)
    /// A mouse button: `left` attacks and breaks, `right` uses and places.
    case mouse(String)
    /// The system keyboard, for chat: `t`, the text, Enter.
    case chat
    /// Opens the layout editor over the game.
    case editLayout
}

struct ControlButton: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String
    /// SF Symbol shown instead of the label, when set.
    var symbol: String?
    var action: ControlAction
    /// Centre, as a fraction of the screen (0…1), so a layout fits every device.
    var x: Double
    var y: Double
    /// Size in points (the hotbar: its width; height is width / 9).
    var size: Double
    var opacity: Double = 0.85
    /// A tap toggles the key instead of holding it (sneak, sprint).
    var toggle: Bool = false
}

/// The touch layout, kept in Library/Horizon/controls.json.
@MainActor
final class ControlLayout: ObservableObject {
    @Published var buttons: [ControlButton] = []

    init() { load() }

    func load() {
        if let data = try? Data(contentsOf: Paths.controls),
           let saved = try? JSONDecoder().decode([ControlButton].self, from: data), !saved.isEmpty {
            buttons = saved
        } else {
            buttons = Self.defaults
        }
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.controls.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(buttons) {
            try? data.write(to: Paths.controls, options: .atomic)
        }
    }

    func reset() {
        buttons = Self.defaults
        save()
    }

    /// The default layout: stick left; jump, attack, use and sneak right; inventory, drop,
    /// chat, pause and the view key along the top; the hotbar at the bottom.
    static let defaults: [ControlButton] = [
        ControlButton(label: "Движение", symbol: nil, action: .joystick, x: 0.14, y: 0.70, size: 150, opacity: 0.7),
        ControlButton(label: "Прыжок", symbol: "arrow.up", action: .key("space"), x: 0.88, y: 0.72, size: 72),
        ControlButton(label: "Ударить", symbol: "hand.raised.fill", action: .mouse("left"), x: 0.78, y: 0.52, size: 66),
        ControlButton(label: "Использовать", symbol: "hand.point.up.left.fill", action: .mouse("right"), x: 0.90, y: 0.45, size: 60),
        ControlButton(label: "Присесть", symbol: "arrow.down.to.line", action: .key("shift"), x: 0.78, y: 0.80, size: 60, toggle: true),
        ControlButton(label: "Бег", symbol: "hare.fill", action: .key("ctrl"), x: 0.27, y: 0.52, size: 52, toggle: true),
        ControlButton(label: "Инвентарь", symbol: "square.grid.3x3.fill", action: .key("e"), x: 0.80, y: 0.93, size: 50),
        ControlButton(label: "Выбросить", symbol: "arrow.down.right.square", action: .key("q"), x: 0.20, y: 0.93, size: 46),
        ControlButton(label: "Чат", symbol: "bubble.left.fill", action: .chat, x: 0.06, y: 0.09, size: 46),
        ControlButton(label: "Пауза", symbol: "pause.fill", action: .key("esc"), x: 0.50, y: 0.07, size: 46),
        ControlButton(label: "Вид", symbol: "eye.fill", action: .key("f5"), x: 0.60, y: 0.07, size: 46),
        ControlButton(label: "Раскладка", symbol: "slider.horizontal.3", action: .editLayout, x: 0.94, y: 0.09, size: 46),
        ControlButton(label: "Хотбар", symbol: nil, action: .hotbar, x: 0.50, y: 0.95, size: 364, opacity: 0.25),
    ]

    /// Keys a custom button can press, with their names in the editor.
    static let keyChoices: [(String, LocalizedStringKey)] = [
        ("space", "Пробел (прыжок)"), ("shift", "Shift (присесть)"), ("ctrl", "Ctrl (бег)"),
        ("e", "E (инвентарь)"), ("q", "Q (выбросить)"), ("f", "F (сменить руку)"),
        ("t", "T (чат)"), ("slash", "/ (команда)"), ("tab", "Tab (игроки)"),
        ("esc", "Esc (пауза)"), ("f1", "F1 (скрыть HUD)"), ("f2", "F2 (скриншот)"),
        ("f3", "F3 (отладка)"), ("f5", "F5 (вид)"), ("l", "L (достижения)"),
        ("1", "1"), ("2", "2"), ("3", "3"), ("4", "4"), ("5", "5"),
        ("6", "6"), ("7", "7"), ("8", "8"), ("9", "9"),
    ]
}
