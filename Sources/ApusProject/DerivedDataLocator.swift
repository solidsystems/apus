import Foundation

/// Locates the DerivedData Index.noindex/DataStore directory for a given project.
public struct DerivedDataLocator: Sendable {
    /// The default DerivedData root path.
    public static let defaultDerivedDataPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Developer/Xcode/DerivedData"
    }()

    private let derivedDataPath: String

    public init(derivedDataPath: String = DerivedDataLocator.defaultDerivedDataPath) {
        self.derivedDataPath = derivedDataPath
    }

    /// Returns the path to the Index DataStore for the given project name,
    /// or nil if it cannot be found.
    public func locateIndexStore(forProject projectName: String) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: derivedDataPath) else {
            return nil
        }

        // Xcode uses a hash-suffixed directory name like "ProjectName-abcdef123456"
        let prefix = projectName + "-"
        let candidates = entries.filter { $0.hasPrefix(prefix) || $0 == projectName }

        for candidate in candidates {
            let indexStorePath = "\(derivedDataPath)/\(candidate)/Index.noindex/DataStore"
            if fm.fileExists(atPath: indexStorePath) {
                return indexStorePath
            }
        }

        return nil
    }

    /// Returns all Index DataStore paths found in DerivedData.
    public func allIndexStorePaths() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: derivedDataPath) else {
            return []
        }

        return entries.compactMap { entry in
            let indexStorePath = "\(derivedDataPath)/\(entry)/Index.noindex/DataStore"
            return fm.fileExists(atPath: indexStorePath) ? indexStorePath : nil
        }
    }

    /// Constructs the expected Index DataStore path for a given project name,
    /// regardless of whether it exists on disk.
    public func expectedIndexStorePath(forProject projectName: String) -> String {
        "\(derivedDataPath)/\(projectName)/Index.noindex/DataStore"
    }
}
