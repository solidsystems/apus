import Testing
import Foundation
@testable import ApusAnalysis
@testable import ApusCore

@Suite("Graph Export Tests")
struct ExportTests {

    // MARK: - Test Helpers

    private func makeSnapshot() -> GraphSnapshot {
        let nodes: [GraphNode] = [
            GraphNode(id: "target:App", kind: .target, name: "App", qualifiedName: "App"),
            GraphNode(id: "target:Core", kind: .target, name: "Core", qualifiedName: "Core"),
            GraphNode(id: "file:Main.swift", kind: .file, name: "Main.swift", qualifiedName: "Main.swift", filePath: "/src/Main.swift", targetName: "App"),
            GraphNode(id: "proto:Storable", kind: .protocol_, name: "Storable", qualifiedName: "Storable", filePath: "/src/Storable.swift", line: 1, accessLevel: .public_, targetName: "Core"),
            GraphNode(id: "struct:User", kind: .struct_, name: "User", qualifiedName: "User", filePath: "/src/User.swift", line: 1, accessLevel: .public_, targetName: "Core"),
            GraphNode(id: "class:ViewModel", kind: .class_, name: "ViewModel", qualifiedName: "App.ViewModel", filePath: "/src/Main.swift", line: 10, accessLevel: .internal_, targetName: "App"),
            GraphNode(id: "enum:Status", kind: .enum_, name: "Status", qualifiedName: "Status", filePath: "/src/Status.swift", line: 1, accessLevel: .public_, targetName: "Core"),
            GraphNode(id: "func:fetch", kind: .function, name: "fetch", qualifiedName: "App.fetch()", filePath: "/src/Main.swift", line: 20, accessLevel: .internal_, targetName: "App"),
            GraphNode(id: "method:save", kind: .method, name: "save", qualifiedName: "User.save()", filePath: "/src/User.swift", line: 10, accessLevel: .public_, targetName: "Core"),
            GraphNode(id: "actor:Store", kind: .actor, name: "Store", qualifiedName: "Core.Store", filePath: "/src/Store.swift", line: 1, accessLevel: .public_, targetName: "Core"),
        ]

        let edges: [GraphEdge] = [
            GraphEdge(sourceID: "target:App", targetID: "target:Core", kind: .dependsOn),
            GraphEdge(sourceID: "struct:User", targetID: "proto:Storable", kind: .conformsTo),
            GraphEdge(sourceID: "class:ViewModel", targetID: "struct:User", kind: .calls),
            GraphEdge(sourceID: "func:fetch", targetID: "method:save", kind: .calls),
            GraphEdge(sourceID: "class:ViewModel", targetID: "class:ViewModel", kind: .extends),
        ]

        return GraphSnapshot(nodes: nodes, edges: edges)
    }

    // MARK: - GraphFilter Tests

    @Test("Filter by target returns only matching nodes")
    func filterByTarget() {
        let snapshot = makeSnapshot()
        let options = GraphFilterOptions(targets: ["Core"])
        let filtered = GraphFilter.filter(snapshot, options: options)

        let targetNames = Set(filtered.allNodes.compactMap(\.targetName))
        #expect(targetNames == ["Core"])
        #expect(!filtered.allNodes.contains { $0.targetName == "App" })
    }

    @Test("Filter by kind returns only matching kinds")
    func filterByKind() {
        let snapshot = makeSnapshot()
        let options = GraphFilterOptions(kinds: [.struct_, .class_])
        let filtered = GraphFilter.filter(snapshot, options: options)

        #expect(filtered.allNodes.allSatisfy { $0.kind == .struct_ || $0.kind == .class_ })
        #expect(filtered.allNodes.count == 2)
    }

    @Test("Exclude kind removes matching kinds")
    func filterExcludeKind() {
        let snapshot = makeSnapshot()
        let options = GraphFilterOptions(excludeKinds: [.file, .target])
        let filtered = GraphFilter.filter(snapshot, options: options)

        #expect(!filtered.allNodes.contains { $0.kind == .file })
        #expect(!filtered.allNodes.contains { $0.kind == .target })
    }

