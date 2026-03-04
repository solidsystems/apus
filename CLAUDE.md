# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Apus is a purpose-built Swift/Xcode code intelligence tool that replaces tree-sitter with native Apple tooling for richer analysis.

## Build & Test

```bash
swift build                          # Build all targets
swift test --filter ApusMCPTests     # Run MCP server tests
swift test --filter ApusCoreTests    # Run core graph tests
swift test                           # Run all tests
```

## Architecture

- **ApusCore**: Graph types (`GraphNode`, `GraphEdge`, `KnowledgeGraph` protocol), SQLite persistence, HybridGraph
- **ApusProject**: SPM/Xcode/XcodeGen project parsers
- **ApusIndexStore**: C API wrappers for Xcode's Index Store
- **ApusSyntax**: SwiftSyntax-based source file parsing
- **ApusMCP**: MCP server exposing graph via tools (search, lookup, context, impact, conformances, extensions)
- **ApusCLI**: `apus index`, `apus query`, `apus serve` commands
- **CIndexStore**: System library wrapper for libIndexStore.dylib

## Usage

```bash
apus index [path]          # Index a Swift project
apus query <search> --path # Query the knowledge graph
apus serve --path          # Start MCP server on stdio
```
