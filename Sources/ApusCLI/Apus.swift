import ArgumentParser

@main
struct Apus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apus",
        abstract: "Swift-native code intelligence powered by Index Store and SwiftSyntax",
        version: "0.1.0",
        subcommands: [IndexCommand.self, QueryCommand.self, ServeCommand.self]
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
    }
}

struct QueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Query the knowledge graph"
    )

    @Argument(help: "Search query")
    var searchQuery: String

    @Option(name: .long, help: "Filter by node kind")
    var kind: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        print("Querying: \(searchQuery)")
        print("Not yet implemented. Coming in Phase 7.")
    }
}

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start MCP server on stdio"
    )

    func run() async throws {
        print("Starting MCP server...")
        print("Not yet implemented. Coming in Phase 7.")
    }
}
