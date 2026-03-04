import Foundation
import ApusCore
import ApusProject
import ApusIndexStore
import ApusSyntax

/// Orchestrates the full indexing pipeline:
/// project discovery → Index Store → SwiftSyntax → persistence.
struct IndexingPipeline {

    struct Options {
        let path: String
        let force: Bool
        let includeTests: Bool
        let verbose: Bool
    }

    struct Result {
        let projectName: String
        let targetCount: Int
        let indexStoreNodes: Int
        let indexStoreEdges: Int
        let syntaxFiles: Int
        let totalNodes: Int
        let totalEdges: Int
        let databasePath: String
        let duration: TimeInterval
    }

    func run(options: Options) async throws -> Result {
        let startTime = Date()
        let resolvedPath = resolvePath(options.path)

        // Step 1: Discover project
        log(options, "Discovering project at \(resolvedPath)...")

        let discovery = ProjectDiscovery()
        let projects = try discovery.discover(at: resolvedPath)

        guard let project = projects.first else {
            throw PipelineError.noProjectFound(resolvedPath)
        }

        log(options, "Found \(project.type.rawValue): \(project.name) (\(project.targets.count) targets)")

        // Step 2: Filter targets
        let targets = project.targets.filter { target in
            if options.includeTests { return true }
            return target.productType != .unitTestBundle && target.productType != .uiTestBundle
        }

        if options.verbose {
            for target in targets {
                print("  \(target.name): \(target.sourceFiles.count) listed source files")
            }
        }

        // Step 3: Open/create persistence
        let persistence = GraphPersistence(projectPath: resolvedPath)

        if options.force {
            log(options, "Force re-index: clearing existing data...")
            try? persistence.deleteStorage()
        }

        let storage = try persistence.openStorage()
        let graph = HybridGraph(storage: storage)

        // Step 4: Read Index Store
        log(options, "Reading Index Store...")

        let locator = DerivedDataLocator()
        let indexBuilder = IndexStoreGraphBuilder()
        var indexResult = IndexStoreGraphBuilder.BuildResult(
            nodes: [], edges: [], unitCount: 0, recordCount: 0
        )

        if let storePath = locator.locateIndexStore(forProject: project.name) {
            log(options, "  Index Store: \(storePath)")
            indexResult = try await indexBuilder.build(storePath: storePath, into: graph)
            log(options, "  \(indexResult.unitCount) units, \(indexResult.recordCount) records → \(indexResult.nodes.count) nodes, \(indexResult.edges.count) edges")
        } else {
            log(options, "  No Index Store found for \"\(project.name)\" — build the project in Xcode first for richer results")
        }

        // Step 5: Collect source files
        let sourceFiles = collectSourceFiles(
            project: project,
            targets: targets,
            verbose: options.verbose
        )

        log(options, "Parsing \(sourceFiles.count) Swift files...")

        // Step 6: Parse with SwiftSyntax
        let syntaxBuilder = SyntaxGraphBuilder()
        let syntaxResult = try await syntaxBuilder.parseFiles(at: sourceFiles)

        log(options, "  \(syntaxResult.nodes.count) syntax nodes, \(syntaxResult.edges.count) edges, \(syntaxResult.imports.count) imports")

        // Step 7: Merge syntax into graph
        log(options, "Merging into knowledge graph...")
        try await syntaxBuilder.mergeIntoGraph(graph, syntaxResult: syntaxResult)

        // Step 8: Store metadata
        let now = ISO8601DateFormatter().string(from: Date())
        try GraphPersistence.setMetadata(key: "indexedAt", value: now, in: storage)
        try GraphPersistence.setMetadata(key: "projectPath", value: resolvedPath, in: storage)
        try GraphPersistence.setMetadata(key: "projectName", value: project.name, in: storage)
        try GraphPersistence.setMetadata(
            key: "targets",
            value: targets.map(\.name).joined(separator: ","),
            in: storage
        )

        let allNodes = try await graph.allNodes()
        let allEdges = try await graph.allEdges()

        return Result(
            projectName: project.name,
            targetCount: targets.count,
            indexStoreNodes: indexResult.nodes.count,
            indexStoreEdges: indexResult.edges.count,
            syntaxFiles: sourceFiles.count,
            totalNodes: allNodes.count,
            totalEdges: allEdges.count,
            databasePath: persistence.databasePath,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Private

    private func resolvePath(_ path: String) -> String {
        resolveProjectPath(path)
    }

    /// Collects .swift source files from targets. Falls back to filesystem scanning
    /// when `sourceFiles` is empty (common for SPM targets using default conventions).
    private func collectSourceFiles(
        project: ProjectDescriptor,
        targets: [TargetDescriptor],
        verbose: Bool
    ) -> [String] {
        var files: [String] = []
        let fm = FileManager.default

        for target in targets {
            if !target.sourceFiles.isEmpty {
                // Source files already known (Xcode project, or explicit SPM sources)
                let swiftFiles = target.sourceFiles.filter { $0.hasSuffix(".swift") }
                files.append(contentsOf: swiftFiles)
            } else {
                // Discover source files from conventional directories
                let candidateDirs: [String]
                switch target.productType {
                case .unitTestBundle, .uiTestBundle:
                    candidateDirs = [
                        "\(project.rootPath)/Tests/\(target.name)",
                    ]
                default:
                    candidateDirs = [
                        "\(project.rootPath)/Sources/\(target.name)",
                    ]
                }

                for dir in candidateDirs {
                    guard fm.fileExists(atPath: dir) else { continue }
                    let discovered = discoverSwiftFiles(in: dir)
                    if verbose && !discovered.isEmpty {
                        print("  Discovered \(discovered.count) Swift files in \(dir)")
                    }
                    files.append(contentsOf: discovered)
                }
            }
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        return files.filter { seen.insert($0).inserted }
    }

    private func discoverSwiftFiles(in directory: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [String] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                results.append(fileURL.path)
            }
        }
        return results
    }

    private func log(_ options: Options, _ message: String) {
        if options.verbose {
            print(message)
        }
    }
}

enum PipelineError: LocalizedError {
    case noProjectFound(String)

    var errorDescription: String? {
        switch self {
        case .noProjectFound(let path):
            return "No Swift project found at \(path)"
        }
    }
}
