import Foundation

/// The type of project being described.
public enum ProjectType: String, Sendable, Codable {
    case xcodeproj
    case xcworkspace
    case swiftPackage
    case xcodeGen
}

/// Describes a discovered project with its targets and metadata.
public struct ProjectDescriptor: Sendable, Codable {
    public let name: String
    public let type: ProjectType
    public let rootPath: String
    public let targets: [TargetDescriptor]

    public init(
        name: String,
        type: ProjectType,
        rootPath: String,
        targets: [TargetDescriptor]
    ) {
        self.name = name
        self.type = type
        self.rootPath = rootPath
        self.targets = targets
    }
}
