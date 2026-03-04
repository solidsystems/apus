# Apus

Swift-native code intelligence for AI coding agents.

## What

Apus builds a rich knowledge graph of your Swift codebase using the same tooling Apple uses — Xcode's Index Store and SwiftSyntax. It exposes this graph through the [Model Context Protocol (MCP)](https://modelcontextprotocol.io), giving AI coding assistants like Claude Code deep understanding of your code's structure, relationships, and dependencies.

Six MCP tools are available:

- **search** — Full-text search across all symbols (types, functions, properties, etc.)
- **lookup** — Get complete details for a symbol: location, access level, doc comments, and all relationships
- **context** — Explore a symbol's neighborhood — related types, callers, members — up to 3 hops deep
- **impact** — Reverse dependency analysis: see everything that would be affected by changing a symbol
- **conformances** — Find what protocols a type conforms to, or what types conform to a protocol
- **extensions** — Find all extensions of a type, what members they add, and what conformances they introduce

## Why

Tree-sitter gives you syntax. Apus gives you semantics.

By using Xcode's Index Store, Apus captures the same symbol resolution, type relationships, and cross-reference data that powers Xcode's "Jump to Definition" and "Find All References." SwiftSyntax adds declaration details, doc comments, attributes, and access levels that the Index Store doesn't track. Together, they produce a knowledge graph that understands your code the way the Swift compiler does.

This matters for AI agents because:

- **Accurate impact analysis** — Know exactly what breaks when you change a protocol or rename a method
- **Real relationships** — Conformances, extensions, call graphs, and containment are first-class edges, not heuristic guesses
- **Full-text search** — FTS5-powered search finds symbols by name, qualified name, or doc comment content
- **Persistent and fast** — The graph is stored in SQLite with an in-memory layer for sub-millisecond traversals

## When

Run `apus index` after building your project in Xcode (Apus reads from the Index Store that Xcode produces during builds). Re-index when your code changes significantly. The MCP server reads from the persisted graph, so it starts instantly.

## Where

Apus runs on macOS and requires Xcode to be installed (for the Index Store and SwiftSyntax toolchain). It stores its graph databases at `~/.apus/<project-hash>/graph.db`.

### Requirements

- macOS 14+
- Xcode (with the project built at least once, so the Index Store is populated)
- Swift 6.0+

## How

### Install

```bash
git clone https://github.com/solidsystems/apus.git
cd apus
swift build -c release
# Copy the binary to your PATH
cp .build/release/apus /usr/local/bin/
```

### Index a project

```bash
# From your project directory (after building in Xcode)
apus index .

# Or specify a path
apus index /path/to/MyApp

# Include test targets
apus index . --include-tests

# Force full re-index
apus index . --force --verbose
```

### Query from the command line

```bash
# Search for symbols
apus query MyViewController

# Filter by kind
apus query "parse" --kind function

# JSON output for scripting
apus query "Model" --json
```

### Analyze a codebase

```bash
# Full analysis report to stdout
apus analyze .

# Select specific sections
apus analyze . --sections overview,hotspots

# Write to a file
apus analyze . --output report.md
```

Available sections: `overview`, `architecture`, `typesystem`, `api`, `dependencies`, `hotspots`, `patterns`.

### Export & Visualize

```bash
# Export as Graphviz DOT
apus export . --format dot
apus export . --format dot --output graph.dot
dot -Tsvg graph.dot -o graph.svg  # requires graphviz

# Export as Mermaid diagram
apus export . --format mermaid
apus export . --format mermaid --max-nodes 50

# Export as JSON (for D3.js, Cytoscape.js, etc.)
apus export . --format json
apus export . --format json --cytoscape

# Filter exports by target or node kind
apus export . --format dot --target ApusCore --exclude-kind file

# Launch interactive web explorer
apus explore .
apus explore . --port 9000 --no-browser
```

The web explorer serves a self-contained Cytoscape.js graph with search, filtering by target/kind, click-to-inspect, multiple layout algorithms, and PNG export.

### Use as an MCP server with Claude Code

Add Apus to your Claude Code MCP configuration (`.claude/settings.json` or project-level):

```json
{
  "mcpServers": {
    "apus": {
      "command": "apus",
      "args": ["serve", "--path", "/path/to/your/project"]
    }
  }
}
```

Claude Code will then have access to all six tools for searching, navigating, and analyzing your Swift codebase.

### Use as an MCP server with other clients

Apus speaks MCP over stdio, so it works with any MCP-compatible client:

```bash
apus serve --path /path/to/your/project
```

## Architecture

```
ApusCLI ─── apus index / query / analyze / serve / export / explore
  ├── ApusProject ──── SPM, Xcode, XcodeGen, Workspace parsers
  ├── ApusIndexStore ─ C API wrappers for Xcode's libIndexStore.dylib
  ├── ApusSyntax ───── SwiftSyntax-based source file parsing
  ├── ApusAnalysis ─── Codebase analysis, graph export (DOT/Mermaid/JSON), web explorer
  ├── ApusMCP ──────── MCP server with tool handlers
  └── ApusCore ─────── GraphNode, GraphEdge, KnowledgeGraph protocol,
                        SQLite persistence (GRDB + FTS5), HybridGraph
```

The indexing pipeline flows: **Project Discovery → Index Store → SwiftSyntax → Graph Merge → SQLite Persistence**

The MCP server loads the persisted graph into memory and serves queries over stdio.

## License

MIT
