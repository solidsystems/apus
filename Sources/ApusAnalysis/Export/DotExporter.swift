import Foundation
import ApusCore

/// Exports a graph snapshot as Graphviz DOT format.
public struct DotExporter: GraphExporting {
    public var clusterByTarget: Bool

    public init(clusterByTarget: Bool = true) {
        self.clusterByTarget = clusterByTarget
    }

    public func export(snapshot: GraphSnapshot) -> ExportResult {
        var lines: [String] = []
        lines.append("digraph G {")
        lines.append("  rankdir=LR;")
        lines.append("  node [fontname=\"Helvetica\", fontsize=11];")
        lines.append("  edge [fontname=\"Helvetica\", fontsize=9];")
        lines.append("")

        let nodeIDs = Set(snapshot.allNodes.map(\.id))

        if clusterByTarget {
            // Group nodes by target
            var byTarget: [String: [GraphNode]] = [:]
            var noTarget: [GraphNode] = []

            for node in snapshot.allNodes {
                if node.kind == .target { continue } // targets rendered as cluster labels
                if let t = node.targetName {
                    byTarget[t, default: []].append(node)
                } else {
                    noTarget.append(node)
                }
            }

            for (target, nodes) in byTarget.sorted(by: { $0.key < $1.key }) {
                let clusterName = target.replacingOccurrences(of: " ", with: "_")
                lines.append("  subgraph cluster_\(clusterName) {")
                lines.append("    label=\"\(target)\";")
                lines.append("    style=rounded;")
                lines.append("    color=\"#bdc3c7\";")
                for node in nodes {
                    lines.append("    \(nodeDecl(node))")
                }
                lines.append("  }")
                lines.append("")
            }

            for node in noTarget {
                lines.append("  \(nodeDecl(node))")
            }
        } else {
            for node in snapshot.allNodes where node.kind != .target {
                lines.append("  \(nodeDecl(node))")
            }
        }

        lines.append("")

        // Edges
        for edge in snapshot.allEdges {
            guard nodeIDs.contains(edge.sourceID), nodeIDs.contains(edge.targetID) else { continue }
            // Skip edges from/to target nodes (they are clusters)
            if snapshot.nodeByID[edge.sourceID]?.kind == .target { continue }
            if snapshot.nodeByID[edge.targetID]?.kind == .target { continue }
            let style = GraphStyling.dotEdgeStyle(for: edge.kind)
            let label = edge.kind.rawValue
            let attrs = style.isEmpty ? "label=\"\(label)\"" : "\(style), label=\"\(label)\""
            lines.append("  \(dotID(edge.sourceID)) -> \(dotID(edge.targetID)) [\(attrs)];")
        }

        lines.append("}")

        let content = lines.joined(separator: "\n")
        return ExportResult(
            content: content,
            format: .dot,
            nodeCount: snapshot.allNodes.count,
            edgeCount: snapshot.allEdges.count
        )
    }

    private func nodeDecl(_ node: GraphNode) -> String {
        let shape = GraphStyling.dotShape(for: node.kind)
        let color = GraphStyling.color(for: node.accessLevel)
        let label = node.name
        return "\(dotID(node.id)) [label=\"\(label)\", shape=\(shape), style=filled, fillcolor=\"\(color)\"];"
    }

    private func dotID(_ id: String) -> String {
        // Wrap in quotes for DOT safety
        let safe = id
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(safe)\""
    }
}
