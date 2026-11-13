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
            case .key, .mouse, .combo:
                HStack {
                    Text("Высота")
                    Slider(value: button.aspect, in: 0.4...1.6)
                }
                Toggle("Нажатие переключает (вкл/выкл)", isOn: button.toggle)
                ComboEditor(action: button.action)
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
        let h = button.action == .hotbar ? w / 9 : w * button.aspect
        ZStack {
            if let symbol = button.symbol {
                Image(systemName: symbol).font(.system(size: min(w, h) * 0.35, weight: .semibold))
            } else {
                Text(button.label).font(.caption.bold()).minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(.white)
        .frame(width: w, height: h)
        .background(shape.fill(.black.opacity(0.45)))
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
        button.action == .joystick ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: button.action == .hotbar ? 6 : min(button.size, button.size * button.aspect) * scale * 0.18, style: .continuous))
    }
}

/// What a button presses: one key or mouse button, or several together (Ctrl + C, Shift + LMB).
private struct ComboEditor: View {
    @Binding var action: ControlAction
    @State private var picking = false

    private var parts: [String] { action.parts }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Клавиши (зажимаются вместе, по порядку)").font(.subheadline.bold())
            FlowRow(items: parts) { index, part in
                HStack(spacing: 4) {
                    Text(KeyCatalog.label(part)).font(.callout.monospaced().bold())
                    Button {
                        var p = parts
                        p.remove(at: index)
                        action = p.isEmpty ? .key("space") : .combo(p)
                    } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.5)))
            }
            Button { picking = true } label: { Label("Добавить клавишу", systemImage: "plus") }
                .glassButton()
        }
        .sheet(isPresented: $picking) {
            KeyPickerSheet { name in
                let p = parts
                if !p.contains(name) { action = .combo(p + [name]) }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// Every key the game knows, by group, and the mouse buttons.
private struct KeyPickerSheet: View {
    var pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(KeyCatalog.groups) { group in
                    let keys = group.keys.filter { search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) }
                    if !keys.isEmpty {
                        Section(group.title) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                                ForEach(keys, id: \.name) { key in
                                    Button {
                                        pick(key.name)
                                        dismiss()
                                    } label: {
                                        Text(key.label)
                                            .font(.callout.bold())
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.5)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Найти клавишу")
            .navigationTitle("Клавиша")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
        }
    }
}

/// Chips that wrap onto new lines.
private struct FlowRow<Item: Hashable, Content: View>: View {
    var items: [Item]
    @ViewBuilder var content: (Int, Item) -> Content

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in content(pair.offset, pair.element) }
        }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

private struct AddControlSheet: View {
    var add: (ControlButton) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var action: ControlAction = .combo(["key.keyboard.f"])
    @State private var toggle = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $label)
                ComboEditor(action: $action)
                Toggle("Нажатие переключает (вкл/выкл)", isOn: $toggle)
            }
            .navigationTitle("Новая кнопка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        let auto = action.parts.map(KeyCatalog.label).joined(separator: "+")
                        add(ControlButton(label: label.isEmpty ? auto : label,
                                          symbol: nil, action: action, x: 0.5, y: 0.5, size: 56,
                                          toggle: toggle))
                        dismiss()
                    }
                }
            }
        }
    }
}
