import SwiftUI
import BrainCore

// Feedback render functions for SkillRenderer.
// Split from SkillRenderer.swift to speed up Swift compilation.
// All functions return AnyView for type erasure to avoid compile timeouts.

extension SkillRenderer {

    func renderToast(_ node: ScreenNode) -> AnyView {
        let message = resolveString(node, "message") ?? ""
        let type = resolveString(node, "type") ?? "info"
        let color: Color = {
            switch type {
            case "error": return BrainTheme.Colors.error
            case "warning": return BrainTheme.Colors.warning
            case "success": return BrainTheme.Colors.success
            default: return BrainTheme.Colors.info
            }
        }()

        return AnyView(
            Text(message)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(color.gradient)
                .clipShape(Capsule())
                .accessibilityLabel(message)
        )
    }

    func renderBanner(_ node: ScreenNode) -> AnyView {
        let message = resolveString(node, "message") ?? ""
        let type = resolveString(node, "type") ?? "info"
        let (icon, color): (String, Color) = {
            switch type {
            case "error": return ("xmark.circle.fill", BrainTheme.Colors.error)
            case "warning": return ("exclamationmark.triangle.fill", BrainTheme.Colors.warning)
            case "success": return ("checkmark.circle.fill", BrainTheme.Colors.success)
            default: return ("info.circle.fill", BrainTheme.Colors.info)
            }
        }()

        return AnyView(
            HStack {
                Image(systemName: icon)
                Text(message)
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.white)
            .padding()
            .background(color)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
        )
    }

    func renderLoading(_ node: ScreenNode) -> AnyView {
        let label = resolveString(node, "label")
        if let label {
            return AnyView(ProgressView(label).accessibilityLabel(label))
        } else {
            return AnyView(ProgressView())
        }
    }

    func renderSkeleton(_ node: ScreenNode) -> AnyView {
        return AnyView(
            renderChildren(node)
                .redacted(reason: .placeholder)
        )
    }

    func renderHaptic(_ node: ScreenNode) -> AnyView {
        let style = resolveString(node, "style") ?? "medium"
        return AnyView(
            Color.clear.frame(width: 0, height: 0)
                .onAppear {
                    let generator: UIImpactFeedbackGenerator
                    switch style {
                    case "light": generator = UIImpactFeedbackGenerator(style: .light)
                    case "heavy": generator = UIImpactFeedbackGenerator(style: .heavy)
                    case "rigid": generator = UIImpactFeedbackGenerator(style: .rigid)
                    case "soft": generator = UIImpactFeedbackGenerator(style: .soft)
                    default: generator = UIImpactFeedbackGenerator(style: .medium)
                    }
                    generator.impactOccurred()
                }
                .accessibilityHidden(true)
        )
    }
}
