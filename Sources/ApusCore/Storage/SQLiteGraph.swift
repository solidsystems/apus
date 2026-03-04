import Foundation
import GRDB

/// GRDB Record type for nodes table.
struct NodeRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "nodes"

    var id: String
    var kind: String
    var name: String
    var qualifiedName: String
    var filePath: String?
    var line: Int?
    var accessLevel: String?
    var docComment: String?
    var attributes: String
    var targetName: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, name
        case qualifiedName = "qualified_name"
        case filePath = "file_path"
        case line
        case accessLevel = "access_level"
        case docComment = "doc_comment"
        case attributes
        case targetName = "target_name"
    }

    init(_ node: GraphNode) {
        self.id = node.id
        self.kind = node.kind.rawValue
        self.name = node.name
        self.qualifiedName = node.qualifiedName
        self.filePath = node.filePath
        self.line = node.line
        self.accessLevel = node.accessLevel?.rawValue
        self.docComment = node.docComment
        self.attributes = (try? JSONEncoder().encode(node.attributes))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.targetName = node.targetName
    }

    func toGraphNode() -> GraphNode {
        let attrs: [String] = (try? JSONDecoder().decode(
            [String].self,
            from: Data(attributes.utf8)
        )) ?? []

        return GraphNode(
            id: id,
            kind: NodeKind(rawValue: kind) ?? .struct_,
            name: name,
            qualifiedName: qualifiedName,
            filePath: filePath,
            line: line,
            accessLevel: accessLevel.flatMap { AccessLevel(rawValue: $0) },
            docComment: docComment,
            attributes: attrs,
            targetName: targetName
        )
    }
}

/// GRDB Record type for edges table.
struct EdgeRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "edges"

    var sourceId: String
    var targetId: String
    var kind: String
    var metadata: String

    enum CodingKeys: String, CodingKey {
        case sourceId = "source_id"
        case targetId = "target_id"
        case kind
        case metadata
    }

    init(_ edge: GraphEdge) {
        self.sourceId = edge.sourceID
        self.targetId = edge.targetID
        self.kind = edge.kind.rawValue
        self.metadata = (try? JSONEncoder().encode(edge.metadata))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    func toGraphEdge() -> GraphEdge {
        let meta: [String: String] = (try? JSONDecoder().decode(
            [String: String].self,
            from: Data(metadata.utf8)
        )) ?? [:]

        return GraphEdge(
            sourceID: sourceId,
            targetID: targetId,
            kind: EdgeKind(rawValue: kind) ?? .dependsOn,
            metadata: meta
        )
    }
}

/// KnowledgeGraph implementation backed by SQLite via GRDB.
public final class SQLiteGraph: KnowledgeGraph, Sendable {
    private let storage: SQLiteStorage

    public init(storage: SQLiteStorage) {
        self.storage = storage
    }

    public func addNode(_ node: GraphNode) async throws {
        try await storage.dbPool.write { db in
            try NodeRecord(node).save(db)
        }
    }

    public func addEdge(_ edge: GraphEdge) async throws {
        try await storage.dbPool.write { db in
            try EdgeRecord(edge).save(db)
        }
    }

    public func node(id: String) async throws -> GraphNode? {
        try await storage.dbPool.read { db in
            try NodeRecord.fetchOne(db, key: id)?.toGraphNode()
        }
    }

    public func edges(from sourceID: String) async throws -> [GraphEdge] {
        try await storage.dbPool.read { db in
            try EdgeRecord
                .filter(Column("source_id") == sourceID)
                .fetchAll(db)
                .map { $0.toGraphEdge() }
        }
    }

    public func edges(to targetID: String) async throws -> [GraphEdge] {
        try await storage.dbPool.read { db in
            try EdgeRecord
                .filter(Column("target_id") == targetID)
                .fetchAll(db)
                .map { $0.toGraphEdge() }
        }
    }

    public func nodes(kind: NodeKind) async throws -> [GraphNode] {
        try await storage.dbPool.read { db in
            try NodeRecord
                .filter(Column("kind") == kind.rawValue)
                .fetchAll(db)
                .map { $0.toGraphNode() }
        }
    }

    public func search(query: String) async throws -> [GraphNode] {
        try await storage.dbPool.read { db in
            let pattern = FTS5Pattern(matchingAnyTokenIn: query)
            guard let pattern else { return [] }
            let sql = """
                SELECT nodes.*
                FROM nodes
                JOIN nodes_fts ON nodes_fts.rowid = nodes.rowid
                WHERE nodes_fts MATCH ?
                """
            return try NodeRecord.fetchAll(db, sql: sql, arguments: [pattern])
                .map { $0.toGraphNode() }
        }
    }

    public func neighbors(of nodeID: String, depth: Int) async throws -> [NeighborResult] {
        guard depth > 0 else { return [] }

        return try await storage.dbPool.read { db in
            var visited = Set<String>()
            var results: [NeighborResult] = []
            var queue: [(String, Int)] = [(nodeID, 0)]
            visited.insert(nodeID)

            while !queue.isEmpty {
                let (currentID, currentDepth) = queue.removeFirst()
                guard currentDepth < depth else { continue }

                let outgoing = try EdgeRecord
                    .filter(Column("source_id") == currentID)
                    .fetchAll(db)
                let incoming = try EdgeRecord
                    .filter(Column("target_id") == currentID)
                    .fetchAll(db)

                for edgeRec in outgoing {
                    guard !visited.contains(edgeRec.targetId) else { continue }
                    guard let nodeRec = try NodeRecord.fetchOne(db, key: edgeRec.targetId) else { continue }
                    visited.insert(edgeRec.targetId)
                    results.append(NeighborResult(
                        node: nodeRec.toGraphNode(),
                        edge: edgeRec.toGraphEdge(),
                        depth: currentDepth + 1
                    ))
                    queue.append((edgeRec.targetId, currentDepth + 1))
                }

                for edgeRec in incoming {
                    guard !visited.contains(edgeRec.sourceId) else { continue }
                    guard let nodeRec = try NodeRecord.fetchOne(db, key: edgeRec.sourceId) else { continue }
                    visited.insert(edgeRec.sourceId)
                    results.append(NeighborResult(
                        node: nodeRec.toGraphNode(),
                        edge: edgeRec.toGraphEdge(),
                        depth: currentDepth + 1
                    ))
                    queue.append((edgeRec.sourceId, currentDepth + 1))
                }
            }

            return results
        }
    }

    public func allNodes() async throws -> [GraphNode] {
        try await storage.dbPool.read { db in
            try NodeRecord.fetchAll(db).map { $0.toGraphNode() }
        }
    }

    public func allEdges() async throws -> [GraphEdge] {
        try await storage.dbPool.read { db in
            try EdgeRecord.fetchAll(db).map { $0.toGraphEdge() }
        }
    }

    public func addNodes(_ nodes: [GraphNode]) async throws {
        try await storage.dbPool.write { db in
            for node in nodes {
                try NodeRecord(node).save(db)
            }
        }
    }

    public func addEdges(_ edges: [GraphEdge]) async throws {
        try await storage.dbPool.write { db in
            for edge in edges {
                try EdgeRecord(edge).save(db)
            }
        }
    }
}
