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
        lines.append("ID".padding(toLength: 4, withPad: " ", startingAt: 0) + "  " + "Date".padding(toLength: 20, withPad: " ", startingAt: 0) + "  " + "Name".padding(toLength: 14, withPad: " ", startingAt: 0) + "  " + "Nodes".leftPad(6) + "  " + "Edges".leftPad(6) + "  " + "Files".leftPad(5))
        lines.append(String(repeating: "-", count: 65))

        for cp in checkpoints {
            let label = cp.name ?? "(auto)"
            let date = formatDate(cp.createdAt)
            let idStr = String(cp.id ?? 0)
            if let metrics = try? cp.metrics() {
                let row = "\(idStr.padding(toLength: 4, withPad: " ", startingAt: 0))  \(date.padding(toLength: 20, withPad: " ", startingAt: 0))  \(label.padding(toLength: 14, withPad: " ", startingAt: 0))  \(String(metrics.totalNodes).leftPad(6))  \(String(metrics.totalEdges).leftPad(6))  \(String(metrics.fileCount).leftPad(5))"
                lines.append(row)
            } else {
                let row = "\(idStr.padding(toLength: 4, withPad: " ", startingAt: 0))  \(date.padding(toLength: 20, withPad: " ", startingAt: 0))  \(label.padding(toLength: 14, withPad: " ", startingAt: 0))       ?       ?      ?"
                lines.append(row)
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

private extension String {
    func leftPad(_ width: Int) -> String {
        if count >= width { return self }
        return String(repeating: " ", count: width - count) + self
    }
}
