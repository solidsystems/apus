import Testing
@testable import ApusCore

@Suite("InMemoryGraph Tests")
struct InMemoryGraphTests {
    @Test("Add and retrieve a node")
    func addAndRetrieveNode() async throws {
        let graph = InMemoryGraph()
        let node = GraphNode(
            id: "test-1",
            kind: .struct_,
            name: "MyStruct",
            qualifiedName: "MyModule.MyStruct",
            filePath: "/path/to/file.swift",
            line: 10,
            accessLevel: .public_
        )
        await graph.addNode(node)
        let retrieved = await graph.node(id: "test-1")
        #expect(retrieved != nil)
        #expect(retrieved?.name == "MyStruct")
        #expect(retrieved?.kind == .struct_)
    }

    @Test("Add and retrieve edges")
    func addAndRetrieveEdges() async throws {
        let graph = InMemoryGraph()
        let parent = GraphNode(id: "parent", kind: .class_, name: "Parent", qualifiedName: "Parent")
        let child = GraphNode(id: "child", kind: .method, name: "doStuff", qualifiedName: "Parent.doStuff")
        await graph.addNode(parent)
        await graph.addNode(child)

        let edge = GraphEdge(sourceID: "parent", targetID: "child", kind: .contains)
        await graph.addEdge(edge)

        let outgoing = await graph.edges(from: "parent")
        #expect(outgoing.count == 1)
        #expect(outgoing[0].targetID == "child")

        let incoming = await graph.edges(to: "child")
        #expect(incoming.count == 1)
        #expect(incoming[0].sourceID == "parent")
    }

    @Test("Filter nodes by kind")
    func filterByKind() async throws {
        let graph = InMemoryGraph()
        await graph.addNode(GraphNode(id: "s1", kind: .struct_, name: "S1", qualifiedName: "S1"))
        await graph.addNode(GraphNode(id: "c1", kind: .class_, name: "C1", qualifiedName: "C1"))
        await graph.addNode(GraphNode(id: "s2", kind: .struct_, name: "S2", qualifiedName: "S2"))

        let structs = await graph.nodes(kind: .struct_)
        #expect(structs.count == 2)

        let classes = await graph.nodes(kind: .class_)
        #expect(classes.count == 1)
    }

    @Test("Search by name")
    func searchByName() async throws {
        let graph = InMemoryGraph()
        await graph.addNode(GraphNode(id: "n1", kind: .function, name: "fetchData", qualifiedName: "fetchData"))
        await graph.addNode(GraphNode(id: "n2", kind: .function, name: "processData", qualifiedName: "processData"))
        await graph.addNode(GraphNode(id: "n3", kind: .struct_, name: "UserModel", qualifiedName: "UserModel"))

        let results = await graph.search(query: "data")
        #expect(results.count == 2)
    }

    @Test("Search is case insensitive")
    func searchCaseInsensitive() async throws {
        let graph = InMemoryGraph()
        await graph.addNode(GraphNode(id: "n1", kind: .class_, name: "NetworkManager", qualifiedName: "NetworkManager"))

        let results = await graph.search(query: "networkmanager")
        #expect(results.count == 1)
    }

    @Test("Neighbors with depth")
    func neighborsWithDepth() async throws {
        let graph = InMemoryGraph()
        await graph.addNode(GraphNode(id: "a", kind: .class_, name: "A", qualifiedName: "A"))
        await graph.addNode(GraphNode(id: "b", kind: .class_, name: "B", qualifiedName: "B"))
        await graph.addNode(GraphNode(id: "c", kind: .class_, name: "C", qualifiedName: "C"))
        await graph.addEdge(GraphEdge(sourceID: "a", targetID: "b", kind: .calls))
        await graph.addEdge(GraphEdge(sourceID: "b", targetID: "c", kind: .calls))

        let depth1 = await graph.neighbors(of: "a", depth: 1)
        #expect(depth1.count == 1)
        #expect(depth1[0].node.id == "b")

        let depth2 = await graph.neighbors(of: "a", depth: 2)
        #expect(depth2.count == 2)
    }

    @Test("Node count and edge count")
    func counts() async throws {
        let graph = InMemoryGraph()
        await graph.addNode(GraphNode(id: "x", kind: .struct_, name: "X", qualifiedName: "X"))
        await graph.addNode(GraphNode(id: "y", kind: .struct_, name: "Y", qualifiedName: "Y"))
        await graph.addEdge(GraphEdge(sourceID: "x", targetID: "y", kind: .dependsOn))

        let nc = await graph.nodeCount
        let ec = await graph.edgeCount
        #expect(nc == 2)
        #expect(ec == 1)
    }

    @Test("Batch add nodes and edges")
    func batchAdd() async throws {
        let graph = InMemoryGraph()
        let nodes = (0..<100).map {
            GraphNode(id: "n\($0)", kind: .function, name: "func\($0)", qualifiedName: "func\($0)")
        }
        try await graph.addNodes(nodes)
        let nc = await graph.nodeCount
        #expect(nc == 100)
    }

    @Test("All nodes and all edges")
    func allNodesAndEdges() async throws {
        let graph = InMemoryGraph()
        await graph.addNode(GraphNode(id: "a", kind: .class_, name: "A", qualifiedName: "A"))
        await graph.addNode(GraphNode(id: "b", kind: .class_, name: "B", qualifiedName: "B"))
        await graph.addEdge(GraphEdge(sourceID: "a", targetID: "b", kind: .extends))

        let allNodes = await graph.allNodes()
        let allEdges = await graph.allEdges()
        #expect(allNodes.count == 2)
        #expect(allEdges.count == 1)
    }
}
