import Foundation

/// Combines InMemoryGraph (fast traversals) with SQLiteGraph (persistence, FTS5 search).
/// Write-through: mutations go to both graphs.
/// Reads prefer in-memory for traversals, SQLite for FTS search.
public final class HybridGraph: KnowledgeGraph, Sendable {
    private let memory: InMemoryGraph
    private let sqlite: SQLiteGraph

    public init(memory: InMemoryGraph, sqlite: SQLiteGraph) {
        self.memory = memory
        self.sqlite = sqlite
    }

    /// Convenience: create from a SQLiteStorage, with a fresh in-memory graph.
    public init(storage: SQLiteStorage) {
        self.memory = InMemoryGraph()
        self.sqlite = SQLiteGraph(storage: storage)
    }

    /// Load all persisted data from SQLite into the in-memory graph.
    public func loadFromDisk() async throws {
        let nodes = try await sqlite.allNodes()
        let edges = try await sqlite.allEdges()
        for node in nodes {
            await memory.addNode(node)
        }
        for edge in edges {
            await memory.addEdge(edge)
        }
    }

    // MARK: - Write-through

    public func addNode(_ node: GraphNode) async throws {
        try await sqlite.addNode(node)
        await memory.addNode(node)
    }

    public func addEdge(_ edge: GraphEdge) async throws {
        try await sqlite.addEdge(edge)
        await memory.addEdge(edge)
    }

    public func addNodes(_ nodes: [GraphNode]) async throws {
        try await sqlite.addNodes(nodes)
        for node in nodes {
            await memory.addNode(node)
        }
    }

    public func addEdges(_ edges: [GraphEdge]) async throws {
        try await sqlite.addEdges(edges)
        for edge in edges {
            await memory.addEdge(edge)
        }
    }

    // MARK: - Reads (prefer in-memory for traversals)

    public func node(id: String) async throws -> GraphNode? {
        await memory.node(id: id)
    }

    public func edges(from sourceID: String) async throws -> [GraphEdge] {
        await memory.edges(from: sourceID)
    }

    public func edges(to targetID: String) async throws -> [GraphEdge] {
        await memory.edges(to: targetID)
    }

    public func nodes(kind: NodeKind) async throws -> [GraphNode] {
        await memory.nodes(kind: kind)
    }

    public func neighbors(of nodeID: String, depth: Int) async throws -> [NeighborResult] {
        await memory.neighbors(of: nodeID, depth: depth)
    }

    public func allNodes() async throws -> [GraphNode] {
        await memory.allNodes()
    }

    public func allEdges() async throws -> [GraphEdge] {
        await memory.allEdges()
    }

    // MARK: - FTS search (uses SQLite)

    public func search(query: String) async throws -> [GraphNode] {
        try await sqlite.search(query: query)
    }
}
