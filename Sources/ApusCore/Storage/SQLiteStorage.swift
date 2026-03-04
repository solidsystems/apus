import Foundation
import GRDB

/// Manages the SQLite database schema and migrations for the Apus knowledge graph.
public struct SQLiteStorage: Sendable {
    public let dbPool: DatabasePool

    public init(path: String) throws {
        dbPool = try DatabasePool(path: path)
        try migrator.migrate(dbPool)
    }

    /// Temporary on-disk database for testing. Deleted when process exits.
    public init() throws {
        let tmpPath = NSTemporaryDirectory() + "apus-test-\(UUID().uuidString).sqlite"
        dbPool = try DatabasePool(path: tmpPath)
        try migrator.migrate(dbPool)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "nodes") { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("id", .text).notNull().unique()
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("qualified_name", .text).notNull()
                t.column("file_path", .text)
                t.column("line", .integer)
                t.column("access_level", .text)
                t.column("doc_comment", .text)
                t.column("attributes", .text).notNull().defaults(to: "[]")
                t.column("target_name", .text)
            }

            try db.create(table: "edges") { t in
                t.column("source_id", .text).notNull()
                    .references("nodes", onDelete: .cascade)
                t.column("target_id", .text).notNull()
                    .references("nodes", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("metadata", .text).notNull().defaults(to: "{}")
                t.primaryKey(["source_id", "target_id", "kind"])
            }

            try db.create(
                virtualTable: "nodes_fts",
                using: FTS5()
            ) { t in
                t.synchronize(withTable: "nodes")
                t.column("name")
                t.column("qualified_name")
                t.column("doc_comment")
            }

            try db.create(table: "metadata") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }

            try db.create(index: "idx_nodes_kind", on: "nodes", columns: ["kind"])
            try db.create(index: "idx_nodes_file_path", on: "nodes", columns: ["file_path"])
            try db.create(index: "idx_nodes_name", on: "nodes", columns: ["name"])
            try db.create(index: "idx_nodes_target_name", on: "nodes", columns: ["target_name"])

            try db.create(index: "idx_edges_source", on: "edges", columns: ["source_id"])
            try db.create(index: "idx_edges_target", on: "edges", columns: ["target_id"])
        }

        // v2: Remove FK constraints from edges — the graph supports dangling references
        // to external symbols (e.g., conformance to Foundation protocols).
        migrator.registerMigration("v2") { db in
            try db.drop(table: "edges")
            try db.create(table: "edges") { t in
                t.column("source_id", .text).notNull()
                t.column("target_id", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("metadata", .text).notNull().defaults(to: "{}")
                t.primaryKey(["source_id", "target_id", "kind"])
            }
            try db.create(index: "idx_edges_source", on: "edges", columns: ["source_id"])
            try db.create(index: "idx_edges_target", on: "edges", columns: ["target_id"])
        }

        // v3: Add checkpoints table for tracking graph metrics over time.
        migrator.registerMigration("v3") { db in
            try db.create(table: "checkpoints") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text)
                t.column("created_at", .text).notNull()
                t.column("metrics_json", .text).notNull()
            }
            try db.create(index: "idx_checkpoints_created_at", on: "checkpoints", columns: ["created_at"])
        }

        return migrator
    }
}
