import Testing
@testable import ApusAnalysis
@testable import ApusCore

@Suite("CodebaseAnalyzer Tests")
struct CodebaseAnalyzerTests {

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

            // Class
            GraphNode(id: "class:ViewModel", kind: .class_, name: "ViewModel", qualifiedName: "App.ViewModel", filePath: "/src/App/Main.swift", line: 1, accessLevel: .internal_, targetName: "App"),
            GraphNode(id: "class:BaseVM", kind: .class_, name: "BaseVM", qualifiedName: "App.BaseVM", filePath: "/src/App/Main.swift", line: 50, accessLevel: .internal_, targetName: "App"),

            // Actor
            GraphNode(id: "actor:Cache", kind: .actor, name: "Cache", qualifiedName: "Core.Cache", filePath: "/src/Core/Model.swift", line: 40, accessLevel: .public_, targetName: "Core"),

            // Functions
            GraphNode(id: "func:fetchUser", kind: .function, name: "fetchUser", qualifiedName: "App.fetchUser()", filePath: "/src/App/Main.swift", line: 10, accessLevel: .internal_, targetName: "App"),
            GraphNode(id: "func:saveUser", kind: .function, name: "saveUser", qualifiedName: "App.saveUser()", filePath: "/src/App/Main.swift", line: 20, accessLevel: .internal_, targetName: "App"),

            // Method
            GraphNode(id: "method:validate", kind: .method, name: "validate", qualifiedName: "User.validate()", filePath: "/src/Core/Model.swift", line: 25, accessLevel: .public_, targetName: "Core"),

            // Property
            GraphNode(id: "prop:name", kind: .property, name: "name", qualifiedName: "User.name", filePath: "/src/Core/Model.swift", line: 21, accessLevel: .public_, targetName: "Core"),

            // Extension
            GraphNode(id: "ext:User+Ext", kind: .extension_, name: "User", qualifiedName: "User", filePath: "/src/Core/Model.swift", line: 50, targetName: "Core"),

