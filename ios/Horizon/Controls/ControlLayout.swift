import Foundation
import SwiftUI

/// What a touch control does.
enum ControlAction: Codable, Hashable {
    /// The movement stick: W, A, S, D, and sprint when pushed to the rim.
    case joystick
    /// The nine hotbar slots, `hotbar N`.
    case hotbar
    /// One key (the control protocol's name: `w`, `space`, `key.keyboard.f7`…).
    case key(String)
    /// One mouse button: `left`, `right`, `middle`.
    case mouse(String)
    /// Keys and mouse buttons pressed together, in order, and released in reverse:
    /// `["key.keyboard.left.control", "key.keyboard.c"]`, `["mouse.left", "key.keyboard.left.shift"]`.
    case combo([String])
    /// The system keyboard, for chat: `t`, the text, Enter.
    case chat
    /// Opens the layout editor over the game.
    case editLayout
    /// The mouse wheel: lines up (positive) or down.
    case wheel(Int)
    /// The system keyboard, typing into whatever the game has focused (a server's name, a sign).
    case keyboard

    /// The parts it presses, as combo items.
    var parts: [String] {
        switch self {
        case .key(let k): return [KeyCatalog.canonical(k)]
        case .mouse(let b): return ["mouse.\(b)"]
        case .combo(let items): return items
        default: return []
        }
    }
}

struct ControlButton: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String
    /// SF Symbol shown under the label, when set.
    var symbol: String?
    var action: ControlAction
    /// Centre, as a fraction of the screen (0…1), so a layout fits every device.
    var x: Double
    var y: Double
    /// Width in points (the hotbar: its width; height is width / 9).
    var size: Double
    var opacity: Double = 0.85
    /// A tap toggles the keys instead of holding them (sneak, sprint).
    var toggle: Bool = false
    /// Height as a fraction of the width (square by default).
    var aspect: Double = 1
}

/// The two touch layouts: the world's (Library/Horizon/controls-v2.json) and the screens' over the
/// virtual mouse (controls-menu.json).
@MainActor
final class ControlLayout: ObservableObject {
    enum Mode: Hashable { case play, menu }

    @Published var buttons: [ControlButton] = []
    @Published var menu: [ControlButton] = []

    private static var menuFile: URL {
        Paths.controls.deletingLastPathComponent().appendingPathComponent("controls-menu.json")
    }

    init() { load() }

    func load() {
        buttons = Self.read(Paths.controls) ?? Self.defaults
        menu = Self.read(Self.menuFile) ?? Self.menuDefaults
    }

    private static func read(_ url: URL) -> [ControlButton]? {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([ControlButton].self, from: data), !saved.isEmpty else { return nil }
        return saved
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.controls.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(buttons) { try? data.write(to: Paths.controls, options: .atomic) }
        if let data = try? JSONEncoder().encode(menu) { try? data.write(to: Self.menuFile, options: .atomic) }
    }

    func reset(_ mode: Mode) {
        switch mode {
        case .play: buttons = Self.defaults
        case .menu: menu = Self.menuDefaults
        }
        save()
    }

    func list(_ mode: Mode) -> [ControlButton] { mode == .play ? buttons : menu }

    func remove(_ id: ControlButton.ID, from mode: Mode) {
        switch mode {
        case .play: buttons.removeAll { $0.id == id }
        case .menu: menu.removeAll { $0.id == id }
        }
    }

    func append(_ button: ControlButton, to mode: Mode) {
        switch mode {
        case .play: buttons.append(button)
        case .menu: menu.append(button)
        }
    }

