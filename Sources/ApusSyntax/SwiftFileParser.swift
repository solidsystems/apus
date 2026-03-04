import Foundation
import SwiftParser
import SwiftSyntax
import ApusCore

/// Result of parsing a single Swift file.
public struct FileParseResult: Sendable {
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]
    public let imports: [String]
}

/// Parses a single Swift source file into graph nodes and edges.
public struct SwiftFileParser: Sendable {

    public init() {}

    /// Parse source code from a string, using the given file path for IDs.
    public func parse(source: String, filePath: String) -> FileParseResult {
        let tree = Parser.parse(source: source)
        return extractGraph(from: tree, filePath: filePath)
    }

    /// Parse a file on disk.
    public func parse(fileAt path: String) throws -> FileParseResult {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        return parse(source: source, filePath: path)
    }

    // MARK: - Internal

    func extractGraph(from tree: SourceFileSyntax, filePath: String) -> FileParseResult {
        // Run visitors
        let declVisitor = DeclarationVisitor(viewMode: .sourceAccurate)
        declVisitor.walk(tree)

        let importVisitor = ImportVisitor(viewMode: .sourceAccurate)
        importVisitor.walk(tree)

        // Build file node
        let fileName = (filePath as NSString).lastPathComponent
        let fileNodeID = "file:\(filePath)"
        let fileNode = GraphNode(
            id: fileNodeID,
            kind: .file,
            name: fileName,
            qualifiedName: filePath,
            filePath: filePath
        )

        var nodes: [GraphNode] = [fileNode]
        var edges: [GraphEdge] = []

        // Convert declarations to nodes/edges
        for decl in declVisitor.declarations {
            let qualifiedName = buildQualifiedName(decl: decl)
            let nodeID = "\(filePath):\(decl.line):\(decl.name)"

            let node = GraphNode(
                id: nodeID,
                kind: decl.kind,
                name: decl.name,
                qualifiedName: qualifiedName,
                filePath: filePath,
                line: decl.line,
                accessLevel: decl.accessLevel,
                docComment: decl.docComment,
                attributes: decl.attributes
            )
            nodes.append(node)

            // Containment: file contains top-level decls, parent contains nested decls
            if decl.parentPath.isEmpty {
                edges.append(GraphEdge(
                    sourceID: fileNodeID,
                    targetID: nodeID,
                    kind: .contains
                ))
            }

            // Conformance/inheritance edges (stored as string references)
            for conformance in decl.conformances {
                edges.append(GraphEdge(
                    sourceID: nodeID,
                    targetID: "ref:\(conformance)",
                    kind: .conformsTo,
                    metadata: ["targetName": conformance]
                ))
            }

            // Extension target edge
            if let extendedType = decl.extendedType {
                edges.append(GraphEdge(
                    sourceID: nodeID,
                    targetID: "ref:\(extendedType)",
                    kind: .extends,
                    metadata: ["targetName": extendedType]
                ))
            }
        }

        // Build parent-child containment edges between declarations
        buildContainmentEdges(declarations: declVisitor.declarations, filePath: filePath, edges: &edges)

        return FileParseResult(
            nodes: nodes,
            edges: edges,
            imports: importVisitor.imports
        )
    }

    private func buildQualifiedName(decl: ExtractedDeclaration) -> String {
        if decl.parentPath.isEmpty {
            return decl.name
        }
        return (decl.parentPath + [decl.name]).joined(separator: ".")
    }

    private func buildContainmentEdges(
        declarations: [ExtractedDeclaration],
        filePath: String,
        edges: inout [GraphEdge]
    ) {
        // For each declaration with a non-empty parent path, find its immediate parent
        // and create a containment edge.
        var parentMap: [String: String] = [:] // qualifiedName -> nodeID

        for decl in declarations {
            let qualifiedName = buildQualifiedName(decl: decl)
            let nodeID = "\(filePath):\(decl.line):\(decl.name)"
            parentMap[qualifiedName] = nodeID
        }

        for decl in declarations {
            guard !decl.parentPath.isEmpty else { continue }
            let nodeID = "\(filePath):\(decl.line):\(decl.name)"
            let parentQualifiedName = decl.parentPath.joined(separator: ".")
            if let parentNodeID = parentMap[parentQualifiedName] {
                edges.append(GraphEdge(
                    sourceID: parentNodeID,
                    targetID: nodeID,
                    kind: .contains
                ))
            }
        }
    }
}
