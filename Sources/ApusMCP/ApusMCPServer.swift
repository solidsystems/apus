import Foundation
import MCP
import ApusCore

/// MCP server that exposes the Apus knowledge graph to Claude Code and other MCP clients.
public actor ApusMCPServer {
    private let graph: any KnowledgeGraph
    private let server: Server
    private let projectName: String

    public init(graph: any KnowledgeGraph, projectName: String) {
        self.graph = graph
        self.projectName = projectName
        self.server = Server(
            name: "apus",
            version: "0.1.0",
            instructions: """
                Apus provides Swift/Xcode code intelligence. Use the tools to search symbols, \
                look up definitions, explore relationships, and analyze impact in the \
                \(projectName) project.
                """,
            capabilities: .init(tools: .init())
        )
    }

    /// Start the server on the given transport (typically stdio).
    public func start(transport: any Transport) async throws {
        await registerTools()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Tool Registration

    private func registerTools() async {
        let tools = toolDefinitions
        await server
            .withMethodHandler(ListTools.self) { _ in
                ListTools.Result(tools: tools)
            }
            .withMethodHandler(CallTool.self) { [self] params in
                try await self.handleToolCall(params)
            }
    }

    // MARK: - Tool Definitions

    private var toolDefinitions: [Tool] {
        [
            Tool(
                name: "search",
                description: "Full-text search for symbols in the Swift codebase. Returns matching types, functions, properties, etc.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search query (supports FTS5 syntax: prefix*, \"exact phrase\", OR)"),
                        ]),
                        "kind": .object([
                            "type": .string("string"),
                            "description": .string("Filter by node kind: class, struct, enum, protocol, function, method, property, etc."),
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Max results to return (default: 20)"),
                        ]),
                    ]),
                    "required": .array([.string("query")]),
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "lookup",
                description: "Look up a specific symbol by its unique ID (USR or synthetic ID). Returns full details including location, access level, and doc comments.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("The symbol's unique ID"),
                        ]),
                    ]),
                    "required": .array([.string("id")]),
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "context",
                description: "Get a symbol and its surrounding context — neighbors, relationships, and related symbols up to a specified depth.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("The symbol's unique ID"),
                        ]),
                        "depth": .object([
                            "type": .string("integer"),
                            "description": .string("How many hops to traverse (default: 1, max: 3)"),
                        ]),
                    ]),
                    "required": .array([.string("id")]),
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "impact",
                description: "Analyze the impact of changing a symbol — shows everything that depends on it (reverse dependencies).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("The symbol's unique ID"),
                        ]),
                    ]),
                    "required": .array([.string("id")]),
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "conformances",
                description: "Find all protocol conformances for a type, or all types conforming to a protocol.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Type or protocol name to search for"),
                        ]),
                    ]),
                    "required": .array([.string("name")]),
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "extensions",
                description: "Find all extensions of a type, including where they're defined and what protocols they add.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Type name to find extensions for"),
                        ]),
                    ]),
                    "required": .array([.string("name")]),
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
        ]
    }

    // MARK: - Tool Call Dispatch

    /// Call a tool by name with the given arguments. Used by MCP and available for testing.
    public func callTool(name: String, arguments: [String: Value]) async throws -> CallTool.Result {
        try await handleToolCall(CallTool.Parameters(name: name, arguments: arguments))
    }

    private func handleToolCall(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "search":
            return try await handleSearch(params.arguments ?? [:])
        case "lookup":
            return try await handleLookup(params.arguments ?? [:])
        case "context":
            return try await handleContext(params.arguments ?? [:])
        case "impact":
            return try await handleImpact(params.arguments ?? [:])
        case "conformances":
            return try await handleConformances(params.arguments ?? [:])
        case "extensions":
            return try await handleExtensions(params.arguments ?? [:])
        default:
            return CallTool.Result(
                content: [.text("Unknown tool: \(params.name)")],
                isError: true
            )
        }
    }

    // MARK: - Tool Handlers

    private func handleSearch(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let query = args["query"]?.stringValue, !query.isEmpty else {
            return CallTool.Result(content: [.text("Missing required parameter: query")], isError: true)
        }

        let limit = args["limit"]?.intValue ?? 20
        let kindFilter = args["kind"]?.stringValue

        var results = try await graph.search(query: query)

        if let kindFilter {
            let kind = NodeKind(rawValue: kindFilter) ?? NodeKind(displayName: kindFilter)
            if let kind {
                results = results.filter { $0.kind == kind }
            }
        }

        results = Array(results.prefix(limit))

        if results.isEmpty {
            return CallTool.Result(content: [.text("No results found for \"\(query)\"")])
        }

        let text = results.map { formatNode($0) }.joined(separator: "\n\n")
        return CallTool.Result(content: [.text("Found \(results.count) results:\n\n\(text)")])
    }

    private func handleLookup(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let id = args["id"]?.stringValue, !id.isEmpty else {
            return CallTool.Result(content: [.text("Missing required parameter: id")], isError: true)
        }

        guard let node = try await graph.node(id: id) else {
            return CallTool.Result(content: [.text("No symbol found with id: \(id)")])
        }

        let outEdges = try await graph.edges(from: id)
        let inEdges = try await graph.edges(to: id)

        var text = formatNodeDetailed(node)

        if !outEdges.isEmpty {
            text += "\n\nOutgoing relationships (\(outEdges.count)):"
            for edge in outEdges {
                let targetName = try await graph.node(id: edge.targetID)?.qualifiedName ?? edge.targetID
                text += "\n  → \(edge.kind.rawValue) \(targetName)"
            }
        }

        if !inEdges.isEmpty {
            text += "\n\nIncoming relationships (\(inEdges.count)):"
            for edge in inEdges {
                let sourceName = try await graph.node(id: edge.sourceID)?.qualifiedName ?? edge.sourceID
                text += "\n  ← \(edge.kind.rawValue) from \(sourceName)"
            }
        }

        return CallTool.Result(content: [.text(text)])
    }

    private func handleContext(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let id = args["id"]?.stringValue, !id.isEmpty else {
            return CallTool.Result(content: [.text("Missing required parameter: id")], isError: true)
        }

        let depth = min(args["depth"]?.intValue ?? 1, 3)

        guard let node = try await graph.node(id: id) else {
            return CallTool.Result(content: [.text("No symbol found with id: \(id)")])
        }

        let neighbors = try await graph.neighbors(of: id, depth: depth)

        var text = "Symbol:\n\(formatNodeDetailed(node))\n"

        if neighbors.isEmpty {
            text += "\nNo related symbols found within depth \(depth)."
        } else {
            // Group by depth
            let grouped = Dictionary(grouping: neighbors) { $0.depth }
            for d in 1...depth {
                guard let items = grouped[d], !items.isEmpty else { continue }
                text += "\n--- Depth \(d) (\(items.count) symbols) ---"
                for item in items {
                    text += "\n  \(item.edge.kind.rawValue) → \(item.node.kind.displayName) \(item.node.qualifiedName)"
                    if let file = item.node.filePath, let line = item.node.line {
                        text += " (\(shortenPath(file)):\(line))"
                    }
                }
            }
        }

        return CallTool.Result(content: [.text(text)])
    }

    private func handleImpact(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let id = args["id"]?.stringValue, !id.isEmpty else {
            return CallTool.Result(content: [.text("Missing required parameter: id")], isError: true)
        }

        guard let node = try await graph.node(id: id) else {
            return CallTool.Result(content: [.text("No symbol found with id: \(id)")])
        }

        // Get everything that points TO this symbol (reverse deps)
        let inEdges = try await graph.edges(to: id)

        if inEdges.isEmpty {
            return CallTool.Result(content: [.text("No dependents found for \(node.qualifiedName). This symbol is a leaf — changing it has no downstream impact.")])
        }

        // Group by edge kind
        let grouped = Dictionary(grouping: inEdges) { $0.kind }
        var text = "Impact analysis for \(node.kind.displayName) \(node.qualifiedName):\n"
        text += "Total dependents: \(inEdges.count)\n"

        for (kind, edges) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            text += "\n\(kind.rawValue) (\(edges.count)):"
            for edge in edges {
                let source = try await graph.node(id: edge.sourceID)
                let name = source?.qualifiedName ?? edge.sourceID
                text += "\n  \(name)"
                if let source, let file = source.filePath, let line = source.line {
                    text += " (\(shortenPath(file)):\(line))"
                }
            }
        }

        return CallTool.Result(content: [.text(text)])
    }

    private func handleConformances(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let name = args["name"]?.stringValue, !name.isEmpty else {
            return CallTool.Result(content: [.text("Missing required parameter: name")], isError: true)
        }

        // Search for the type/protocol
        let candidates = try await graph.search(query: name)
        let matches = candidates.filter {
            $0.name == name || $0.qualifiedName == name || $0.qualifiedName.hasSuffix(".\(name)")
        }

        if matches.isEmpty {
            return CallTool.Result(content: [.text("No type or protocol found matching \"\(name)\"")])
        }

        var text = ""
        for match in matches {
            let outEdges = try await graph.edges(from: match.id)
            let inEdges = try await graph.edges(to: match.id)

            let conformsTo = outEdges.filter { $0.kind == .conformsTo }
            let conformedBy = inEdges.filter { $0.kind == .conformsTo }

            if !conformsTo.isEmpty || !conformedBy.isEmpty {
                text += "\(match.kind.displayName) \(match.qualifiedName):\n"

                if !conformsTo.isEmpty {
                    text += "  Conforms to:"
                    for edge in conformsTo {
                        let target = try await graph.node(id: edge.targetID)
                        text += "\n    \(target?.qualifiedName ?? edge.targetID)"
                    }
                    text += "\n"
                }

                if !conformedBy.isEmpty {
                    text += "  Conformed to by:"
                    for edge in conformedBy {
                        let source = try await graph.node(id: edge.sourceID)
                        text += "\n    \(source?.qualifiedName ?? edge.sourceID)"
                    }
                    text += "\n"
                }
                text += "\n"
            }
        }

        if text.isEmpty {
            return CallTool.Result(content: [.text("No conformance relationships found for \"\(name)\"")])
        }

        return CallTool.Result(content: [.text(text.trimmingCharacters(in: .whitespacesAndNewlines))])
    }

    private func handleExtensions(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let name = args["name"]?.stringValue, !name.isEmpty else {
            return CallTool.Result(content: [.text("Missing required parameter: name")], isError: true)
        }

        // Find extension nodes that extend the named type
        let extensions = try await graph.nodes(kind: .extension_)
        let matching = extensions.filter {
            $0.name == name || $0.qualifiedName == name || $0.qualifiedName.hasSuffix(".\(name)")
        }

        if matching.isEmpty {
            return CallTool.Result(content: [.text("No extensions found for \"\(name)\"")])
        }

        var text = "Extensions of \(name) (\(matching.count)):\n"

        for ext in matching {
            text += "\n  \(ext.qualifiedName)"
            if let file = ext.filePath, let line = ext.line {
                text += " at \(shortenPath(file)):\(line)"
            }

            // Show what the extension adds
            let members = try await graph.edges(from: ext.id)
                .filter { $0.kind == .contains || $0.kind == .defines }
            if !members.isEmpty {
                for member in members {
                    let memberNode = try await graph.node(id: member.targetID)
                    if let memberNode {
                        text += "\n    \(memberNode.kind.displayName) \(memberNode.name)"
                    }
                }
            }

            // Show conformances added by this extension
            let conformances = try await graph.edges(from: ext.id)
                .filter { $0.kind == .conformsTo }
            if !conformances.isEmpty {
                text += "\n    Adds conformances:"
                for c in conformances {
                    let proto = try await graph.node(id: c.targetID)
                    text += "\n      \(proto?.qualifiedName ?? c.targetID)"
                }
            }
        }

        return CallTool.Result(content: [.text(text)])
    }

    // MARK: - Formatting

    private func formatNode(_ node: GraphNode) -> String {
        var text = "\(node.kind.displayName) \(node.qualifiedName)"
        if let file = node.filePath, let line = node.line {
            text += "\n  \(shortenPath(file)):\(line)"
        }
        text += "\n  id: \(node.id)"
        if let access = node.accessLevel {
            text += " | \(access.displayName)"
        }
        return text
    }

    private func formatNodeDetailed(_ node: GraphNode) -> String {
        var text = "\(node.kind.displayName) \(node.qualifiedName)"
        text += "\n  id: \(node.id)"
        if let file = node.filePath, let line = node.line {
            text += "\n  location: \(shortenPath(file)):\(line)"
        }
        if let access = node.accessLevel {
            text += "\n  access: \(access.displayName)"
        }
        if let target = node.targetName {
            text += "\n  target: \(target)"
        }
        if !node.attributes.isEmpty {
            text += "\n  attributes: \(node.attributes.joined(separator: ", "))"
        }
        if let doc = node.docComment, !doc.isEmpty {
            text += "\n  doc: \(doc)"
        }
        return text
    }

    private func shortenPath(_ path: String) -> String {
        // Show last 3 path components for readability
        let components = path.split(separator: "/")
        if components.count > 3 {
            return ".../" + components.suffix(3).joined(separator: "/")
        }
        return path
    }
}
