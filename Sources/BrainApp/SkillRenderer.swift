import SwiftUI
import BrainCore
import Charts
import MapKit
import WebKit
import AVKit
import CoreImage.CIFilterBuiltins

// The main renderer that converts a ScreenNode tree into native SwiftUI views.
// This is the "cell membrane" — it translates JSON instructions into visual reality.
// Supports 92 UI primitives across 9 categories.
//
// All render functions return AnyView for type erasure, which dramatically reduces
// Swift type-checker load and compile time (from 31+ minutes to seconds).
//
// Implementation functions are split into extension files to speed up compilation:
//   SkillRendererLayout.swift      — layout primitives (stack, list, grid, etc.)
//   SkillRendererContent.swift     — content primitives (text, image, icon, etc.)
//   SkillRendererInput.swift       — input primitives + binding helpers
//   SkillRendererInteraction.swift — interaction primitives (button, link, menu, etc.)
//   SkillRendererData.swift        — data/visualization primitives (chart, map, etc.)
//   SkillRendererFeedback.swift    — feedback primitives (toast, banner, loading, etc.)
//   SkillRendererContainer.swift   — container primitives (card, grouped-list, overlay)
//   SkillRendererSystem.swift      — system primitives (open-url, qr-code, video, etc.)
struct SkillRenderer: View {
    let node: ScreenNode
    let context: ExpressionContext
    let onAction: (String, ExpressionContext) -> Void
    let onSetVariable: (String, ExpressionValue) -> Void

    let parser = ExpressionParser()

    init(
        node: ScreenNode,
        context: ExpressionContext = ExpressionContext(),
        onAction: @escaping (String, ExpressionContext) -> Void = { _, _ in },
        onSetVariable: @escaping (String, ExpressionValue) -> Void = { _, _ in }
    ) {
        self.node = node
        self.context = context
        self.onAction = onAction
        self.onSetVariable = onSetVariable
    }

    var body: some View {
        renderNode(node)
    }

    // Recursive renderer: maps node.type to the corresponding SwiftUI view.
    func renderNode(_ node: ScreenNode) -> AnyView {
        if let condition = node.condition {
            let value = parser.evaluateExpression(condition, context: context)
            if value.isTruthy {
                return renderPrimitive(node)
            } else {
                return AnyView(EmptyView())
            }
        } else {
            return renderPrimitive(node)
        }
    }

    // Route to category-specific renderers to reduce Swift type-checker load.
    // A single @ViewBuilder with 92 cases causes exponential type-checking time.
    // Splitting into ~10 cases per function keeps compile time linear.
    private func renderPrimitive(_ node: ScreenNode) -> AnyView {
        let t = node.type
        if layoutTypes.contains(t) { return renderLayoutPrimitive(node) }
        else if contentTypes.contains(t) { return renderContentPrimitive(node) }
        else if inputTypes.contains(t) { return renderInputPrimitive(node) }
        else if interactionTypes.contains(t) { return renderInteractionPrimitive(node) }
        else if dataTypes.contains(t) { return renderDataPrimitive(node) }
        else if feedbackTypes.contains(t) { return renderFeedbackPrimitive(node) }
        else if containerTypes.contains(t) { return renderContainerPrimitive(node) }
        else if systemTypes.contains(t) { return renderSystemPrimitive(node) }
        else if specialTypes.contains(t) { return renderSpecialPrimitive(node) }
        else { return renderFallback(node) }
    }

    // MARK: - Type Sets (for fast routing)

