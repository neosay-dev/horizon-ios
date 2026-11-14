import SwiftUI

/// The original Horizon launcher's look (launcher/, crates/horizon-theme): a near-black page,
/// Geist and Geist Mono, numbered rows between hairlines, lilac Play.
enum HZ {
    static let page = Color(hex: 0x0B0C10)
    static let raised = Color(hex: 0x16181D)
    static let pill = Color(hex: 0x1A1C22)
    static let rule = Color.white.opacity(0.08)
    static let ink = Color(hex: 0xECEDF0)
    static let muted = Color(hex: 0x8B8F98)
    static let faint = Color(hex: 0x5C606A)
    static let accent = Color(hex: 0xA28BFF)
    static let accentText = Color(hex: 0xC6B8FF)
    static let onAccent = Color(hex: 0x15112A)
    static let ready = Color(hex: 0x4ADE80)
    static let warn = Color(hex: 0xF2C46B)
    static let danger = Color(hex: 0xFF8A8A)

    enum Weight { case regular, medium, semibold }

    static func sans(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .regular: name = "Geist-Regular"
        case .medium: name = "Geist-Medium"
        case .semibold: name = "Geist-SemiBold"
        }
        return .custom(name, fixedSize: size)
    }

    static func mono(_ size: CGFloat) -> Font { .custom("GeistMono-Regular", fixedSize: size) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// The launcher's buttons: lilac Play, dark pills, and text-only actions on the rows.
struct HZButton: ButtonStyle {
    enum Kind { case accent, pill, text }
    var kind: Kind = .pill
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
        Group {
            switch kind {
            case .accent:
                label.font(HZ.sans(15, .medium))
                    .foregroundStyle(HZ.onAccent)
                    .padding(.horizontal, 22).frame(minHeight: 40)
                    .background(HZ.accent.opacity(enabled ? 1 : 0.35), in: Capsule())
            case .pill:
                label.font(HZ.sans(13, .medium))
                    .foregroundStyle(HZ.ink)
                    .padding(.horizontal, 14).frame(minHeight: 32)
                    .background(HZ.pill, in: Capsule())
            case .text:
                label.font(HZ.sans(13, .medium))
                    .foregroundStyle(HZ.muted)
                    .padding(.vertical, 6)
            }
        }
        .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
        .contentShape(Rectangle())
    }
}

/// The small mark: two bars, the lilac horizon across them (the app icon's drawing).
struct HorizonMark: View {
    var size: CGFloat = 16

    var body: some View {
        Canvas { ctx, s in
            let k = s.width / 512
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(CGRect(x: x * k, y: y * k, width: w * k, height: h * k))
            }
            for x in [128.0, 320.0] {
                ctx.fill(r(x, 96, 64, 128), with: .color(HZ.ink))
                ctx.fill(r(x, 256, 64, 128), with: .color(HZ.faint))
            }
            ctx.fill(r(0, 224, 512, 32), with: .color(HZ.accent))
        }
        .frame(width: size, height: size)
    }
}

/// `MINECRAFT 26.3 · READY`: small mono capitals over a page's title.
struct Eyebrow: View {
    var text: String
    var status: String?
    var statusColor: Color = HZ.ready

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased()).foregroundStyle(HZ.muted)
            if let status {
                Circle().fill(HZ.faint).frame(width: 3, height: 3)
                Text(status.uppercased()).foregroundStyle(statusColor)
            }
        }
        .font(HZ.mono(11))
        .kerning(0.6)
    }
}

/// A page's head: the title and the line under it.
struct PageHead: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(HZ.sans(40, .medium)).foregroundStyle(HZ.ink)
            Text(subtitle).font(HZ.sans(14)).foregroundStyle(HZ.muted)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `01  Title / detail ......... Action`, between hairlines, as on the original's pages.
struct NumberedRow<Trailing: View>: View {
    var number: Int
    var title: String
    var detail: String?
    var detailColor: Color = HZ.muted
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(String(format: "%02d", number))
                .font(HZ.mono(11)).foregroundStyle(HZ.faint)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(HZ.sans(14, .medium)).foregroundStyle(HZ.ink)
                if let detail, !detail.isEmpty {
                    Text(detail).font(HZ.sans(12)).foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(HZ.rule).frame(height: 1) }
    }
}

extension NumberedRow where Trailing == EmptyView {
    init(number: Int, title: String, detail: String?, detailColor: Color = HZ.muted) {
        self.init(number: number, title: title, detail: detail, detailColor: detailColor) { EmptyView() }
    }
}

/// The list's top hairline.
struct Hairline: View {
    var body: some View { Rectangle().fill(HZ.rule).frame(height: 1) }
}

/// The original's two-way switches (Client / Server): a dark capsule, the chosen one light.
struct Segmented<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.0 == selection
                Button { selection = option.0 } label: {
                    Text(option.1)
                        .font(HZ.sans(13, .medium))
                        .foregroundStyle(on ? HZ.page : HZ.muted)
                        .padding(.horizontal, 14).frame(minHeight: 28)
                        .background(on ? HZ.ink : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(HZ.pill, in: Capsule())
    }
}

/// The toggle of the original's settings: a lilac track when on.
struct HZToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().tint(HZ.accent)
    }
}
