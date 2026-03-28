import SwiftUI
import BrainCore

// Interaction render functions for SkillRenderer.
// Split from SkillRenderer.swift to speed up Swift compilation.
// All functions return AnyView for type erasure to avoid compile timeouts.

extension SkillRenderer {

    func renderButton(_ node: ScreenNode) -> AnyView {
        let title = resolveString(node, "title")
        let action = node.onTap ?? resolveString(node, "action") ?? ""
        let style = resolveString(node, "style") ?? "default"

        return AnyView(
            Button(action: { onAction(action, context) }) {
                if let children = node.children, !children.isEmpty {
                    renderChildren(node)
                } else {
                    Text(title ?? "Button")
                }
            }
            .buttonStyleForName(style)
            .accessibilityLabel(title ?? "Button")
            .accessibilityAddTraits(.isButton)
        )
    }

    func renderLink(_ node: ScreenNode) -> AnyView {
        let title = resolveString(node, "title") ?? ""
        let destination = resolveString(node, "destination") ?? ""
        if let url = URL(string: destination), destination.hasPrefix("https://") {
            return AnyView(
                Link(title, destination: url)
                    .accessibilityLabel(title)
            )
        } else {
            return AnyView(
                Text(title)
                    .foregroundStyle(.blue)
                    .accessibilityLabel(title)
            )
        }
    }

    func renderMenu(_ node: ScreenNode) -> AnyView {
        let title = resolveString(node, "title") ?? "Menü"
        return AnyView(
            Menu(title) {
                if let children = node.children {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        if child.type == "button" {
                            let itemTitle = child.properties?["title"]?.stringValue ?? "Item"
                            let action = child.onTap ?? child.properties?["action"]?.stringValue ?? ""
                            Button(itemTitle) { onAction(action, context) }
                        } else {
                            renderNode(child)
                        }
                    }
                }
            }
            .accessibilityLabel(title)
        )
    }

    func renderLongPress(_ node: ScreenNode) -> AnyView {
        let action = node.onTap ?? resolveString(node, "action") ?? ""
        return AnyView(
            renderChildren(node)
                .onLongPressGesture { onAction(action, context) }
        )
    }

    func renderNavigationLink(_ node: ScreenNode) -> AnyView {
        let title = resolveString(node, "title") ?? ""
        let destination = resolveString(node, "destination") ?? ""
        return AnyView(
            Button {
                onAction("navigate:\(destination)", context)
            } label: {
                HStack {
                    if let children = node.children, !children.isEmpty {
                        renderChildren(node)
                    } else {
                        Text(title)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
        )
    }

    func renderContextMenu(_ node: ScreenNode) -> AnyView {
        if let children = node.children, children.count >= 2 {
            return AnyView(
                renderNode(children[0])
                    .contextMenu {
                        ForEach(Array(children.dropFirst().enumerated()), id: \.offset) { _, menuChild in
                            renderNode(menuChild)
                        }
                    }
            )
        } else {
            return renderChildren(node)
        }
    }

    func renderShareLink(_ node: ScreenNode) -> AnyView {
        let text = resolveString(node, "text") ?? ""
        let title = resolveString(node, "title") ?? "Teilen"
        if #available(iOS 16.0, *) {
            return AnyView(
                ShareLink(item: text) {
                    Label(title, systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(title)
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    func renderDoubleTap(_ node: ScreenNode) -> AnyView {
        let action = node.onTap ?? resolveString(node, "action") ?? ""
        return AnyView(
            renderChildren(node)
                .onTapGesture(count: 2) { onAction(action, context) }
        )
    }
}