    private static let _layoutTypes: Set<String> = [
        "stack", "scroll", "list", "repeater", "grid", "spacer", "sheet",
        "tab-view", "split-view", "conditional", "lazy-vstack", "lazy-hstack",
        "section", "disclosure-group", "view-that-fits"
    ]
    private static let _contentTypes: Set<String> = [
        "text", "image", "icon", "avatar", "badge", "divider", "markdown",
        "label", "async-image", "date-text", "redacted", "color-swatch"
    ]
    private static let _inputTypes: Set<String> = [
        "text-field", "text-editor", "toggle", "picker", "slider", "stepper",
        "date-picker", "color-picker", "search-field", "secure-field",
        "photo-picker", "paste-button", "multi-picker"
    ]
    private static let _interactionTypes: Set<String> = [
        "button", "link", "menu", "swipe-actions", "pull-to-refresh", "long-press",
        "navigation-link", "context-menu", "share-link", "confirmation-dialog", "double-tap"
    ]
    private static let _dataTypes: Set<String> = [
        "stat-card", "progress", "empty-state", "chart", "map", "calendar-grid",
        "gauge", "timer-display", "graph", "line-chart", "bar-chart", "pie-chart",
        "sparkline", "countdown", "metric", "heat-map"
    ]
    private static let _feedbackTypes: Set<String> = [
        "alert", "toast", "banner", "loading", "skeleton", "haptic"
    ]
    private static let _containerTypes: Set<String> = [
        "card", "grouped-list", "toolbar", "overlay", "full-screen-cover"
    ]
    private static let _systemTypes: Set<String> = [
        "open-url", "copy-button", "qr-code", "video-player", "live-activity", "widget-preview"
    ]
    private static let _specialTypes: Set<String> = [
        "rich-editor", "canvas", "camera", "scanner", "audio-player", "web-view"
    ]

    private var layoutTypes: Set<String> { Self._layoutTypes }
    private var contentTypes: Set<String> { Self._contentTypes }
    private var inputTypes: Set<String> { Self._inputTypes }
    private var interactionTypes: Set<String> { Self._interactionTypes }
    private var dataTypes: Set<String> { Self._dataTypes }
    private var feedbackTypes: Set<String> { Self._feedbackTypes }
    private var containerTypes: Set<String> { Self._containerTypes }
    private var systemTypes: Set<String> { Self._systemTypes }
    private var specialTypes: Set<String> { Self._specialTypes }

    // MARK: - Category Routers (each ≤15 cases for fast type-checking)

    private func renderLayoutPrimitive(_ node: ScreenNode) -> AnyView {
        switch node.type {
        case "stack": return renderStack(node)
        case "scroll": return AnyView(ScrollView { renderChildren(node) })
        case "list": return renderList(node)
        case "repeater": return renderRepeater(node)
        case "grid": return renderGrid(node)
        case "spacer": return AnyView(Spacer())
        case "sheet": return renderChildren(node)
        case "tab-view": return renderTabView(node)
        case "split-view": return renderSplitView(node)
        case "conditional": return renderConditional(node)
        case "lazy-vstack": return AnyView(LazyVStack(spacing: resolveDouble(node, "spacing").map { CGFloat($0) }) { renderChildren(node) })
        case "lazy-hstack": return AnyView(LazyHStack(spacing: resolveDouble(node, "spacing").map { CGFloat($0) }) { renderChildren(node) })
        case "section": return renderSection(node)
        case "disclosure-group": return renderDisclosureGroup(node)
        case "view-that-fits": return AnyView(ViewThatFits { renderChildren(node) })
        default: return renderFallback(node)
        }
    }

    private func renderContentPrimitive(_ node: ScreenNode) -> AnyView {
        switch node.type {
        case "text": return renderText(node)
        case "image": return renderImage(node)
        case "icon": return renderIcon(node)
        case "avatar": return renderAvatar(node)
        case "badge": return renderBadge(node)
        case "divider": return AnyView(Divider())
        case "markdown": return renderMarkdown(node)
        case "label": return renderLabel(node)
        case "async-image": return renderAsyncImage(node)
        case "date-text": return renderDateText(node)
        case "redacted": return AnyView(renderChildren(node).redacted(reason: .placeholder))
        case "color-swatch": return renderColorSwatch(node)
        default: return renderFallback(node)
        }
    }

    private func renderInputPrimitive(_ node: ScreenNode) -> AnyView {
        switch node.type {
        case "text-field": return renderTextField(node)
        case "text-editor": return renderTextEditor(node)
        case "toggle": return renderToggle(node)
        case "picker": return renderPicker(node)
        case "slider": return renderSlider(node)
        case "stepper": return renderStepper(node)
        case "date-picker": return renderDatePicker(node)
        case "color-picker": return renderColorPicker(node)
        case "search-field": return renderSearchField(node)
        case "secure-field": return renderSecureField(node)
        case "photo-picker": return renderSpecialPlaceholder("Foto-Auswahl", icon: "photo.on.rectangle.angled")
        case "paste-button": return renderPasteButton(node)
        case "multi-picker": return renderMultiPicker(node)
        default: return renderFallback(node)
        }
    }

