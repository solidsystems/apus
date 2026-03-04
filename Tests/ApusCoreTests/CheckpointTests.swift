import Testing
import Foundation
import GRDB
@testable import ApusCore

@Suite("Checkpoint Tests")
struct CheckpointTests {

    private func makeStorage() throws -> SQLiteStorage {
        try SQLiteStorage()
    }

    private func insertNode(
        _ db: GRDB.Database,
        id: String,
        kind: NodeKind,
        name: String,
        accessLevel: String? = nil,
        targetName: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO nodes (id, kind, name, qualified_name, access_level, target_name)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [id, kind.rawValue, name, name, accessLevel, targetName]
        )
    }

    private func insertEdge(
        _ db: GRDB.Database,
        source: String,
        target: String,
        kind: EdgeKind
    ) throws {
        try db.execute(
            sql: "INSERT INTO edges (source_id, target_id, kind) VALUES (?, ?, ?)",
            arguments: [source, target, kind.rawValue]
        )
    }

    @Test("captureMetrics returns correct counts")
    func captureMetricsRoundTrip() throws {
        let storage = try makeStorage()

        try storage.dbPool.write { db in
            try insertNode(db, id: "f1", kind: .file, name: "File1.swift", targetName: "App")
            try insertNode(db, id: "f2", kind: .file, name: "File2.swift", targetName: "App")
            try insertNode(db, id: "s1", kind: .struct_, name: "MyStruct", accessLevel: "public_", targetName: "App")
            try insertNode(db, id: "c1", kind: .class_, name: "MyClass", accessLevel: "public_", targetName: "Lib")
            try insertNode(db, id: "m1", kind: .method, name: "doStuff", targetName: "Lib")

            try insertEdge(db, source: "s1", target: "c1", kind: .dependsOn)
            try insertEdge(db, source: "c1", target: "m1", kind: .contains)
        }

        let metrics = try CheckpointStore.captureMetrics(from: storage)

        #expect(metrics.totalNodes == 5)
        #expect(metrics.totalEdges == 2)
        #expect(metrics.fileCount == 2)
        #expect(metrics.publicAPICount == 2)
        #expect(metrics.nodeCountsByKind["file"] == 2)
        #expect(metrics.nodeCountsByKind["struct_"] == 1)
        #expect(metrics.nodeCountsByKind["class_"] == 1)
        #expect(metrics.nodeCountsByKind["method"] == 1)
        #expect(metrics.nodeCountsByTarget["App"] == 3)
        #expect(metrics.nodeCountsByTarget["Lib"] == 2)
        #expect(metrics.edgeCountsByKind["dependsOn"] == 1)
        #expect(metrics.edgeCountsByKind["contains"] == 1)
    }

    @Test("save and latest round-trip")
    func saveAndLatest() throws {
        let storage = try makeStorage()

        let metrics = CheckpointMetrics(
            totalNodes: 10,
            totalEdges: 5,
            fileCount: 3,
            publicAPICount: 4,
            nodeCountsByKind: ["struct_": 3, "class_": 2],
            nodeCountsByTarget: ["App": 7, "Lib": 3],
            edgeCountsByKind: ["contains": 3, "dependsOn": 2]
        )

        let id = try CheckpointStore.save(metrics: metrics, name: "baseline", in: storage)
        #expect(id > 0)

        let latest = try CheckpointStore.latest(from: storage)
        #expect(latest != nil)
        #expect(latest?.name == "baseline")

        let restored = try latest?.metrics()
        #expect(restored == metrics)
    }

    @Test("list ordering is newest first")
    func listOrdering() throws {
        let storage = try makeStorage()

        let m1 = CheckpointMetrics(
            totalNodes: 5, totalEdges: 2, fileCount: 1, publicAPICount: 1,
            nodeCountsByKind: [:], nodeCountsByTarget: [:], edgeCountsByKind: [:]
        )
        let m2 = CheckpointMetrics(
            totalNodes: 10, totalEdges: 4, fileCount: 2, publicAPICount: 2,
            nodeCountsByKind: [:], nodeCountsByTarget: [:], edgeCountsByKind: [:]
        )

        try CheckpointStore.save(metrics: m1, name: "first", in: storage)
        // Small delay to ensure different timestamps
        Thread.sleep(forTimeInterval: 0.01)
        try CheckpointStore.save(metrics: m2, name: "second", in: storage)

        let list = try CheckpointStore.list(from: storage)
        #expect(list.count == 2)
        #expect(list[0].name == "second")
        #expect(list[1].name == "first")
    }

    @Test("diff computation with known deltas")
    func diffComputation() {
        let old = CheckpointMetrics(
            totalNodes: 10, totalEdges: 5, fileCount: 3, publicAPICount: 4,
            nodeCountsByKind: ["struct_": 3, "class_": 2, "method": 5],
            nodeCountsByTarget: ["App": 7, "Lib": 3],
            edgeCountsByKind: ["contains": 3, "dependsOn": 2]
        )
        let new = CheckpointMetrics(
            totalNodes: 15, totalEdges: 8, fileCount: 4, publicAPICount: 3,
            nodeCountsByKind: ["struct_": 5, "class_": 2, "method": 6, "enum_": 2],
            nodeCountsByTarget: ["App": 10, "Lib": 3, "Tests": 2],
            edgeCountsByKind: ["contains": 5, "dependsOn": 2, "calls": 1]
        )

        let diff = CheckpointDiff.compute(old: old, new: new)

        #expect(diff.nodeDelta == 5)
        #expect(diff.edgeDelta == 3)
        #expect(diff.fileDelta == 1)
        #expect(diff.publicAPIDelta == -1)
        #expect(diff.hasChanges)

        // Node kind deltas (sorted by magnitude)
        let kindMap = Dictionary(uniqueKeysWithValues: diff.nodeKindDeltas.map { ($0.key, $0.delta) })
        #expect(kindMap["struct_"] == 2)
        #expect(kindMap["enum_"] == 2)
        #expect(kindMap["method"] == 1)
        #expect(kindMap["class_"] == nil) // no change, should be absent

        // Target deltas
        let targetMap = Dictionary(uniqueKeysWithValues: diff.targetDeltas.map { ($0.key, $0.delta) })
        #expect(targetMap["App"] == 3)
        #expect(targetMap["Tests"] == 2)
        #expect(targetMap["Lib"] == nil) // no change

        // Edge kind deltas
        let edgeMap = Dictionary(uniqueKeysWithValues: diff.edgeKindDeltas.map { ($0.key, $0.delta) })
        #expect(edgeMap["contains"] == 2)
        #expect(edgeMap["calls"] == 1)
        #expect(edgeMap["dependsOn"] == nil)
    }

    @Test("diff with no changes")
    func diffNoChanges() {
        let metrics = CheckpointMetrics(
            totalNodes: 10, totalEdges: 5, fileCount: 3, publicAPICount: 4,
            nodeCountsByKind: ["struct_": 3],
            nodeCountsByTarget: ["App": 10],
            edgeCountsByKind: ["contains": 5]
        )

        let diff = CheckpointDiff.compute(old: metrics, new: metrics)

        #expect(!diff.hasChanges)
        #expect(diff.nodeDelta == 0)
        #expect(diff.edgeDelta == 0)
        #expect(diff.nodeKindDeltas.isEmpty)
        #expect(diff.targetDeltas.isEmpty)
        #expect(diff.edgeKindDeltas.isEmpty)
    }

    @Test("diff with added and removed targets")
    func diffAddedRemovedTargets() {
        let old = CheckpointMetrics(
            totalNodes: 10, totalEdges: 5, fileCount: 3, publicAPICount: 2,
            nodeCountsByKind: [:],
            nodeCountsByTarget: ["App": 5, "OldLib": 5],
            edgeCountsByKind: [:]
        )
        let new = CheckpointMetrics(
            totalNodes: 12, totalEdges: 6, fileCount: 4, publicAPICount: 3,
            nodeCountsByKind: [:],
            nodeCountsByTarget: ["App": 8, "NewLib": 4],
            edgeCountsByKind: [:]
        )

        let diff = CheckpointDiff.compute(old: old, new: new)

        let targetMap = Dictionary(uniqueKeysWithValues: diff.targetDeltas.map { ($0.key, $0.delta) })
        #expect(targetMap["OldLib"] == -5) // removed
        #expect(targetMap["NewLib"] == 4)  // added
        #expect(targetMap["App"] == 3)     // grew
    }
}
