import Foundation
import Yams

/// Parses XcodeGen project.yml files using the Yams YAML parser.
public struct XcodeGenParser: Sendable {
    public init() {}

    /// Parses a project.yml file at the given path.
    public func parse(at path: String) throws -> ProjectDescriptor {
        let url = URL(fileURLWithPath: path)
        let yamlString = try String(contentsOf: url, encoding: .utf8)
        let yaml = try Yams.load(yaml: yamlString) as? [String: Any] ?? [:]

        let projectName = yaml["name"] as? String ?? URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .lastPathComponent

        var targets: [TargetDescriptor] = []

        if let targetsDict = yaml["targets"] as? [String: Any] {
            for (targetName, value) in targetsDict {
                guard let targetDict = value as? [String: Any] else { continue }

                let productType = mapProductType(targetDict["type"] as? String)
                let dependencies = parseDependencies(targetDict["dependencies"])
                let sourceFiles = parseSources(targetDict["sources"])

                var buildSettings: [String: String] = [:]
                if let settings = targetDict["settings"] as? [String: Any] {
                    if let base = settings["base"] as? [String: Any] {
                        for (k, v) in base {
                            if let sv = v as? String { buildSettings[k] = sv }
                        }
                    }
                    for (k, v) in settings where k != "base" && k != "configs" && k != "groups" {
                        if let sv = v as? String { buildSettings[k] = sv }
                    }
                }

                targets.append(TargetDescriptor(
                    name: targetName,
                    productType: productType,
                    sourceFiles: sourceFiles,
                    dependencies: dependencies,
                    buildSettings: buildSettings
                ))
            }
        }

        let rootPath = URL(fileURLWithPath: path).deletingLastPathComponent().path

        return ProjectDescriptor(
            name: projectName,
            type: .xcodeGen,
            rootPath: rootPath,
            targets: targets
        )
    }

    private func mapProductType(_ type: String?) -> TargetProductType {
        guard let type else { return .other }
        switch type.lowercased() {
        case "application", "application.on-demand-install-capable":
            return .application
        case "framework", "framework.static":
            return .framework
        case "library.static":
            return .staticLibrary
        case "library.dynamic":
            return .dynamicLibrary
        case "bundle.unit-test":
            return .unitTestBundle
        case "bundle.ui-testing":
            return .uiTestBundle
        case "app-extension", "extensionkit-extension":
            return .appExtension
        case "tool", "command-line-tool":
            return .commandLineTool
        case "bundle":
            return .bundle
        default:
            return .other
        }
    }

    private func parseDependencies(_ value: Any?) -> [String] {
        guard let deps = value as? [[String: Any]] else { return [] }
        return deps.compactMap { dep -> String? in
            if let target = dep["target"] as? String { return target }
            if let framework = dep["framework"] as? String { return framework }
            if let carthage = dep["carthage"] as? String { return carthage }
            if let sdk = dep["sdk"] as? String { return sdk }
            if let package = dep["package"] as? String { return package }
            return nil
        }
    }

    private func parseSources(_ value: Any?) -> [String] {
        guard let sources = value else { return [] }
        if let stringArray = sources as? [String] {
            return stringArray
        }
        if let dictArray = sources as? [[String: Any]] {
            return dictArray.compactMap { $0["path"] as? String }
        }
        if let single = sources as? String {
            return [single]
        }
        return []
    }
}
