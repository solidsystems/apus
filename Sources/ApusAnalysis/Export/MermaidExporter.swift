import Foundation
import ApusCore

/// Exports a graph snapshot as Mermaid diagram format.
public struct MermaidExporter: GraphExporting {
    public var maxNodes: Int
    public var direction: String

    public init(maxNodes: Int = 200, direction: String = "TD") {
        self.maxNodes = maxNodes
        self.direction = direction
    }

    public func export(snapshot: GraphSnapshot) -> ExportResult {
        var workingSnapshot = snapshot
        var simplified = false

        if workingSnapshot.allNodes.count > maxNodes {
            workingSnapshot = GraphFilter.simplify(workingSnapshot, maxNodes: maxNodes)
            simplified = true
            if workingSnapshot.allNodes.count != snapshot.allNodes.count {
                FileHandle.standardError.write(
                    Data("Warning: Graph simplified from \(snapshot.allNodes.count) to \(workingSnapshot.allNodes.count) nodes for Mermaid export.\n".utf8)
                )
            }
        }

        // Build ID mapping (Mermaid needs simple alphanumeric IDs)
        var idMap: [String: String] = [:]
        for (i, node) in workingSnapshot.allNodes.enumerated() {
            idMap[node.id] = "n\(i)"
        }

        var lines: [String] = []
        lines.append("flowchart \(direction)")
        lines.append("")

        // Group by target using subgraphs
        var byTarget: [String: [GraphNode]] = [:]
        var noTarget: [GraphNode] = []

        for node in workingSnapshot.allNodes {
            if node.kind == .target { continue }
            if let t = node.targetName {
                byTarget[t, default: []].append(node)
            } else {
                noTarget.append(node)
            }
        }

        for (target, nodes) in byTarget.sorted(by: { $0.key < $1.key }) {
            lines.append("  subgraph \(mermaidSafeLabel(target))")
            for node in nodes {
                guard let mid = idMap[node.id] else { continue }
                let shape = GraphStyling.mermaidShape(for: node.kind, label: node.name)
                lines.append("    \(mid)\(shape)")
            }
            lines.append("  end")
            lines.append("")
        }

        for node in noTarget {
            guard let mid = idMap[node.id] else { continue }
            let shape = GraphStyling.mermaidShape(for: node.kind, label: node.name)
            lines.append("  \(mid)\(shape)")
        }

        lines.append("")

        // Edges
        for edge in workingSnapshot.allEdges {
            guard let srcID = idMap[edge.sourceID],
                  let dstID = idMap[edge.targetID] else { continue }
            if workingSnapshot.nodeByID[edge.sourceID]?.kind == .target { continue }
            if workingSnapshot.nodeByID[edge.targetID]?.kind == .target { continue }
            let arrow = GraphStyling.mermaidArrow(for: edge.kind)
            let label = edge.kind.rawValue
            lines.append("  \(srcID) \(arrow)|\(label)| \(dstID)")
        }

        lines.append("")

        // Style classes for access levels
        let accessColors: [(AccessLevel, String)] = [
            (.open, "fill:#2ecc71,stroke:#27ae60,color:#fff"),
            (.public_, "fill:#3498db,stroke:#2980b9,color:#fff"),
            (.package_, "fill:#9b59b6,stroke:#8e44ad,color:#fff"),
            (.internal_, "fill:#95a5a6,stroke:#7f8c8d,color:#fff"),
            (.fileprivate_, "fill:#e67e22,stroke:#d35400,color:#fff"),
            (.private_, "fill:#e74c3c,stroke:#c0392b,color:#fff"),
        ]

        for (access, style) in accessColors {
            let className = "access_\(access.displayName)"
            lines.append("  classDef \(className) \(style)")

            let nodeIDs = workingSnapshot.allNodes
                .filter { $0.accessLevel == access }
                .compactMap { idMap[$0.id] }
            if !nodeIDs.isEmpty {
                lines.append("  class \(nodeIDs.joined(separator: ",")) \(className)")
            }
        }

        let content = lines.joined(separator: "\n")
        return ExportResult(
            content: content,
            format: .mermaid,
            nodeCount: workingSnapshot.allNodes.count,
            edgeCount: workingSnapshot.allEdges.count,
            wasSimplified: simplified
        )
    }

    private func mermaidSafeLabel(_ label: String) -> String {
        // Mermaid subgraph names: alphanumeric + underscores
        label.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}
