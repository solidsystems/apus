import Foundation

/// Represents the difference between two checkpoint snapshots.
public struct CheckpointDiff: Sendable {
    public var nodeDelta: Int
    public var edgeDelta: Int
    public var fileDelta: Int
    public var publicAPIDelta: Int
    public var nodeKindDeltas: [(key: String, delta: Int)]
    public var targetDeltas: [(key: String, delta: Int)]
    public var edgeKindDeltas: [(key: String, delta: Int)]

    /// Whether any metric changed between the two snapshots.
    public var hasChanges: Bool {
        nodeDelta != 0 || edgeDelta != 0 || fileDelta != 0 || publicAPIDelta != 0
            || !nodeKindDeltas.isEmpty || !targetDeltas.isEmpty || !edgeKindDeltas.isEmpty
    }

    /// Computes the diff from an old snapshot to a new one.
    public static func compute(old: CheckpointMetrics, new: CheckpointMetrics) -> CheckpointDiff {
        CheckpointDiff(
            nodeDelta: new.totalNodes - old.totalNodes,
            edgeDelta: new.totalEdges - old.totalEdges,
            fileDelta: new.fileCount - old.fileCount,
            publicAPIDelta: new.publicAPICount - old.publicAPICount,
            nodeKindDeltas: computeMapDelta(old: old.nodeCountsByKind, new: new.nodeCountsByKind),
            targetDeltas: computeMapDelta(old: old.nodeCountsByTarget, new: new.nodeCountsByTarget),
            edgeKindDeltas: computeMapDelta(old: old.edgeCountsByKind, new: new.edgeCountsByKind)
        )
    }

    /// Computes per-key deltas between two dictionaries, returning only non-zero entries
    /// sorted by absolute magnitude descending.
    private static func computeMapDelta(
        old: [String: Int],
        new: [String: Int]
    ) -> [(key: String, delta: Int)] {
        var allKeys = Set(old.keys)
        allKeys.formUnion(new.keys)

        var deltas: [(key: String, delta: Int)] = []
        for key in allKeys {
            let delta = (new[key] ?? 0) - (old[key] ?? 0)
            if delta != 0 {
                deltas.append((key: key, delta: delta))
            }
        }
        deltas.sort { abs($0.delta) > abs($1.delta) }
        return deltas
    }
}
