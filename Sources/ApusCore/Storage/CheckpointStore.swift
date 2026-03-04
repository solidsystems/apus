import Foundation
import GRDB

/// Saves and loads checkpoint snapshots from the SQLite database.
public enum CheckpointStore {

    /// Captures current graph metrics directly from the database using SQL aggregates.
    public static func captureMetrics(from storage: SQLiteStorage) throws -> CheckpointMetrics {
        try storage.dbPool.read { db in
            let totalNodes = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM nodes") ?? 0
            let totalEdges = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM edges") ?? 0
            let fileCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM nodes WHERE kind = ?",
                arguments: [NodeKind.file.rawValue]
            ) ?? 0
            let publicAPICount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM nodes WHERE access_level = 'public_'"
            ) ?? 0

            // Node counts by kind
            var nodeCountsByKind: [String: Int] = [:]
            let kindRows = try Row.fetchAll(db, sql: "SELECT kind, COUNT(*) as cnt FROM nodes GROUP BY kind")
            for row in kindRows {
                let kind: String = row["kind"]
                let count: Int = row["cnt"]
                nodeCountsByKind[kind] = count
            }

            // Node counts by target
            var nodeCountsByTarget: [String: Int] = [:]
            let targetRows = try Row.fetchAll(
                db,
                sql: "SELECT COALESCE(target_name, '(no target)') as tgt, COUNT(*) as cnt FROM nodes GROUP BY tgt"
            )
            for row in targetRows {
                let target: String = row["tgt"]
                let count: Int = row["cnt"]
                nodeCountsByTarget[target] = count
            }

            // Edge counts by kind
            var edgeCountsByKind: [String: Int] = [:]
            let edgeRows = try Row.fetchAll(db, sql: "SELECT kind, COUNT(*) as cnt FROM edges GROUP BY kind")
            for row in edgeRows {
                let kind: String = row["kind"]
                let count: Int = row["cnt"]
                edgeCountsByKind[kind] = count
            }

            return CheckpointMetrics(
                totalNodes: totalNodes,
                totalEdges: totalEdges,
                fileCount: fileCount,
                publicAPICount: publicAPICount,
                nodeCountsByKind: nodeCountsByKind,
                nodeCountsByTarget: nodeCountsByTarget,
                edgeCountsByKind: edgeCountsByKind
            )
        }
    }

    /// Saves a checkpoint and returns its ID.
    @discardableResult
    public static func save(
        metrics: CheckpointMetrics,
        name: String? = nil,
        in storage: SQLiteStorage
    ) throws -> Int64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(metrics)
        let json = String(data: data, encoding: .utf8)!

        var record = CheckpointRecord(
            name: name,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            metricsJson: json
        )
        try storage.dbPool.write { db in
            try record.insert(db)
        }
        return record.id!
    }

    /// Lists all checkpoints, newest first.
    public static func list(from storage: SQLiteStorage) throws -> [CheckpointRecord] {
        try storage.dbPool.read { db in
            try CheckpointRecord
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    /// Returns the most recent checkpoint, or nil if none exist.
    public static func latest(from storage: SQLiteStorage) throws -> CheckpointRecord? {
        try storage.dbPool.read { db in
            try CheckpointRecord
                .order(Column("created_at").desc)
                .fetchOne(db)
        }
    }
}
