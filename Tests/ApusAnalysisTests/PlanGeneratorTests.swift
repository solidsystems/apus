import Testing
import Foundation
@testable import ApusAnalysis
@testable import ApusCore

@Suite("PlanGenerator Tests")
struct PlanGeneratorTests {

    // MARK: - Test Helpers

    private func makeSnapshot() -> GraphSnapshot {
        let nodes: [GraphNode] = [
            // Targets
            GraphNode(id: "target:App", kind: .target, name: "App", qualifiedName: "App"),
            GraphNode(id: "target:Core", kind: .target, name: "Core", qualifiedName: "Core"),

            // Files
            GraphNode(id: "file:App/Main.swift", kind: .file, name: "Main.swift", qualifiedName: "Main.swift", filePath: "/src/App/Main.swift", targetName: "App"),
            GraphNode(id: "file:Core/Model.swift", kind: .file, name: "Model.swift", qualifiedName: "Model.swift", filePath: "/src/Core/Model.swift", targetName: "Core"),

            // Protocols
            GraphNode(id: "proto:Identifiable", kind: .protocol_, name: "Identifiable", qualifiedName: "Identifiable", filePath: "/src/Core/Model.swift", line: 1, accessLevel: .public_, targetName: "Core"),
            GraphNode(id: "proto:Cacheable", kind: .protocol_, name: "Cacheable", qualifiedName: "Cacheable", filePath: "/src/Core/Model.swift", line: 10, accessLevel: .public_, targetName: "Core"),

            // Structs
            GraphNode(id: "struct:User", kind: .struct_, name: "User", qualifiedName: "User", filePath: "/src/Core/Model.swift", line: 20, accessLevel: .public_, targetName: "Core"),
            GraphNode(id: "struct:Post", kind: .struct_, name: "Post", qualifiedName: "Post", filePath: "/src/Core/Model.swift", line: 30, accessLevel: .public_, targetName: "Core"),

            // Class (no subclass, no superclass -> struct candidate)
            GraphNode(id: "class:ViewModel", kind: .class_, name: "ViewModel", qualifiedName: "App.ViewModel", filePath: "/src/App/Main.swift", line: 1, accessLevel: .internal_, targetName: "App"),

            // Actor
            GraphNode(id: "actor:Cache", kind: .actor, name: "Cache", qualifiedName: "Core.Cache", filePath: "/src/Core/Model.swift", line: 40, accessLevel: .public_, targetName: "Core"),

            // Functions
            GraphNode(id: "func:fetchUser", kind: .function, name: "fetchUser", qualifiedName: "App.fetchUser()", filePath: "/src/App/Main.swift", line: 10, accessLevel: .internal_, targetName: "App"),
            GraphNode(id: "func:saveUser", kind: .function, name: "saveUser", qualifiedName: "App.saveUser()", filePath: "/src/App/Main.swift", line: 20, accessLevel: .internal_, targetName: "App"),

            // Method
            GraphNode(id: "method:validate", kind: .method, name: "validate", qualifiedName: "User.validate()", filePath: "/src/Core/Model.swift", line: 25, accessLevel: .public_, targetName: "Core"),

            // Property
            GraphNode(id: "prop:name", kind: .property, name: "name", qualifiedName: "User.name", filePath: "/src/Core/Model.swift", line: 21, accessLevel: .public_, targetName: "Core"),
        ]

        let edges: [GraphEdge] = [
            // Target dependencies
            GraphEdge(sourceID: "target:App", targetID: "target:Core", kind: .dependsOn),

            // Conformances
            GraphEdge(sourceID: "struct:User", targetID: "proto:Identifiable", kind: .conformsTo),
            GraphEdge(sourceID: "struct:Post", targetID: "proto:Identifiable", kind: .conformsTo),
            GraphEdge(sourceID: "struct:User", targetID: "proto:Cacheable", kind: .conformsTo),

            // Calls
            GraphEdge(sourceID: "func:fetchUser", targetID: "method:validate", kind: .calls),
            GraphEdge(sourceID: "func:fetchUser", targetID: "func:saveUser", kind: .calls),
            GraphEdge(sourceID: "func:saveUser", targetID: "method:validate", kind: .calls),
        ]

        return GraphSnapshot(nodes: nodes, edges: edges)
    }

