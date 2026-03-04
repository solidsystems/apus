import Foundation
import XcodeProj
import PathKit

/// Parses .xcodeproj bundles to extract targets, source files, dependencies, and build settings.
public struct XcodeProjParser: Sendable {
    public init() {}

    /// Parses a .xcodeproj at the given path and returns a ProjectDescriptor.
    public func parse(at path: String) throws -> ProjectDescriptor {
        let projPath = Path(path)
        let xcodeproj = try XcodeProj(path: projPath)
        let projectName = projPath.lastComponentWithoutExtension

        let targets = xcodeproj.pbxproj.nativeTargets.map { nativeTarget -> TargetDescriptor in
            let productType = mapProductType(nativeTarget.productType)

            let sourceFiles: [String] = (try? nativeTarget.sourceFiles().compactMap { fileElement in
                fileElement.path
            }) ?? []

            let dependencyNames = nativeTarget.dependencies.compactMap { dep -> String? in
                dep.target?.name ?? dep.name
            }

            var buildSettings: [String: String] = [:]
            if let configList = nativeTarget.buildConfigurationList {
                for config in configList.buildConfigurations {
                    for (key, value) in config.buildSettings {
                        if let stringValue = value as? String {
                            buildSettings[key] = stringValue
                        }
                    }
                }
            }

            return TargetDescriptor(
                name: nativeTarget.name,
                productType: productType,
                sourceFiles: sourceFiles,
                dependencies: dependencyNames,
                buildSettings: buildSettings
            )
        }

        return ProjectDescriptor(
            name: projectName,
            type: .xcodeproj,
            rootPath: projPath.parent().string,
            targets: targets
        )
    }

    private func mapProductType(_ pbxType: PBXProductType?) -> TargetProductType {
        guard let pbxType else { return .other }
        switch pbxType {
        case .application, .watchApp, .watch2App, .watch2AppContainer,
             .messagesApplication, .onDemandInstallCapableApplication:
            return .application
        case .framework, .staticFramework, .xcFramework:
            return .framework
        case .staticLibrary:
            return .staticLibrary
        case .dynamicLibrary:
            return .dynamicLibrary
        case .unitTestBundle, .ocUnitTestBundle:
            return .unitTestBundle
        case .uiTestBundle:
            return .uiTestBundle
        case .appExtension, .extensionKitExtension, .tvExtension,
             .watchExtension, .watch2Extension, .messagesExtension,
             .stickerPack, .intentsServiceExtension:
            return .appExtension
        case .commandLineTool:
            return .commandLineTool
        case .bundle:
            return .bundle
        default:
            return .other
        }
    }
}
