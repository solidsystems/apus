import Foundation
import ApusCore

/// Formats checkpoint data for terminal output.
enum CheckpointFormatter {

    /// Formats a checkpoint diff for display.
    static func format(diff: CheckpointDiff) -> String {
        var lines: [String] = []

        if !diff.hasChanges {
            lines.append("  No changes since last checkpoint.")
            return lines.joined(separator: "\n")
        }

        // Overall summary
        lines.append("  Overall:")
        lines.append("    Nodes: \(formatDelta(diff.nodeDelta))")
        lines.append("    Edges: \(formatDelta(diff.edgeDelta))")
        lines.append("    Files: \(formatDelta(diff.fileDelta))")
        lines.append("    Public API: \(formatDelta(diff.publicAPIDelta))")

        // Node kinds
        if !diff.nodeKindDeltas.isEmpty {
            lines.append("")
            lines.append("  By node kind:")
            for entry in diff.nodeKindDeltas {
                let name = NodeKind(rawValue: entry.key)?.displayName ?? entry.key
                lines.append("    \(name): \(formatDelta(entry.delta))")
            }
        }

        // Targets
        if !diff.targetDeltas.isEmpty {
            lines.append("")
            lines.append("  By target:")
            for entry in diff.targetDeltas {
                lines.append("    \(entry.key): \(formatDelta(entry.delta))")
            }
        }

        // Edge kinds
        if !diff.edgeKindDeltas.isEmpty {
            lines.append("")
            lines.append("  By edge kind:")
            for entry in diff.edgeKindDeltas {
                lines.append("    \(entry.key): \(formatDelta(entry.delta))")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Formats a list of checkpoints as a table.
    static func formatList(_ checkpoints: [CheckpointRecord]) -> String {
        if checkpoints.isEmpty {
            return "No checkpoints saved."
        }

        var lines: [String] = []
        lines.append(String(format: "%-4s  %-20s  %-14s  %6s  %6s  %5s", "ID", "Date", "Name", "Nodes", "Edges", "Files"))
        lines.append(String(repeating: "-", count: 65))

        for cp in checkpoints {
            let label = cp.name ?? "(auto)"
            let date = formatDate(cp.createdAt)
            if let metrics = try? cp.metrics() {
                lines.append(String(format: "%-4d  %-20s  %-14s  %6d  %6d  %5d",
                    cp.id ?? 0, date, label, metrics.totalNodes, metrics.totalEdges, metrics.fileCount))
            } else {
                lines.append(String(format: "%-4d  %-20s  %-14s  %6s  %6s  %5s",
                    cp.id ?? 0, date, label, "?", "?", "?"))
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Formats a checkpoint diff for the auto-checkpoint summary shown after indexing.
    static func formatAutoSummary(diff: CheckpointDiff) -> String {
        if !diff.hasChanges {
            return "  Checkpoint: no changes since last index."
        }

        var parts: [String] = []
        if diff.nodeDelta != 0 { parts.append("nodes \(formatDelta(diff.nodeDelta))") }
        if diff.edgeDelta != 0 { parts.append("edges \(formatDelta(diff.edgeDelta))") }
        if diff.fileDelta != 0 { parts.append("files \(formatDelta(diff.fileDelta))") }
        if diff.publicAPIDelta != 0 { parts.append("public API \(formatDelta(diff.publicAPIDelta))") }

        return "  Checkpoint: \(parts.joined(separator: ", "))"
    }

    // MARK: - Private

    private static func formatDelta(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "\(delta)" }
        return "0"
    }

    private static func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateFormat = "yyyy-MM-dd HH:mm"
            return display.string(from: date)
        }
        return String(iso.prefix(16))
    }
}
