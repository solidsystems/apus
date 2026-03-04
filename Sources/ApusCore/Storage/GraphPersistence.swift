import Foundation
import CryptoKit

/// Manages the on-disk location for the Apus knowledge graph database.
/// Each project gets its own database at `~/.apus/<project-hash>/graph.db`
/// where project-hash is a SHA256 of the canonical project path.
public struct GraphPersistence: Sendable {
    private let projectPath: String

    public init(projectPath: String) {
        self.projectPath = projectPath
    }

    /// SHA256 hash of the canonical project path, used as the directory name.
    public var projectHash: String {
        let canonical = (projectPath as NSString).standardizingPath
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The directory containing the graph database for this project.
    public var databaseDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".apus/\(projectHash)", isDirectory: true)
    }

    /// The path to the graph.db file.
    public var databasePath: String {
        databaseDirectory.appendingPathComponent("graph.db").path
    }

    /// Creates the database directory if needed and returns a configured SQLiteStorage.
    public func openStorage() throws -> SQLiteStorage {
        try FileManager.default.createDirectory(
            at: databaseDirectory,
            withIntermediateDirectories: true
        )
        return try SQLiteStorage(path: databasePath)
    }

    /// Creates a HybridGraph backed by on-disk persistence.
    /// Call `loadFromDisk()` on the returned graph to populate the in-memory layer.
    public func openGraph() throws -> HybridGraph {
        let storage = try openStorage()
        return HybridGraph(storage: storage)
    }

    /// Removes the entire database directory for this project.
    public func deleteStorage() throws {
        try FileManager.default.removeItem(at: databaseDirectory)
    }

    /// Stores a metadata key-value pair in the database.
    public static func setMetadata(
        key: String,
        value: String,
        in storage: SQLiteStorage
    ) throws {
        try storage.dbPool.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)",
                arguments: [key, value]
            )
        }
    }

    /// Retrieves a metadata value by key.
    public static func getMetadata(
        key: String,
        from storage: SQLiteStorage
    ) throws -> String? {
        try storage.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM metadata WHERE key = ?",
                arguments: [key]
            )
        }
    }
}