    private func renderInteractionPrimitive(_ node: ScreenNode) -> AnyView {
        switch node.type {
        case "button": return renderButton(node)
        case "link": return renderLink(node)
        case "menu": return renderMenu(node)
        case "swipe-actions": return renderChildren(node)
        case "pull-to-refresh": return renderChildren(node)
        case "long-press": return renderLongPress(node)
        case "navigation-link": return renderNavigationLink(node)
        case "context-menu": return renderContextMenu(node)
        case "share-link": return renderShareLink(node)
        case "confirmation-dialog": return renderChildren(node)
        case "double-tap": return renderDoubleTap(node)
        default: return renderFallback(node)
        }
    }

    private func renderDataPrimitive(_ node: ScreenNode) -> AnyView {
        switch node.type {
        case "stat-card": return renderStatCard(node)
        case "progress": return renderProgress(node)
        case "empty-state": return renderEmptyState(node)
        case "chart": return renderChart(node)
        case "map": return renderMap(node)
        case "calendar-grid": return renderCalendarGrid(node)
        case "gauge": return renderGauge(node)
        case "timer-display": return renderTimerDisplay(node)
        case "graph": return renderSpecialPlaceholder("Knowledge Graph", icon: "point.3.connected.trianglepath.dotted")
        case "line-chart": return renderLineChart(node)
        case "bar-chart": return renderBarChart(node)
        case "pie-chart": return renderPieChart(node)
        case "sparkline": return renderSparkline(node)
        case "countdown": return renderCountdown(node)
        case "metric": return renderMetric(node)
        case "heat-map": return renderHeatMap(node)
        default: return renderFallback(node)
        }
    }

    private func renderFeedbackPrimitive(_ node: ScreenNode) -> AnyView {
        switch node.type {
        case "alert": return renderChildren(node)
        case "toast": return renderToast(node)
        case "banner": return renderBanner(node)
        case "loading": return renderLoading(node)
        case "skeleton": return renderSkeleton(node)
        case "haptic": return renderHaptic(node)
        default: return renderFallback(node)
        }
    }

    private func renderContainerPrimitive(_ node: ScreenNode) -> AnyView {
        switch node.type {
        case "card": return renderCard(node)
        case "grouped-list": return renderGroupedList(node)
        case "toolbar": return renderChildren(node)
        case "overlay": return renderOverlay(node)
        case "full-screen-cover": return renderChildren(node)
        default: return renderFallback(node)
        }
    }

    private func renderSystemPrimitive(_ node: ScreenNode) -> AnyView {
        switch node.type {
        case "open-url": return renderOpenUrl(node)
        case "copy-button": return renderCopyButton(node)
        case "qr-code": return renderQRCode(node)
        case "video-player": return renderVideoPlayer(node)
        case "live-activity": return renderSpecialPlaceholder("Live Activity", icon: "dot.radiowaves.left.and.right")
        case "widget-preview": return renderSpecialPlaceholder("Widget Preview", icon: "widget.small")
        default: return renderFallback(node)
        }
    }

    private func renderSpecialPrimitive(_ node: ScreenNode) -> AnyView {
        switch node.type {
        case "rich-editor": return renderSpecialPlaceholder("Rich Editor", icon: "doc.richtext")
        case "canvas": return renderSpecialPlaceholder("Canvas", icon: "pencil.and.outline")
        case "camera": return renderSpecialPlaceholder("Kamera", icon: "camera")
        case "scanner": return renderSpecialPlaceholder("Scanner", icon: "doc.viewfinder")
        case "audio-player": return renderAudioPlayer(node)
        case "web-view": return renderWebView(node)
        default: return renderFallback(node)
        }
    }

    // MARK: - Fallback & Special Placeholder

