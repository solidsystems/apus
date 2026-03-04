import Foundation
import GRDB

/// Metrics snapshot captured from the knowledge graph at a point in time.
public struct CheckpointMetrics: Codable, Sendable, Equatable {
    public var totalNodes: Int
    public var totalEdges: Int
    public var fileCount: Int
    public var publicAPICount: Int
    public var nodeCountsByKind: [String: Int]
    public var nodeCountsByTarget: [String: Int]
    public var edgeCountsByKind: [String: Int]

    public init(
        totalNodes: Int,
        totalEdges: Int,
        fileCount: Int,
        publicAPICount: Int,
        nodeCountsByKind: [String: Int],
        nodeCountsByTarget: [String: Int],
        edgeCountsByKind: [String: Int]
    ) {
        self.totalNodes = totalNodes
        self.totalEdges = totalEdges
        self.fileCount = fileCount
        self.publicAPICount = publicAPICount
        self.nodeCountsByKind = nodeCountsByKind
        self.nodeCountsByTarget = nodeCountsByTarget
        self.edgeCountsByKind = edgeCountsByKind
    }
}

/// GRDB record for the checkpoints table.
public struct CheckpointRecord: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "checkpoints"

    public var id: Int64?
    public var name: String?
    public var createdAt: String
    public var metricsJson: String

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case metricsJson = "metrics_json"
    }

    public init(name: String?, createdAt: String, metricsJson: String) {
        self.name = name
        self.createdAt = createdAt
        self.metricsJson = metricsJson
    }

    public func metrics() throws -> CheckpointMetrics {
        let data = Data(metricsJson.utf8)
        return try JSONDecoder().decode(CheckpointMetrics.self, from: data)
    }
}
