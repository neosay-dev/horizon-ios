import SwiftUI
import UIKit

/// The touch controls over the game's window. They show only while the player is in the world
/// with no screen open (`hz_playing`); elsewhere every touch goes through to the game, where a
/// finger is the pointer (menus, inventory, chests).
@MainActor
final class TouchControlsController: UIViewController {
    private let layout: ControlLayout
    private let settings: LauncherSettings
    private let look = LookView()
    private var controls: [UIView] = []
    private var link: CADisplayLink?
    private var shown = false

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
        look.frame = view.bounds
        look.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(look)
        rebuild()
        setShown(false)
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
        let playing = hz_playing()
        if playing != shown { setShown(playing) }
    }

    private func setShown(_ on: Bool) {
        shown = on
        if !on {
            // Into a screen: nothing stays held (a lost release keeps the player walking).
            gameInput("release")
            for case let b as ControlButtonView in controls { b.reset() }
            (controls.first { $0 is JoystickView } as? JoystickView)?.reset()
            look.reset()
        }
        UIView.animate(withDuration: 0.15) { self.applyAlpha() }
        for v in controls + [look] { v.isUserInteractionEnabled = on }
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
            v.isUserInteractionEnabled = shown
            view.addSubview(v)
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
        applyAlpha()
    }

    /// Each control's own opacity while shown, none while hidden.
    private func applyAlpha() {
        look.alpha = shown ? 1 : 0
        for (v, b) in zip(controls, layout.buttons) {
            v.alpha = shown ? b.opacity * settings.controlOpacity : 0
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

// MARK: - The view: turn with a drag, tap to use, hold to break

/// Behind the other controls, over the whole screen: a drag turns the view (`turn`), a quick
/// tap uses or places (right click), a still hold breaks or attacks (left button held).
final class LookView: UIView {
    var sensitivity: Double = 0.25
    private var finger: UITouch?
    private var last: CGPoint = .zero
    private var travelled: CGFloat = 0
    private var started = Date()
    private var holdTimer: Timer?
    private var breaking = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        finger = nil
        holdTimer?.invalidate()
        breaking = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard finger == nil, let t = touches.first else { return }
        finger = t
        last = t.location(in: self)
        travelled = 0
        started = Date()
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self, self.finger != nil, self.travelled < 12 else { return }
            self.breaking = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            gameInput("mouse left down")
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = finger, touches.contains(t) else { return }
        let p = t.location(in: self)
        let dx = p.x - last.x, dy = p.y - last.y
        last = p
        travelled += hypot(dx, dy)
        if dx != 0 || dy != 0 {
            gameInput(String(format: "turn %.3f %.3f", dx * sensitivity, dy * sensitivity))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = finger, touches.contains(t) else { return }
        holdTimer?.invalidate()
        if breaking {
            gameInput("mouse left up")
        } else if travelled < 12 && Date().timeIntervalSince(started) < 0.3 {
            gameInput("mouse right click")
        }
        reset()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if breaking { gameInput("mouse left up") }
        reset()
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
