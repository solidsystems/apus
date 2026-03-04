import ArgumentParser
import Foundation
import ApusCore

struct CheckpointCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "checkpoint",
        abstract: "Compare graph metrics against previous checkpoints",
        subcommands: [ListCheckpoints.self, SaveCheckpoint.self],
        defaultSubcommand: nil
    )

    @Argument(help: "Path to the project root")
    var path: String = "."

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let (storage, _) = try openStorage(path: path)

        let currentMetrics = try CheckpointStore.captureMetrics(from: storage)

        guard let latest = try CheckpointStore.latest(from: storage) else {
            print("No previous checkpoint found. Showing current metrics:")
            printMetrics(currentMetrics, json: json)
            return
        }

        let previousMetrics = try latest.metrics()
        let diff = CheckpointDiff.compute(old: previousMetrics, new: currentMetrics)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(currentMetrics)
            print(String(data: data, encoding: .utf8)!)
        } else {
            let label = latest.name ?? "auto"
            print("Changes since checkpoint \(latest.id ?? 0) (\(label)):\n")
            print(CheckpointFormatter.format(diff: diff))
        }
    }
}

struct ListCheckpoints: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all saved checkpoints"
    )

    @Argument(help: "Path to the project root")
    var path: String = "."

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let (storage, _) = try openStorage(path: path)
        let checkpoints = try CheckpointStore.list(from: storage)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            struct ListItem: Codable {
                let id: Int64
                let name: String?
                let createdAt: String
                let totalNodes: Int
                let totalEdges: Int
                let fileCount: Int
            }
            let codableItems = try checkpoints.map { cp -> ListItem in
                let m = try cp.metrics()
                return ListItem(
                    id: cp.id ?? 0,
                    name: cp.name,
                    createdAt: cp.createdAt,
                    totalNodes: m.totalNodes,
                    totalEdges: m.totalEdges,
                    fileCount: m.fileCount
                )
            }
            let data = try encoder.encode(codableItems)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print(CheckpointFormatter.formatList(checkpoints))
        }
    }
}

struct SaveCheckpoint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "save",
        abstract: "Save a named checkpoint"
    )

    @Argument(help: "Path to the project root")
    var path: String = "."

    @Option(name: .long, help: "Label for this checkpoint")
    var name: String?

    func run() async throws {
        let (storage, _) = try openStorage(path: path)
        let metrics = try CheckpointStore.captureMetrics(from: storage)
        let id = try CheckpointStore.save(metrics: metrics, name: name, in: storage)
        let label = name.map { "\"\($0)\"" } ?? "(auto)"
        print("Saved checkpoint \(id) \(label): \(metrics.totalNodes) nodes, \(metrics.totalEdges) edges, \(metrics.fileCount) files")
    }
}

// MARK: - Shared helpers

private func openStorage(path: String) throws -> (SQLiteStorage, String) {
    let resolvedPath = URL(
        fileURLWithPath: path,
        relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ).standardized.path

    let persistence = GraphPersistence(projectPath: resolvedPath)
    guard FileManager.default.fileExists(atPath: persistence.databasePath) else {
        print("No index found. Run `apus index \(path)` first.")
        throw ExitCode.failure
    }

    return (try persistence.openStorage(), resolvedPath)
}

private func printMetrics(_ metrics: CheckpointMetrics, json: Bool) {
    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(metrics) {
            print(String(data: data, encoding: .utf8)!)
        }
    } else {
        print("  Nodes: \(metrics.totalNodes)")
        print("  Edges: \(metrics.totalEdges)")
        print("  Files: \(metrics.fileCount)")
        print("  Public API: \(metrics.publicAPICount)")
    }
}
