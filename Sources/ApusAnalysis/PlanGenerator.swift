import Foundation
import ApusCore

// MARK: - Data Types

public struct PlanDocument: Codable, Sendable {
    public let projectName: String
    public let generatedAt: String
    public let overview: ProjectOverview?
    public let modules: [ModuleEntry]?
    public let protocolRelationships: [ProtocolRelationship]?
    public let entryPoints: [KeyTypeEntry]?
    public let tasks: [ImprovementTask]?
}

public struct ProjectOverview: Codable, Sendable {
    public let targetCount: Int
    public let fileCount: Int
    public let symbolCount: Int
    public let edgeCount: Int
    public let topKinds: [KindCount]
}

public struct KindCount: Codable, Sendable {
    public let kind: String
    public let count: Int
}

public struct ModuleEntry: Codable, Sendable {
    public let name: String
    public let symbolCount: Int
    public let fileCount: Int
    public let dependsOn: [String]
    public let dependedOnBy: [String]
    public let keyTypes: [KeyTypeEntry]
    public let publicAPICount: Int
}

public struct KeyTypeEntry: Codable, Sendable {
    public let name: String
    public let qualifiedName: String
    public let kind: String
    public let filePath: String?
    public let line: Int?
    public let incomingEdges: Int
    public let outgoingEdges: Int
    public let conformsTo: [String]
}

public struct ProtocolRelationship: Codable, Sendable {
    public let protocolName: String
    public let conformers: [String]
    public let target: String?
}

public struct ImprovementTask: Codable, Sendable {
    public let title: String
    public let category: String
    public let description: String
    public let priority: TaskPriority
    public let affectedFiles: [FileReference]
    public let suggestedApproach: String
    public let impactMetric: String
}

public struct FileReference: Codable, Sendable {
    public let path: String
    public let line: Int?
    public let symbolName: String?
}

public enum TaskPriority: String, Codable, Sendable, Comparable {
    case high
    case medium
    case low

    private var sortOrder: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Options

public struct PlanOptions: Sendable {
    public var fanOutThreshold: Int
    public var largeFileThreshold: Int
    public var maxKeyTypesPerModule: Int
    public var maxTasks: Int
    public var includeContext: Bool
    public var includeTasks: Bool

    public init(
        fanOutThreshold: Int = 8,
        largeFileThreshold: Int = 30,
        maxKeyTypesPerModule: Int = 5,
        maxTasks: Int = 25,
        includeContext: Bool = true,
        includeTasks: Bool = true
    ) {
        self.fanOutThreshold = fanOutThreshold
        self.largeFileThreshold = largeFileThreshold
        self.maxKeyTypesPerModule = maxKeyTypesPerModule
        self.maxTasks = maxTasks
        self.includeContext = includeContext
        self.includeTasks = includeTasks
    }
}

// MARK: - Generator

public struct PlanGenerator: Sendable {
    public let snapshot: GraphSnapshot
    public let projectName: String
    public let options: PlanOptions

    public init(snapshot: GraphSnapshot, projectName: String, options: PlanOptions = PlanOptions()) {
        self.snapshot = snapshot
        self.projectName = projectName
        self.options = options
    }

    public func generate() -> PlanDocument {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())

        let overview: ProjectOverview?
        let modules: [ModuleEntry]?
        let protocols: [ProtocolRelationship]?
        let entryPoints: [KeyTypeEntry]?

        if options.includeContext {
            overview = computeOverview()
            modules = computeModules()
            protocols = computeProtocolRelationships()
            entryPoints = computeEntryPoints()
        } else {
            overview = nil
            modules = nil
            protocols = nil
            entryPoints = nil
        }

        let tasks: [ImprovementTask]?
        if options.includeTasks {
            var allTasks: [ImprovementTask] = []
            allTasks.append(contentsOf: detectHighFanOutFunctions())
            allTasks.append(contentsOf: detectLargeFiles())
            allTasks.append(contentsOf: detectHighCoupling())
            allTasks.append(contentsOf: detectOrphanedTypes())
            allTasks.append(contentsOf: detectThinAPISurface())
            allTasks.append(contentsOf: detectPatternOpportunities())
            allTasks.sort { $0.priority < $1.priority }
            tasks = Array(allTasks.prefix(options.maxTasks))
        } else {
            tasks = nil
        }

        return PlanDocument(
            projectName: projectName,
            generatedAt: timestamp,
            overview: overview,
            modules: modules,
            protocolRelationships: protocols,
            entryPoints: entryPoints,
            tasks: tasks
        )
    }

