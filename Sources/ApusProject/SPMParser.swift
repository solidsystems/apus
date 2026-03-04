import Foundation

/// Parses Swift Package Manager projects by running `swift package dump-package`
/// and decoding the resulting JSON.
public struct SPMParser: Sendable {
    public init() {}

    /// Parses a Swift package at the given directory path.
    /// The directory must contain a Package.swift file.
    public func parse(at directoryPath: String) throws -> ProjectDescriptor {
        let jsonData = try dumpPackage(at: directoryPath)
        let packageDump = try JSONDecoder().decode(PackageDump.self, from: jsonData)

        let targets = packageDump.targets.map { target -> TargetDescriptor in
            let productType: TargetProductType
            switch target.type {
            case "executable":
                productType = .commandLineTool
            case "test":
                productType = .unitTestBundle
            case "library", "regular":
                productType = .staticLibrary
            default:
                productType = .other
            }

            return TargetDescriptor(
                name: target.name,
                productType: productType,
                sourceFiles: target.sources ?? [],
                dependencies: target.dependencies.compactMap { $0.resolvedName }
            )
        }

        return ProjectDescriptor(
            name: packageDump.name,
            type: .swiftPackage,
            rootPath: directoryPath,
            targets: targets
        )
    }

    private func dumpPackage(at directoryPath: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["package", "dump-package"]
        process.currentDirectoryURL = URL(fileURLWithPath: directoryPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SPMParserError.dumpFailed(
                status: process.terminationStatus,
                path: directoryPath
            )
        }

        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}

// MARK: - Errors

public enum SPMParserError: Error, Sendable {
    case dumpFailed(status: Int32, path: String)
}

// MARK: - JSON decoding types

struct PackageDump: Decodable, Sendable {
    let name: String
    let targets: [PackageTarget]
}

struct PackageTarget: Decodable, Sendable {
    let name: String
    let type: String
    let sources: [String]?
    let dependencies: [PackageDependency]

    enum CodingKeys: String, CodingKey {
        case name, type, sources, dependencies
    }
}

struct PackageDependency: Decodable, Sendable {
    let byName: [AnyCodableValue?]?
    let product: [AnyCodableValue?]?
    let target: [AnyCodableValue?]?

    var resolvedName: String? {
        if let byName, let first = byName.first, case .string(let name) = first {
            return name
        }
        if let product, let first = product.first, case .string(let name) = first {
            return name
        }
        if let target, let first = target.first, case .string(let name) = first {
            return name
        }
        return nil
    }
}

enum AnyCodableValue: Decodable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        if let i = try? container.decode(Int.self) {
            self = .int(i)
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        self = .other
    }
}
