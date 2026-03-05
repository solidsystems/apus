import ArgumentParser
import Foundation
import ApusCore
import ApusAnalysis

struct PlanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Generate a Claude Code implementation plan from the knowledge graph"
    )

    @Argument(help: "Path to the project root")
    var path: String = "."

    @Option(name: .long, help: "Write plan to file instead of stdout")
    var output: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Maximum number of improvement tasks (default: 25)")
    var maxTasks: Int = 25

    @Flag(name: .long, help: "Only include codebase context, no tasks")
    var contextOnly: Bool = false

    @Flag(name: .long, help: "Only include improvement tasks, no context")
    var tasksOnly: Bool = false

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

        let options = PlanOptions(
            maxTasks: maxTasks,
            includeContext: !tasksOnly,
            includeTasks: !contextOnly
        )

        let snapshot = GraphSnapshot(
            nodes: try await graph.allNodes(),
            edges: try await graph.allEdges()
        )

        let generator = PlanGenerator(snapshot: snapshot, projectName: projectName, options: options)
        let plan = generator.generate()

        let content: String
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(plan)
            content = String(data: data, encoding: .utf8)!
        } else {
            let renderer = PlanRenderer()
            content = renderer.renderMarkdown(plan)
        }

        if let output {
            try content.write(toFile: output, atomically: true, encoding: .utf8)
            print("Plan written to \(output)")
        } else {
            print(content)
        }
    }
}
