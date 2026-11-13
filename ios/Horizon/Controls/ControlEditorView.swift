import SwiftUI

/// The layout editor: drag controls into place, select one to resize it, change its opacity,
/// what it presses and whether a tap toggles it; add custom buttons; reset to the default.
struct ControlEditorView: View {
    @EnvironmentObject var layout: ControlLayout
    @EnvironmentObject var settings: LauncherSettings
    var onDone: () -> Void

    @State private var selected: ControlButton.ID?
    @State private var adding = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { selected = nil }

                ForEach($layout.buttons) { $button in
                    EditableControl(button: $button, selected: selected == button.id,
                                    screen: geo.size, scale: settings.controlScale)
                        .onTapGesture { selected = button.id }
                }

                VStack {
                    toolbar
                    Spacer()
                    if let index = layout.buttons.firstIndex(where: { $0.id == selected }) {
                        inspector(index)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding()
                .animation(.spring(duration: 0.3), value: selected)
            }
        }
        .sheet(isPresented: $adding) {
            AddControlSheet { button in
                layout.buttons.append(button)
                selected = button.id
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var toolbar: some View {
        GlassGroup {
            HStack(spacing: 12) {
                Button { layout.reset() } label: {
                    Label("Сбросить", systemImage: "arrow.counterclockwise")
                }
                .glassButton()
                Spacer()
                Button { adding = true } label: {
                    Label("Кнопка", systemImage: "plus")
                }
                .glassButton()
                Button {
                    layout.save()
                    onDone()
                } label: {
                    Label("Готово", systemImage: "checkmark")
                }
                .glassButton(prominent: true)
            }
        }
    }

    @ViewBuilder
    private func inspector(_ i: Int) -> some View {
        let button = $layout.buttons[i]
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Название", text: button.label)
                    .font(.headline)
                Spacer()
                if layout.buttons[i].action != .joystick && layout.buttons[i].action != .hotbar {
                    Button(role: .destructive) {
                        layout.buttons.remove(at: i)
                        selected = nil
                    } label: { Image(systemName: "trash") }
                    .glassButton()
                }
            }
            HStack {
                Text("Размер")
                Slider(value: button.size, in: layout.buttons[i].action == .hotbar ? 180...720 : 32...220)
            }
            HStack {
                Text("Прозрачность")
                Slider(value: button.opacity, in: 0.1...1)
            }
            switch layout.buttons[i].action {
            case .key, .mouse:
                Toggle("Нажатие переключает (вкл/выкл)", isOn: button.toggle)
                ActionPicker(action: button.action)
            default:
                EmptyView()
            }
        }
        .padding(18)
        .glassCard()
        .frame(maxWidth: 520)
    }
}

/// One control as the editor draws it, dragged to move.
private struct EditableControl: View {
    @Binding var button: ControlButton
    var selected: Bool
    var screen: CGSize
    var scale: Double
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        let w = button.size * scale
        let h = button.action == .hotbar ? w / 9 : w
        ZStack {
            if let symbol = button.symbol {
                Image(systemName: symbol).font(.system(size: min(w, h) * 0.35, weight: .semibold))
            } else {
                Text(button.label).font(.caption.bold()).minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(.white)
        .frame(width: w, height: h)
        .background(shape.fill(.white.opacity(0.12)))
        .overlay(shape.stroke(selected ? Color.yellow : .white.opacity(0.6), lineWidth: selected ? 3 : 1))
        .opacity(button.opacity)
        .position(x: screen.width * button.x + drag.width, y: screen.height * button.y + drag.height)
        .gesture(
            DragGesture()
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    button.x = min(max(button.x + value.translation.width / screen.width, 0.02), 0.98)
                    button.y = min(max(button.y + value.translation.height / screen.height, 0.02), 0.98)
                })
    }

    private var shape: AnyShape {
        button.action == .hotbar ? AnyShape(RoundedRectangle(cornerRadius: 6)) : AnyShape(Circle())
    }
}

/// What a custom button presses: a key or a mouse button.
private struct ActionPicker: View {
    @Binding var action: ControlAction

    var body: some View {
        Picker("Действие", selection: $action) {
            Text("Левая кнопка мыши (ударить/ломать)").tag(ControlAction.mouse("left"))
            Text("Правая кнопка мыши (использовать)").tag(ControlAction.mouse("right"))
            Text("Средняя кнопка мыши (выбрать блок)").tag(ControlAction.mouse("middle"))
            ForEach(ControlLayout.keyChoices, id: \.0) { key, name in
                Text(name).tag(ControlAction.key(key))
            }
        }
        .pickerStyle(.menu)
    }
}

private struct AddControlSheet: View {
    var add: (ControlButton) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var action: ControlAction = .key("f")
    @State private var toggle = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $label)
                ActionPicker(action: $action)
                Toggle("Нажатие переключает (вкл/выкл)", isOn: $toggle)
            }
            .navigationTitle("Новая кнопка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        add(ControlButton(label: label.isEmpty ? String(localized: "Кнопка") : label,
                                          symbol: nil, action: action, x: 0.5, y: 0.5, size: 56,
                                          toggle: toggle))
                        dismiss()
                    }
                }
            }
        }
    }
}
