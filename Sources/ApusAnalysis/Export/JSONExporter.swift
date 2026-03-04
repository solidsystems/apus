import Foundation
import ApusCore

/// Exports a graph snapshot as JSON (standard or Cytoscape format).
public struct JSONExporter: GraphExporting {
    public var prettyPrint: Bool
    public var cytoscapeFormat: Bool

    public init(prettyPrint: Bool = true, cytoscapeFormat: Bool = false) {
        self.prettyPrint = prettyPrint
        self.cytoscapeFormat = cytoscapeFormat
    }

    public func export(snapshot: GraphSnapshot) -> ExportResult {
        let content: String
        if cytoscapeFormat {
            content = exportCytoscape(snapshot: snapshot)
        } else {
            content = exportStandard(snapshot: snapshot)
        }
        return ExportResult(
            content: content,
            format: .json,
            nodeCount: snapshot.allNodes.count,
            edgeCount: snapshot.allEdges.count
        )
    }

    // MARK: - Standard Format

    private func exportStandard(snapshot: GraphSnapshot) -> String {
        let exportNodes = snapshot.allNodes.map { node -> ExportNode in
            let inDegree = snapshot.incoming[node.id]?.count ?? 0
            let outDegree = snapshot.outgoing[node.id]?.count ?? 0
            return ExportNode(
                id: node.id,
                name: node.name,
                qualifiedName: node.qualifiedName,
                kind: node.kind.rawValue,
                accessLevel: node.accessLevel?.displayName,
                targetName: node.targetName,
                filePath: node.filePath,
                line: node.line,
                inDegree: inDegree,
                outDegree: outDegree
            )
        }

        let exportEdges = snapshot.allEdges.map { edge -> ExportEdge in
            ExportEdge(
                source: edge.sourceID,
                target: edge.targetID,
                kind: edge.kind.rawValue
            )
        }

        let doc = ExportDocument(
            metadata: ExportMetadata(
                nodeCount: snapshot.allNodes.count,
                edgeCount: snapshot.allEdges.count,
                exportedAt: ISO8601DateFormatter().string(from: Date())
            ),
            nodes: exportNodes,
            edges: exportEdges
        )

        return encode(doc)
    }

    // MARK: - Cytoscape Format

    private func exportCytoscape(snapshot: GraphSnapshot) -> String {
        let cyNodes = snapshot.allNodes.map { node -> CytoscapeElement in
            CytoscapeElement(data: CytoscapeData(
                id: node.id,
                label: node.name,
                kind: node.kind.rawValue,
                accessLevel: node.accessLevel?.displayName,
                targetName: node.targetName,
                shape: GraphStyling.cytoscapeShape(for: node.kind),
                color: GraphStyling.color(for: node.accessLevel),
                source: nil,
                target: nil
            ))
        }

        let cyEdges = snapshot.allEdges.map { edge -> CytoscapeElement in
            CytoscapeElement(data: CytoscapeData(
                id: "\(edge.sourceID)-\(edge.kind.rawValue)-\(edge.targetID)",
                label: edge.kind.rawValue,
                kind: edge.kind.rawValue,
                accessLevel: nil,
                targetName: nil,
                shape: nil,
                color: nil,
                source: edge.sourceID,
                target: edge.targetID
            ))
        }

        let doc = CytoscapeDocument(
            elements: CytoscapeElements(nodes: cyNodes, edges: cyEdges)
        )

        return encode(doc)
    }

    // MARK: - Encoding

    private func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

// MARK: - Codable Wrappers

struct ExportMetadata: Codable, Sendable {
    let nodeCount: Int
    let edgeCount: Int
    let exportedAt: String
}

struct ExportNode: Codable, Sendable {
    let id: String
    let name: String
    let qualifiedName: String
    let kind: String
    let accessLevel: String?
    let targetName: String?
    let filePath: String?
    let line: Int?
    let inDegree: Int
    let outDegree: Int
}

struct ExportEdge: Codable, Sendable {
    let source: String
    let target: String
    let kind: String
}

struct ExportDocument: Codable, Sendable {
    let metadata: ExportMetadata
    let nodes: [ExportNode]
    let edges: [ExportEdge]
}

struct CytoscapeData: Codable, Sendable {
    let id: String
    let label: String?
    let kind: String?
    let accessLevel: String?
    let targetName: String?
    let shape: String?
    let color: String?
    let source: String?
    let target: String?
}

struct CytoscapeElement: Codable, Sendable {
    let data: CytoscapeData
}

struct CytoscapeElements: Codable, Sendable {
    let nodes: [CytoscapeElement]
    let edges: [CytoscapeElement]
}

struct CytoscapeDocument: Codable, Sendable {
    let elements: CytoscapeElements
}
