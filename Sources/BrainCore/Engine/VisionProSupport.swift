import Foundation

// Phase 12: Vision Pro Support
// Provides visionOS-specific functionality: 3D Knowledge Graph,
// Multi-Window support, and spatial UI adaptations.
//
// Architecture:
// - Uses the same SkillDefinition/ScreenNode model as iPhone/iPad
// - Adds visionOS-specific primitives (3D graph, volumes, ornaments)
// - Multi-Window: each skill can open in its own window
// - RealityKit for 3D Knowledge Graph visualization

// MARK: - Spatial Layout Configuration

/// Describes how a skill should be presented in visionOS.
public enum SpatialPresentation: String, Codable, Sendable {
    case window          // Standard 2D window (default)
    case volume          // 3D volume (for knowledge graph, 3D visualizations)
    case fullSpace       // Immersive space (future: for focus modes)
}

/// Configuration for a skill's spatial presentation.
public struct SpatialConfig: Codable, Sendable {
    public var presentation: SpatialPresentation
    public var defaultSize: WindowSize?
    public var supportsMultiWindow: Bool

    public init(
        presentation: SpatialPresentation = .window,
        defaultSize: WindowSize? = nil,
        supportsMultiWindow: Bool = false
    ) {
        self.presentation = presentation
        self.defaultSize = defaultSize
        self.supportsMultiWindow = supportsMultiWindow
    }
}

public struct WindowSize: Codable, Sendable {
    public var width: Double
    public var height: Double
    public var depth: Double?  // Only for volumes

    public init(width: Double, height: Double, depth: Double? = nil) {
        self.width = width
        self.height = height
        self.depth = depth
    }
}

// MARK: - Knowledge Graph 3D

/// A node in the 3D knowledge graph visualization.
public struct GraphNode3D: Sendable, Identifiable {
    public let id: Int64
    public let title: String
    public let type: String
    public let position: SIMD3<Float>
    public let color: SIMD3<Float>
    public let size: Float

    public init(
        id: Int64,
        title: String,
        type: String,
        position: SIMD3<Float> = .zero,
        color: SIMD3<Float> = SIMD3<Float>(0.3, 0.6, 1.0),
        size: Float = 0.05
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.position = position
        self.color = color
        self.size = size
    }
}

/// An edge connecting two nodes in the 3D graph.
public struct GraphEdge3D: Sendable {
    public let sourceId: Int64
    public let targetId: Int64
    public let relation: String
    public let weight: Float

    public init(sourceId: Int64, targetId: Int64, relation: String, weight: Float = 1.0) {
        self.sourceId = sourceId
        self.targetId = targetId
        self.relation = relation
        self.weight = weight
    }
}

// MARK: - Graph Layout Engine

/// Force-directed layout algorithm for positioning nodes in 3D space.
/// Runs on CPU (not GPU) — sufficient for graphs up to ~1000 nodes.
public struct ForceDirectedLayout: Sendable {

    public let repulsionForce: Float
    public let attractionForce: Float
    public let damping: Float
    public let iterations: Int

    public init(
        repulsionForce: Float = 5.0,
        attractionForce: Float = 0.01,
        damping: Float = 0.9,
        iterations: Int = 100
    ) {
        self.repulsionForce = repulsionForce
        self.attractionForce = attractionForce
        self.damping = damping
        self.iterations = iterations
    }

    /// Compute positions for nodes given edges.
    /// Returns updated nodes with positions set.
    public func layout(nodes: [GraphNode3D], edges: [GraphEdge3D]) -> [GraphNode3D] {
        guard nodes.count > 1 else { return nodes }

        var positions = nodes.map { $0.position }
        var velocities = Array(repeating: SIMD3<Float>.zero, count: nodes.count)

        // Initialize random positions if all at origin
        let allAtOrigin = positions.allSatisfy { $0 == .zero }
        if allAtOrigin {
            for i in positions.indices {
                positions[i] = SIMD3<Float>(
                    Float.random(in: -1...1),
                    Float.random(in: -1...1),
                    Float.random(in: -1...1)
                )
            }
        }

        // Build ID-to-index lookup
        var idToIndex: [Int64: Int] = [:]
        for (i, node) in nodes.enumerated() {
            idToIndex[node.id] = i
        }

        // Force-directed iterations
        for _ in 0..<iterations {
            var forces = Array(repeating: SIMD3<Float>.zero, count: nodes.count)

            // Repulsion between all node pairs (O(n^2) — acceptable for <1000 nodes)
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let delta = positions[i] - positions[j]
                    let dist = max(length(delta), 0.01)
                    let force = normalize(delta) * (repulsionForce / (dist * dist))
                    forces[i] += force
                    forces[j] -= force
                }
            }

