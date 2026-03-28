import SwiftUI
import BrainCore

// E4: Visual Knowledge Graph — 2D force-directed graph of entries and their links.
// Uses the existing KnowledgeGraphProvider and ForceDirectedLayout from BrainCore.
// Replaces the Map tab placeholder with a more useful visualization.
struct KnowledgeGraphView: View {
    @Environment(DataBridge.self) private var dataBridge

    @State private var nodes: [GraphNode2D] = []
    @State private var edges: [GraphEdge2D] = []
    @State private var selectedNode: GraphNode2D?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var searchText = ""

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Lade Wissensnetz...")
            } else if nodes.isEmpty {
                ContentUnavailableView(
                    "Noch kein Wissensnetz",
                    systemImage: "circle.hexagongrid",
                    description: Text("Erstelle Einträge und verlinke sie, um dein Wissensnetz zu sehen.")
                )
            } else {
                graphCanvas
            }
        }
        .navigationTitle("Wissensnetz")
        .searchable(text: $searchText, prompt: "Knoten suchen...")
        .task { await loadGraph() }
        .sheet(item: $selectedNode) { node in
            nodeDetailSheet(node)
        }
    }

    // MARK: - Graph Canvas

    private var graphCanvas: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            Canvas { context, size in
                let transform = CGAffineTransform(translationX: offset.width + center.x,
                                                   y: offset.height + center.y)
                    .scaledBy(x: scale, y: scale)

                // Draw edges
                for edge in edges {
                    guard let source = nodes.first(where: { $0.id == edge.sourceId }),
                          let target = nodes.first(where: { $0.id == edge.targetId })
                    else { continue }

                    let from = CGPoint(x: source.x, y: source.y).applying(transform)
                    let to = CGPoint(x: target.x, y: target.y).applying(transform)

                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)
                    context.stroke(path, with: .color(Color.gray.opacity(0.2)), lineWidth: 0.5)
                }

                // Draw nodes
                for node in filteredNodes {
                    let point = CGPoint(x: node.x, y: node.y).applying(transform)
                    let radius = max(6, CGFloat(node.size) * 15) * scale

                    let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                      width: radius * 2, height: radius * 2)
                    context.fill(Circle().path(in: rect), with: .color(node.color))

                    // Label
                    if scale > 0.6 {
                        let labelPoint = CGPoint(x: point.x, y: point.y + radius + 8)
                        context.draw(Text(node.title).font(.caption2).foregroundStyle(.primary),
                                     at: labelPoint)
                    }
                }
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = max(0.2, min(5.0, lastScale * value.magnification))
                    }
                    .onEnded { value in
                        lastScale = scale
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture { location in
                handleTap(at: location, center: center)
            }
        }
    }

    // MARK: - Node Detail

    private func nodeDetailSheet(_ node: GraphNode2D) -> some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("Typ", value: node.type)
                    LabeledContent("Titel", value: node.title)
                }
                Section("Verbindungen") {
                    let connected = edges.filter { $0.sourceId == node.id || $0.targetId == node.id }
                    if connected.isEmpty {
                        Text("Keine Verbindungen").foregroundStyle(.secondary)
                    } else {
                        ForEach(connected, id: \.id) { edge in
                            let otherId = edge.sourceId == node.id ? edge.targetId : edge.sourceId
                            if let other = nodes.first(where: { $0.id == otherId }) {
                                Label(other.title, systemImage: "link")
                            }
                        }
                    }
                }
            }
            .navigationTitle(node.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { selectedNode = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Data Loading

    private func loadGraph() async {
        isLoading = true
        do {
            let provider = KnowledgeGraphProvider(
                entryService: EntryService(pool: dataBridge.db.pool),
                linkService: LinkService(pool: dataBridge.db.pool),
                tagService: TagService(pool: dataBridge.db.pool)
            )
            let (nodes3d, edges3d) = try provider.buildGraph(limit: 200)

            // Convert 3D positions to 2D (project onto XY plane, scale up)
            let scaleFactor: Float = 300
            self.nodes = nodes3d.map { n in
                GraphNode2D(
                    id: n.id,
                    title: n.title,
                    type: n.type,
                    x: CGFloat(n.position.x * scaleFactor),
                    y: CGFloat(n.position.y * scaleFactor),
                    color: Color(
                        red: Double(n.color.x),
                        green: Double(n.color.y),
                        blue: Double(n.color.z)
                    ),
                    size: n.size
                )
            }
            self.edges = edges3d.map { e in
                GraphEdge2D(sourceId: e.sourceId, targetId: e.targetId, relation: e.relation)
            }
            // Auto-fit: calculate scale so all nodes are visible
            if !self.nodes.isEmpty {
                let maxExtent = self.nodes.reduce(CGFloat(0)) { result, node in
                    max(result, abs(node.x), abs(node.y))
                }
                if maxExtent > 0 {
                    // Fit within ~80% of a typical screen half-width (~160pt)
                    let fitScale = 160 / maxExtent
                    self.scale = max(0.2, min(2.0, fitScale))
                    self.lastScale = self.scale
                }
            }
        } catch {
            // Silently fail — show empty state
        }
        isLoading = false
    }

    // MARK: - Filtering

    private var filteredNodes: [GraphNode2D] {
        guard !searchText.isEmpty else { return nodes }
        return nodes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint, center: CGPoint) {
        let adjustedX = (location.x - offset.width - center.x) / scale
        let adjustedY = (location.y - offset.height - center.y) / scale

        let hitRadius: CGFloat = 20
        if let tapped = nodes.first(where: { node in
            let dx = CGFloat(node.x) - adjustedX
            let dy = CGFloat(node.y) - adjustedY
            return sqrt(dx*dx + dy*dy) < hitRadius
        }) {
            selectedNode = tapped
        }
    }
}

// MARK: - 2D Graph Models

struct GraphNode2D: Identifiable {
    let id: Int64
    let title: String
    let type: String
    let x: CGFloat
    let y: CGFloat
    let color: Color
    let size: Float
}

struct GraphEdge2D: Identifiable {
    let id = UUID()
    let sourceId: Int64
    let targetId: Int64
    let relation: String
}
