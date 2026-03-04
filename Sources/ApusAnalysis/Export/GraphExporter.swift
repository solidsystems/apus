import Foundation
import ApusCore

/// Supported export formats.
public enum ExportFormat: String, Sendable, CaseIterable {
    case dot
    case mermaid
    case json
}

/// Result of exporting a graph snapshot.
public struct ExportResult: Sendable {
    public let content: String
    public let format: ExportFormat
    public let nodeCount: Int
    public let edgeCount: Int
    public let wasSimplified: Bool

    public init(content: String, format: ExportFormat, nodeCount: Int, edgeCount: Int, wasSimplified: Bool = false) {
        self.content = content
        self.format = format
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.wasSimplified = wasSimplified
    }
}

/// Protocol for graph exporters.
public protocol GraphExporting: Sendable {
    func export(snapshot: GraphSnapshot) -> ExportResult
}

/// Shared visual styling maps for graph exports.
public enum GraphStyling {

    // MARK: - DOT Shapes

    public static func dotShape(for kind: NodeKind) -> String {
        switch kind {
        case .class_: "box"
        case .struct_: "record"
        case .enum_: "diamond"
        case .protocol_: "hexagon"
        case .actor: "box3d"
        case .function, .method, .constructor: "ellipse"
        case .target: "folder"
        case .extension_: "component"
        case .file: "note"
        case .module: "tab"
        case .property, .variable: "plaintext"
        default: "ellipse"
        }
    }

    // MARK: - Mermaid Shapes

    public static func mermaidShape(for kind: NodeKind, label: String) -> String {
        let escaped = label.replacingOccurrences(of: "\"", with: "#quot;")
        switch kind {
        case .class_, .struct_, .extension_: return "[\"\(escaped)\"]"
        case .enum_: return "{\"\(escaped)\"}"
        case .protocol_: return "{{\"\(escaped)\"}}"
        case .actor: return "[/\"\(escaped)\"/]"
        case .function, .method, .constructor: return "(\"\(escaped)\")"
        case .target: return "[\"\(escaped)\"]"
        default: return "[\"\(escaped)\"]"
        }
    }

    // MARK: - Cytoscape Shapes

    public static func cytoscapeShape(for kind: NodeKind) -> String {
        switch kind {
        case .class_, .struct_, .extension_: "round-rectangle"
        case .enum_: "diamond"
        case .protocol_: "hexagon"
        case .actor: "barrel"
        case .function, .method, .constructor: "ellipse"
        case .target: "rectangle"
        default: "ellipse"
        }
    }

    // MARK: - Access Level Colors

    public static func color(for access: AccessLevel?) -> String {
        switch access {
        case .open: "#2ecc71"
        case .public_: "#3498db"
        case .package_: "#9b59b6"
        case .internal_: "#95a5a6"
        case .fileprivate_: "#e67e22"
        case .private_: "#e74c3c"
        case nil: "#95a5a6"
        }
    }

    // MARK: - DOT Edge Styles

    public static func dotEdgeStyle(for kind: EdgeKind) -> String {
        switch kind {
        case .calls: "style=bold"
        case .conformsTo: "style=dashed, arrowhead=empty"
        case .extends: "arrowhead=empty"
        case .imports: "style=dotted"
        case .contains, .defines: "style=dashed"
        case .dependsOn: "style=bold, color=red"
        default: ""
        }
    }

    // MARK: - Mermaid Arrow Styles

    public static func mermaidArrow(for kind: EdgeKind) -> String {
        switch kind {
        case .calls: "-->"
        case .conformsTo: "-.->"
        case .extends: "==>"
        case .imports: "-.->"
        case .contains, .defines: "-.->"
        case .dependsOn: "==>"
        default: "-->"
        }
    }

    // MARK: - Edge Labels

    public static func edgeLabel(for kind: EdgeKind) -> String {
        kind.rawValue
    }
}
