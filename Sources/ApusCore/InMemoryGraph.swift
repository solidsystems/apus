import Foundation

public actor InMemoryGraph: KnowledgeGraph {
    private var nodeStore: [String: GraphNode] = [:]
    private var outgoing: [String: [GraphEdge]] = [:]
    private var incoming: [String: [GraphEdge]] = [:]

    public init() {}

    public func addNode(_ node: GraphNode) {
        nodeStore[node.id] = node
    }

    public func addEdge(_ edge: GraphEdge) {
        outgoing[edge.sourceID, default: []].append(edge)
        incoming[edge.targetID, default: []].append(edge)
    }

    public func node(id: String) -> GraphNode? {
        nodeStore[id]
    }

    public func edges(from sourceID: String) -> [GraphEdge] {
        outgoing[sourceID] ?? []
    }

    public func edges(to targetID: String) -> [GraphEdge] {
        incoming[targetID] ?? []
    }

    public func nodes(kind: NodeKind) -> [GraphNode] {
        nodeStore.values.filter { $0.kind == kind }
    }

    public func search(query: String) -> [GraphNode] {
        let lowered = query.lowercased()
        return nodeStore.values.filter {
            $0.name.lowercased().contains(lowered)
            || $0.qualifiedName.lowercased().contains(lowered)
            || ($0.docComment?.lowercased().contains(lowered) ?? false)
        }
    }

    public func neighbors(of nodeID: String, depth: Int) -> [NeighborResult] {
        guard depth > 0 else { return [] }

        var visited = Set<String>()
        var results: [NeighborResult] = []
        var queue: [(String, Int)] = [(nodeID, 0)]
        visited.insert(nodeID)

        while !queue.isEmpty {
            let (currentID, currentDepth) = queue.removeFirst()
            guard currentDepth < depth else { continue }

            let edgesOut = outgoing[currentID] ?? []
            let edgesIn = incoming[currentID] ?? []

            for edge in edgesOut {
                guard !visited.contains(edge.targetID),
                      let targetNode = nodeStore[edge.targetID] else { continue }
                visited.insert(edge.targetID)
                results.append(NeighborResult(node: targetNode, edge: edge, depth: currentDepth + 1))
                queue.append((edge.targetID, currentDepth + 1))
            }

            for edge in edgesIn {
                guard !visited.contains(edge.sourceID),
                      let sourceNode = nodeStore[edge.sourceID] else { continue }
                visited.insert(edge.sourceID)
                results.append(NeighborResult(node: sourceNode, edge: edge, depth: currentDepth + 1))
                queue.append((edge.sourceID, currentDepth + 1))
            }
        }

        return results
    }

    public func allNodes() -> [GraphNode] {
        Array(nodeStore.values)
    }

    public func allEdges() -> [GraphEdge] {
        outgoing.values.flatMap { $0 }
    }

    public func addNodes(_ nodes: [GraphNode]) {
        for node in nodes {
            nodeStore[node.id] = node
        }
    }

    public func addEdges(_ edges: [GraphEdge]) {
        for edge in edges {
            outgoing[edge.sourceID, default: []].append(edge)
            incoming[edge.targetID, default: []].append(edge)
        }
    }

    public func updateNode(_ node: GraphNode) {
        nodeStore[node.id] = node
    }

    public func removeNode(id: String) {
        nodeStore.removeValue(forKey: id)
        outgoing.removeValue(forKey: id)
        incoming.removeValue(forKey: id)
        for key in outgoing.keys {
            outgoing[key]?.removeAll { $0.targetID == id }
        }
        for key in incoming.keys {
            incoming[key]?.removeAll { $0.sourceID == id }
        }
    }

    public var nodeCount: Int { nodeStore.count }
    public var edgeCount: Int { outgoing.values.reduce(0) { $0 + $1.count } }
}
