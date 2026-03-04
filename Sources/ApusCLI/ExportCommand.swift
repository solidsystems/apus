import ArgumentParser
import Foundation
import ApusCore
import ApusAnalysis

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export the knowledge graph as DOT, Mermaid, or JSON"
    )

    @Argument(help: "Path to the project root")
    var path: String = "."

    @Option(name: .long, help: "Export format: dot, mermaid, json")
    var format: String = "dot"

    @Option(name: .shortAndLong, help: "Write output to file instead of stdout")
    var output: String?

    @Option(name: .long, help: "Filter to specific targets (repeatable)")
    var target: [String] = []

    @Option(name: .long, help: "Filter to specific node kinds (repeatable)")
    var kind: [String] = []

    @Option(name: .long, help: "Exclude specific node kinds (repeatable)")
    var excludeKind: [String] = []

    @Option(name: .long, help: "Maximum number of nodes to include")
    var maxNodes: Int?

    @Flag(name: .long, help: "Use Cytoscape.js-compatible JSON format")
    var cytoscape: Bool = false

    @Flag(name: .long, help: "Disable target clustering in DOT output")
    var noCluster: Bool = false

    @Option(name: .long, help: "Mermaid diagram direction: TD or LR (default: TD)")
    var direction: String = "TD"

    func run() async throws {
        let resolvedPath = URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardized.path

        let persistence = GraphPersistence(projectPath: resolvedPath)
        guard FileManager.default.fileExists(atPath: persistence.databasePath) else {
            print("No index found. Run `apus index \(path)` first.")
            throw ExitCode.failure
        }

        let graph = try persistence.openGraph()
        try await graph.loadFromDisk()

        // Build snapshot
        let allNodes = try await graph.allNodes()
        let allEdges = try await graph.allEdges()
        var snapshot = GraphSnapshot(nodes: allNodes, edges: allEdges)

        // Apply filters
        let parsedKinds = kind.compactMap { NodeKind(rawValue: $0) ?? NodeKind(displayName: $0) }
        let parsedExcludes = excludeKind.compactMap { NodeKind(rawValue: $0) ?? NodeKind(displayName: $0) }

        let filterOptions = GraphFilterOptions(
            targets: target,
            kinds: parsedKinds,
            excludeKinds: parsedExcludes,
            maxNodes: maxNodes
        )

        if !target.isEmpty || !parsedKinds.isEmpty || !parsedExcludes.isEmpty || maxNodes != nil {
            snapshot = GraphFilter.filter(snapshot, options: filterOptions)
        }

        // Dispatch to exporter
        guard let exportFormat = ExportFormat(rawValue: format) else {
            print("Unknown format: \(format). Use: dot, mermaid, json")
            throw ExitCode.failure
        }

        let exporter: any GraphExporting
        switch exportFormat {
        case .dot:
            exporter = DotExporter(clusterByTarget: !noCluster)
        case .mermaid:
            exporter = MermaidExporter(maxNodes: maxNodes ?? 200, direction: direction)
        case .json:
            exporter = JSONExporter(prettyPrint: true, cytoscapeFormat: cytoscape)
        }

        let result = exporter.export(snapshot: snapshot)

        if let output {
            try result.content.write(toFile: output, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(
                Data("Exported \(result.nodeCount) nodes, \(result.edgeCount) edges to \(output)\n".utf8)
            )
        } else {
            print(result.content)
        }
    }
}
