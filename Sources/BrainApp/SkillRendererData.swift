import SwiftUI
import BrainCore
import Charts
import MapKit

// Data/visualization render functions for SkillRenderer.
// Split from SkillRenderer.swift to speed up Swift compilation.
// All functions return AnyView for type erasure to avoid compile timeouts.

extension SkillRenderer {

    func renderStatCard(_ node: ScreenNode) -> AnyView {
        let title = resolveString(node, "title") ?? ""
        let value = resolveString(node, "value") ?? ""
        let suffix = resolveString(node, "suffix")

        return AnyView(
            VStack(alignment: .leading, spacing: BrainTheme.Spacing.xs) {
                Text(title).font(BrainTheme.Typography.caption).foregroundStyle(BrainTheme.Colors.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(.title, design: .rounded)).fontWeight(.bold)
                        .contentTransition(.numericText())
                    if let suffix { Text(suffix).font(BrainTheme.Typography.caption).foregroundStyle(BrainTheme.Colors.textSecondary) }
                }
            }
            .padding(BrainTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BrainTheme.Radius.card))
            .shadow(color: BrainTheme.Shadow.subtle.color, radius: BrainTheme.Shadow.subtle.radius, x: 0, y: 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(value)\(suffix.map { " \($0)" } ?? "")")
        )
    }

    func renderProgress(_ node: ScreenNode) -> AnyView {
        let value = resolveDouble(node, "value") ?? 0
        let total = resolveDouble(node, "total") ?? 1.0
        return AnyView(
            ProgressView(value: value, total: total)
                .accessibilityLabel("Fortschritt: \(Int(value / total * 100))%")
        )
    }

    func renderEmptyState(_ node: ScreenNode) -> AnyView {
        return AnyView(
            VStack(spacing: BrainTheme.Spacing.md) {
                if let icon = resolveString(node, "icon") {
                    Image(systemName: icon)
                        .font(.system(size: 48))
                        .foregroundStyle(BrainTheme.Colors.textTertiary)
                        .symbolEffect(.pulse, options: .speed(0.5))
                }
                if let title = resolveString(node, "title") {
                    Text(title).font(BrainTheme.Typography.headline)
                }
                if let message = resolveString(node, "message") {
                    Text(message).font(BrainTheme.Typography.subheadline).foregroundStyle(BrainTheme.Colors.textSecondary).multilineTextAlignment(.center)
                }
            }
            .padding(BrainTheme.Spacing.xl)
            .accessibilityElement(children: .combine)
        )
    }

    func renderChart(_ node: ScreenNode) -> AnyView {
        let chartType = resolveString(node, "chartType") ?? "line"
        let data = resolveChartData(node)
        let title = resolveString(node, "title")

        return AnyView(
            VStack(alignment: .leading) {
                if let title { Text(title).font(.caption).foregroundStyle(.secondary) }
                Chart(Array(data.enumerated()), id: \.offset) { index, point in
                    switch chartType {
                    case "bar":
                        BarMark(x: .value("Label", point.label), y: .value("Wert", point.value))
                    case "area":
                        AreaMark(x: .value("X", index), y: .value("Wert", point.value))
                    default:
                        LineMark(x: .value("X", index), y: .value("Wert", point.value))
                    }
                }
                .frame(height: 200)
            }
        )
    }

    func renderLineChart(_ node: ScreenNode) -> AnyView {
        let data = resolveChartData(node)
        let title = resolveString(node, "title")
        return AnyView(
            VStack(alignment: .leading) {
                if let title { Text(title).font(.caption).foregroundStyle(.secondary) }
                Chart(Array(data.enumerated()), id: \.offset) { index, point in
                    LineMark(x: .value("X", index), y: .value("Wert", point.value))
                }
                .frame(height: 200)
            }
        )
    }

    func renderBarChart(_ node: ScreenNode) -> AnyView {
        let data = resolveChartData(node)
        let title = resolveString(node, "title")
        return AnyView(
            VStack(alignment: .leading) {
                if let title { Text(title).font(.caption).foregroundStyle(.secondary) }
                Chart(Array(data.enumerated()), id: \.offset) { _, point in
                    BarMark(x: .value("Label", point.label), y: .value("Wert", point.value))
                }
                .frame(height: 200)
            }
        )
    }

    func renderPieChart(_ node: ScreenNode) -> AnyView {
        let data = resolveChartData(node)
        let title = resolveString(node, "title")
        return AnyView(
            VStack(alignment: .leading) {
                if let title { Text(title).font(.caption).foregroundStyle(.secondary) }
                Chart(Array(data.enumerated()), id: \.offset) { _, point in
                    SectorMark(angle: .value(point.label, point.value))
                        .foregroundStyle(by: .value("Kategorie", point.label))
                }
                .frame(height: 200)
            }
        )
    }

    func renderSparkline(_ node: ScreenNode) -> AnyView {
        let data = resolveChartData(node)
        return AnyView(
            Chart(Array(data.enumerated()), id: \.offset) { index, point in
                LineMark(x: .value("X", index), y: .value("Y", point.value))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 30)
        )
    }

    func renderMap(_ node: ScreenNode) -> AnyView {
        let lat = resolveDouble(node, "latitude") ?? 47.3769
        let lon = resolveDouble(node, "longitude") ?? 8.5417
        let span = resolveDouble(node, "span") ?? 0.05
        let height = resolveDouble(node, "height") ?? 200

        return AnyView(
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )))
            .frame(height: CGFloat(height))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }

    func renderCalendarGrid(_ node: ScreenNode) -> AnyView {
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        let days = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

        return AnyView(
            VStack {
                LazyVGrid(columns: columns) {
                    ForEach(days, id: \.self) { day in
                        Text(day).font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(1..<32, id: \.self) { day in
                        Text("\(day)").font(.caption).padding(4)
                    }
                }
            }
        )
    }

    func renderGauge(_ node: ScreenNode) -> AnyView {
        let value = resolveDouble(node, "value") ?? 0
        let min = resolveDouble(node, "min") ?? 0
        let max = resolveDouble(node, "max") ?? 100
        let label = resolveString(node, "label") ?? ""

        return AnyView(
            Gauge(value: value, in: min...max) {
                Text(label)
            } currentValueLabel: {
                Text("\(Int(value))")
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel("\(label): \(Int(value))")
        )
    }

    func renderTimerDisplay(_ node: ScreenNode) -> AnyView {
        let duration = resolveDouble(node, "duration") ?? 0
        let targetDate = Date().addingTimeInterval(duration)
        return AnyView(
            Text(targetDate, style: .timer)
                .font(.system(.title, design: .monospaced))
        )
    }

    func renderCountdown(_ node: ScreenNode) -> AnyView {
        let dateStr = resolveString(node, "target")
        let target: Date = {
            if let s = dateStr {
                let fmt = ISO8601DateFormatter()
                return fmt.date(from: s) ?? Date().addingTimeInterval(3600)
            }
            return Date().addingTimeInterval(3600)
        }()
        return AnyView(
            Text(target, style: .timer)
                .font(.system(.title2, design: .monospaced))
                .monospacedDigit()
        )
    }

    func renderMetric(_ node: ScreenNode) -> AnyView {
        let value = resolveString(node, "value") ?? "0"
        let label = resolveString(node, "label") ?? ""
        let unit = resolveString(node, "unit")

        return AnyView(
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                    if let unit {
                        Text(unit).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !label.isEmpty {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value) \(unit ?? "")")
        )
    }

    func renderHeatMap(_ node: ScreenNode) -> AnyView {
        let cols = resolveDouble(node, "columns").map { Int($0) } ?? 7
        let data = resolveChartData(node)
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: cols)

        return AnyView(
            LazyVGrid(columns: gridColumns, spacing: 2) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                    let intensity = min(1.0, max(0.0, point.value / 100.0))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(0.1 + intensity * 0.9))
                        .frame(height: 16)
                }
            }
        )
    }
}
