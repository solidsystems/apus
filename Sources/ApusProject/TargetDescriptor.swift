import Foundation

/// The kind of build product a target produces.
public enum TargetProductType: String, Sendable, Codable {
    case application
    case framework
    case staticLibrary
    case dynamicLibrary
    case unitTestBundle
    case uiTestBundle
    case appExtension
    case commandLineTool
    case bundle
    case other
}

/// Describes a single build target within a project.
public struct TargetDescriptor: Sendable, Codable {
    public let name: String
    public let productType: TargetProductType
    public let sourceFiles: [String]
    public let dependencies: [String]
    public let buildSettings: [String: String]

    public init(
        name: String,
        productType: TargetProductType = .other,
        sourceFiles: [String] = [],
        dependencies: [String] = [],
        buildSettings: [String: String] = [:]
    ) {
        self.name = name
        self.productType = productType
        self.sourceFiles = sourceFiles
        self.dependencies = dependencies
        self.buildSettings = buildSettings
    }
}
