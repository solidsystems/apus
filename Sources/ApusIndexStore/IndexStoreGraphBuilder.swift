import Foundation
import CIndexStore
import ApusCore

/// Orchestrates reading from an IndexStore and building a KnowledgeGraph.
///
/// Opens the store, iterates units and records, creates GraphNodes with USR as ID,
/// creates GraphEdges for relationships, deduplicates by USR, and populates a KnowledgeGraph.
public struct IndexStoreGraphBuilder: Sendable {

    /// Result of building a graph from an IndexStore.
    public struct BuildResult: Sendable {
        public let nodes: [GraphNode]
        public let edges: [GraphEdge]
        public let unitCount: Int
        public let recordCount: Int

        public init(nodes: [GraphNode], edges: [GraphEdge], unitCount: Int, recordCount: Int) {
            self.nodes = nodes
            self.edges = edges
            self.unitCount = unitCount
            self.recordCount = recordCount
        }
    }

    public init() {}

    /// Builds a KnowledgeGraph from the IndexStore at the given path.
    ///
    /// - Parameters:
    ///   - storePath: Path to the IndexStore directory.
    ///   - graph: The KnowledgeGraph to populate.
    /// - Returns: A BuildResult with statistics.
    public func build(storePath: String, into graph: some KnowledgeGraph) async throws -> BuildResult {
        let reader: IndexStoreReader
        do {
            reader = try IndexStoreReader(storePath: storePath)
        } catch {
            // Store doesn't exist or can't be opened — return empty result
            return BuildResult(nodes: [], edges: [], unitCount: 0, recordCount: 0)
        }

        let unitNames = reader.unitNames()

        // Collect record names from all non-system units
        var allRecordNames: Set<String> = []
        var unitCount = 0

        for unitName in unitNames {
            guard let unitInfo = try? reader.readUnit(name: unitName) else { continue }
            // Skip system units
            guard !unitInfo.isSystem else { continue }
            unitCount += 1
            for recordName in unitInfo.recordNames {
                allRecordNames.insert(recordName)
            }
        }

        // Process records and collect nodes/edges
        var nodesByUSR: [String: GraphNode] = [:]
        var edgeSet: Set<GraphEdge> = []
        var recordCount = 0

        for recordName in allRecordNames {
            guard let occurrences = try? reader.readRecord(name: recordName) else { continue }
            recordCount += 1

            for occurrence in occurrences {
                processOccurrence(
                    occurrence,
                    nodesByUSR: &nodesByUSR,
                    edgeSet: &edgeSet
                )
            }
        }

        let nodes = Array(nodesByUSR.values)
        let edges = Array(edgeSet)

        // Populate the graph
        try await graph.addNodes(nodes)
        try await graph.addEdges(edges)

        return BuildResult(
            nodes: nodes,
            edges: edges,
            unitCount: unitCount,
            recordCount: recordCount
        )
    }

    /// Discovers IndexStore paths under DerivedData for a given project.
    public static func findIndexStorePaths(derivedDataPath: String? = nil) -> [String] {
        let derivedData = derivedDataPath
            ?? (NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData")

        let fm = FileManager.default
        guard fm.fileExists(atPath: derivedData) else { return [] }

        var results: [String] = []
        guard let projects = try? fm.contentsOfDirectory(atPath: derivedData) else {
            return []
        }

        for project in projects {
            let indexStorePath = "\(derivedData)/\(project)/Index.noindex/DataStore"
            if fm.fileExists(atPath: indexStorePath) {
                results.append(indexStorePath)
            }
            // Also check the newer index path format
            let altPath = "\(derivedData)/\(project)/Index/DataStore"
            if fm.fileExists(atPath: altPath) {
                results.append(altPath)
            }
        }

        return results
    }

    // MARK: - Private

    private func processOccurrence(
        _ occurrence: OccurrenceInfo,
        nodesByUSR: inout [String: GraphNode],
        edgeSet: inout Set<GraphEdge>
    ) {
        let usr = occurrence.usr
        guard !usr.isEmpty else { return }

        // Map symbol kind to NodeKind
        guard let nodeKind = SymbolMapper.mapKind(occurrence.symbolKind) else { return }

        // Create or update node for this symbol
        if nodesByUSR[usr] == nil {
            let accessLevel = SymbolMapper.mapAccessLevel(occurrence.symbolProperties)
            let node = GraphNode(
                id: usr,
                kind: nodeKind,
                name: occurrence.name,
                qualifiedName: occurrence.name,
                line: occurrence.line > 0 ? occurrence.line : nil,
                accessLevel: accessLevel
            )
            nodesByUSR[usr] = node
        }

        // Process relations to create edges
        for relation in occurrence.relations {
            guard !relation.usr.isEmpty else { continue }

            // Ensure the related symbol also has a node
            if nodesByUSR[relation.usr] == nil {
                if let relKind = SymbolMapper.mapKind(relation.symbolKind) {
                    let relNode = GraphNode(
                        id: relation.usr,
                        kind: relKind,
                        name: relation.name,
                        qualifiedName: relation.name
                    )
                    nodesByUSR[relation.usr] = relNode
                }
            }

            // Map relation roles to edge kinds
            let edgeKinds = RelationMapper.mapRoles(relation.roles)
            for edgeKind in edgeKinds {
                // The relation says the occurrence symbol has this relation TO the related symbol.
                // e.g., REL_CALLEDBY means the occurrence is called by the related symbol.
                // So the edge direction depends on the relation:
                let edge: GraphEdge
                switch edgeKind {
                case .calls:
                    // REL_CALLEDBY: occurrence is called BY relation → relation calls occurrence
                    edge = GraphEdge(sourceID: relation.usr, targetID: usr, kind: .calls)
                case .conformsTo:
                    // REL_BASEOF: occurrence is base OF relation → relation conforms to occurrence
                    edge = GraphEdge(sourceID: relation.usr, targetID: usr, kind: .conformsTo)
                case .overrides:
                    // REL_OVERRIDEOF: occurrence overrides OF relation → occurrence overrides relation
                    edge = GraphEdge(sourceID: usr, targetID: relation.usr, kind: .overrides)
                case .extends:
                    // REL_EXTENDEDBY: occurrence is extended BY relation → relation extends occurrence
                    edge = GraphEdge(sourceID: relation.usr, targetID: usr, kind: .extends)
                case .memberOf:
                    // REL_CHILDOF: occurrence is child OF relation → occurrence is member of relation
                    edge = GraphEdge(sourceID: usr, targetID: relation.usr, kind: .memberOf)
                case .contains:
                    // REL_CONTAINEDBY: occurrence is contained BY relation → relation contains occurrence
                    edge = GraphEdge(sourceID: relation.usr, targetID: usr, kind: .contains)
                default:
                    edge = GraphEdge(sourceID: usr, targetID: relation.usr, kind: edgeKind)
                }
                edgeSet.insert(edge)
            }
        }
    }
}
