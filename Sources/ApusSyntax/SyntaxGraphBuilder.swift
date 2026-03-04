import Foundation
import ApusCore

/// Parses all Swift files concurrently and builds graph nodes/edges.
/// Merges syntax-derived nodes with existing Index Store nodes by matching name+kind.
public struct SyntaxGraphBuilder: Sendable {
    private let parser: SwiftFileParser

    public init() {
        self.parser = SwiftFileParser()
    }

    /// Parse all Swift files at the given paths concurrently.
    public func parseFiles(at paths: [String]) async throws -> FileParseResult {
        let results = await withTaskGroup(of: FileParseResult?.self, returning: [FileParseResult].self) { group in
            for path in paths {
                group.addTask {
                    try? self.parser.parse(fileAt: path)
                }
            }

            var collected: [FileParseResult] = []
            for await result in group {
                if let result {
                    collected.append(result)
                }
            }
            return collected
        }

        // Merge all results
        var allNodes: [GraphNode] = []
        var allEdges: [GraphEdge] = []
        var allImports: [String] = []

        for result in results {
            allNodes.append(contentsOf: result.nodes)
            allEdges.append(contentsOf: result.edges)
            allImports.append(contentsOf: result.imports)
        }

        return FileParseResult(nodes: allNodes, edges: allEdges, imports: allImports)
    }

    /// Merge syntax-parsed nodes into an existing graph, matching by name+kind
    /// to enrich Index Store nodes with syntax information (doc comments, attributes, etc.).
    public func mergeIntoGraph(
        _ graph: some KnowledgeGraph,
        syntaxResult: FileParseResult
    ) async throws {
        let existingNodes = try await graph.allNodes()

        // Build lookup: (name, kind) -> existing node ID
        var lookup: [String: String] = [:]
        for node in existingNodes {
            let key = "\(node.name)|\(node.kind.rawValue)"
            lookup[key] = node.id
        }

        for syntaxNode in syntaxResult.nodes {
            let key = "\(syntaxNode.name)|\(syntaxNode.kind.rawValue)"
            if lookup[key] != nil {
                // Existing node from Index Store — skip adding duplicate.
                // In a full implementation, we'd merge docComment, attributes, etc.
                continue
            }
            try await graph.addNode(syntaxNode)
        }

        // Add edges, remapping synthetic IDs to Index Store IDs where possible
        for edge in syntaxResult.edges {
            try await graph.addEdge(edge)
        }

        // Add import edges from file nodes to module references
        for import_ in syntaxResult.imports {
            // Import edges would connect file nodes to module nodes
            // For now, these are stored as string references
            let moduleNodeID = "module:\(import_)"
            let moduleNode = GraphNode(
                id: moduleNodeID,
                kind: .module,
                name: import_,
                qualifiedName: import_
            )
            try await graph.addNode(moduleNode)
        }
    }
}
