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
    /// Strategy: 1) Remove members (keep types/targets), 2) Keep only types, 3) Keep only targets.
    public static func simplify(_ snapshot: GraphSnapshot, maxNodes: Int) -> GraphSnapshot {
        if snapshot.allNodes.count <= maxNodes {
            return snapshot
        }

        // Level 1: Remove member-level nodes (methods, properties, functions, etc.)
        let memberKinds: Set<NodeKind> = [
            .method, .property, .variable, .constructor, .subscript_, .operator_,
            .function, .typeAlias, .associatedType
        ]
        let level1Nodes = snapshot.allNodes.filter { !memberKinds.contains($0.kind) }

        if level1Nodes.count <= maxNodes {
            let nodeIDs = Set(level1Nodes.map(\.id))
            let edges = snapshot.allEdges.filter { nodeIDs.contains($0.sourceID) && nodeIDs.contains($0.targetID) }
            return GraphSnapshot(nodes: level1Nodes, edges: edges)
        }

        // Level 2: Keep only types and targets
        let typeKinds: Set<NodeKind> = [
            .class_, .struct_, .enum_, .protocol_, .actor, .extension_, .target, .module
        ]
        let level2Nodes = snapshot.allNodes.filter { typeKinds.contains($0.kind) }

        if level2Nodes.count <= maxNodes {
            let nodeIDs = Set(level2Nodes.map(\.id))
            let edges = snapshot.allEdges.filter { nodeIDs.contains($0.sourceID) && nodeIDs.contains($0.targetID) }
            return GraphSnapshot(nodes: level2Nodes, edges: edges)
        }

        // Level 3: Keep only targets/modules
        let structuralKinds: Set<NodeKind> = [.target, .module]
        let level3Nodes = snapshot.allNodes.filter { structuralKinds.contains($0.kind) }
        let nodeIDs = Set(level3Nodes.map(\.id))
        let edges = snapshot.allEdges.filter { nodeIDs.contains($0.sourceID) && nodeIDs.contains($0.targetID) }
        return GraphSnapshot(nodes: level3Nodes, edges: edges)
    }
}
