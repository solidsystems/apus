import Testing
@testable import ApusMCP
@testable import ApusCore
import MCP

@Suite("ApusMCPServer Tests")
struct ApusMCPServerTests {

    /// Build a small graph for testing.
    private func buildTestGraph() async -> InMemoryGraph {
        let graph = InMemoryGraph()

        // Protocol
        await graph.addNode(GraphNode(
            id: "proto:Sendable", kind: .protocol_, name: "Sendable",
            qualifiedName: "Swift.Sendable"
        ))

        // Struct
        await graph.addNode(GraphNode(
            id: "struct:MyModel", kind: .struct_, name: "MyModel",
            qualifiedName: "App.MyModel",
            filePath: "/project/Sources/App/MyModel.swift", line: 5,
            accessLevel: .public_,
            docComment: "A data model",
            targetName: "App"
        ))

        // Method on struct
        await graph.addNode(GraphNode(
            id: "method:MyModel.validate", kind: .method, name: "validate",
            qualifiedName: "App.MyModel.validate()",
            filePath: "/project/Sources/App/MyModel.swift", line: 15,
            accessLevel: .public_,
            targetName: "App"
        ))

        // Class that depends on MyModel
        await graph.addNode(GraphNode(
            id: "class:Service", kind: .class_, name: "Service",
            qualifiedName: "App.Service",
            filePath: "/project/Sources/App/Service.swift", line: 1,
            accessLevel: .internal_,
            targetName: "App"
        ))

        // Extension
        await graph.addNode(GraphNode(
            id: "ext:MyModel+Codable", kind: .extension_, name: "MyModel",
            qualifiedName: "App.MyModel",
            filePath: "/project/Sources/App/MyModel+Codable.swift", line: 1,
            targetName: "App"
        ))

        // Edges
        await graph.addEdge(GraphEdge(sourceID: "struct:MyModel", targetID: "proto:Sendable", kind: .conformsTo))
        await graph.addEdge(GraphEdge(sourceID: "struct:MyModel", targetID: "method:MyModel.validate", kind: .contains))
        await graph.addEdge(GraphEdge(sourceID: "class:Service", targetID: "struct:MyModel", kind: .dependsOn))
        await graph.addEdge(GraphEdge(sourceID: "class:Service", targetID: "method:MyModel.validate", kind: .calls))
        await graph.addEdge(GraphEdge(sourceID: "ext:MyModel+Codable", targetID: "struct:MyModel", kind: .extends))

        return graph
    }

    @Test("Server initializes with correct info")
    func serverInit() async {
        let graph = await buildTestGraph()
        let _ = ApusMCPServer(graph: graph, projectName: "TestProject")
        // If we get here without error, initialization works
    }

    @Test("Search finds matching symbols")
    func searchTool() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        let result = try await server.callTool(name: "search", arguments: ["query": .string("MyModel")])
        #expect(result.isError == nil)

        let text = result.content.first.flatMap {
            if case .text(let t) = $0 { return t }
            return nil
        } ?? ""
        #expect(text.contains("MyModel"))
        #expect(text.contains("struct"))
    }

    @Test("Search with kind filter")
    func searchWithKindFilter() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        let result = try await server.callTool(
            name: "search",
            arguments: ["query": .string("MyModel"), "kind": .string("struct")]
        )
        let text = extractText(result)
        #expect(text.contains("struct"))
        #expect(!text.contains("extension"))
    }

    @Test("Lookup returns detailed node info")
    func lookupTool() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        let result = try await server.callTool(name: "lookup", arguments: ["id": .string("struct:MyModel")])
        let text = extractText(result)
        #expect(text.contains("App.MyModel"))
        #expect(text.contains("public"))
        #expect(text.contains("A data model"))
        #expect(text.contains("conformsTo"))
    }

    @Test("Lookup with unknown ID returns not found")
    func lookupUnknown() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        let result = try await server.callTool(name: "lookup", arguments: ["id": .string("nonexistent")])
        let text = extractText(result)
        #expect(text.contains("No symbol found"))
    }

    @Test("Context returns neighbors at depth")
    func contextTool() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        let result = try await server.callTool(
            name: "context",
            arguments: ["id": .string("struct:MyModel"), "depth": .int(1)]
        )
        let text = extractText(result)
        #expect(text.contains("App.MyModel"))
        #expect(text.contains("Depth 1"))
    }

    @Test("Impact shows reverse dependencies")
    func impactTool() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        let result = try await server.callTool(name: "impact", arguments: ["id": .string("struct:MyModel")])
        let text = extractText(result)
        #expect(text.contains("Impact analysis"))
        #expect(text.contains("Service"))
        #expect(text.contains("dependsOn"))
    }

    @Test("Impact on leaf symbol reports no dependents")
    func impactLeaf() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        // method:MyModel.validate has incoming calls but no outgoing deps that point to it
        // except the calls edge — use an ID with no inbound edges
        let result = try await server.callTool(name: "impact", arguments: ["id": .string("class:Service")])
        let text = extractText(result)
        #expect(text.contains("No dependents"))
    }

    @Test("Conformances finds protocol relationships")
    func conformancesTool() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        let result = try await server.callTool(name: "conformances", arguments: ["name": .string("MyModel")])
        let text = extractText(result)
        #expect(text.contains("Conforms to"))
        #expect(text.contains("Sendable"))
    }

    @Test("Extensions finds type extensions")
    func extensionsTool() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        let result = try await server.callTool(name: "extensions", arguments: ["name": .string("MyModel")])
        let text = extractText(result)
        #expect(text.contains("Extensions of MyModel"))
    }

    @Test("Unknown tool returns error")
    func unknownTool() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        let result = try await server.callTool(name: "nonexistent", arguments: [:])
        #expect(result.isError == true)
    }

    @Test("Missing required parameter returns error")
    func missingParam() async throws {
        let graph = await buildTestGraph()
        let server = ApusMCPServer(graph: graph, projectName: "TestProject")

        let result = try await server.callTool(name: "search", arguments: [:])
        #expect(result.isError == true)
        let text = extractText(result)
        #expect(text.contains("Missing required parameter"))
    }

    // MARK: - Helpers

    private func extractText(_ result: CallTool.Result) -> String {
        result.content.compactMap {
            if case .text(let t) = $0 { return t }
            return nil
        }.joined()
    }
}