    /// A button's binding by its id, safe when it is gone (a deleted button's editor may still draw once).
    func binding(_ id: ControlButton.ID, in mode: Mode) -> Binding<ControlButton>? {
        guard let first = list(mode).first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.list(mode).first { $0.id == id } ?? first },
            set: { [weak self] new in
                guard let self else { return }
                switch mode {
                case .play: if let i = self.buttons.firstIndex(where: { $0.id == id }) { self.buttons[i] = new }
                case .menu: if let i = self.menu.firstIndex(where: { $0.id == id }) { self.menu[i] = new }
                }
            })
    }

    private static func key(_ label: String, _ name: String, x: Double, y: Double, size: Double = 54,
                            toggle: Bool = false, symbol: String? = nil, aspect: Double = 1) -> ControlButton {
        ControlButton(label: label, symbol: symbol, action: .key(name), x: x, y: y, size: size,
                      toggle: toggle, aspect: aspect)
    }

    /// The default layout: a cross of arrows to walk (Sneak in its middle), Jump, LMB and RMB on
    /// the right, the screens' keys along the top, the hotbar at the bottom.
    static let defaults: [ControlButton] = [
        key("", "w", x: 0.13, y: 0.56, symbol: "arrowtriangle.up.fill"),
        key("", "a", x: 0.06, y: 0.71, symbol: "arrowtriangle.left.fill"),
        key("", "s", x: 0.13, y: 0.86, symbol: "arrowtriangle.down.fill"),
        key("", "d", x: 0.20, y: 0.71, symbol: "arrowtriangle.right.fill"),
        key("Присесть", "shift", x: 0.13, y: 0.71, size: 50, toggle: true),
        key("Бег", "ctrl", x: 0.20, y: 0.56, size: 46, toggle: true),
        key("Прыжок", "space", x: 0.90, y: 0.74, size: 70),
        ControlButton(label: "ЛКМ", symbol: nil, action: .mouse("left"), x: 0.78, y: 0.56, size: 62),
        ControlButton(label: "ПКМ", symbol: nil, action: .mouse("right"), x: 0.91, y: 0.50, size: 58),
        key("Инв.", "e", x: 0.80, y: 0.94, size: 50, aspect: 0.7),
        key("Q", "q", x: 0.70, y: 0.94, size: 44, aspect: 0.8),
        ControlButton(label: "Чат", symbol: nil, action: .chat, x: 0.05, y: 0.08, size: 52, aspect: 0.7),
        key("Esc", "esc", x: 0.15, y: 0.08, size: 52, aspect: 0.7),
        key("F3", "f3", x: 0.25, y: 0.08, size: 46, aspect: 0.8),
        key("F5", "f5", x: 0.34, y: 0.08, size: 46, aspect: 0.8),
        key("Tab", "tab", x: 0.43, y: 0.08, size: 46, aspect: 0.8),
        ControlButton(label: "⚙︎", symbol: nil, action: .editLayout, x: 0.95, y: 0.08, size: 46, aspect: 0.8),
        ControlButton(label: "Хотбар", symbol: nil, action: .hotbar, x: 0.50, y: 0.95, size: 364, opacity: 0.25),
    ]

    /// Over the screens (menus, inventory): LMB and RMB at the cursor, Back, the wheel, the keyboard.
    static let menuDefaults: [ControlButton] = [
        ControlButton(label: "ЛКМ", symbol: "computermouse.fill", action: .mouse("left"), x: 0.93, y: 0.84, size: 62),
        ControlButton(label: "ПКМ", symbol: "computermouse", action: .mouse("right"), x: 0.93, y: 0.60, size: 62),
        ControlButton(label: "Назад", symbol: "arrow.uturn.backward", action: .key("esc"), x: 0.07, y: 0.14, size: 62),
        ControlButton(label: "Вверх", symbol: "chevron.up", action: .wheel(1), x: 0.07, y: 0.60, size: 62),
        ControlButton(label: "Вниз", symbol: "chevron.down", action: .wheel(-1), x: 0.07, y: 0.84, size: 62),
        ControlButton(label: "Клавиатура", symbol: "keyboard", action: .keyboard, x: 0.93, y: 0.14, size: 62),
    ]
}

/// Every key the game knows (`horizon-client-input` keybinds), grouped for the picker.
enum KeyCatalog {
    struct Key: Hashable {
        let name: String
        let label: String
    }

