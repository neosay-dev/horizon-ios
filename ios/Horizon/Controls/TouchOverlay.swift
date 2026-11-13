import SwiftUI
import UIKit

/// Over the game's window, two modes:
/// - in the world with no screen open (`hz_playing`): the touch controls; a drag turns the view
///   and does nothing else, actions are buttons (LMB breaks and attacks, RMB uses and places);
/// - on every screen (menus, inventory, chests): the virtual mouse, a cursor moved like a
///   trackpad, with LMB, RMB, Back and the wheel as buttons. A tap clicks at the cursor.
/// No finger reaches the game itself (horizon_client::ios drops winit's touches).
@MainActor
final class TouchControlsController: UIViewController {
    private let layout: ControlLayout
    private let settings: LauncherSettings
    private let look = LookView()
    private let mouse = VirtualMouseView()
    private var controls: [UIView] = []
    private var link: CADisplayLink?
    private var playing = false

    init(layout: ControlLayout, settings: LauncherSettings) {
        self.layout = layout
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        look.sensitivity = settings.sensitivity
        for v in [look, mouse] as [UIView] {
            v.frame = view.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(v)
        }
        rebuild()
        setPlaying(false)
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        place()
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    @objc private func tick() {
        let now = hz_playing()
        if now != playing { setPlaying(now) }
    }

    private func setPlaying(_ on: Bool) {
        playing = on
        // Between the world and a screen nothing stays held (a lost release keeps the player walking).
        gameInput("release")
        for case let b as ControlButtonView in controls { b.reset() }
        (controls.first { $0 is JoystickView } as? JoystickView)?.reset()
        look.reset()
        mouse.reset()
        if !on { mouse.centre() }
        UIView.animate(withDuration: 0.15) { self.applyAlpha() }
        for v in controls + [look] { v.isUserInteractionEnabled = on }
        mouse.isUserInteractionEnabled = !on
    }

    func rebuild() {
        controls.forEach { $0.removeFromSuperview() }
        controls = layout.buttons.map { button in
            let v: UIView
            switch button.action {
            case .joystick: v = JoystickView(button: button)
            case .hotbar: v = HotbarView(button: button)
            default:
                let b = ControlButtonView(button: button)
                b.onChat = { [weak self] in self?.chat() }
                b.onEdit = { [weak self] in self?.editLayout() }
                v = b
            }
            v.isUserInteractionEnabled = playing
            view.insertSubview(v, belowSubview: mouse)
            return v
        }
        place()
    }

    private func place() {
        let bounds = view.bounds
        let scale = settings.controlScale
        for (v, b) in zip(controls, layout.buttons) {
            let w = b.size * scale
            let h = b.action == .hotbar ? w / 9 : w
            v.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            v.center = CGPoint(x: bounds.width * b.x, y: bounds.height * b.y)
        }
        mouse.layoutButtons(scale: scale)
        applyAlpha()
    }

    /// The world's controls at their own opacity while playing; the mouse on the screens.
    private func applyAlpha() {
        look.alpha = playing ? 1 : 0
        mouse.alpha = playing ? 0 : 1
        for (v, b) in zip(controls, layout.buttons) {
            v.alpha = playing ? b.opacity * settings.controlOpacity : 0
        }
    }

    private func chat() {
        gameInput("key t tap")
        let alert = UIAlertController(title: String(localized: "Чат"), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = String(localized: "Сообщение или /команда") }
        alert.addAction(UIAlertAction(title: String(localized: "Отмена"), style: .cancel) { _ in
            gameInput("key esc tap")
        })
        alert.addAction(UIAlertAction(title: String(localized: "Отправить"), style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            if text.isEmpty {
                gameInput("key esc tap")
            } else {
                gameInput("type \(text)")
                gameInput("key enter tap")
            }
        })
        present(alert, animated: true)
    }

    private func editLayout() {
        gameInput("key esc tap") // pause while the layout changes
        let editor = UIHostingController(rootView: ControlEditorView(onDone: { [weak self] in
            self?.dismiss(animated: true)
            self?.rebuild()
        }).environmentObject(layout).environmentObject(settings))
        editor.modalPresentationStyle = .fullScreen
        editor.view.backgroundColor = .clear
        present(editor, animated: true)
    }
}

// MARK: - The view: a drag turns it, nothing else

/// Behind the other controls, over the whole screen, in the world: a drag turns the view
/// (`turn`). Taps and holds do nothing: breaking, attacking, using and placing are buttons.
final class LookView: UIView {
    var sensitivity: Double = 0.25
    private var finger: UITouch?
    private var last: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() { finger = nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard finger == nil, let t = touches.first else { return }
        finger = t
        last = t.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = finger, touches.contains(t) else { return }
        let p = t.location(in: self)
        let dx = p.x - last.x, dy = p.y - last.y
        last = p
        if dx != 0 || dy != 0 {
            gameInput(String(format: "turn %.3f %.3f", dx * sensitivity, dy * sensitivity))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = finger, touches.contains(t) { reset() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { reset() }
}

// MARK: - Virtual mouse

/// The screens' mouse: a drag anywhere moves the cursor (like a trackpad), a tap clicks at it,
/// two fingers up or down scroll. LMB and RMB can be held while another finger drags (moving
/// stacks in the inventory).
final class VirtualMouseView: UIView {
    private let cursor = UIImageView()
    private var position = CGPoint(x: 200, y: 200)
    private var finger: UITouch?
    private var last: CGPoint = .zero
    private var travelled: CGFloat = 0
    private var started = Date()
    private var scrollFrom: CGFloat?
    private var buttons: [MouseButtonView] = []
    var speed: CGFloat = 1.4

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
        cursor.image = UIImage(systemName: "cursorarrow", withConfiguration: config)
        cursor.tintColor = .white
        cursor.layer.shadowColor = UIColor.black.cgColor
        cursor.layer.shadowOpacity = 0.8
        cursor.layer.shadowRadius = 2
        cursor.layer.shadowOffset = .zero
        cursor.sizeToFit()
        cursor.isUserInteractionEnabled = false
        addSubview(cursor)
        let specs: [(String, String, MouseButtonView.Kind)] = [
            ("ЛКМ", "computermouse.fill", .button(0)),
            ("ПКМ", "computermouse", .button(1)),
            ("Назад", "arrow.uturn.backward", .key("esc")),
            ("Вверх", "chevron.up", .wheel(1)),
            ("Вниз", "chevron.down", .wheel(-1)),
        ]
        buttons = specs.map { MouseButtonView(title: $0.0, symbol: $0.1, kind: $0.2) }
        buttons.forEach(addSubview)
        bringSubviewToFront(cursor)
    }

    required init?(coder: NSCoder) { fatalError() }

    func layoutButtons(scale: Double) {
        let s = 64 * scale
        let b = bounds
        let frames: [CGPoint] = [
            CGPoint(x: b.width - s * 0.9, y: b.height - s * 1.0),   // LMB
            CGPoint(x: b.width - s * 0.9, y: b.height - s * 2.2),   // RMB
            CGPoint(x: s * 0.9, y: s * 0.9),                        // Back
            CGPoint(x: s * 0.9, y: b.height - s * 2.2),             // wheel up
            CGPoint(x: s * 0.9, y: b.height - s * 1.0),             // wheel down
        ]
        for (button, centre) in zip(buttons, frames) {
            button.bounds = CGRect(x: 0, y: 0, width: s, height: s)
            button.center = centre
        }
        clamp()
    }

    func reset() {
        finger = nil
        scrollFrom = nil
        buttons.forEach { $0.release() }
    }

    func centre() {
        position = CGPoint(x: bounds.midX, y: bounds.midY)
        clamp()
        send()
    }

    /// The game's view: winit's window, below this one.
    private func gameView() -> UIView? {
        let windows = window?.windowScene?.windows ?? []
        return windows.first { !($0 is PassthroughWindow) && !$0.isHidden && $0.windowLevel == .normal }?
            .rootViewController?.view
    }

    private func clamp() {
        var area = bounds
        if let game = gameView() { area = game.convert(game.bounds, to: self) }
        position.x = min(max(position.x, area.minX), area.maxX - 1)
        position.y = min(max(position.y, area.minY), area.maxY - 1)
        cursor.frame.origin = CGPoint(x: position.x - 4, y: position.y - 3)
    }

    /// The cursor to the game, in its view's pixels.
    private func send() {
        guard let game = gameView() else {
            // No game view found: the screen's pixels, which it fills on most devices.
            let scale = window?.screen.nativeScale ?? 2
            hz_pointer_move(Double(position.x * scale), Double(position.y * scale))
            return
        }
        let p = game.convert(position, from: self)
        let scale = game.contentScaleFactor
        hz_pointer_move(Double(p.x * scale), Double(p.y * scale))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let active = event?.allTouches?.filter { $0.view === self && $0.phase != .ended && $0.phase != .cancelled } ?? []
        if active.count >= 2 {
            // Two fingers: scroll.
            finger = nil
            scrollFrom = active.map { $0.location(in: self).y }.reduce(0, +) / CGFloat(active.count)
            return
        }
        guard finger == nil, let t = touches.first else { return }
        finger = t
        last = t.location(in: self)
        travelled = 0
        started = Date()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let from = scrollFrom {
            let active = event?.allTouches?.filter { $0.view === self } ?? []
            guard !active.isEmpty else { return }
            let y = active.map { $0.location(in: self).y }.reduce(0, +) / CGFloat(active.count)
            if abs(y - from) > 24 {
                hz_pointer_wheel(y > from ? 1 : -1)
                scrollFrom = y
            }
            return
        }
        guard let t = finger, touches.contains(t) else { return }
        let p = t.location(in: self)
        let dx = p.x - last.x, dy = p.y - last.y
        last = p
        travelled += hypot(dx, dy)
        position.x += dx * speed
        position.y += dy * speed
        clamp()
        send()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if scrollFrom != nil {
            let left = event?.allTouches?.filter { $0.view === self && $0.phase != .ended && $0.phase != .cancelled } ?? []
            if left.isEmpty { scrollFrom = nil }
            return
        }
        guard let t = finger, touches.contains(t) else { return }
        finger = nil
        // A tap clicks where the cursor is.
        if travelled < 10 && Date().timeIntervalSince(started) < 0.3 {
            send()
            hz_pointer_button(0, true)
            hz_pointer_button(0, false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finger = nil
        scrollFrom = nil
    }
}

/// A virtual mouse button on glass: held while the finger is down.
final class MouseButtonView: UIView {
    enum Kind {
        case button(UInt8)
        case key(String)
        case wheel(Float)
    }

    private let kind: Kind
    private var down = false

    init(title: String, symbol: String, kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        clipsToBounds = true
        layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        layer.borderWidth = 1
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.isUserInteractionEnabled = false
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blur)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = .white
        let label = UILabel()
        label.text = String(localized: String.LocalizationValue(title))
        label.textColor = .white
        label.font = .systemFont(ofSize: 11, weight: .bold)
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        subviews.first?.frame = bounds
    }

    private func highlight(_ on: Bool) {
        backgroundColor = on ? UIColor.white.withAlphaComponent(0.35) : .clear
        transform = on ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
    }

    func release() {
        if down, case .button(let b) = kind { hz_pointer_button(b, false) }
        down = false
        highlight(false)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        highlight(true)
        switch kind {
        case .button(let b):
            down = true
            hz_pointer_button(b, true)
        case .key(let k):
            gameInput("key \(k) tap")
        case .wheel(let lines):
            hz_pointer_wheel(lines)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release()
    }
}

// MARK: - Movement stick

final class JoystickView: UIView {
    private let base = UIView()
    private let knob = UIView()
    private var finger: UITouch?
    private var held: Set<String> = []

    init(button: ControlButton) {
        super.init(frame: .zero)
        for v in [base, knob] {
            v.isUserInteractionEnabled = false
            v.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            v.layer.borderWidth = 1
            addSubview(v)
        }
        base.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.isUserInteractionEnabled = false
        blur.clipsToBounds = true
        base.insertSubview(blur, at: 0)
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        base.frame = bounds
        base.layer.cornerRadius = bounds.width / 2
        base.subviews.first?.frame = base.bounds
        base.subviews.first?.layer.cornerRadius = bounds.width / 2
        if finger == nil { centreKnob() }
    }

    private func centreKnob() {
        let k = bounds.width * 0.42
        knob.frame = CGRect(x: (bounds.width - k) / 2, y: (bounds.height - k) / 2, width: k, height: k)
        knob.layer.cornerRadius = k / 2
    }

    func reset() {
        finger = nil
        set([])
        centreKnob()
    }

    private func set(_ keys: Set<String>) {
        for k in held.subtracting(keys) { gameInput("key \(k) up") }
        for k in keys.subtracting(held) { gameInput("key \(k) down") }
        held = keys
    }

    private func update(_ p: CGPoint) {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let r = bounds.width / 2
        var v = CGVector(dx: p.x - c.x, dy: p.y - c.y)
        let len = hypot(v.dx, v.dy)
        if len > r { v = CGVector(dx: v.dx / len * r, dy: v.dy / len * r) }
        knob.center = CGPoint(x: c.x + v.dx, y: c.y + v.dy)
        let m = min(len / r, 1)
        guard m > 0.25 else { set([]); return }
        // Eight directions, 45° each.
        let angle = atan2(-v.dy, v.dx) // 0 = right, π/2 = up
        let sector = Int((angle + .pi * 2 + .pi / 8).truncatingRemainder(dividingBy: .pi * 2) / (.pi / 4))
        let dirs: [Set<String>] = [["d"], ["w", "d"], ["w"], ["w", "a"], ["a"], ["s", "a"], ["s"], ["s", "d"]]
        var keys = dirs[sector % 8]
        // Pushed to the rim straight ahead: sprint.
        if m > 0.97 && sector == 2 { keys.insert("ctrl") }
        set(keys)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard finger == nil, let t = touches.first else { return }
        finger = t
        update(t.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = finger, touches.contains(t) else { return }
        update(t.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = finger, touches.contains(t) else { return }
        reset()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        reset()
    }
}

// MARK: - Buttons

final class ControlButtonView: UIView {
    let button: ControlButton
    var onChat: (() -> Void)?
    var onEdit: (() -> Void)?
    private var on = false
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let icon = UIImageView()
    private let label = UILabel()

    init(button: ControlButton) {
        self.button = button
        super.init(frame: .zero)
        clipsToBounds = true
        layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        layer.borderWidth = 1
        blur.isUserInteractionEnabled = false
        addSubview(blur)
        if let symbol = button.symbol, let image = UIImage(systemName: symbol) {
            icon.image = image
            icon.tintColor = .white
            icon.contentMode = .scaleAspectFit
            addSubview(icon)
        } else {
            label.text = button.label
            label.textColor = .white
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.adjustsFontSizeToFitWidth = true
            label.textAlignment = .center
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        blur.frame = bounds
        icon.frame = bounds.insetBy(dx: bounds.width * 0.28, dy: bounds.height * 0.28)
        label.frame = bounds.insetBy(dx: 6, dy: 6)
    }

    func reset() {
        on = false
        highlight(false)
    }

    private func highlight(_ down: Bool) {
        backgroundColor = down ? UIColor.white.withAlphaComponent(0.35) : .clear
        transform = down ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
    }

    private func send(_ down: Bool) {
        switch button.action {
        case .key(let k): gameInput("key \(k) \(down ? "down" : "up")")
        case .mouse(let b): gameInput("mouse \(b) \(down ? "down" : "up")")
        default: break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch button.action {
        case .chat: highlight(true); onChat?()
        case .editLayout: highlight(true); onEdit?()
        default:
            if button.toggle {
                on.toggle()
                highlight(on)
                send(on)
            } else {
                highlight(true)
                send(true)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch button.action {
        case .chat, .editLayout: highlight(false)
        default:
            if !button.toggle {
                highlight(false)
                send(false)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}

// MARK: - Hotbar

/// Nine slots over the game's hotbar: a touch selects the slot under it. Resize it in the
/// editor to sit exactly over the game's (it depends on the GUI scale).
final class HotbarView: UIView {
    init(button: ControlButton) {
        super.init(frame: .zero)
        layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 6
    }

    required init?(coder: NSCoder) { fatalError() }

    private var slot = -1

    private func select(_ t: UITouch) {
        let x = t.location(in: self).x
        let s = min(max(Int(x / bounds.width * 9), 0), 8)
        if s != slot {
            slot = s
            UISelectionFeedbackGenerator().selectionChanged()
            gameInput("hotbar \(s + 1)")
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        slot = -1
        touches.first.map(select)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touches.first.map(select)
    }
}
