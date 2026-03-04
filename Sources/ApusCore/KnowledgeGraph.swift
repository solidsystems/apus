public struct NeighborResult: Sendable {
    public let node: GraphNode
    public let edge: GraphEdge
    public let depth: Int

    public init(node: GraphNode, edge: GraphEdge, depth: Int) {
        self.node = node
        self.edge = edge
        self.depth = depth
    }
}

public protocol KnowledgeGraph: Sendable {
    func addNode(_ node: GraphNode) async throws
    func addEdge(_ edge: GraphEdge) async throws

    func node(id: String) async throws -> GraphNode?
    func edges(from sourceID: String) async throws -> [GraphEdge]
    func edges(to targetID: String) async throws -> [GraphEdge]
    func nodes(kind: NodeKind) async throws -> [GraphNode]
    func search(query: String) async throws -> [GraphNode]
    func neighbors(of nodeID: String, depth: Int) async throws -> [NeighborResult]

    func allNodes() async throws -> [GraphNode]
    func allEdges() async throws -> [GraphEdge]

    func addNodes(_ nodes: [GraphNode]) async throws
    func addEdges(_ edges: [GraphEdge]) async throws
}

extension KnowledgeGraph {
    public func addNodes(_ nodes: [GraphNode]) async throws {
        for node in nodes {
            try await addNode(node)
        }
    }

    public func addEdges(_ edges: [GraphEdge]) async throws {
        for edge in edges {
            try await addEdge(edge)
        }
    }
}
