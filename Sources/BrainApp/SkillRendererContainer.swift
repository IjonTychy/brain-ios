import SwiftUI
import BrainCore

// Container render functions for SkillRenderer.
// Split from SkillRenderer.swift to speed up Swift compilation.
// All functions return AnyView for type erasure to avoid compile timeouts.

extension SkillRenderer {

    func renderCard(_ node: ScreenNode) -> AnyView {
        let title = resolveString(node, "title")
        let subtitle = resolveString(node, "subtitle")
        let detail = resolveString(node, "detail")
        let icon = resolveString(node, "icon")

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                if title != nil || icon != nil {
                    HStack(spacing: 10) {
                        if let icon {
                            Image(systemName: icon)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if let title {
                                Text(title).font(.headline)
                            }
                            if let subtitle {
                                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                renderChildren(node)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    func renderGroupedList(_ node: ScreenNode) -> AnyView {
        return AnyView(
            List {
                renderChildren(node)
            }
            .listStyle(.insetGrouped)
        )
    }

    func renderOverlay(_ node: ScreenNode) -> AnyView {
        if let children = node.children, children.count >= 2 {
            return AnyView(
                renderNode(children[0])
                    .overlay {
                        ForEach(Array(children.dropFirst().enumerated()), id: \.offset) { _, overlayChild in
                            renderNode(overlayChild)
                        }
                    }
            )
        } else {
            return renderChildren(node)
        }
    }
}