    @Test("Simplify reduces graph to fit maxNodes")
    func simplify() {
        let snapshot = makeSnapshot()
        let simplified = GraphFilter.simplify(snapshot, maxNodes: 5)

        #expect(simplified.allNodes.count <= 5)
        // Should have removed members (method, function) first
        #expect(!simplified.allNodes.contains { $0.kind == .method })
    }

    @Test("Simplify is no-op when under maxNodes")
    func simplifyNoOp() {
        let snapshot = makeSnapshot()
        let simplified = GraphFilter.simplify(snapshot, maxNodes: 100)

        #expect(simplified.allNodes.count == snapshot.allNodes.count)
    }

    // MARK: - DotExporter Tests

    @Test("DotExporter produces valid digraph")
    func dotBasic() {
        let snapshot = makeSnapshot()
        let exporter = DotExporter()
        let result = exporter.export(snapshot: snapshot)

        #expect(result.format == .dot)
        #expect(result.content.contains("digraph G {"))
        #expect(result.content.hasSuffix("}"))
        #expect(result.nodeCount == snapshot.allNodes.count)
        #expect(result.edgeCount == snapshot.allEdges.count)
    }

    @Test("DotExporter uses correct shapes")
    func dotShapes() {
        let snapshot = makeSnapshot()
        let exporter = DotExporter()
        let result = exporter.export(snapshot: snapshot)

        #expect(result.content.contains("shape=hexagon")) // protocol
        #expect(result.content.contains("shape=diamond"))  // enum
        #expect(result.content.contains("shape=box3d"))    // actor
    }

    @Test("DotExporter clusters by target")
    func dotClusters() {
        let snapshot = makeSnapshot()
        let exporter = DotExporter(clusterByTarget: true)
        let result = exporter.export(snapshot: snapshot)

        #expect(result.content.contains("subgraph cluster_App"))
        #expect(result.content.contains("subgraph cluster_Core"))
    }

    @Test("DotExporter without clustering omits subgraphs")
    func dotNoClusters() {
        let snapshot = makeSnapshot()
        let exporter = DotExporter(clusterByTarget: false)
        let result = exporter.export(snapshot: snapshot)

        #expect(!result.content.contains("subgraph"))
    }

    // MARK: - MermaidExporter Tests

    @Test("MermaidExporter produces valid flowchart")
    func mermaidBasic() {
        let snapshot = makeSnapshot()
        let exporter = MermaidExporter()
        let result = exporter.export(snapshot: snapshot)

        #expect(result.format == .mermaid)
        #expect(result.content.contains("flowchart TD"))
    }

    @Test("MermaidExporter uses safe IDs")
    func mermaidSafeIDs() {
        let snapshot = makeSnapshot()
        let exporter = MermaidExporter()
        let result = exporter.export(snapshot: snapshot)

        // Should use n<digit> IDs, not raw IDs with colons
        #expect(result.content.contains("n2"))
        #expect(result.content.contains("n3"))
        #expect(!result.content.contains("struct:User"))
        #expect(!result.content.contains("proto:Storable"))
    }

    @Test("MermaidExporter auto-simplifies large graphs")
    func mermaidAutoSimplify() {
        let snapshot = makeSnapshot()
        let exporter = MermaidExporter(maxNodes: 3)
        let result = exporter.export(snapshot: snapshot)

        #expect(result.wasSimplified)
        #expect(result.nodeCount <= snapshot.allNodes.count)
    }

    @Test("MermaidExporter uses subgraphs for targets")
    func mermaidSubgraphs() {
        let snapshot = makeSnapshot()
        let exporter = MermaidExporter()
        let result = exporter.export(snapshot: snapshot)

        #expect(result.content.contains("subgraph App"))
        #expect(result.content.contains("subgraph Core"))
    }

    // MARK: - JSONExporter Tests

    @Test("JSONExporter produces valid JSON")
    func jsonBasic() {
        let snapshot = makeSnapshot()
        let exporter = JSONExporter()
        let result = exporter.export(snapshot: snapshot)

        #expect(result.format == .json)
        // Verify it's valid JSON
        let data = Data(result.content.utf8)
        let json = try? JSONSerialization.jsonObject(with: data)
        #expect(json != nil)
    }