    // MARK: - High Fan-Out Detection

    @Test("Detects high fan-out functions")
    func highFanOut() {
        // Create a function with >8 call edges
        var nodes: [GraphNode] = [
            GraphNode(id: "func:bigFunc", kind: .function, name: "bigFunc", qualifiedName: "bigFunc()", filePath: "/src/big.swift", line: 1, targetName: "App"),
        ]
        var edges: [GraphEdge] = []

        for i in 0..<10 {
            let targetID = "func:helper\(i)"
            nodes.append(GraphNode(id: targetID, kind: .function, name: "helper\(i)", qualifiedName: "helper\(i)()", targetName: "App"))
            edges.append(GraphEdge(sourceID: "func:bigFunc", targetID: targetID, kind: .calls))
        }

        let snapshot = GraphSnapshot(nodes: nodes, edges: edges)
        let generator = PlanGenerator(snapshot: snapshot, projectName: "Test")
        let tasks = generator.detectHighFanOutFunctions()

        #expect(tasks.count == 1)
        #expect(tasks[0].title.contains("bigFunc"))
        #expect(tasks[0].category == "Complexity")
        #expect(tasks[0].impactMetric.contains("10"))
    }

    // MARK: - Large File Detection

    @Test("Detects large files")
    func largeFiles() {
        var nodes: [GraphNode] = []
        for i in 0..<35 {
            nodes.append(GraphNode(id: "func:\(i)", kind: .function, name: "func\(i)", qualifiedName: "func\(i)()", filePath: "/src/huge.swift", targetName: "App"))
        }

        let snapshot = GraphSnapshot(nodes: nodes, edges: [])
        let generator = PlanGenerator(snapshot: snapshot, projectName: "Test")
        let tasks = generator.detectLargeFiles()

        #expect(tasks.count == 1)
        #expect(tasks[0].category == "File Size")
        #expect(tasks[0].impactMetric.contains("35"))
    }

    // MARK: - Orphaned Type Detection

    @Test("Detects orphaned types with zero non-structural edges")
    func orphanedTypes() {
        let nodes: [GraphNode] = [
            GraphNode(id: "struct:Lonely", kind: .struct_, name: "Lonely", qualifiedName: "Lonely", filePath: "/src/lonely.swift", line: 1, targetName: "App"),
            GraphNode(id: "struct:Connected", kind: .struct_, name: "Connected", qualifiedName: "Connected", filePath: "/src/connected.swift", targetName: "App"),
            GraphNode(id: "proto:P", kind: .protocol_, name: "P", qualifiedName: "P", targetName: "App"),
        ]
        let edges: [GraphEdge] = [
            // Connected has a non-structural edge
            GraphEdge(sourceID: "struct:Connected", targetID: "proto:P", kind: .conformsTo),
        ]

        let snapshot = GraphSnapshot(nodes: nodes, edges: edges)
        let generator = PlanGenerator(snapshot: snapshot, projectName: "Test")
        let tasks = generator.detectOrphanedTypes()

        let orphanNames = tasks.map(\.title)
        #expect(orphanNames.contains { $0.contains("Lonely") })
        #expect(!orphanNames.contains { $0.contains("Connected") })
    }

    // MARK: - Module Entries

    @Test("Generates valid module entries with deps and key types")
    func moduleEntries() {
        let snapshot = makeSnapshot()
        let generator = PlanGenerator(snapshot: snapshot, projectName: "TestProject")
        let modules = generator.computeModules()

        #expect(modules.count == 2)

        let app = modules.first { $0.name == "App" }
        let core = modules.first { $0.name == "Core" }

        #expect(app != nil)
        #expect(core != nil)
        #expect(app!.dependsOn.contains("Core"))
        #expect(core!.dependedOnBy.contains("App"))
        #expect(!core!.keyTypes.isEmpty)
    }

    // MARK: - JSON Round-Trip