    struct Group: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let keys: [Key]

        init(id: String, title: LocalizedStringKey, keys: [(String, String)]) {
            self.id = id
            self.title = title
            self.keys = keys.map { Key(name: $0.0, label: $0.1) }
        }
    }

    private static func kb(_ s: String) -> String { "key.keyboard.\(s)" }

    static let groups: [Group] = [
        Group(id: "mouse", title: "Мышь", keys: [
            ("mouse.left", "ЛКМ"), ("mouse.right", "ПКМ"), ("mouse.middle", "СКМ"),
        ]),
        Group(id: "letters", title: "Буквы", keys:
            "abcdefghijklmnopqrstuvwxyz".map { (kb(String($0)), String($0).uppercased()) }),
        Group(id: "digits", title: "Цифры", keys: (0...9).map { (kb("\($0)"), "\($0)") }),
        Group(id: "fn", title: "F1–F12", keys: (1...12).map { (kb("f\($0)"), "F\($0)") }),
        Group(id: "mods", title: "Модификаторы", keys: [
            (kb("left.shift"), "Shift"), (kb("right.shift"), "Правый Shift"),
            (kb("left.control"), "Ctrl"), (kb("right.control"), "Правый Ctrl"),
            (kb("left.alt"), "Alt"), (kb("right.alt"), "Правый Alt"),
            (kb("left.win"), "Win / Cmd"),
        ]),
        Group(id: "nav", title: "Управляющие", keys: [
            (kb("escape"), "Esc"), (kb("tab"), "Tab"), (kb("enter"), "Enter"),
            (kb("space"), "Пробел"), (kb("backspace"), "Backspace"), (kb("delete"), "Delete"),
            (kb("insert"), "Insert"), (kb("home"), "Home"), (kb("end"), "End"),
            (kb("page.up"), "Page Up"), (kb("page.down"), "Page Down"),
            (kb("up"), "↑"), (kb("down"), "↓"), (kb("left"), "←"), (kb("right"), "→"),
            (kb("caps.lock"), "Caps Lock"), (kb("print.screen"), "Print Screen"), (kb("pause"), "Pause"),
        ]),
        Group(id: "symbols", title: "Символы", keys: [
            (kb("grave.accent"), "`"), (kb("minus"), "-"), (kb("equal"), "="),
            (kb("left.bracket"), "["), (kb("right.bracket"), "]"), (kb("backslash"), "\\"),
            (kb("semicolon"), ";"), (kb("apostrophe"), "'"), (kb("comma"), ","),
            (kb("period"), "."), (kb("slash"), "/"),
        ]),
        Group(id: "numpad", title: "Цифровой блок", keys:
            (0...9).map { (kb("keypad.\($0)"), "Num \($0)") } + [
                (kb("keypad.add"), "Num +"), (kb("keypad.subtract"), "Num −"),
                (kb("keypad.multiply"), "Num ×"), (kb("keypad.divide"), "Num ÷"),
                (kb("keypad.enter"), "Num Enter"), (kb("keypad.period"), "Num ."),
            ]),
    ]

    /// The short protocol names old layouts used, as the game's own.
    static func canonical(_ name: String) -> String {
        if name.hasPrefix("key.") || name.hasPrefix("mouse.") { return name }
        switch name {
        case "shift": return kb("left.shift")
        case "ctrl": return kb("left.control")
        case "esc": return kb("escape")
        default: return kb(name)
        }
    }

    static func label(_ name: String) -> String {
        for g in groups { if let k = g.keys.first(where: { $0.name == name }) { return k.label } }
        return name.replacingOccurrences(of: "key.keyboard.", with: "")
    }

    /// The control lines that press (`down`) or release one part.
    static func line(_ part: String, down: Bool) -> String {
        if part.hasPrefix("mouse.") {
            return "mouse \(part.dropFirst(6)) \(down ? "down" : "up")"
        }
        return "key \(part) \(down ? "down" : "up")"
    }
}
