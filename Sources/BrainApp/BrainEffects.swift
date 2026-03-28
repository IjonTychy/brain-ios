import SwiftUI

// MARK: - BrainEffects: Animations, transitions, and delightful interactions

enum BrainEffects {

    // MARK: - Staggered appearance for lists

    struct StaggeredAppear: ViewModifier {
        let index: Int
        @State private var appeared = false

        func body(content: Content) -> some View {
            content
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .onAppear {
                    withAnimation(
                        .spring(duration: 0.5, bounce: 0.3)
                        .delay(Double(index) * 0.05)
                    ) {
                        appeared = true
                    }
                }
        }
    }

    // MARK: - Shimmer loading effect

    struct Shimmer: ViewModifier {
        @State private var phase: CGFloat = 0

        func body(content: Content) -> some View {
            content
                .overlay(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.3), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: phase)
                    .mask(content)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 200
                    }
                }
        }
    }

    // MARK: - Pulse (subtle breathing for active elements)

    struct Pulse: ViewModifier {
        @State private var isPulsing = false

        func body(content: Content) -> some View {
            content
                .scaleEffect(isPulsing ? 1.05 : 1.0)
                .opacity(isPulsing ? 0.85 : 1.0)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 2.0)
                        .repeatForever(autoreverses: true)
                    ) {
                        isPulsing = true
                    }
                }
        }
    }

    // MARK: - Confetti for celebrations

    struct ConfettiPiece: Identifiable {
        let id = UUID()
        let color: Color
        let x: CGFloat
        let rotation: Double
        let delay: Double
    }

    struct ConfettiOverlay: View {
        @State private var animate = false
        let pieces: [ConfettiPiece] = (0..<30).map { _ in
            ConfettiPiece(
                color: [
                    BrainTheme.Colors.brandPurple,
                    BrainTheme.Colors.accentMint,
                    BrainTheme.Colors.accentCoral,
                    BrainTheme.Colors.accentAmber,
                    BrainTheme.Colors.accentSky
                ].randomElement()!,
                x: CGFloat.random(in: -150...150),
                rotation: Double.random(in: 0...360),
                delay: Double.random(in: 0...0.3)
            )
        }

        var body: some View {
            ZStack {
                ForEach(pieces) { piece in
                    Circle()
                        .fill(piece.color)
                        .frame(width: CGFloat.random(in: 4...8))
                        .offset(
                            x: piece.x,
                            y: animate ? 400 : -50
                        )
                        .rotationEffect(.degrees(animate ? piece.rotation : 0))
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeIn(duration: 1.5).delay(piece.delay),
                            value: animate
                        )
                }
            }
            .onAppear { animate = true }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - View extensions for effects

extension View {
    func staggeredAppear(index: Int) -> some View {
        modifier(BrainEffects.StaggeredAppear(index: index))
    }

    func shimmerLoading() -> some View {
        modifier(BrainEffects.Shimmer())
    }

    func pulseEffect() -> some View {
        modifier(BrainEffects.Pulse())
    }

    func confettiOverlay(isActive: Bool) -> some View {
        self.overlay {
            if isActive {
                BrainEffects.ConfettiOverlay()
            }
        }
    }
}
