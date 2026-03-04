// swift-tools-version: 6.0

import PackageDescription

let xcodeToolchainLib = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"

let package = Package(
    name: "Apus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "apus", targets: ["ApusCLI"]),
        .executable(name: "apus-hook", targets: ["ApusHook"]),
        .library(name: "ApusCore", targets: ["ApusCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "8.24.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        // MARK: - C Index Store (system library wrapper)
        .systemLibrary(
            name: "CIndexStore"
        ),

        // MARK: - Core
        .target(
            name: "ApusCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        // MARK: - Project Parsing
        .target(
            name: "ApusProject",
            dependencies: [
                "ApusCore",
                .product(name: "XcodeProj", package: "XcodeProj"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),

        // MARK: - Index Store
        .target(
            name: "ApusIndexStore",
            dependencies: [
                "ApusCore",
                "CIndexStore",
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(xcodeToolchainLib)",
                    "-Xlinker", "-rpath", "-Xlinker", xcodeToolchainLib,
                ]),
            ]
        ),

        // MARK: - Syntax Parsing
        .target(
            name: "ApusSyntax",
            dependencies: [
                "ApusCore",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),

        // MARK: - MCP Server
        .target(
            name: "ApusMCP",
            dependencies: [
                "ApusCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),

        // MARK: - Analysis
        .target(
            name: "ApusAnalysis",
            dependencies: [
                "ApusCore",
            ]
        ),

        // MARK: - CLI
        .executableTarget(
            name: "ApusCLI",
            dependencies: [
                "ApusCore",
                "ApusProject",
                "ApusIndexStore",
                "ApusSyntax",
                "ApusMCP",
                "ApusAnalysis",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // MARK: - Hook
        .executableTarget(
            name: "ApusHook",
            dependencies: [
                "ApusCore",
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "ApusCoreTests",
            dependencies: ["ApusCore"]
        ),
        .testTarget(
            name: "ApusProjectTests",
            dependencies: ["ApusProject"]
        ),
        .testTarget(
            name: "ApusIndexStoreTests",
            dependencies: ["ApusIndexStore"]
        ),
        .testTarget(
            name: "ApusSyntaxTests",
            dependencies: ["ApusSyntax"]
        ),
        .testTarget(
            name: "ApusMCPTests",
            dependencies: ["ApusMCP"]
        ),
        .testTarget(
            name: "ApusAnalysisTests",
            dependencies: ["ApusAnalysis"]
        ),
    ]
)
