import Foundation
import Testing
@testable import BrainCore

@Suite("Vision Pro Support")
struct VisionProTests {

    // MARK: - Spatial Config

    @Test("SpatialConfig Default-Werte")
    func spatialConfigDefaults() {
        let config = SpatialConfig()
        #expect(config.presentation == .window)
        #expect(config.defaultSize == nil)
        #expect(config.supportsMultiWindow == false)
    }

    @Test("SpatialConfig Volume mit Groesse")
    func spatialConfigVolume() {
        let config = SpatialConfig(
            presentation: .volume,
            defaultSize: WindowSize(width: 1.0, height: 0.8, depth: 0.6),
            supportsMultiWindow: true
        )
        #expect(config.presentation == .volume)
        #expect(config.defaultSize?.depth == 0.6)
        #expect(config.supportsMultiWindow == true)
    }

    @Test("SpatialPresentation Codable")
    func spatialPresentationCodable() throws {
        let original = SpatialPresentation.volume
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpatialPresentation.self, from: data)
        #expect(decoded == .volume)
    }

    // MARK: - Graph Nodes

    @Test("GraphNode3D erstellen")
    func graphNodeCreation() {
        let node = GraphNode3D(
            id: 42,
            title: "Test Entry",
            type: "thought"
        )
        #expect(node.id == 42)
        #expect(node.title == "Test Entry")
        #expect(node.position == .zero)
        #expect(node.size == 0.05)
    }

    @Test("GraphEdge3D erstellen")
    func graphEdgeCreation() {
        let edge = GraphEdge3D(
            sourceId: 1,
            targetId: 2,
            relation: "related"
        )
        #expect(edge.sourceId == 1)
        #expect(edge.targetId == 2)
        #expect(edge.weight == 1.0)
    }

    // MARK: - Force-Directed Layout

    @Test("Layout mit einem Node gibt Position unveraendert zurueck")
    func layoutSingleNode() {
        let layout = ForceDirectedLayout(iterations: 10)
        let nodes = [GraphNode3D(id: 1, title: "Single", type: "thought")]
        let result = layout.layout(nodes: nodes, edges: [])
        #expect(result.count == 1)
    }

    @Test("Layout positioniert Nodes nicht alle am Ursprung")
    func layoutSpreadsNodes() {
        let layout = ForceDirectedLayout(iterations: 50)
        let nodes = [
            GraphNode3D(id: 1, title: "A", type: "thought"),
            GraphNode3D(id: 2, title: "B", type: "thought"),
            GraphNode3D(id: 3, title: "C", type: "thought"),
        ]
        let edges = [
            GraphEdge3D(sourceId: 1, targetId: 2, relation: "related"),
            GraphEdge3D(sourceId: 2, targetId: 3, relation: "related"),
        ]

        let result = layout.layout(nodes: nodes, edges: edges)
        #expect(result.count == 3)

        // Nodes should not all be at the same position
        let positions = Set(result.map { "\($0.position.x),\($0.position.y),\($0.position.z)" })
        #expect(positions.count == 3)
    }

    @Test("Layout mit verbundenen Nodes veraendert Positionen")
    func layoutAttractsConnected() {
        let layout = ForceDirectedLayout(
            repulsionForce: 0.1,
            attractionForce: 0.01,
            damping: 0.5,
            iterations: 20
        )

        let nodes = [
            GraphNode3D(id: 1, title: "A", type: "thought",
                       position: SIMD3<Float>(-1, 0, 0)),
            GraphNode3D(id: 2, title: "B", type: "thought",
                       position: SIMD3<Float>(1, 0, 0)),
            GraphNode3D(id: 3, title: "C", type: "thought",
                       position: SIMD3<Float>(0, 1, 0)),
        ]
        let edges = [
            GraphEdge3D(sourceId: 1, targetId: 2, relation: "related"),
            GraphEdge3D(sourceId: 2, targetId: 3, relation: "related"),
        ]

        let result = layout.layout(nodes: nodes, edges: edges)
        // Layout should produce valid (non-NaN) positions
        for node in result {
            #expect(!node.position.x.isNaN)
            #expect(!node.position.y.isNaN)
            #expect(!node.position.z.isNaN)
        }
        // Positions should have changed from initial
        #expect(result[0].position != SIMD3<Float>(-1, 0, 0))
    }

    @Test("Layout erhaelt Node-Metadaten")
    func layoutPreservesMetadata() {
        let layout = ForceDirectedLayout(iterations: 10)
        let nodes = [
            GraphNode3D(id: 99, title: "Wichtig", type: "task",
                       color: SIMD3<Float>(1, 0, 0), size: 0.1),
            GraphNode3D(id: 100, title: "Normal", type: "thought"),
        ]

        let result = layout.layout(nodes: nodes, edges: [])
        #expect(result[0].id == 99)
        #expect(result[0].title == "Wichtig")
        #expect(result[0].type == "task")
        #expect(result[0].color == SIMD3<Float>(1, 0, 0))
        #expect(result[0].size == 0.1)
    }

}