    @Test("JSONExporter includes metadata")
    func jsonMetadata() {
        let snapshot = makeSnapshot()
        let exporter = JSONExporter()
        let result = exporter.export(snapshot: snapshot)

        #expect(result.content.contains("\"metadata\""))
        #expect(result.content.contains("\"nodeCount\""))
        #expect(result.content.contains("\"edgeCount\""))
        #expect(result.content.contains("\"exportedAt\""))
    }

    @Test("JSONExporter includes degree counts")
    func jsonDegrees() {
        let snapshot = makeSnapshot()
        let exporter = JSONExporter()
        let result = exporter.export(snapshot: snapshot)

        #expect(result.content.contains("\"inDegree\""))
        #expect(result.content.contains("\"outDegree\""))
    }

    @Test("JSONExporter cytoscape format uses elements wrapper")
    func jsonCytoscape() {
        let snapshot = makeSnapshot()
        let exporter = JSONExporter(cytoscapeFormat: true)
        let result = exporter.export(snapshot: snapshot)

        #expect(result.content.contains("\"elements\""))
        #expect(result.content.contains("\"nodes\""))
        #expect(result.content.contains("\"edges\""))
        #expect(result.content.contains("\"shape\""))
        #expect(result.content.contains("\"color\""))
    }

    @Test("JSONExporter cytoscape format includes source/target on edges")
    func jsonCytoscapeEdges() {
        let snapshot = makeSnapshot()
        let exporter = JSONExporter(cytoscapeFormat: true)
        let result = exporter.export(snapshot: snapshot)

        let data = Data(result.content.utf8)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let elements = json?["elements"] as? [String: Any]
        let edges = elements?["edges"] as? [[String: Any]]
        #expect(edges != nil)
        if let firstEdge = edges?.first, let edgeData = firstEdge["data"] as? [String: Any] {
            #expect(edgeData["source"] != nil)
            #expect(edgeData["target"] != nil)
        }
    }

    // MARK: - WebExplorerTemplate Tests

    @Test("WebExplorerTemplate generates valid HTML with CDN links")
    func webExplorerHTML() {
        let snapshot = makeSnapshot()
        let template = WebExplorerTemplate()
        let html = template.generateHTML(snapshot: snapshot, projectName: "TestProject")

        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("unpkg.com/cytoscape@3"))
        #expect(html.contains("unpkg.com/cytoscape-cose-bilkent@4"))
        #expect(html.contains("TestProject"))
    }

    @Test("WebExplorerTemplate fetches graph data from API")
    func webExplorerData() {
        let snapshot = makeSnapshot()
        let template = WebExplorerTemplate()
        let html = template.generateHTML(snapshot: snapshot, projectName: "TestProject")

        // Data is fetched from /api/graph, not inlined
        #expect(html.contains("fetch('/api/graph')"))
        #expect(html.contains("Loading graph data..."))
    }

    @Test("WebExplorerTemplate includes interactive features")
    func webExplorerFeatures() {
        let snapshot = makeSnapshot()
        let template = WebExplorerTemplate()
        let html = template.generateHTML(snapshot: snapshot, projectName: "TestProject")

        #expect(html.contains("id=\"search\""))
        #expect(html.contains("target-filters"))
        #expect(html.contains("kind-filters"))
        #expect(html.contains("exportPNG"))
        #expect(html.contains("setLayout"))
    }

    // MARK: - Empty Graph Tests

    @Test("Exporters handle empty graph gracefully")
    func emptyGraph() {
        let snapshot = GraphSnapshot(nodes: [], edges: [])

        let dotResult = DotExporter().export(snapshot: snapshot)
        #expect(dotResult.content.contains("digraph G {"))
        #expect(dotResult.nodeCount == 0)

        let mermaidResult = MermaidExporter().export(snapshot: snapshot)
        #expect(mermaidResult.content.contains("flowchart TD"))
        #expect(mermaidResult.nodeCount == 0)

        let jsonResult = JSONExporter().export(snapshot: snapshot)
        let data = Data(jsonResult.content.utf8)
        let json = try? JSONSerialization.jsonObject(with: data)
        #expect(json != nil)
        #expect(jsonResult.nodeCount == 0)
    }
}
