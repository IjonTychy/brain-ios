import SwiftUI
import BrainCore

// Content render functions for SkillRenderer.
// Split from SkillRenderer.swift to speed up Swift compilation.
// All functions return AnyView for type erasure to avoid compile timeouts.

extension SkillRenderer {

    func renderText(_ node: ScreenNode) -> AnyView {
        let value = resolveString(node, "value") ?? ""
        let style = resolveString(node, "style") ?? "body"

        return AnyView(
            Text(value)
                .font(fontForStyle(style))
                .foregroundStyle(colorForHex(resolveString(node, "color")) ?? BrainTheme.Colors.textPrimary)
                .multilineTextAlignment(alignmentForString(resolveString(node, "alignment")))
                .accessibilityLabel(value)
        )
    }

    func renderImage(_ node: ScreenNode) -> AnyView {
        let source = resolveString(node, "source") ?? ""
        let width = resolveDouble(node, "width").map { CGFloat($0) }
        let height = resolveDouble(node, "height").map { CGFloat($0) }

        if source.hasPrefix("https://") {
            return AnyView(
                AsyncImage(url: URL(string: source)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: width, height: height)
                .accessibilityLabel(resolveString(node, "alt") ?? "Bild")
            )
        } else if source.hasPrefix("http://") {
            return AnyView(
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Unsicheres Bild blockiert")
            )
        } else {
            return AnyView(
                Image(systemName: source)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: height)
                    .accessibilityLabel(resolveString(node, "alt") ?? source)
            )
        }
    }

    func renderAvatar(_ node: ScreenNode) -> AnyView {
        let size = resolveDouble(node, "size") ?? 40
        let initials = resolveString(node, "initials") ?? "?"

        if let source = resolveString(node, "source"), source.hasPrefix("https://") {
            return AnyView(
                AsyncImage(url: URL(string: source)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    avatarPlaceholder(initials: initials, size: size)
                }
                .frame(width: CGFloat(size), height: CGFloat(size))
                .clipShape(Circle())
                .accessibilityLabel("Avatar \(initials)")
            )
        } else {
            return AnyView(
                avatarPlaceholder(initials: initials, size: size)
                    .accessibilityLabel("Avatar \(initials)")
            )
        }
    }

    func avatarPlaceholder(initials: String, size: Double) -> some View {
        ZStack {
            Circle()
                .fill(BrainTheme.Colors.brandPurple.opacity(0.15))
            Text(initials)
                .font(.system(size: CGFloat(size) * 0.4))
                .fontWeight(.medium)
                .foregroundStyle(BrainTheme.Colors.brandPurple)
        }
        .frame(width: CGFloat(size), height: CGFloat(size))
    }

    func renderIcon(_ node: ScreenNode) -> AnyView {
        let name = resolveString(node, "name") ?? "questionmark"
        let size = resolveDouble(node, "size") ?? 24
        return AnyView(
            Image(systemName: name)
                .font(.system(size: CGFloat(size)))
                .foregroundStyle(colorForHex(resolveString(node, "color")) ?? BrainTheme.Colors.brandBlue)
                .accessibilityLabel(name)
        )
    }

    func renderBadge(_ node: ScreenNode) -> AnyView {
        let value = resolveString(node, "value") ?? resolveString(node, "text") ?? ""
        let color = colorForHex(resolveString(node, "color")) ?? BrainTheme.Colors.brandPurple
        return AnyView(
            Text(value)
                .font(.caption2).fontWeight(.medium)
                .padding(.horizontal, BrainTheme.Spacing.sm).padding(.vertical, BrainTheme.Spacing.xs)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(Capsule())
                .accessibilityLabel(value)
        )
    }

    func renderMarkdown(_ node: ScreenNode) -> AnyView {
        let value = resolveString(node, "value") ?? ""
        let sanitized = sanitizeMarkdown(value)
        if let attributed = try? AttributedString(markdown: sanitized) {
            return AnyView(Text(attributed))
        } else {
            return AnyView(Text(sanitized))
        }
    }

    func renderLabel(_ node: ScreenNode) -> AnyView {
        let title = resolveString(node, "title") ?? ""
        let icon = resolveString(node, "icon") ?? "circle"
        return AnyView(
            Label(title, systemImage: icon)
                .accessibilityLabel(title)
        )
    }

    func renderAsyncImage(_ node: ScreenNode) -> AnyView {
        let urlStr = resolveString(node, "url") ?? ""
        let width = resolveDouble(node, "width").map { CGFloat($0) }
        let height = resolveDouble(node, "height").map { CGFloat($0) }

        if urlStr.hasPrefix("https://"), let url = URL(string: urlStr) {
            return AnyView(
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .failure:
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    @unknown default:
                        ProgressView()
                    }
                }
                .frame(width: width, height: height)
                .accessibilityLabel(resolveString(node, "alt") ?? "Bild")
            )
        } else {
            return AnyView(
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            )
        }
    }

    func renderDateText(_ node: ScreenNode) -> AnyView {
        let style = resolveString(node, "style") ?? "relative"
        let dateStr = resolveString(node, "date")
        let date: Date = {
            if let s = dateStr {
                let fmt = ISO8601DateFormatter()
                return fmt.date(from: s) ?? Date()
            }
            return Date()
        }()

        switch style {
        case "timer": return AnyView(Text(date, style: .timer))
        case "offset": return AnyView(Text(date, style: .offset))
        case "date": return AnyView(Text(date, style: .date))
        case "time": return AnyView(Text(date, style: .time))
        default: return AnyView(Text(date, style: .relative))
        }
    }

    func renderColorSwatch(_ node: ScreenNode) -> AnyView {
        let color = colorForHex(resolveString(node, "color")) ?? .blue
        let size = resolveDouble(node, "size") ?? 32
        return AnyView(
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: CGFloat(size), height: CGFloat(size))
                .accessibilityLabel(resolveString(node, "color") ?? "Farbe")
        )
    }
}
