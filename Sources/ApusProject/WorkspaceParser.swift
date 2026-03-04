import Foundation
import XcodeProj
import PathKit

/// Parses .xcworkspace bundles by extracting file references and delegating
/// .xcodeproj parsing to XcodeProjParser.
public struct WorkspaceParser: Sendable {
    private let xcodeProjParser: XcodeProjParser

    public init(xcodeProjParser: XcodeProjParser = XcodeProjParser()) {
        self.xcodeProjParser = xcodeProjParser
    }

    /// Parses a .xcworkspace at the given path. Returns a ProjectDescriptor for the workspace
    /// that aggregates targets from all contained .xcodeproj files.
    public func parse(at path: String) throws -> ProjectDescriptor {
        let workspacePath = Path(path)
        let workspace = try XCWorkspace(path: workspacePath)
        let workspaceName = workspacePath.lastComponentWithoutExtension

        var allTargets: [TargetDescriptor] = []
        let projectPaths = collectProjectPaths(
            from: workspace.data.children,
            relativeTo: workspacePath.parent()
        )

        for projPath in projectPaths {
            if let descriptor = try? xcodeProjParser.parse(at: projPath.string) {
                allTargets.append(contentsOf: descriptor.targets)
            }
        }

        return ProjectDescriptor(
            name: workspaceName,
            type: .xcworkspace,
            rootPath: workspacePath.parent().string,
            targets: allTargets
        )
    }

    /// Recursively collects .xcodeproj paths from workspace data elements.
    private func collectProjectPaths(
        from elements: [XCWorkspaceDataElement],
        relativeTo basePath: Path
    ) -> [Path] {
        var paths: [Path] = []
        for element in elements {
            switch element {
            case .file(let fileRef):
                let resolvedPath = resolvePath(fileRef.location, relativeTo: basePath)
                if resolvedPath.extension == "xcodeproj" {
                    paths.append(resolvedPath)
                }
            case .group(let group):
                let groupBase = resolvePath(group.location, relativeTo: basePath)
                paths.append(contentsOf: collectProjectPaths(from: group.children, relativeTo: groupBase))
            }
        }
        return paths
    }

    private func resolvePath(
        _ location: XCWorkspaceDataElementLocationType,
        relativeTo basePath: Path
    ) -> Path {
        switch location {
        case .absolute(let path):
            return Path(path)
        case .container(let path), .group(let path), .current(let path):
            return basePath + Path(path)
        case .developer(let path):
            return Path(path)
        case .other(_, let path):
            return basePath + Path(path)
        }
    }
}
