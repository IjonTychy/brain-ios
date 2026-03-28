import SwiftUI
import MapKit
import BrainCore
import GRDB

// Map view showing geo-tagged entries on a MapKit map.
// Entries store location in sourceMeta as JSON: {"latitude": 47.3, "longitude": 8.5}
// TODO: Phase 2 — Geocode contact postal addresses and show as pins
struct EntryMapView: View {
    @Environment(DataBridge.self) private var dataBridge
    @State private var annotations: [EntryAnnotation] = []
    @State private var selectedAnnotation: EntryAnnotation?
    @State private var position: MapCameraPosition = .automatic
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Lade Karte...")
            } else if annotations.isEmpty {
                ContentUnavailableView(
                    "Keine Orte",
                    systemImage: "map",
                    description: Text("Es gibt noch keine Einträge mit Standort-Daten.\nBrain kann beim Erfassen automatisch den Standort speichern.")
                )
            } else {
                Map(position: $position, selection: $selectedAnnotation) {
                    ForEach(annotations) { annotation in
                        Marker(
                            annotation.title,
                            systemImage: annotation.icon,
                            coordinate: annotation.coordinate
                        )
                        .tint(annotation.color)
                        .tag(annotation)
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }

                // Entry count badge
                VStack {
                    HStack {
                        Label("\(annotations.count) Orte", systemImage: "mappin.circle.fill")
                            .font(BrainTheme.Typography.caption)
                            .padding(.horizontal, BrainTheme.Spacing.md)
                            .padding(.vertical, BrainTheme.Spacing.sm)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }
            }
        }
        .navigationTitle("Karte")
        .sheet(item: $selectedAnnotation) { annotation in
            NavigationStack {
                EntryMapDetailSheet(annotation: annotation)
                    .navigationTitle(annotation.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fertig") { selectedAnnotation = nil }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .onAppear { loadGeoEntries() }
        .refreshable { loadGeoEntries() }
    }

    // MARK: - Data loading

    private func loadGeoEntries() {
        isLoading = true
        defer { isLoading = false }

        do {
            let pool = dataBridge.db.pool
            let entries = try pool.read { db in
                try Entry.fetchAll(db, sql: """
                    SELECT * FROM entries
                    WHERE deletedAt IS NULL
                    AND sourceMeta IS NOT NULL
                    AND sourceMeta LIKE '%latitude%'
                    ORDER BY createdAt DESC
                    LIMIT 500
                """)
            }

            annotations = entries.compactMap { entry -> EntryAnnotation? in
                guard let meta = entry.sourceMeta,
                      let data = meta.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let lat = json["latitude"] as? Double,
                      let lon = json["longitude"] as? Double else { return nil }

                return EntryAnnotation(
                    entryId: entry.id ?? 0,
                    title: entry.title ?? "Ohne Titel",
                    body: entry.body,
                    type: entry.type,
                    status: entry.status,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    createdAt: entry.createdAt
                )
            }
        } catch {
            annotations = []
        }
    }
}

// MARK: - Detail sheet

private struct EntryMapDetailSheet: View {
    let annotation: EntryAnnotation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: annotation.icon)
                    .foregroundStyle(annotation.color)
                Text(annotation.typeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let dateStr = annotation.createdAt {
                    Text(formatDate(dateStr))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let body = annotation.body, !body.isEmpty {
                Text(body)
                    .font(.body)
                    .lineLimit(10)
            }

            HStack {
                Image(systemName: "location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.4f, %.4f", annotation.coordinate.latitude, annotation.coordinate.longitude))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private static let dbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func formatDate(_ dateStr: String) -> String {
        guard let date = Self.dbDateFormatter.date(from: dateStr) else { return dateStr }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_CH")
        fmt.dateFormat = "d. MMM yyyy, HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - Annotation model

struct EntryAnnotation: Identifiable, Hashable {
    let id = UUID()
    let entryId: Int64
    let title: String
    let body: String?
    let type: EntryType
    let status: EntryStatus
    let coordinate: CLLocationCoordinate2D
    let createdAt: String?

    var icon: String { type.icon }

    var color: Color { type.color }

    var typeName: String { type.label }

    // Hashable conformance for CLLocationCoordinate2D
    static func == (lhs: EntryAnnotation, rhs: EntryAnnotation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
