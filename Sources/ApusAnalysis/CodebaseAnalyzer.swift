import Foundation
import ApusCore

/// Pre-indexed snapshot of the entire graph for efficient analysis.
public struct GraphSnapshot: Sendable {
    public let allNodes: [GraphNode]
    public let allEdges: [GraphEdge]
    public let nodeByID: [String: GraphNode]
    public let nodesByKind: [NodeKind: [GraphNode]]
    public let nodesByTarget: [String: [GraphNode]]
    public let nodesByFile: [String: [GraphNode]]
    public let outgoing: [String: [GraphEdge]]
    public let incoming: [String: [GraphEdge]]
    public let edgesByKind: [EdgeKind: [GraphEdge]]

    public init(nodes: [GraphNode], edges: [GraphEdge]) {
        self.allNodes = nodes
        self.allEdges = edges

        var byID: [String: GraphNode] = [:]
        var byKind: [NodeKind: [GraphNode]] = [:]
        var byTarget: [String: [GraphNode]] = [:]
        var byFile: [String: [GraphNode]] = [:]

        for node in nodes {
            byID[node.id] = node
            byKind[node.kind, default: []].append(node)
            if let t = node.targetName {
                byTarget[t, default: []].append(node)
            }
            if let f = node.filePath {
                byFile[f, default: []].append(node)
            }
        }

        var out: [String: [GraphEdge]] = [:]
        var inc: [String: [GraphEdge]] = [:]
        var byEdgeKind: [EdgeKind: [GraphEdge]] = [:]

        for edge in edges {
            out[edge.sourceID, default: []].append(edge)
            inc[edge.targetID, default: []].append(edge)
            byEdgeKind[edge.kind, default: []].append(edge)
        }

        self.nodeByID = byID
        self.nodesByKind = byKind
        self.nodesByTarget = byTarget
        self.nodesByFile = byFile
        self.outgoing = out
        self.incoming = inc
        self.edgesByKind = byEdgeKind
    }
}

/// Analyzes a knowledge graph and produces a structured markdown report.
public struct CodebaseAnalyzer: Sendable {
    public let snapshot: GraphSnapshot
    public let projectName: String

    public init(snapshot: GraphSnapshot, projectName: String = "Project") {
        self.snapshot = snapshot
        self.projectName = projectName
    }

    /// Convenience initializer that loads snapshot from a KnowledgeGraph.
    public init(graph: any KnowledgeGraph, projectName: String = "Project") async throws {
        let nodes = try await graph.allNodes()
        let edges = try await graph.allEdges()
        self.snapshot = GraphSnapshot(nodes: nodes, edges: edges)
        self.projectName = projectName
    }

    public func analyze(sections: [AnalysisSection]? = nil) -> AnalysisReport {
        let requested = sections ?? AnalysisSection.allCases
        let results = requested.map { section -> SectionResult in
            switch section {
            case .overview: computeOverview()
            case .architecture: computeArchitecture()
            case .typesystem: computeTypeSystem()
            case .api: computeAPI()
            case .dependencies: computeDependencies()
            case .hotspots: computeHotspots()
            case .patterns: computePatterns()
            }
        }
        return AnalysisReport(projectName: projectName, sections: results)
    }

    // MARK: - Section 1: Overview

    private func computeOverview() -> SectionResult {
        let targets = snapshot.nodesByKind[.target] ?? []
        let files = snapshot.nodesByKind[.file] ?? []

        // Symbol counts by kind (excluding structural kinds)
        let structuralKinds: Set<NodeKind> = [.target, .file, .module]
        let symbolNodes = snapshot.allNodes.filter { !structuralKinds.contains($0.kind) }

        var kindCounts: [(NodeKind, Int)] = []
        for kind in NodeKind.allCases where !structuralKinds.contains(kind) {
            let count = snapshot.nodesByKind[kind]?.count ?? 0
            if count > 0 {
                kindCounts.append((kind, count))
            }
        }
        kindCounts.sort { $0.1 > $1.1 }

        var lines: [String] = []
        lines.append("| Metric | Count |")
        lines.append("|--------|------:|")
        lines.append("| Targets | \(targets.count) |")
        lines.append("| Files | \(files.count) |")
        lines.append("| Symbols | \(symbolNodes.count) |")
        lines.append("| Edges | \(snapshot.allEdges.count) |")
        lines.append("")

        if !kindCounts.isEmpty {
            lines.append("### Symbols by Kind")
            lines.append("")
            lines.append("| Kind | Count |")
            lines.append("|------|------:|")
            for (kind, count) in kindCounts {
                lines.append("| \(kind.displayName) | \(count) |")
            }
        }

        return SectionResult(section: .overview, title: "Overview", content: lines.joined(separator: "\n"))
    }

