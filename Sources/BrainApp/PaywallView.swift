import SwiftUI

// Paywall shown when trial expires. Offers one-time purchase (no subscription).
struct PaywallView: View {
    var store: StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrainTheme.Spacing.xl) {
                    // Hero
                    VStack(spacing: BrainTheme.Spacing.md) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 64))
                            .foregroundStyle(BrainTheme.Gradients.brand)
                            .pulseEffect()

                        Text("I, Brain")
                            .font(BrainTheme.Typography.displayLarge)

                        Text("Dein persönliches Gehirn.\nEinmal kaufen, für immer nutzen.")
                            .font(BrainTheme.Typography.subheadline)
                            .foregroundStyle(BrainTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, BrainTheme.Spacing.xxl)

                    // Features
                    VStack(alignment: .leading, spacing: BrainTheme.Spacing.md) {
                        FeatureRow(icon: "cpu", color: BrainTheme.Colors.brandPurple,
                                   title: "Multi-LLM", detail: "Claude, GPT, Gemini, Grok & On-Device")
                        FeatureRow(icon: "lock.shield", color: BrainTheme.Colors.accentMint,
                                   title: "Offline-First", detail: "Deine Daten bleiben auf deinem Gerät")
                        FeatureRow(icon: "sparkles", color: BrainTheme.Colors.accentAmber,
                                   title: "Skills", detail: "KI erstellt neue Features per Chat")
                        FeatureRow(icon: "brain", color: BrainTheme.Colors.accentCoral,
                                   title: "Proaktiv", detail: "Erkennt Muster und erinnert dich")
                        FeatureRow(icon: "envelope", color: BrainTheme.Colors.accentSky,
                                   title: "E-Mail & Kalender", detail: "Alles an einem Ort")
                    }
                    .brainGlassCard()

                    // Price
                    VStack(spacing: BrainTheme.Spacing.sm) {
                        if let product = store.product {
                            Text(product.displayPrice)
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(BrainTheme.Gradients.brand)
                            Text("Einmaliger Kauf — kein Abo")
                                .font(BrainTheme.Typography.caption)
                                .foregroundStyle(BrainTheme.Colors.textSecondary)
                        } else {
                            Text("CHF 49.-")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(BrainTheme.Gradients.brand)
                            Text("Einmaliger Kauf — kein Abo")
                                .font(BrainTheme.Typography.caption)
                                .foregroundStyle(BrainTheme.Colors.textSecondary)
                        }
                    }

                    // Purchase button
                    Button {
                        isPurchasing = true
                        Task {
                            await store.purchase()
                            isPurchasing = false
                            if store.purchaseState == .purchased {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isPurchasing ? "Wird verarbeitet..." : "Jetzt freischalten")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrainTheme.Spacing.md)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrainTheme.Colors.brandPurple)
                    .disabled(isPurchasing || store.product == nil)
                    .brainPressEffect()

                    // Restore
                    Button("Kauf wiederherstellen") {
                        Task { await store.restorePurchases() }
                    }
                    .font(BrainTheme.Typography.caption)
                    .foregroundStyle(BrainTheme.Colors.textSecondary)

                    // Trial info
                    if case .trial(let days) = store.purchaseState {
                        Text("Noch \(days) Tage kostenlos testen")
                            .font(BrainTheme.Typography.caption)
                            .foregroundStyle(BrainTheme.Colors.accentMint)
                            .padding(.vertical, BrainTheme.Spacing.xs)
                            .padding(.horizontal, BrainTheme.Spacing.md)
                            .background(BrainTheme.Colors.accentMint.opacity(0.12), in: Capsule())
                    }

                    if let error = store.errorMessage {
                        Text(error)
                            .font(BrainTheme.Typography.caption)
                            .foregroundStyle(BrainTheme.Colors.error)
                    }
                }
                .padding(.horizontal, BrainTheme.Spacing.xl)
                .padding(.bottom, BrainTheme.Spacing.xxl)
            }
            .background(BrainTheme.Gradients.purpleMist.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Spaeter") { dismiss() }
                        .foregroundStyle(BrainTheme.Colors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: BrainTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(BrainTheme.Typography.caption)
                    .foregroundStyle(BrainTheme.Colors.textSecondary)
            }
        }
    }
}
