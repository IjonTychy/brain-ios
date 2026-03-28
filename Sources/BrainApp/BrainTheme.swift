import SwiftUI

enum BrainTheme {
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32
    static let cornerRadiusMD: CGFloat = 12
    static let cornerRadiusLG: CGFloat = 16

    enum Colors {
        static let brandPurple = Color(red: 0.42, green: 0.35, blue: 0.82)
        static let brandBlue = Color.accentColor
        static let brandAmber = Color(red: 0.95, green: 0.75, blue: 0.30)
        static let accentMint = Color(red: 0.40, green: 0.82, blue: 0.72)
        static let accentCoral = Color(red: 0.92, green: 0.45, blue: 0.42)
        static let accentAmber = Color(red: 0.95, green: 0.75, blue: 0.30)
        static let accentSky = Color(red: 0.35, green: 0.68, blue: 0.95)
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let destructive = Color.red
        static let info = Color.blue
        static let textPrimary = Color(.label)
        static let textSecondary = Color(.secondaryLabel)
        static let textTertiary = Color(.tertiaryLabel)
        static let glassTint = Color.white.opacity(0.05)
        static let glassBorder = Color.white.opacity(0.15)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let card: CGFloat = 14
    }

    enum Shadow {
        static let subtle = ShadowStyle(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        static let medium = ShadowStyle(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    enum Shadows {
        static let subtle: Color = .black.opacity(0.06)
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    enum Typography {
        static let displayLarge: Font = .largeTitle.weight(.bold)
        static let headline: Font = .headline
        static let subheadline: Font = .subheadline
        static let callout: Font = .callout
        static let caption: Font = .caption
        static let captionSmall: Font = .caption2
        static let statSmall: Font = .title2.weight(.semibold)
    }

    enum Animations {
        static let springDefault: Animation = .spring(duration: 0.4, bounce: 0.2)
        static let springSnappy: Animation = .spring(duration: 0.3, bounce: 0.15)
        static let springGentle: Animation = .spring(duration: 0.6, bounce: 0.3)
    }

    enum Gradients {
        static let brand = LinearGradient(
            colors: [Colors.brandPurple, Colors.accentSky],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let purpleMist = LinearGradient(
            colors: [Colors.brandPurple.opacity(0.15), Colors.accentSky.opacity(0.08), Color(.systemBackground)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let heroCard = LinearGradient(
            colors: [Colors.brandPurple, Colors.brandPurple.opacity(0.85), Colors.accentSky.opacity(0.9)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let freshMint = LinearGradient(
            colors: [Colors.accentMint.opacity(0.12), Colors.accentSky.opacity(0.06), Color(.systemBackground)],
            startPoint: .top, endPoint: .bottom
        )
        static func timeOfDaySubtle() -> LinearGradient {
            let hour = Calendar.current.component(.hour, from: Date())
            let colors: [Color]
            switch hour {
            case 5..<8:
                colors = [Color(red: 1.0, green: 0.85, blue: 0.7).opacity(0.3), Color(.systemBackground)]
            case 8..<17:
                colors = [Color(red: 0.9, green: 0.95, blue: 1.0).opacity(0.3), Color(.systemBackground)]
            case 17..<20:
                colors = [Color(red: 1.0, green: 0.8, blue: 0.6).opacity(0.3), Color(.systemBackground)]
            default:
                colors = [Color(red: 0.15, green: 0.15, blue: 0.3).opacity(0.3), Color(.systemBackground)]
            }
            return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        }
    }

    static func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Guten Morgen"
        case 12..<17: return "Guten Tag"
        case 17..<22: return "Guten Abend"
        default: return "Gute Nacht"
        }
    }

    static func seasonalGreeting() -> String? {
        let cal = Calendar.current
        let month = cal.component(.month, from: Date())
        let day = cal.component(.day, from: Date())
        if month == 12 && day >= 20 { return "Frohe Weihnachten!" }
        if month == 1 && day <= 3 { return "Frohes neues Jahr!" }
        if month == 8 && day == 1 { return "Happy 1. August!" }
        return nil
    }
}

// MARK: - View Modifiers

extension View {
    func brainCard(padding: CGFloat = BrainTheme.Spacing.lg) -> some View {
        self
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BrainTheme.Radius.card))
            .shadow(color: BrainTheme.Shadow.subtle.color, radius: BrainTheme.Shadow.subtle.radius, x: 0, y: 2)
    }

    func brainGlassCard(cornerRadius: CGFloat = BrainTheme.Radius.card) -> some View {
        self
            .padding(BrainTheme.Spacing.lg)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(BrainTheme.Colors.glassBorder, lineWidth: 0.5)
                    )
            }
            .shadow(color: BrainTheme.Shadow.subtle.color, radius: BrainTheme.Shadow.subtle.radius, x: 0, y: 2)
    }

    func brainPressEffect() -> some View {
        self.buttonStyle(BrainPressButtonStyle())
    }

    func brainSectionHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrainTheme.Colors.brandPurple)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrainTheme.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, BrainTheme.Spacing.lg)
        .padding(.top, BrainTheme.Spacing.lg)
        .padding(.bottom, BrainTheme.Spacing.xs)
    }

    func brainToast(_ message: Binding<String?>) -> some View {
        self.overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrainTheme.Spacing.lg)
                    .padding(.vertical, BrainTheme.Spacing.sm)
                    .background(.black.opacity(0.8), in: Capsule())
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                message.wrappedValue = nil
                            }
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: message.wrappedValue != nil)
    }
}

struct BrainPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

struct BrainTagView: View {
    let text: String
    var color: Color = BrainTheme.Colors.brandPurple
    var removable: Bool = false
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
            if removable {
                Button { onRemove?() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(color.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: return nil
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}


// MARK: - FlowLayout (wrapping horizontal layout for tags)

// MARK: - Brain Facts Easter Egg
enum BrainFacts {
    static let facts = [
        "Dein Gehirn verbraucht ~20% deiner Energie",
        "Das Gehirn besteht zu 73% aus Wasser",
        "Dein Gehirn erzeugt genug Strom für eine Glühbirne",
        "Das Gehirn verarbeitet Bilder in nur 13 Millisekunden",
        "Dein Gehirn hat ~86 Milliarden Neuronen",
        "Informationen reisen mit bis zu 430 km/h durch dein Gehirn",
        "Das Gehirn kann 10^16 Prozesse pro Sekunde ausführen",
        "Träume dauern durchschnittlich 2-3 Sekunden",
    ]
    static func random() -> String { facts.randomElement() ?? facts[0] }
}

// MARK: - Thinking Phrases (Pull-to-refresh Easter Egg)
enum ThinkingPhrases {
    static let phrases = [
        "Neuronen feuern...", "Synapsen verknüpfen...",
        "Gedanken sortieren...", "Kreativ denken...",
        "Ideen brauen...", "Muster erkennen...",
    ]
    static func random() -> String { phrases.randomElement() ?? phrases[0] }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        totalHeight = currentY + lineHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