            // Module for imports
            GraphNode(id: "module:Foundation", kind: .module, name: "Foundation", qualifiedName: "Foundation"),
        ]

        let edges: [GraphEdge] = [
            // Target dependencies
            GraphEdge(sourceID: "target:App", targetID: "target:Core", kind: .dependsOn),

            // Conformances
            GraphEdge(sourceID: "struct:User", targetID: "proto:Identifiable", kind: .conformsTo),
            GraphEdge(sourceID: "struct:Post", targetID: "proto:Identifiable", kind: .conformsTo),
            GraphEdge(sourceID: "struct:User", targetID: "proto:Cacheable", kind: .conformsTo),

            // Inheritance
            GraphEdge(sourceID: "class:ViewModel", targetID: "class:BaseVM", kind: .extends),

            // Calls
            GraphEdge(sourceID: "func:fetchUser", targetID: "method:validate", kind: .calls),
            GraphEdge(sourceID: "func:fetchUser", targetID: "func:saveUser", kind: .calls),
            GraphEdge(sourceID: "func:saveUser", targetID: "method:validate", kind: .calls),

            // Contains (extension members)
            GraphEdge(sourceID: "ext:User+Ext", targetID: "method:validate", kind: .contains),
            GraphEdge(sourceID: "ext:User+Ext", targetID: "prop:name", kind: .contains),

            // Imports
            GraphEdge(sourceID: "file:App/Main.swift", targetID: "module:Foundation", kind: .imports),
            GraphEdge(sourceID: "file:Core/Model.swift", targetID: "module:Foundation", kind: .imports),
        ]

        return GraphSnapshot(nodes: nodes, edges: edges)
    }

    // MARK: - Tests

    @Test("Overview section shows correct counts")
    func overviewSection() {
        let snapshot = makeSnapshot()
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "TestProject")
        let report = analyzer.analyze(sections: [.overview])

        #expect(report.sections.count == 1)
        #expect(report.sections[0].section == .overview)

        let content = report.sections[0].content
        #expect(content.contains("Targets"))
        #expect(content.contains("Files"))
        #expect(content.contains("Symbols"))
        #expect(content.contains("Edges"))
    }

    @Test("Architecture section shows targets and dependencies")
    func architectureSection() {
        let snapshot = makeSnapshot()
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "TestProject")
        let report = analyzer.analyze(sections: [.architecture])

        let content = report.sections[0].content
        #expect(content.contains("App"))
        #expect(content.contains("Core"))
        #expect(content.contains("App → Core"))
    }

    @Test("Type system section shows conformances and inheritance")
    func typeSystemSection() {
        let snapshot = makeSnapshot()
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "TestProject")
        let report = analyzer.analyze(sections: [.typesystem])

        let content = report.sections[0].content
        #expect(content.contains("Identifiable"))
        #expect(content.contains("User"))
        #expect(content.contains("Post"))
        #expect(content.contains("BaseVM"))
    }

    @Test("API surface section lists public symbols")
    func apiSection() {
        let snapshot = makeSnapshot()
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "TestProject")
        let report = analyzer.analyze(sections: [.api])

        let content = report.sections[0].content
        #expect(content.contains("public/open"))
        #expect(content.contains("User"))
        #expect(content.contains("Identifiable"))
        // ViewModel is internal, should not appear
        #expect(!content.contains("ViewModel"))
    }

    @Test("Dependencies section shows import graph")
    func dependenciesSection() {
        let snapshot = makeSnapshot()
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "TestProject")
        let report = analyzer.analyze(sections: [.dependencies])

        let content = report.sections[0].content
        #expect(content.contains("Foundation"))
    }

    @Test("Hotspots section identifies referenced symbols")
    func hotspotsSection() {
        let snapshot = makeSnapshot()
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "TestProject")
        let report = analyzer.analyze(sections: [.hotspots])

        let content = report.sections[0].content
        // validate is called by two functions
        #expect(content.contains("validate"))
    }

    @Test("Patterns section detects actors")
    func patternsSection() {
        let snapshot = makeSnapshot()
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "TestProject")
        let report = analyzer.analyze(sections: [.patterns])

        let content = report.sections[0].content
        #expect(content.contains("Cache"))
        #expect(content.contains("Actor"))
    }

    @Test("Section filtering works")
    func sectionFiltering() {
        let snapshot = makeSnapshot()
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "TestProject")

        let report = analyzer.analyze(sections: [.overview, .hotspots])
        #expect(report.sections.count == 2)
        #expect(report.sections[0].section == .overview)
        #expect(report.sections[1].section == .hotspots)
    }

    @Test("Full report includes all sections")
    func fullReport() {
        let snapshot = makeSnapshot()
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "TestProject")

        let report = analyzer.analyze()
        #expect(report.sections.count == AnalysisSection.allCases.count)
    }

    @Test("Report renders valid markdown")
    func markdownRendering() {
        let snapshot = makeSnapshot()
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "TestProject")

        let report = analyzer.analyze()
        let markdown = report.renderMarkdown()

        #expect(markdown.starts(with: "# Codebase Analysis: TestProject"))
        #expect(markdown.contains("## Overview"))
        #expect(markdown.contains("## Architecture"))
        #expect(markdown.contains("Table of Contents"))
    }

    @Test("Empty graph produces valid report")
    func emptyGraph() {
        let snapshot = GraphSnapshot(nodes: [], edges: [])
        let analyzer = CodebaseAnalyzer(snapshot: snapshot, projectName: "Empty")

        let report = analyzer.analyze()
        let markdown = report.renderMarkdown()

        #expect(markdown.contains("# Codebase Analysis: Empty"))
        #expect(report.sections.count == AnalysisSection.allCases.count)
    }

    @Test("GraphSnapshot indexes correctly")
    func snapshotIndexing() {
        let snapshot = makeSnapshot()

        #expect(snapshot.nodeByID["struct:User"]?.name == "User")
        #expect(snapshot.nodesByKind[.actor]?.count == 1)
        #expect(snapshot.nodesByTarget["Core"]!.count > 0)
        #expect(snapshot.outgoing["func:fetchUser"]?.count == 2)
        #expect(snapshot.incoming["method:validate"]?.count == 3) // 2 calls + 1 contains
        #expect(snapshot.edgesByKind[.conformsTo]?.count == 3)
    }
}