    // MARK: - Part 1: Context

    private static let structuralKinds: Set<NodeKind> = [.target, .file, .module]
    private static let typeKinds: Set<NodeKind> = [.class_, .struct_, .enum_, .protocol_, .actor]
    private static let functionKinds: Set<NodeKind> = [.function, .method, .constructor]

    func computeOverview() -> ProjectOverview {
        let targets = snapshot.nodesByKind[.target] ?? []
        let files = snapshot.nodesByKind[.file] ?? []
        let symbolNodes = snapshot.allNodes.filter { !Self.structuralKinds.contains($0.kind) }

        var kindCounts: [KindCount] = []
        for kind in NodeKind.allCases where !Self.structuralKinds.contains(kind) {
            let count = snapshot.nodesByKind[kind]?.count ?? 0
            if count > 0 {
                kindCounts.append(KindCount(kind: kind.displayName, count: count))
            }
        }
        kindCounts.sort { $0.count > $1.count }

        return ProjectOverview(
            targetCount: targets.count,
            fileCount: files.count,
            symbolCount: symbolNodes.count,
            edgeCount: snapshot.allEdges.count,
            topKinds: kindCounts
        )
    }

    func computeModules() -> [ModuleEntry] {
        let targets = snapshot.nodesByKind[.target] ?? []
        let targetDeps = snapshot.edgesByKind[.dependsOn] ?? []

        // Build dependency maps
        var forwardDeps: [String: [String]] = [:]
        var reverseDeps: [String: [String]] = [:]
        for edge in targetDeps {
            guard let src = snapshot.nodeByID[edge.sourceID], src.kind == .target,
                  let dst = snapshot.nodeByID[edge.targetID], dst.kind == .target else { continue }
            forwardDeps[src.name, default: []].append(dst.name)
            reverseDeps[dst.name, default: []].append(src.name)
        }

        let publicLevels: Set<AccessLevel> = [.open, .public_]

        return targets.sorted { $0.name < $1.name }.map { target in
            let targetNodes = snapshot.nodesByTarget[target.name] ?? []
            let symbols = targetNodes.filter { !Self.structuralKinds.contains($0.kind) }
            let files = targetNodes.filter { $0.kind == .file }
            let publicCount = symbols.filter { publicLevels.contains($0.accessLevel ?? .internal_) }.count

            // Key types ranked by edge degree
            let types = symbols.filter { Self.typeKinds.contains($0.kind) }
            let rankedTypes = types.map { node -> (GraphNode, Int) in
                let total = (snapshot.outgoing[node.id]?.count ?? 0) + (snapshot.incoming[node.id]?.count ?? 0)
                return (node, total)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(options.maxKeyTypesPerModule)

            let keyTypes = rankedTypes.map { node, _ in
                makeKeyTypeEntry(node)
            }

            return ModuleEntry(
                name: target.name,
                symbolCount: symbols.count,
                fileCount: files.count,
                dependsOn: (forwardDeps[target.name] ?? []).sorted(),
                dependedOnBy: (reverseDeps[target.name] ?? []).sorted(),
                keyTypes: keyTypes,
                publicAPICount: publicCount
            )
        }
    }

    func computeProtocolRelationships() -> [ProtocolRelationship] {
        let conformances = snapshot.edgesByKind[.conformsTo] ?? []

        var protoConformers: [String: (target: String?, conformers: [String])] = [:]
        for edge in conformances {
            let target = snapshot.nodeByID[edge.targetID]
            let protoName = target?.name ?? edge.targetID
            let srcName = snapshot.nodeByID[edge.sourceID]?.name ?? edge.sourceID
            var entry = protoConformers[protoName] ?? (target: target?.targetName, conformers: [])
            entry.conformers.append(srcName)
            protoConformers[protoName] = entry
        }

        return protoConformers
            .sorted { $0.value.conformers.count > $1.value.conformers.count }
            .map { ProtocolRelationship(
                protocolName: $0.key,
                conformers: $0.value.conformers.sorted(),
                target: $0.value.target
            )}
    }

    func computeEntryPoints() -> [KeyTypeEntry] {
        let publicLevels: Set<AccessLevel> = [.open, .public_]
        let publicTypes = snapshot.allNodes.filter {
            Self.typeKinds.contains($0.kind) && publicLevels.contains($0.accessLevel ?? .internal_)
        }

        let ranked = publicTypes.map { node -> (GraphNode, Int) in
            let total = (snapshot.outgoing[node.id]?.count ?? 0) + (snapshot.incoming[node.id]?.count ?? 0)
            return (node, total)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(15)

        return ranked.map { makeKeyTypeEntry($0.0) }
    }

    // MARK: - Part 2: Tasks

    func detectHighFanOutFunctions() -> [ImprovementTask] {
        let callEdges = snapshot.edgesByKind[.calls] ?? []
        var fanOut: [String: [GraphEdge]] = [:]
        for edge in callEdges {
            fanOut[edge.sourceID, default: []].append(edge)
        }

        return fanOut.compactMap { id, edges -> ImprovementTask? in
            guard edges.count > options.fanOutThreshold,
                  let node = snapshot.nodeByID[id],
                  Self.functionKinds.contains(node.kind) else { return nil }

            let calledNames = edges.compactMap { snapshot.nodeByID[$0.targetID]?.name }
            return ImprovementTask(
                title: "Decompose \(node.qualifiedName)",
                category: "Complexity",
                description: "\(node.qualifiedName) calls \(edges.count) other functions, suggesting it handles too many responsibilities.",
                priority: edges.count > options.fanOutThreshold * 2 ? .high : .medium,
                affectedFiles: [FileReference(path: node.filePath ?? "unknown", line: node.line, symbolName: node.qualifiedName)],
                suggestedApproach: "Extract groups of related calls into helper methods. Called functions: \(calledNames.prefix(5).joined(separator: ", "))\(calledNames.count > 5 ? "..." : "")",
                impactMetric: "\(edges.count) outgoing calls"
            )
        }
        .sorted { $0.priority < $1.priority }
    }

    func detectLargeFiles() -> [ImprovementTask] {
        let structuralKinds = Self.structuralKinds
        return snapshot.nodesByFile.compactMap { file, nodes -> ImprovementTask? in
            let symbolCount = nodes.filter { !structuralKinds.contains($0.kind) }.count
            guard symbolCount > options.largeFileThreshold else { return nil }

            let kindBreakdown = Dictionary(grouping: nodes.filter { !structuralKinds.contains($0.kind) }, by: \.kind)
                .map { "\($0.value.count) \($0.key.displayName)s" }
                .joined(separator: ", ")

            return ImprovementTask(
                title: "Split \(shortenPath(file))",
                category: "File Size",
                description: "File contains \(symbolCount) symbols (\(kindBreakdown)), making it harder to navigate and maintain.",
                priority: symbolCount > options.largeFileThreshold * 2 ? .high : .medium,
                affectedFiles: [FileReference(path: file, line: nil, symbolName: nil)],
                suggestedApproach: "Group related types/functions into separate files by responsibility. Consider one primary type per file.",
                impactMetric: "\(symbolCount) symbols"
            )
        }
        .sorted { $0.priority < $1.priority }
    }

    func detectHighCoupling() -> [ImprovementTask] {
        let targets = snapshot.nodesByKind[.target] ?? []
        guard targets.count > 1 else { return [] }

        // Count cross-module edges (non-structural)
        let structuralEdges: Set<EdgeKind> = [.contains, .defines, .memberOf]
        var crossModuleCount: [String: [String: Int]] = [:]

        for edge in snapshot.allEdges where !structuralEdges.contains(edge.kind) {
            guard let src = snapshot.nodeByID[edge.sourceID],
                  let dst = snapshot.nodeByID[edge.targetID],
                  let srcTarget = src.targetName,
                  let dstTarget = dst.targetName,
                  srcTarget != dstTarget else { continue }
            crossModuleCount[srcTarget, default: [:]][dstTarget, default: 0] += 1
        }

        return crossModuleCount.flatMap { source, destinations -> [ImprovementTask] in
            destinations.compactMap { dest, count -> ImprovementTask? in
                guard count > 20 else { return nil }
                return ImprovementTask(
                    title: "Reduce coupling: \(source) \u{2192} \(dest)",
                    category: "Coupling",
                    description: "\(source) has \(count) cross-module references to \(dest), indicating tight coupling.",
                    priority: count > 50 ? .high : .medium,
                    affectedFiles: [],
                    suggestedApproach: "Introduce a protocol boundary between \(source) and \(dest). Move shared types to a common module or define interfaces that \(source) depends on rather than concrete types from \(dest).",
                    impactMetric: "\(count) cross-module edges"
                )
            }
        }
        .sorted { $0.priority < $1.priority }
    }

    func detectOrphanedTypes() -> [ImprovementTask] {
        let structuralEdges: Set<EdgeKind> = [.contains, .defines, .memberOf]

        return snapshot.allNodes.compactMap { node -> ImprovementTask? in
            guard Self.typeKinds.contains(node.kind) else { return nil }

            let outgoing = (snapshot.outgoing[node.id] ?? []).filter { !structuralEdges.contains($0.kind) }
            let incoming = (snapshot.incoming[node.id] ?? []).filter { !structuralEdges.contains($0.kind) }

            guard outgoing.isEmpty && incoming.isEmpty else { return nil }

            return ImprovementTask(
                title: "Review orphaned type: \(node.name)",
                category: "Dead Code",
                description: "\(node.qualifiedName) (\(node.kind.displayName)) has no non-structural edges, suggesting it may be unused.",
                priority: .low,
                affectedFiles: [FileReference(path: node.filePath ?? "unknown", line: node.line, symbolName: node.qualifiedName)],
                suggestedApproach: "Verify whether this type is used at runtime (e.g., via reflection, XIB/Storyboard references, or dynamic dispatch). If truly unused, remove it.",
                impactMetric: "0 connections"
            )
        }
        .sorted { $0.priority < $1.priority }
    }

    func detectThinAPISurface() -> [ImprovementTask] {
        let targets = snapshot.nodesByKind[.target] ?? []
        let publicLevels: Set<AccessLevel> = [.open, .public_]

        return targets.compactMap { target -> ImprovementTask? in
            let targetNodes = snapshot.nodesByTarget[target.name] ?? []
            let symbols = targetNodes.filter { !Self.structuralKinds.contains($0.kind) }
            guard symbols.count >= 20 else { return nil } // skip tiny modules

            let publicCount = symbols.filter { publicLevels.contains($0.accessLevel ?? .internal_) }.count
            let percentage = symbols.isEmpty ? 0 : (publicCount * 100) / symbols.count
            guard percentage < 5 else { return nil }

            return ImprovementTask(
                title: "Review API surface: \(target.name)",
                category: "API Design",
                description: "\(target.name) has \(symbols.count) symbols but only \(publicCount) (\(percentage)%) are public. This may indicate missing public API or over-restricted access.",
                priority: .low,
                affectedFiles: [],
                suggestedApproach: "Review which types and functions should be part of the module's public API. Consider whether consumers need access to more of the module's functionality.",
                impactMetric: "\(percentage)% public (\(publicCount)/\(symbols.count))"
            )
        }
        .sorted { $0.priority < $1.priority }
    }

    func detectPatternOpportunities() -> [ImprovementTask] {
        var tasks: [ImprovementTask] = []

        // Classes without subclasses -> could be structs
        let classes = snapshot.nodesByKind[.class_] ?? []
        let inheritance = snapshot.edgesByKind[.extends] ?? []
        let parentIDs = Set(inheritance.map(\.targetID))

        for cls in classes where !parentIDs.contains(cls.id) {
            // Also check it doesn't extend anything (might need class for ObjC interop)
            let extendsAnything = (snapshot.outgoing[cls.id] ?? []).contains { $0.kind == .extends }
            guard !extendsAnything else { continue }

            tasks.append(ImprovementTask(
                title: "Consider struct for \(cls.name)",
                category: "Swift Patterns",
                description: "\(cls.qualifiedName) is a class with no subclasses and no superclass. It could potentially be a struct for value semantics.",
                priority: .low,
                affectedFiles: [FileReference(path: cls.filePath ?? "unknown", line: cls.line, symbolName: cls.qualifiedName)],
                suggestedApproach: "Evaluate if this type needs reference semantics. If not, convert to a struct for better performance and thread safety.",
                impactMetric: "class \u{2192} struct candidate"
            ))
        }

        return tasks
    }

    // MARK: - Helpers

    private func makeKeyTypeEntry(_ node: GraphNode) -> KeyTypeEntry {
        let conformances = (snapshot.outgoing[node.id] ?? [])
            .filter { $0.kind == .conformsTo }
            .compactMap { snapshot.nodeByID[$0.targetID]?.name }

        return KeyTypeEntry(
            name: node.name,
            qualifiedName: node.qualifiedName,
            kind: node.kind.displayName,
            filePath: node.filePath,
            line: node.line,
            incomingEdges: snapshot.incoming[node.id]?.count ?? 0,
            outgoingEdges: snapshot.outgoing[node.id]?.count ?? 0,
            conformsTo: conformances.sorted()
        )
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count > 3 {
            return ".../" + components.suffix(3).joined(separator: "/")
        }
        return path
    }
}
