import SwiftUI
import BrainCore

// Layout render functions for SkillRenderer.
// Split from SkillRenderer.swift to speed up Swift compilation.
// All functions return AnyView for type erasure to avoid compile timeouts.

extension SkillRenderer {

    func renderStack(_ node: ScreenNode) -> AnyView {
        let direction = resolveString(node, "direction") ?? "vertical"
        let spacing = resolveDouble(node, "spacing").map { CGFloat($0) }

        if direction == "horizontal" {
            return AnyView(HStack(spacing: spacing) { renderChildren(node) })
        } else if direction == "z" {
            return AnyView(ZStack { renderChildren(node) })
        } else {
            return AnyView(VStack(spacing: spacing) { renderChildren(node) })
        }
    }

    func renderList(_ node: ScreenNode) -> AnyView {
        let dataExpr = resolveString(node, "data")
        let items: [ExpressionValue] = {
            if let expr = dataExpr {
                let val = parser.evaluateExpression(expr, context: context)
                if case .array(let arr) = val { return arr }
            }
            return []
        }()

        if items.isEmpty {
            return AnyView(
                List { renderChildren(node) }
                    .listStyle(.plain)
            )
        } else if let template = node.children?.first {
            let itemName = resolveString(node, "as") ?? "item"
            return AnyView(
                List(Array(items.enumerated()), id: \.offset) { index, item in
                    let itemContext = contextWith(itemName, value: item, index: index)
                    SkillRenderer(node: template, context: itemContext, onAction: onAction, onSetVariable: onSetVariable)
                }
                .listStyle(.plain)
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    func renderRepeater(_ node: ScreenNode) -> AnyView {
        let dataExpr = resolveString(node, "data") ?? ""
        let itemName = resolveString(node, "as") ?? "item"

        let items: [ExpressionValue] = {
            let val = parser.evaluateExpression(dataExpr, context: context)
            if case .array(let arr) = val { return arr }
            return []
        }()

        if let template = node.children?.first {
            return AnyView(
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let itemContext = contextWith(itemName, value: item, index: index)
                    SkillRenderer(node: template, context: itemContext, onAction: onAction, onSetVariable: onSetVariable)
                }
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    func renderGrid(_ node: ScreenNode) -> AnyView {
        let columns = resolveDouble(node, "columns").map { Int($0) } ?? 2
        let spacing = resolveDouble(node, "spacing").map { CGFloat($0) } ?? BrainTheme.Spacing.sm

        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)

        return AnyView(
            LazyVGrid(columns: gridColumns, spacing: spacing) {
                if let children = node.children {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        renderNode(child)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        )
    }

    func renderTabView(_ node: ScreenNode) -> AnyView {
        if let children = node.children {
            return AnyView(
                TabView {
                    ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                        let label = child.properties?["title"]?.stringValue ?? "Tab \(index + 1)"
                        let icon = child.properties?["icon"]?.stringValue ?? "circle"
                        renderNode(child)
                            .tabItem {
                                Label(label, systemImage: icon)
                            }
                            .tag(index)
                    }
                }
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    func renderSplitView(_ node: ScreenNode) -> AnyView {
        if let children = node.children {
            return AnyView(
                NavigationSplitView {
                    if children.count > 0 { renderNode(children[0]) }
                } detail: {
                    if children.count > 1 { renderNode(children[1]) }
                }
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    func renderSection(_ node: ScreenNode) -> AnyView {
        let header = resolveString(node, "header")
        let footer = resolveString(node, "footer")
        return AnyView(
            Section {
                renderChildren(node)
            } header: {
                if let header { Text(header) }
            } footer: {
                if let footer { Text(footer) }
            }
        )
    }

    func renderDisclosureGroup(_ node: ScreenNode) -> AnyView {
        let title = resolveString(node, "title") ?? ""
        return AnyView(
            DisclosureGroup(title) {
                renderChildren(node)
            }
        )
    }

    func renderConditional(_ node: ScreenNode) -> AnyView {
        let condition = resolveString(node, "condition") ?? "false"
        let value = parser.evaluateExpression(condition, context: context)

        if value.isTruthy {
            if let children = node.children, children.count > 0 {
                return renderNode(children[0])
            }
        } else {
            if let children = node.children, children.count > 1 {
                return renderNode(children[1])
            }
        }
        return AnyView(EmptyView())
    }
}
