import Testing
import Foundation
@testable import ApusCore

@Suite("SQLiteGraph Tests")
struct SQLiteGraphTests {

    private func makeGraph() throws -> SQLiteGraph {
        let storage = try SQLiteStorage()
        return SQLiteGraph(storage: storage)
    }

    @Test("Persist and reload nodes")
    func persistAndReloadNodes() async throws {
        let storage = try SQLiteStorage()
        let graph = SQLiteGraph(storage: storage)

        let node = GraphNode(
            id: "node-1",
            kind: .struct_,
            name: "MyStruct",
            qualifiedName: "MyModule.MyStruct",
            filePath: "/path/to/file.swift",
            line: 42,
            accessLevel: .public_,
            docComment: "A test struct",
            attributes: ["@Sendable"],
            targetName: "MyTarget"
        )
        try await graph.addNode(node)

        let retrieved = try await graph.node(id: "node-1")
        #expect(retrieved != nil)
        #expect(retrieved?.name == "MyStruct")
        #expect(retrieved?.kind == .struct_)
        #expect(retrieved?.qualifiedName == "MyModule.MyStruct")
        #expect(retrieved?.filePath == "/path/to/file.swift")
        #expect(retrieved?.line == 42)
        #expect(retrieved?.accessLevel == .public_)
        #expect(retrieved?.docComment == "A test struct")
        #expect(retrieved?.attributes == ["@Sendable"])
        #expect(retrieved?.targetName == "MyTarget")
    }

    @Test("Persist and reload edges")
    func persistAndReloadEdges() async throws {
        let graph = try makeGraph()

        let parent = GraphNode(id: "parent", kind: .class_, name: "Parent", qualifiedName: "Parent")
        let child = GraphNode(id: "child", kind: .method, name: "doStuff", qualifiedName: "Parent.doStuff")
        try await graph.addNode(parent)
        try await graph.addNode(child)

        let edge = GraphEdge(sourceID: "parent", targetID: "child", kind: .contains, metadata: ["scope": "public"])
        try await graph.addEdge(edge)

        let outgoing = try await graph.edges(from: "parent")
        #expect(outgoing.count == 1)
        #expect(outgoing[0].targetID == "child")
        #expect(outgoing[0].kind == .contains)
        #expect(outgoing[0].metadata["scope"] == "public")

        let incoming = try await graph.edges(to: "child")
        #expect(incoming.count == 1)
        #expect(incoming[0].sourceID == "parent")
    }

    @Test("FTS5 search works")
    func ftsSearch() async throws {
        let graph = try makeGraph()

        try await graph.addNode(GraphNode(
            id: "n1", kind: .function, name: "fetchData",
            qualifiedName: "API.fetchData",
            docComment: "Fetches data from the network"
        ))
        try await graph.addNode(GraphNode(
            id: "n2", kind: .function, name: "processData",
            qualifiedName: "Service.processData"
        ))
        try await graph.addNode(GraphNode(
            id: "n3", kind: .struct_, name: "UserModel",
            qualifiedName: "Models.UserModel"
        ))

        // Search by name token
        let results = try await graph.search(query: "fetchData")
        #expect(results.count == 1)
        #expect(results[0].id == "n1")

        // Search by doc comment
        let docResults = try await graph.search(query: "network")
        #expect(docResults.count == 1)
        #expect(docResults[0].id == "n1")

        // Search that matches qualified name
        let qualResults = try await graph.search(query: "UserModel")
        #expect(qualResults.count == 1)
        #expect(qualResults[0].id == "n3")
    }

    @Test("Filter nodes by kind")
    func filterByKind() async throws {
        let graph = try makeGraph()
        try await graph.addNode(GraphNode(id: "s1", kind: .struct_, name: "S1", qualifiedName: "S1"))
        try await graph.addNode(GraphNode(id: "c1", kind: .class_, name: "C1", qualifiedName: "C1"))
        try await graph.addNode(GraphNode(id: "s2", kind: .struct_, name: "S2", qualifiedName: "S2"))

        let structs = try await graph.nodes(kind: .struct_)
        #expect(structs.count == 2)

        let classes = try await graph.nodes(kind: .class_)
        #expect(classes.count == 1)
    }

    @Test("Neighbors with depth via DB")
    func neighbors() async throws {
        let graph = try makeGraph()
        try await graph.addNode(GraphNode(id: "a", kind: .class_, name: "A", qualifiedName: "A"))
        try await graph.addNode(GraphNode(id: "b", kind: .class_, name: "B", qualifiedName: "B"))
        try await graph.addNode(GraphNode(id: "c", kind: .class_, name: "C", qualifiedName: "C"))
        try await graph.addEdge(GraphEdge(sourceID: "a", targetID: "b", kind: .calls))
        try await graph.addEdge(GraphEdge(sourceID: "b", targetID: "c", kind: .calls))

        let depth1 = try await graph.neighbors(of: "a", depth: 1)
        #expect(depth1.count == 1)
        #expect(depth1[0].node.id == "b")

        let depth2 = try await graph.neighbors(of: "a", depth: 2)
        #expect(depth2.count == 2)
    }

