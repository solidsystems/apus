import Foundation

/// Resolves a CLI path argument to a canonical absolute path.
/// This must be used consistently everywhere to ensure the same path
/// produces the same GraphPersistence hash.
func resolveProjectPath(_ path: String) -> String {
    let url: URL
    if path.hasPrefix("/") {
        url = URL(fileURLWithPath: path)
    } else {
        url = URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
    }
    return url.standardized.path
}
