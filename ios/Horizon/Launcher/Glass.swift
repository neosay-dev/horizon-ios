import SwiftUI

/// Liquid Glass on iOS 26, the closest material before it.
extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 28) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                in: .capsule)
        } else {
            self.background((tint ?? .clear).opacity(0.35), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

/// Groups glass shapes so they blend and morph together on iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// The launcher's backdrop: a slow dusk gradient for the glass to refract.
struct LauncherBackdrop: View {
    @State private var phase = false

    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.10, green: 0.12, blue: 0.30),
                     Color(red: 0.36, green: 0.20, blue: 0.55),
                     Color(red: 0.95, green: 0.55, blue: 0.35)],
            startPoint: phase ? .topLeading : .top,
            endPoint: phase ? .bottomTrailing : .bottom)
        .overlay(alignment: .bottom) {
            // Blocky hills: the silhouette of a world at sunset.
            Canvas { ctx, size in
                let block = max(size.width / 24, 18)
                var x: CGFloat = 0
                var seed: UInt64 = 7
                while x < size.width {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let h = CGFloat(2 + Int(seed >> 60) % 4) * block
                    ctx.fill(Path(CGRect(x: x, y: size.height - h, width: block + 1, height: h)),
                             with: .color(Color(red: 0.06, green: 0.08, blue: 0.16)))
                    x += block
                }
            }
            .frame(height: 220)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) { phase.toggle() }
        }
    }
}
