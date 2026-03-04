import ArgumentParser
import Foundation
import ApusCore
import ApusMCP
import ApusAnalysis
import MCP

@main
struct Apus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apus",
        abstract: "Swift-native code intelligence powered by Index Store and SwiftSyntax",
        version: "0.1.0",
        subcommands: [IndexCommand.self, QueryCommand.self, ServeCommand.self, AnalyzeCommand.self, ExportCommand.self, ExploreCommand.self, UpdateCommand.self, CheckpointCommand.self]
    )
}

struct IndexCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Index a Swift project"
    )

    @Argument(help: "Path to the project root")
    var path: String = "."

    @Flag(name: .long, help: "Force a full re-index")
    var force: Bool = false

    @Flag(name: .long, help: "Include test targets")
    var includeTests: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    func run() async throws {
        let pipeline = IndexingPipeline()
        let options = IndexingPipeline.Options(
            path: path,
            force: force,
            includeTests: includeTests,
            verbose: verbose
        )

        let result = try await pipeline.run(options: options)

        print("Indexed \(result.projectName)")
        print("  Targets: \(result.targetCount)")
        print("  Index Store: \(result.indexStoreNodes) nodes, \(result.indexStoreEdges) edges")
        print("  SwiftSyntax: \(result.syntaxFiles) files parsed")
        print("  Total: \(result.totalNodes) nodes, \(result.totalEdges) edges")
        print("  Database: \(result.databasePath)")
        print("  Duration: \(String(format: "%.2f", result.duration))s")

        // Auto-checkpoint: save metrics and show diff vs previous
        do {
            let storage = try SQLiteStorage(path: result.databasePath)
            let previous = try CheckpointStore.latest(from: storage)
            let metrics = try CheckpointStore.captureMetrics(from: storage)
            try CheckpointStore.save(metrics: metrics, in: storage)

            if let previous, let previousMetrics = try? previous.metrics() {
                let diff = CheckpointDiff.compute(old: previousMetrics, new: metrics)
                print(CheckpointFormatter.formatAutoSummary(diff: diff))
            }
        } catch {
            // Checkpoint failures should never block indexing
        }
    }
}

struct QueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Query the knowledge graph"
    )

    @Argument(help: "Search query")
    var searchQuery: String

    @Option(name: .long, help: "Path to the project root (default: current directory)")
    var path: String = "."

    @Option(name: .long, help: "Filter by node kind (class, struct, enum, protocol, function, method, property, etc.)")
    var kind: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let resolvedPath = resolveProjectPath(path)
        let persistence = GraphPersistence(projectPath: resolvedPath)
        guard FileManager.default.fileExists(atPath: persistence.databasePath) else {
            print("No index found. Run `apus index \(path)` first.")
            throw ExitCode.failure
        }

        let graph = try persistence.openGraph()
        try await graph.loadFromDisk()

        var results = try await graph.search(query: searchQuery)

        if let kind {
            let nodeKind = NodeKind(rawValue: kind) ?? NodeKind(displayName: kind)
            if let nodeKind {
                results = results.filter { $0.kind == nodeKind }
            } else {
                print("Unknown kind: \(kind)")
                print("Valid kinds: \(NodeKind.allCases.map(\.displayName).joined(separator: ", "))")
                throw ExitCode.failure
            }
        }

        if results.isEmpty {
            print("No results found for \"\(searchQuery)\"")
            return
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(results)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Found \(results.count) results:\n")
            for node in results {
                print("  \(node.kind.displayName) \(node.qualifiedName)")
                if let file = node.filePath, let line = node.line {
                    print("    \(file):\(line)")
                }
                print("    id: \(node.id)")
                print()
            }
        }
    }
}

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start MCP server on stdio"
    )

    @Option(name: .long, help: "Path to the project root (default: current directory)")
    var path: String = "."

    func run() async throws {
        let resolvedPath = resolveProjectPath(path)
        let persistence = GraphPersistence(projectPath: resolvedPath)
        guard FileManager.default.fileExists(atPath: persistence.databasePath) else {
            // Write to stderr so it doesn't interfere with MCP stdio protocol
            FileHandle.standardError.write(Data("No index found. Run `apus index \(path)` first.\n".utf8))
            throw ExitCode.failure
        }

        let graph = try persistence.openGraph()
        try await graph.loadFromDisk()

        let projectName = try GraphPersistence.getMetadata(
            key: "projectName",
            from: persistence.openStorage()
        ) ?? "Unknown"

        FileHandle.standardError.write(Data("Apus MCP server starting for \(projectName)...\n".utf8))

        let server = ApusMCPServer(graph: graph, projectName: projectName)
        let transport = StdioTransport()
        try await server.start(transport: transport)
    }
}

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Generate a comprehensive codebase analysis report"
    )

    @Argument(help: "Path to the project root")
    var path: String = "."

    @Option(name: .long, help: "Write report to file instead of stdout")
    var output: String?

    @Option(name: .long, help: "Comma-separated sections to include (overview,architecture,typesystem,api,dependencies,hotspots,patterns)")
    var sections: String?

    func run() async throws {
        let resolvedPath = resolveProjectPath(path)
        let persistence = GraphPersistence(projectPath: resolvedPath)
        guard FileManager.default.fileExists(atPath: persistence.databasePath) else {
            print("No index found. Run `apus index \(path)` first.")
            throw ExitCode.failure
        }

        let graph = try persistence.openGraph()
        try await graph.loadFromDisk()

        let projectName = try GraphPersistence.getMetadata(
            key: "projectName",
            from: persistence.openStorage()
        ) ?? URL(fileURLWithPath: resolvedPath).lastPathComponent

        // Parse section filter
        var requestedSections: [AnalysisSection]?
        if let sections {
            requestedSections = sections.split(separator: ",").compactMap { name in
                AnalysisSection(rawValue: String(name).trimmingCharacters(in: .whitespaces))
            }
            if requestedSections?.isEmpty == true {
                print("No valid sections specified. Available: \(AnalysisSection.allCases.map(\.rawValue).joined(separator: ", "))")
                throw ExitCode.failure
            }
        }

        let analyzer = try await CodebaseAnalyzer(graph: graph, projectName: projectName)
        let report = analyzer.analyze(sections: requestedSections)
        let markdown = report.renderMarkdown()

        if let output {
            try markdown.write(toFile: output, atomically: true, encoding: .utf8)
            print("Report written to \(output)")
        } else {
            print(markdown)
        }
    }
}
