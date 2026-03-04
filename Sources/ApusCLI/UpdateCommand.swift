import ArgumentParser
import Foundation

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update apus to the latest version from source"
    )

    @Option(name: .long, help: "Path to the apus source repository")
    var repo: String?

    func run() async throws {
        let repoPath: String
        if let repo {
            repoPath = URL(
                fileURLWithPath: repo,
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            ).standardized.path
        } else {
            guard let found = findSourceRepo() else {
                print("Could not locate apus source repository.")
                print("Install location: \(resolveCurrentBinary())")
                print("Use --repo to specify the source repo path:")
                print("  apus update --repo /path/to/apus")
                throw ExitCode.failure
            }
            repoPath = found
        }

        // Verify git repo
        let gitCheck = runProcess(
            executable: "/usr/bin/git",
            arguments: ["-C", repoPath, "rev-parse", "--git-dir"]
        )
        guard gitCheck.status == 0 else {
            print("Not a git repository: \(repoPath)")
            throw ExitCode.failure
        }

        // Get current commit
        let oldCommitResult = runProcess(
            executable: "/usr/bin/git",
            arguments: ["-C", repoPath, "rev-parse", "--short", "HEAD"]
        )
        let oldCommit = oldCommitResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pull
        print("Pulling latest changes...")
        let pullResult = runProcess(
            executable: "/usr/bin/git",
            arguments: ["-C", repoPath, "pull", "--ff-only"]
        )
        guard pullResult.status == 0 else {
            print("Failed to pull. Your local repo may have diverged or have uncommitted changes.")
            print("Resolve manually, then retry `apus update`.")
            throw ExitCode.failure
        }

        // Get new commit
        let newCommitResult = runProcess(
            executable: "/usr/bin/git",
            arguments: ["-C", repoPath, "rev-parse", "--short", "HEAD"]
        )
        let newCommit = newCommitResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if oldCommit == newCommit {
            print("Already up to date. (\(oldCommit))")
            return
        }

        // Rebuild
        print("Building release (\(oldCommit) → \(newCommit))...")
        let buildResult = runProcess(
            executable: "/usr/bin/swift",
            arguments: ["build", "-c", "release"],
            cwd: repoPath,
            streamOutput: true
        )
        guard buildResult.status == 0 else {
            print("Build failed.")
            throw ExitCode.failure
        }

        // Copy new binary over current
        let newBinary = (repoPath as NSString).appendingPathComponent(".build/release/apus")
        let currentBinary = resolveCurrentBinary()

        guard FileManager.default.fileExists(atPath: newBinary) else {
            print("Built binary not found at \(newBinary)")
            throw ExitCode.failure
        }

        do {
            let tempPath = currentBinary + ".new"
            // Copy new binary next to current, then atomically replace
            if FileManager.default.fileExists(atPath: tempPath) {
                try FileManager.default.removeItem(atPath: tempPath)
            }
            try FileManager.default.copyItem(atPath: newBinary, toPath: tempPath)
            _ = try FileManager.default.replaceItemAt(
                URL(fileURLWithPath: currentBinary),
                withItemAt: URL(fileURLWithPath: tempPath)
            )
        } catch {
            print("Failed to replace binary at \(currentBinary): \(error.localizedDescription)")
            print("Try: sudo cp \(newBinary) \(currentBinary)")
            throw ExitCode.failure
        }

        print("Updated apus: \(oldCommit) → \(newCommit)")
    }
}

// MARK: - Helpers

private func runProcess(
    executable: String,
    arguments: [String],
    cwd: String? = nil,
    streamOutput: Bool = false
) -> (status: Int32, stdout: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let cwd {
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    }

    let pipe = Pipe()
    process.standardOutput = streamOutput ? FileHandle.standardOutput : pipe
    process.standardError = streamOutput ? FileHandle.standardError : Pipe()

    do {
        try process.run()
    } catch {
        return (-1, "")
    }
    process.waitUntilExit()

    let stdout: String
    if streamOutput {
        stdout = ""
    } else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        stdout = String(data: data, encoding: .utf8) ?? ""
    }

    return (process.terminationStatus, stdout)
}

private func resolveCurrentBinary() -> String {
    let path = CommandLine.arguments[0]
    let url = URL(fileURLWithPath: path).standardized
    // Resolve symlinks
    if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
        return URL(fileURLWithPath: resolved, relativeTo: url.deletingLastPathComponent()).standardized.path
    }
    return url.path
}

private func findSourceRepo() -> String? {
    let binaryPath = resolveCurrentBinary()
    var dir = URL(fileURLWithPath: binaryPath).deletingLastPathComponent()

    // Walk up from binary location looking for Package.swift in a git repo
    for _ in 0..<10 {
        let packageSwift = dir.appendingPathComponent("Package.swift").path
        if FileManager.default.fileExists(atPath: packageSwift) {
            // Verify it's the apus package
            if let contents = try? String(contentsOfFile: packageSwift, encoding: .utf8),
               contents.contains("name: \"Apus\"") {
                // Verify it's a git repo
                let gitCheck = runProcess(
                    executable: "/usr/bin/git",
                    arguments: ["-C", dir.path, "rev-parse", "--git-dir"]
                )
                if gitCheck.status == 0 {
                    return dir.path
                }
            }
        }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { break }
        dir = parent
    }
    return nil
}
