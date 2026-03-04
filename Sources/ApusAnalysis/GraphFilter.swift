import Foundation
import ApusCore

/// Options for filtering a graph snapshot before export.
public struct GraphFilterOptions: Sendable {
    public var targets: [String]
    public var kinds: [NodeKind]
    public var excludeKinds: [NodeKind]
    public var maxNodes: Int?

    public init(
        targets: [String] = [],
        kinds: [NodeKind] = [],
        excludeKinds: [NodeKind] = [],
        maxNodes: Int? = nil
    ) {
        self.targets = targets
        self.kinds = kinds
        self.excludeKinds = excludeKinds
        self.maxNodes = maxNodes
    }
}

/// Filters and simplifies graph snapshots for export.
public enum GraphFilter {

    /// Filter a snapshot by targets, kinds, and exclusions, then apply maxNodes limit.
    public static func filter(_ snapshot: GraphSnapshot, options: GraphFilterOptions) -> GraphSnapshot {
        var nodes = snapshot.allNodes

        // Filter by target
        if !options.targets.isEmpty {
            let targetSet = Set(options.targets)
            nodes = nodes.filter { node in
                if let t = node.targetName { return targetSet.contains(t) }
                // Keep target nodes themselves if they match
                if node.kind == .target { return targetSet.contains(node.name) }
                return false
            }
        }

        // Filter by kinds (include only these)
        if !options.kinds.isEmpty {
            let kindSet = Set(options.kinds)
            nodes = nodes.filter { kindSet.contains($0.kind) }
        }

        // Exclude kinds
        if !options.excludeKinds.isEmpty {
            let excludeSet = Set(options.excludeKinds)
            nodes = nodes.filter { !excludeSet.contains($0.kind) }
        }

        // Build filtered snapshot with only edges between remaining nodes
        let nodeIDs = Set(nodes.map(\.id))
        let edges = snapshot.allEdges.filter { nodeIDs.contains($0.sourceID) && nodeIDs.contains($0.targetID) }

        var result = GraphSnapshot(nodes: nodes, edges: edges)

        // Apply maxNodes via simplification
        if let max = options.maxNodes, result.allNodes.count > max {
            result = simplify(result, maxNodes: max)
        }

        return result
    }

    /// Progressively simplify a snapshot to fit within maxNodes.
    /// Strategy: remove members first, then keep only types, then truncate by connectivity.
    public static func simplify(_ snapshot: GraphSnapshot, maxNodes: Int) -> GraphSnapshot {
        if snapshot.allNodes.count <= maxNodes {
            return snapshot
        }

        // Level 1: Remove member-level nodes (methods, properties, functions, etc.)
        let memberKinds: Set<NodeKind> = [
            .method, .property, .variable, .constructor, .subscript_, .operator_,
            .function, .typeAlias, .associatedType
        ]
        var candidates = snapshot.allNodes.filter { !memberKinds.contains($0.kind) }

        if candidates.count <= maxNodes {
            return buildSnapshot(nodes: candidates, allEdges: snapshot.allEdges)
        }

        // Level 2: Keep only types and targets
        let typeKinds: Set<NodeKind> = [
            .class_, .struct_, .enum_, .protocol_, .actor, .extension_, .target, .module
        ]
        candidates = snapshot.allNodes.filter { typeKinds.contains($0.kind) }

        if candidates.count <= maxNodes {
            return buildSnapshot(nodes: candidates, allEdges: snapshot.allEdges)
        }

        // Level 3: Still too many — keep top N by edge degree (most connected first)
        return topByDegree(nodes: candidates, allEdges: snapshot.allEdges, maxNodes: maxNodes)
    }

    /// Build a snapshot from a node subset, keeping only edges between included nodes.
    private static func buildSnapshot(nodes: [GraphNode], allEdges: [GraphEdge]) -> GraphSnapshot {
        let nodeIDs = Set(nodes.map(\.id))
        let edges = allEdges.filter { nodeIDs.contains($0.sourceID) && nodeIDs.contains($0.targetID) }
        return GraphSnapshot(nodes: nodes, edges: edges)
    }

    /// Keep the top N most-connected nodes by total edge degree.
    private static func topByDegree(nodes: [GraphNode], allEdges: [GraphEdge], maxNodes: Int) -> GraphSnapshot {
        let nodeIDs = Set(nodes.map(\.id))
        // Count degree only for edges between candidate nodes
        var degree: [String: Int] = [:]
        for edge in allEdges where nodeIDs.contains(edge.sourceID) && nodeIDs.contains(edge.targetID) {
            degree[edge.sourceID, default: 0] += 1
            degree[edge.targetID, default: 0] += 1
        }
        let sorted = nodes.sorted { (degree[$0.id] ?? 0) > (degree[$1.id] ?? 0) }
        let kept = Array(sorted.prefix(maxNodes))
        return buildSnapshot(nodes: kept, allEdges: allEdges)
    }
}
