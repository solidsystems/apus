import Foundation
import ApusCore

/// Scans a directory tree for Xcode projects, workspaces, SPM packages, and
/// XcodeGen project specs. Returns ordered project descriptors.
public struct ProjectDiscovery: Sendable {
    private let xcodeProjParser: XcodeProjParser
    private let workspaceParser: WorkspaceParser
    private let spmParser: SPMParser
    private let xcodeGenParser: XcodeGenParser

    public init(
        xcodeProjParser: XcodeProjParser = XcodeProjParser(),
        workspaceParser: WorkspaceParser = WorkspaceParser(),
        spmParser: SPMParser = SPMParser(),
        xcodeGenParser: XcodeGenParser = XcodeGenParser()
    ) {
        self.xcodeProjParser = xcodeProjParser
        self.workspaceParser = workspaceParser
        self.spmParser = spmParser
        self.xcodeGenParser = xcodeGenParser
    }

    /// Discovers and parses all projects under the given root path.
    /// Results are ordered by priority: workspaces first, then xcodeproj,
    /// then SPM packages, then XcodeGen specs.
    public func discover(at rootPath: String) throws -> [ProjectDescriptor] {
        let fm = FileManager.default
        var workspaces: [ProjectDescriptor] = []
        var xcodeProjects: [ProjectDescriptor] = []
        var spmPackages: [ProjectDescriptor] = []
        var xcodeGenSpecs: [ProjectDescriptor] = []

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: rootPath),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var visitedPaths: Set<String> = []

        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            let lastComponent = fileURL.lastPathComponent

            // Skip build directories and common non-project paths
            if lastComponent == ".build" || lastComponent == "DerivedData" ||
               lastComponent == "Pods" || lastComponent == "Carthage" ||
               lastComponent == "node_modules" {
                enumerator.skipDescendants()
                continue
            }

            if lastComponent.hasSuffix(".xcworkspace") {
                // Skip embedded workspace inside xcodeproj
                if fileURL.deletingLastPathComponent().pathExtension == "xcodeproj" {
                    continue
                }
                guard !visitedPaths.contains(path) else { continue }
                visitedPaths.insert(path)
                if let desc = try? workspaceParser.parse(at: path) {
                    workspaces.append(desc)
                }
                enumerator.skipDescendants()
            } else if lastComponent.hasSuffix(".xcodeproj") {
                guard !visitedPaths.contains(path) else { continue }
                visitedPaths.insert(path)
                if let desc = try? xcodeProjParser.parse(at: path) {
                    xcodeProjects.append(desc)
                }
                enumerator.skipDescendants()
            } else if lastComponent == "Package.swift" {
                let dir = fileURL.deletingLastPathComponent().path
                guard !visitedPaths.contains(dir) else { continue }
                visitedPaths.insert(dir)
                if let desc = try? spmParser.parse(at: dir) {
                    spmPackages.append(desc)
                }
            } else if lastComponent == "project.yml" {
                guard !visitedPaths.contains(path) else { continue }
                visitedPaths.insert(path)
                if let desc = try? xcodeGenParser.parse(at: path) {
                    xcodeGenSpecs.append(desc)
                }
            }
        }

        return workspaces + xcodeProjects + spmPackages + xcodeGenSpecs
    }

    /// Discovers a single project at the given path.
    /// Automatically detects the project type based on file extensions.
    public func discoverSingle(at path: String) throws -> ProjectDescriptor? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        let lastComponent = url.lastPathComponent

        switch ext {
        case "xcworkspace":
            return try workspaceParser.parse(at: path)
        case "xcodeproj":
            return try xcodeProjParser.parse(at: path)
        default:
            break
        }

        if lastComponent == "Package.swift" {
            return try spmParser.parse(at: url.deletingLastPathComponent().path)
        }

        if lastComponent == "project.yml" {
            return try xcodeGenParser.parse(at: path)
        }

        // Check if directory contains project files
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []

        if contents.contains("Package.swift") {
            return try spmParser.parse(at: path)
        }

        for item in contents {
            if item.hasSuffix(".xcworkspace") {
                let wsPath = "\(path)/\(item)"
                // Skip embedded workspace inside xcodeproj
                if URL(fileURLWithPath: wsPath).deletingLastPathComponent().pathExtension != "xcodeproj" {
                    return try workspaceParser.parse(at: wsPath)
                }
            }
        }

        for item in contents where item.hasSuffix(".xcodeproj") {
            return try xcodeProjParser.parse(at: "\(path)/\(item)")
        }

        if contents.contains("project.yml") {
            return try xcodeGenParser.parse(at: "\(path)/project.yml")
        }

        return nil
    }
}