    @Test("All nodes and edges")
    func allNodesAndEdges() async throws {
        let graph = try makeGraph()
        try await graph.addNode(GraphNode(id: "x", kind: .struct_, name: "X", qualifiedName: "X"))
        try await graph.addNode(GraphNode(id: "y", kind: .struct_, name: "Y", qualifiedName: "Y"))
        try await graph.addEdge(GraphEdge(sourceID: "x", targetID: "y", kind: .dependsOn))

        let allN = try await graph.allNodes()
        let allE = try await graph.allEdges()
        #expect(allN.count == 2)
        #expect(allE.count == 1)
    }

    @Test("Batch add nodes and edges")
    func batchAdd() async throws {
        let graph = try makeGraph()
        let nodes = (0..<50).map {
            GraphNode(id: "n\($0)", kind: .function, name: "func\($0)", qualifiedName: "func\($0)")
        }
        try await graph.addNodes(nodes)
        let allN = try await graph.allNodes()
        #expect(allN.count == 50)
    }
}

@Suite("HybridGraph Tests")
struct HybridGraphTests {

    @Test("Write-through: data in both memory and SQLite")
    func writeThrough() async throws {
        let storage = try SQLiteStorage()
        let memory = InMemoryGraph()
        let sqlite = SQLiteGraph(storage: storage)
        let hybrid = HybridGraph(memory: memory, sqlite: sqlite)

        let node = GraphNode(id: "h1", kind: .class_, name: "Hybrid", qualifiedName: "Hybrid")
        try await hybrid.addNode(node)

        // Should be in memory
        let fromMemory = await memory.node(id: "h1")
        #expect(fromMemory != nil)
        #expect(fromMemory?.name == "Hybrid")

        // Should be in SQLite
        let fromDB = try await sqlite.node(id: "h1")
        #expect(fromDB != nil)
        #expect(fromDB?.name == "Hybrid")
    }

    @Test("HybridGraph uses SQLite for FTS search")
    func ftsViaHybrid() async throws {
        let storage = try SQLiteStorage()
        let hybrid = HybridGraph(storage: storage)

        try await hybrid.addNode(GraphNode(
            id: "n1", kind: .function, name: "calculateTotal",
            qualifiedName: "Cart.calculateTotal",
            docComment: "Calculates the total price"
        ))
        try await hybrid.addNode(GraphNode(
            id: "n2", kind: .struct_, name: "CartItem",
            qualifiedName: "Models.CartItem"
        ))

        let results = try await hybrid.search(query: "calculate")
        #expect(results.count == 1)
        #expect(results[0].id == "n1")
    }

    @Test("HybridGraph loadFromDisk populates memory")
    func loadFromDisk() async throws {
        let storage = try SQLiteStorage()

        // Write directly to SQLite
        let sqlite = SQLiteGraph(storage: storage)
        try await sqlite.addNode(GraphNode(id: "pre1", kind: .struct_, name: "Pre", qualifiedName: "Pre"))
        try await sqlite.addEdge(GraphEdge(sourceID: "pre1", targetID: "pre1", kind: .dependsOn))

        // Create a new hybrid graph and load
        let hybrid = HybridGraph(storage: storage)
        try await hybrid.loadFromDisk()

        let node = try await hybrid.node(id: "pre1")
        #expect(node != nil)
        #expect(node?.name == "Pre")

        let edges = try await hybrid.edges(from: "pre1")
        #expect(edges.count == 1)
    }

    @Test("HybridGraph traversal uses in-memory graph")
    func traversalUsesMemory() async throws {
        let storage = try SQLiteStorage()
        let hybrid = HybridGraph(storage: storage)

        try await hybrid.addNode(GraphNode(id: "a", kind: .class_, name: "A", qualifiedName: "A"))
        try await hybrid.addNode(GraphNode(id: "b", kind: .class_, name: "B", qualifiedName: "B"))
        try await hybrid.addEdge(GraphEdge(sourceID: "a", targetID: "b", kind: .calls))

        let neighbors = try await hybrid.neighbors(of: "a", depth: 1)
        #expect(neighbors.count == 1)
        #expect(neighbors[0].node.id == "b")
    }
}

@Suite("GraphPersistence Tests")
struct GraphPersistenceTests {

    @Test("Project hash is deterministic")
    func projectHashDeterministic() {
        let p1 = GraphPersistence(projectPath: "/Users/test/project")
        let p2 = GraphPersistence(projectPath: "/Users/test/project")
        #expect(p1.projectHash == p2.projectHash)
    }

    @Test("Different paths produce different hashes")
    func differentPathsDifferentHashes() {
        let p1 = GraphPersistence(projectPath: "/Users/test/project1")
        let p2 = GraphPersistence(projectPath: "/Users/test/project2")
        #expect(p1.projectHash != p2.projectHash)
    }

    @Test("Database path structure")
    func databasePathStructure() {
        let p = GraphPersistence(projectPath: "/Users/test/myproject")
        #expect(p.databasePath.contains(".apus"))
        #expect(p.databasePath.hasSuffix("graph.db"))
    }

    @Test("Metadata round-trip")
    func metadataRoundTrip() throws {
        let storage = try SQLiteStorage()
        try GraphPersistence.setMetadata(key: "schema_version", value: "1", in: storage)
        let value = try GraphPersistence.getMetadata(key: "schema_version", from: storage)
        #expect(value == "1")
    }

    @Test("Metadata returns nil for missing key")
    func metadataMissing() throws {
        let storage = try SQLiteStorage()
        let value = try GraphPersistence.getMetadata(key: "nonexistent", from: storage)
        #expect(value == nil)
    }
}