    // MARK: - Section 2: Architecture

    private func computeArchitecture() -> SectionResult {
        let targets = snapshot.nodesByKind[.target] ?? []
        var lines: [String] = []

        if targets.isEmpty {
            lines.append("No targets found in the graph.")
            return SectionResult(section: .architecture, title: "Architecture", content: lines.joined(separator: "\n"))
        }

        // Target breakdown
        lines.append("### Targets")
        lines.append("")
        lines.append("| Target | Symbols | Files |")
        lines.append("|--------|--------:|------:|")

        let structuralKinds: Set<NodeKind> = [.target, .file, .module]
        let sortedTargets = targets.sorted { $0.name < $1.name }

        for target in sortedTargets {
            let targetNodes = snapshot.nodesByTarget[target.name] ?? []
            let symbols = targetNodes.filter { !structuralKinds.contains($0.kind) }.count
            let files = targetNodes.filter { $0.kind == .file }.count
            lines.append("| \(target.name) | \(symbols) | \(files) |")
        }
        lines.append("")

        // Target dependency graph
        let targetDeps = (snapshot.edgesByKind[.dependsOn] ?? []).filter { edge in
            snapshot.nodeByID[edge.sourceID]?.kind == .target &&
            snapshot.nodeByID[edge.targetID]?.kind == .target
        }

        if !targetDeps.isEmpty {
            lines.append("### Target Dependencies")
            lines.append("")
            lines.append("```")
            for edge in targetDeps {
                let src = snapshot.nodeByID[edge.sourceID]?.name ?? edge.sourceID
                let dst = snapshot.nodeByID[edge.targetID]?.name ?? edge.targetID
                lines.append("\(src) → \(dst)")
            }
            lines.append("```")
            lines.append("")
        }

        // Key types per target (top 5 by edge count)
        lines.append("### Key Types per Target")
        lines.append("")

        let typeKinds: Set<NodeKind> = [.class_, .struct_, .enum_, .protocol_, .actor]

        for target in sortedTargets {
            let targetNodes = snapshot.nodesByTarget[target.name] ?? []
            let types = targetNodes.filter { typeKinds.contains($0.kind) }
            if types.isEmpty { continue }

            let ranked = types.map { node -> (GraphNode, Int) in
                let edgeCount = (snapshot.outgoing[node.id]?.count ?? 0) +
                                (snapshot.incoming[node.id]?.count ?? 0)
                return (node, edgeCount)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(5)

            lines.append("**\(target.name)**: " + ranked.map { "\($0.0.name) (\($0.0.kind.displayName))" }.joined(separator: ", "))
        }

        return SectionResult(section: .architecture, title: "Architecture", content: lines.joined(separator: "\n"))
    }

    // MARK: - Section 3: Type System

    private func computeTypeSystem() -> SectionResult {
        var lines: [String] = []

        // Protocol conformances
        let conformances = snapshot.edgesByKind[.conformsTo] ?? []
        if !conformances.isEmpty {
            lines.append("### Protocol Conformances")
            lines.append("")

            // Group by target protocol
            var protoConformers: [String: [String]] = [:]
            for edge in conformances {
                let srcName = snapshot.nodeByID[edge.sourceID]?.name ?? edge.sourceID
                let dstName = snapshot.nodeByID[edge.targetID]?.name ?? edge.targetID
                protoConformers[dstName, default: []].append(srcName)
            }

            let sorted = protoConformers.sorted { $0.value.count > $1.value.count }
            for (proto, conformers) in sorted.prefix(20) {
                lines.append("- **\(proto)**: \(conformers.sorted().joined(separator: ", "))")
            }
            lines.append("")
        }

        // Inheritance
        let inheritance = snapshot.edgesByKind[.extends] ?? []
        if !inheritance.isEmpty {
            lines.append("### Class Inheritance")
            lines.append("")

            var parentChildren: [String: [String]] = [:]
            for edge in inheritance {
                let child = snapshot.nodeByID[edge.sourceID]?.name ?? edge.sourceID
                let parent = snapshot.nodeByID[edge.targetID]?.name ?? edge.targetID
                parentChildren[parent, default: []].append(child)
            }

            let sorted = parentChildren.sorted { $0.value.count > $1.value.count }
            for (parent, children) in sorted.prefix(20) {
                lines.append("- **\(parent)** ← \(children.sorted().joined(separator: ", "))")
            }
            lines.append("")
        }

        // Extensions
        let extensions = snapshot.nodesByKind[.extension_] ?? []
        if !extensions.isEmpty {
            lines.append("### Extensions")
            lines.append("")

            // Extensions with members they add
            let extWithMembers = extensions.compactMap { ext -> (String, Int)? in
                let members = snapshot.outgoing[ext.id]?.filter {
                    $0.kind == .contains || $0.kind == .defines
                }.count ?? 0
                guard members > 0 else { return nil }
                return (ext.name, members)
            }
            .sorted { $0.1 > $1.1 }

            lines.append("| Extended Type | Added Members |")
            lines.append("|--------------|-------------:|")
            for (name, count) in extWithMembers.prefix(20) {
                lines.append("| \(name) | \(count) |")
            }
        }

        if lines.isEmpty {
            lines.append("No type system relationships found in the graph.")
        }

        return SectionResult(section: .typesystem, title: "Type System", content: lines.joined(separator: "\n"))
    }

    // MARK: - Section 4: API Surface

    private func computeAPI() -> SectionResult {
        let publicLevels: Set<AccessLevel> = [.open, .public_]
        let publicNodes = snapshot.allNodes.filter {
            guard let access = $0.accessLevel else { return false }
            return publicLevels.contains(access)
        }

        var lines: [String] = []

        if publicNodes.isEmpty {
            lines.append("No public/open symbols found.")
            return SectionResult(section: .api, title: "API Surface", content: lines.joined(separator: "\n"))
        }

        lines.append("**\(publicNodes.count)** public/open symbols")
        lines.append("")

        // Group by target, then by kind
        var byTarget: [String: [GraphNode]] = [:]
        for node in publicNodes {
            let target = node.targetName ?? "(unknown)"
            byTarget[target, default: []].append(node)
        }

        for (target, nodes) in byTarget.sorted(by: { $0.key < $1.key }) {
            lines.append("### \(target)")
            lines.append("")

            var byKind: [NodeKind: [GraphNode]] = [:]
            for node in nodes {
                byKind[node.kind, default: []].append(node)
            }

            for kind in NodeKind.allCases {
                guard let kindNodes = byKind[kind], !kindNodes.isEmpty else { continue }
                let names = kindNodes.map(\.name).sorted().joined(separator: ", ")
                lines.append("- **\(kind.displayName)** (\(kindNodes.count)): \(names)")
            }
            lines.append("")
        }

        return SectionResult(section: .api, title: "API Surface", content: lines.joined(separator: "\n"))
    }

    // MARK: - Section 5: Dependencies

    private func computeDependencies() -> SectionResult {
        let imports = snapshot.edgesByKind[.imports] ?? []
        var lines: [String] = []

        if imports.isEmpty {
            lines.append("No import relationships found.")
            return SectionResult(section: .dependencies, title: "Dependencies", content: lines.joined(separator: "\n"))
        }

        // Internal module imports
        let targetNames = Set((snapshot.nodesByKind[.target] ?? []).map(\.name))
        let moduleNames = Set((snapshot.nodesByKind[.module] ?? []).map(\.name))
        let knownInternal = targetNames.union(moduleNames)

        var internalImports: [String: Set<String>] = [:]
        var externalCounts: [String: Int] = [:]

        for edge in imports {
            let srcNode = snapshot.nodeByID[edge.sourceID]
            let dstNode = snapshot.nodeByID[edge.targetID]
            let srcName = srcNode?.targetName ?? srcNode?.name ?? edge.sourceID
            let dstName = dstNode?.name ?? edge.targetID

            if knownInternal.contains(dstName) {
                internalImports[srcName, default: []].insert(dstName)
            } else {
                externalCounts[dstName, default: 0] += 1
            }
        }

        if !internalImports.isEmpty {
            lines.append("### Internal Module Graph")
            lines.append("")
            lines.append("```")
            for (src, dsts) in internalImports.sorted(by: { $0.key < $1.key }) {
                for dst in dsts.sorted() {
                    lines.append("\(src) → \(dst)")
                }
            }
            lines.append("```")
            lines.append("")
        }

        if !externalCounts.isEmpty {
            lines.append("### External Frameworks")
            lines.append("")
            lines.append("| Framework | Import Count |")
            lines.append("|-----------|------------:|")
            for (name, count) in externalCounts.sorted(by: { $0.value > $1.value }) {
                lines.append("| \(name) | \(count) |")
            }
        }

        return SectionResult(section: .dependencies, title: "Dependencies", content: lines.joined(separator: "\n"))
    }

    // MARK: - Section 6: Hotspots

    private func computeHotspots() -> SectionResult {
        var lines: [String] = []
        let structuralKinds: Set<NodeKind> = [.target, .file, .module]

        // Top 20 most-referenced symbols (by incoming edge count)
        let referencedSymbols = snapshot.allNodes
            .filter { !structuralKinds.contains($0.kind) }
            .map { node -> (GraphNode, Int) in
                let incoming = snapshot.incoming[node.id]?.count ?? 0
                return (node, incoming)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(20)

        if !referencedSymbols.isEmpty {
            lines.append("### Most Referenced Symbols")
            lines.append("")
            lines.append("| Symbol | Kind | References |")
            lines.append("|--------|------|----------:|")
            for (node, count) in referencedSymbols {
                lines.append("| \(node.name) | \(node.kind.displayName) | \(count) |")
            }
            lines.append("")
        }

        // Top 10 largest files (by symbol count)
        let largestFiles = snapshot.nodesByFile
            .map { (file, nodes) -> (String, Int) in
                let symbols = nodes.filter { !structuralKinds.contains($0.kind) }.count
                return (file, symbols)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(10)

        if !largestFiles.isEmpty {
            lines.append("### Largest Files")
            lines.append("")
            lines.append("| File | Symbols |")
            lines.append("|------|--------:|")
            for (file, count) in largestFiles {
                let short = shortenPath(file)
                lines.append("| \(short) | \(count) |")
            }
            lines.append("")
        }

        // Top 10 high fan-out functions (most outgoing calls)
        let callEdges = snapshot.edgesByKind[.calls] ?? []
        var fanOut: [String: Int] = [:]
        for edge in callEdges {
            fanOut[edge.sourceID, default: 0] += 1
        }

        let functionKinds: Set<NodeKind> = [.function, .method, .constructor]
        let highFanOut = fanOut
            .compactMap { (id, count) -> (GraphNode, Int)? in
                guard let node = snapshot.nodeByID[id],
                      functionKinds.contains(node.kind) else { return nil }
                return (node, count)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(10)

        if !highFanOut.isEmpty {
            lines.append("### High Fan-Out Functions")
            lines.append("")
            lines.append("| Function | Calls |")
            lines.append("|----------|------:|")
            for (node, count) in highFanOut {
                lines.append("| \(node.qualifiedName) | \(count) |")
            }
        }

        if lines.isEmpty {
            lines.append("No hotspot data available.")
        }

        return SectionResult(section: .hotspots, title: "Hotspots", content: lines.joined(separator: "\n"))
    }

    // MARK: - Section 7: Patterns

    private func computePatterns() -> SectionResult {
        var lines: [String] = []

        let patternChecks: [(String, NodeKind?, (GraphNode) -> Bool)] = [
            ("Actors", .actor, { _ in true }),
            ("Property Wrappers", .propertyWrapper, { _ in true }),
            ("Result Builders", .resultBuilder, { _ in true }),
            ("Macros", .macro, { _ in true }),
        ]

        for (title, kind, filter) in patternChecks {
            if let kind {
                let nodes = (snapshot.nodesByKind[kind] ?? []).filter(filter)
                if !nodes.isEmpty {
                    lines.append("### \(title)")
                    lines.append("")
                    for node in nodes.sorted(by: { $0.name < $1.name }) {
                        let location = locationString(for: node)
                        lines.append("- `\(node.name)`\(location)")
                    }
                    lines.append("")
                }
            }
        }

        // SwiftUI Views — structs conforming to View
        let conformances = snapshot.edgesByKind[.conformsTo] ?? []
        let viewConformers = conformances.compactMap { edge -> GraphNode? in
            guard let target = snapshot.nodeByID[edge.targetID],
                  target.name == "View" || target.name == "SwiftUI.View",
                  let source = snapshot.nodeByID[edge.sourceID] else { return nil }
            return source
        }

        if !viewConformers.isEmpty {
            lines.append("### SwiftUI Views")
            lines.append("")
            for node in viewConformers.sorted(by: { $0.name < $1.name }) {
                let location = locationString(for: node)
                lines.append("- `\(node.name)`\(location)")
            }
            lines.append("")
        }

        // ViewModels — types with "ViewModel" in name or @Observable
        let viewModels = snapshot.allNodes.filter { node in
            node.name.contains("ViewModel") ||
            node.name.contains("ObservableObject") ||
            node.attributes.contains("@Observable") ||
            node.attributes.contains("Observable")
        }

        if !viewModels.isEmpty {
            lines.append("### ViewModels & Observables")
            lines.append("")
            for node in viewModels.sorted(by: { $0.name < $1.name }) {
                let location = locationString(for: node)
                lines.append("- `\(node.name)` (\(node.kind.displayName))\(location)")
            }
            lines.append("")
        }

        if lines.isEmpty {
            lines.append("No notable patterns detected.")
        }

        return SectionResult(section: .patterns, title: "Patterns", content: lines.joined(separator: "\n"))
    }

    // MARK: - Helpers

    private func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count > 3 {
            return ".../" + components.suffix(3).joined(separator: "/")
        }
        return path
    }

    private func locationString(for node: GraphNode) -> String {
        if let target = node.targetName {
            return " (\(target))"
        }
        return ""
    }
}