            // Attraction along edges
            for edge in edges {
                guard let sourceIdx = idToIndex[edge.sourceId],
                      let targetIdx = idToIndex[edge.targetId] else { continue }

                let delta = positions[targetIdx] - positions[sourceIdx]
                let dist = length(delta)
                guard dist > 0.001 else { continue }
                let force = normalize(delta) * (attractionForce * dist * edge.weight)
                forces[sourceIdx] += force
                forces[targetIdx] -= force
            }

            // Apply forces with damping
            for i in 0..<nodes.count {
                velocities[i] = (velocities[i] + forces[i]) * damping
                // Clamp velocity to prevent numerical explosion
                let speed = length(velocities[i])
                if speed > 2.0 {
                    velocities[i] = normalize(velocities[i]) * 2.0
                }
                positions[i] += velocities[i]
            }
        }

        // Return nodes with updated positions
        return nodes.enumerated().map { (i, node) in
            GraphNode3D(
                id: node.id,
                title: node.title,
                type: node.type,
                position: positions[i],
                color: node.color,
                size: node.size
            )
        }
    }
}

// MARK: - Graph Data Provider

/// Loads graph data from the local database for 3D visualization.
public struct KnowledgeGraphProvider: Sendable {

    private let entryService: EntryService
    private let linkService: LinkService
    private let tagService: TagService

    public init(entryService: EntryService, linkService: LinkService, tagService: TagService) {
        self.entryService = entryService
        self.linkService = linkService
        self.tagService = tagService
    }

    /// Build a 3D graph from entries and their links.
    public func buildGraph(limit: Int = 200) throws -> (nodes: [GraphNode3D], edges: [GraphEdge3D]) {
        let entries = try entryService.list(limit: limit)

        let colorMap: [String: SIMD3<Float>] = [
            "thought": SIMD3<Float>(0.3, 0.6, 1.0),   // Blue
            "task": SIMD3<Float>(1.0, 0.6, 0.2),       // Orange
            "note": SIMD3<Float>(0.4, 0.8, 0.4),       // Green
            "event": SIMD3<Float>(0.8, 0.3, 0.8),      // Purple
            "contact": SIMD3<Float>(1.0, 0.4, 0.4),    // Red
            "bookmark": SIMD3<Float>(0.9, 0.9, 0.3),   // Yellow
        ]

        var nodes: [GraphNode3D] = []
        var edges: [GraphEdge3D] = []

        let entryIds = entries.compactMap(\.id)
        for entry in entries {
            guard let id = entry.id else { continue }
            let color = colorMap[entry.type.rawValue] ?? SIMD3<Float>(0.5, 0.5, 0.5)
            nodes.append(GraphNode3D(
                id: id,
                title: entry.title ?? "Ohne Titel",
                type: entry.type.rawValue,
                color: color
            ))
        }

        // Batch-load all links in a single query (was N+1: one query per entry)
        let allLinks = try linkService.linksForEntries(entryIds)
        let entryIdSet = Set(entryIds)
        for link in allLinks {
            // Only add edge once (from source perspective) and only for loaded entries
            if entryIdSet.contains(link.sourceId) {
                edges.append(GraphEdge3D(
                    sourceId: link.sourceId,
                    targetId: link.targetId,
                    relation: link.relation.rawValue
                ))
            }
        }

        // Apply layout
        let layout = ForceDirectedLayout()
        let positionedNodes = layout.layout(nodes: nodes, edges: edges)

        return (positionedNodes, edges)
    }
}

// MARK: - Multi-Window Manager

/// Tracks open skill windows for visionOS multi-window support.
/// Actor-based to prevent data races on the openWindows dictionary.
public actor MultiWindowManager {

    private var openWindows: [String: WindowInfo] = [:]

    public init() {}

    /// Open a new window for a skill.
    public func openWindow(skillId: String, config: SpatialConfig) {
        openWindows[skillId] = WindowInfo(
            skillId: skillId,
            config: config,
            openedAt: Date()
        )
    }

    /// Close a skill's window.
    public func closeWindow(skillId: String) {
        openWindows.removeValue(forKey: skillId)
    }

    /// All currently active windows.
    public var activeWindows: [WindowInfo] {
        Array(openWindows.values)
    }
}

public struct WindowInfo: Sendable {
    public let skillId: String
    public let config: SpatialConfig
    public let openedAt: Date
}

// MARK: - SIMD Helpers (cross-platform, works on Linux without simd module)

private func length(_ v: SIMD3<Float>) -> Float {
    (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
}

private func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let len = length(v)
    guard len > 0 else { return .zero }
    return v / len
}