    @Test("JSON round-trip encoding/decoding")
    func jsonRoundTrip() throws {
        let snapshot = makeSnapshot()
        let generator = PlanGenerator(snapshot: snapshot, projectName: "TestProject")
        let plan = generator.generate()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(plan)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlanDocument.self, from: data)

        #expect(decoded.projectName == "TestProject")
        #expect(decoded.overview?.targetCount == 2)
        #expect(decoded.modules?.count == 2)
        #expect(decoded.protocolRelationships != nil)
        #expect(decoded.entryPoints != nil)
    }

    // MARK: - Context/Tasks Filtering

    @Test("contextOnly excludes tasks")
    func contextOnly() {
        let snapshot = makeSnapshot()
        let options = PlanOptions(includeContext: true, includeTasks: false)
        let generator = PlanGenerator(snapshot: snapshot, projectName: "Test", options: options)
        let plan = generator.generate()

        #expect(plan.overview != nil)
        #expect(plan.modules != nil)
        #expect(plan.tasks == nil)
    }

    @Test("tasksOnly excludes context")
    func tasksOnly() {
        let snapshot = makeSnapshot()
        let options = PlanOptions(includeContext: false, includeTasks: true)
        let generator = PlanGenerator(snapshot: snapshot, projectName: "Test", options: options)
        let plan = generator.generate()

        #expect(plan.overview == nil)
        #expect(plan.modules == nil)
        #expect(plan.protocolRelationships == nil)
        #expect(plan.entryPoints == nil)
        #expect(plan.tasks != nil)
    }

    // MARK: - Empty Graph

    @Test("Empty graph produces valid plan")
    func emptyGraph() {
        let snapshot = GraphSnapshot(nodes: [], edges: [])
        let generator = PlanGenerator(snapshot: snapshot, projectName: "Empty")
        let plan = generator.generate()

        #expect(plan.projectName == "Empty")
        #expect(plan.overview?.symbolCount == 0)
        #expect(plan.modules?.isEmpty == true)
        #expect(plan.tasks?.isEmpty == true)

        // Also verify markdown rendering works
        let renderer = PlanRenderer()
        let markdown = renderer.renderMarkdown(plan)
        #expect(markdown.contains("Implementation Plan: Empty"))
    }

    // MARK: - Pattern Opportunities

    @Test("Detects class-to-struct candidates")
    func classToStruct() {
        let nodes: [GraphNode] = [
            // Standalone class with no inheritance
            GraphNode(id: "class:Solo", kind: .class_, name: "Solo", qualifiedName: "Solo", filePath: "/src/solo.swift", line: 1, targetName: "App"),
            // Class with a subclass - should NOT be suggested
            GraphNode(id: "class:Parent", kind: .class_, name: "Parent", qualifiedName: "Parent", filePath: "/src/parent.swift", line: 1, targetName: "App"),
            GraphNode(id: "class:Child", kind: .class_, name: "Child", qualifiedName: "Child", filePath: "/src/child.swift", line: 1, targetName: "App"),
        ]
        let edges: [GraphEdge] = [
            GraphEdge(sourceID: "class:Child", targetID: "class:Parent", kind: .extends),
        ]

        let snapshot = GraphSnapshot(nodes: nodes, edges: edges)
        let generator = PlanGenerator(snapshot: snapshot, projectName: "Test")
        let tasks = generator.detectPatternOpportunities()

        let titles = tasks.map(\.title)
        #expect(titles.contains { $0.contains("Solo") })
        #expect(!titles.contains { $0.contains("Parent") })
        #expect(!titles.contains { $0.contains("Child") }) // Child extends Parent
    }

    // MARK: - Renderer

    @Test("Renderer produces valid markdown structure")
    func rendererOutput() {
        let snapshot = makeSnapshot()
        let generator = PlanGenerator(snapshot: snapshot, projectName: "TestProject")
        let plan = generator.generate()
        let renderer = PlanRenderer()
        let markdown = renderer.renderMarkdown(plan)

        #expect(markdown.contains("# Implementation Plan: TestProject"))
        #expect(markdown.contains("## Codebase Context"))
        #expect(markdown.contains("### Overview"))
        #expect(markdown.contains("### Modules"))
        #expect(markdown.contains("## Improvement Tasks"))
    }
}