    func renderFallback(_ node: ScreenNode) -> AnyView {
        AnyView(
            VStack {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(.secondary)
                Text(node.type)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(4)
            .accessibilityLabel("Unbekanntes Element: \(node.type)")
        )
    }

    func renderSpecialPlaceholder(_ title: String, icon: String) -> AnyView {
        AnyView(
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Coming in v1.1")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("\(title) — bald verfügbar")
        )
    }

    // MARK: - Children

    func renderChildren(_ node: ScreenNode) -> AnyView {
        if let children = node.children {
            return AnyView(
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    renderNode(child)
                }
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    // MARK: - Context helpers

    func contextWith(_ name: String, value: ExpressionValue, index: Int) -> ExpressionContext {
        var childContext = context
        childContext.variables[name] = value
        childContext.variables["index"] = .int(index)
        return childContext
    }

    // MARK: - Resolution helpers

    func resolveString(_ node: ScreenNode, _ key: String) -> String? {
        guard let prop = node.properties?[key] else { return nil }
        if case .string(let s) = prop {
            return s.contains("{{") ? parser.evaluate(s, context: context) : s
        }
        return nil
    }

    func resolveDouble(_ node: ScreenNode, _ key: String) -> Double? {
        node.properties?[key]?.doubleValue
    }

    func resolveBool(_ node: ScreenNode, _ key: String) -> Bool? {
        node.properties?[key]?.boolValue
    }

    func resolveStringArray(_ node: ScreenNode, _ key: String) -> [String] {
        guard let prop = node.properties?[key] else { return [] }
        if case .array(let arr) = prop {
            return arr.compactMap { item in
                if case .string(let s) = item { return s }
                return nil
            }
        }
        if case .string(let s) = prop {
            let val = s.contains("{{") ? parser.evaluate(s, context: context) : s
            let result = parser.evaluateExpression(val, context: context)
            if case .array(let arr) = result {
                return arr.map(\.stringRepresentation)
            }
        }
        return []
    }

    // MARK: - Chart data helpers

    struct ChartDataPoint {
        let label: String
        let value: Double
    }

    func resolveChartData(_ node: ScreenNode) -> [ChartDataPoint] {
        guard let prop = node.properties?["data"] else { return [] }
        if case .array(let arr) = prop {
            return arr.enumerated().map { index, item in
                switch item {
                case .double(let d):
                    return ChartDataPoint(label: "\(index)", value: d)
                case .int(let i):
                    return ChartDataPoint(label: "\(index)", value: Double(i))
                case .object(let obj):
                    let label = obj["label"]?.stringValue ?? obj["x"]?.stringValue ?? "\(index)"
                    let value: Double = {
                        if let v = obj["value"]?.doubleValue { return v }
                        if let v = obj["y"]?.doubleValue { return v }
                        return 0
                    }()
                    return ChartDataPoint(label: label, value: value)
                default:
                    return ChartDataPoint(label: "\(index)", value: 0)
                }
            }
        }
        if case .string(let s) = prop {
            let val = parser.evaluateExpression(s, context: context)
            if case .array(let arr) = val {
                return arr.enumerated().map { index, item in
                    switch item {
                    case .double(let d): return ChartDataPoint(label: "\(index)", value: d)
                    case .int(let i): return ChartDataPoint(label: "\(index)", value: Double(i))
                    default: return ChartDataPoint(label: "\(index)", value: 0)
                    }
                }
            }
        }
        return []
    }

    // MARK: - Style helpers

    func fontForStyle(_ style: String) -> Font {
        switch style {
        case "largeTitle": .largeTitle
        case "title": .title
        case "title2": .title2
        case "title3": .title3
        case "headline": .headline
        case "subheadline": .subheadline
        case "callout": .callout
        case "caption": .caption
        case "caption2": .caption2
        case "footnote": .footnote
        default: .body
        }
    }

    func alignmentForString(_ s: String?) -> TextAlignment {
        switch s {
        case "center": .center
        case "trailing", "right": .trailing
        default: .leading
        }
    }

    func colorForHex(_ hex: String?) -> Color? {
        guard let hex, hex.hasPrefix("#"), hex.count == 7 else { return nil }
        let scanner = Scanner(string: String(hex.dropFirst()))
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else { return nil }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    // Strip potentially dangerous content from skill-provided markdown.
    func sanitizeMarkdown(_ input: String) -> String {
        var result = input
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\]\\(javascript:[^)]*\\)", with: "]()", options: .regularExpression)
        return result
    }
}

// MARK: - Button style modifier

extension View {
    @ViewBuilder
    func buttonStyleForName(_ style: String) -> some View {
        switch style {
        case "bordered": self.buttonStyle(.bordered)
        case "borderedProminent": self.buttonStyle(.borderedProminent)
        case "borderless": self.buttonStyle(.borderless)
        default: self
        }
    }
}

// MARK: - WKWebView wrapper

struct WebViewWrapper: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
