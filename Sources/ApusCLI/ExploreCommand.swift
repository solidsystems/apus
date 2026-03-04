import ArgumentParser
import Foundation
import ApusCore
import ApusAnalysis
#if canImport(Network)
import Network
#endif

/// Ensures a `CheckedContinuation` is resumed exactly once, safely across threads.
private final class OnceContinuation: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}

struct ExploreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explore",
        abstract: "Launch an interactive web-based graph explorer"
    )

    @Argument(help: "Path to the project root")
    var path: String = "."

    @Option(name: .long, help: "HTTP port (default: 8090)")
    var port: Int = 8090

    @Option(name: .long, help: "Maximum nodes to display (default: 500, 0 for unlimited)")
    var maxNodes: Int = 500

    @Flag(name: .long, help: "Don't auto-open browser")
    var noBrowser: Bool = false

    func run() async throws {
        let resolvedPath = URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardized.path

        let persistence = GraphPersistence(projectPath: resolvedPath)
        guard FileManager.default.fileExists(atPath: persistence.databasePath) else {
            print("No index found. Run `apus index \(path)` first.")
            throw ExitCode.failure
        }

        let graph = try persistence.openGraph()
        try await graph.loadFromDisk()

        let projectName = try GraphPersistence.getMetadata(
            key: "projectName",
            from: persistence.openStorage()
        ) ?? URL(fileURLWithPath: resolvedPath).lastPathComponent

        let allNodes = try await graph.allNodes()
        let allEdges = try await graph.allEdges()
        var snapshot = GraphSnapshot(nodes: allNodes, edges: allEdges)
        let totalNodes = snapshot.allNodes.count
        let totalEdges = snapshot.allEdges.count

        // Simplify for browser rendering
        if maxNodes > 0 {
            snapshot = GraphFilter.simplify(snapshot, maxNodes: maxNodes)
        }

        // Generate HTML
        let template = WebExplorerTemplate()
        let html = template.generateHTML(snapshot: snapshot, projectName: projectName)
        let htmlData = Data(html.utf8)

        // Generate JSON for API endpoint
        let jsonExporter = JSONExporter(prettyPrint: false, cytoscapeFormat: true)
        let jsonResult = jsonExporter.export(snapshot: snapshot)
        let jsonData = Data(jsonResult.content.utf8)

        print("Apus Graph Explorer for \(projectName)")
        if snapshot.allNodes.count < totalNodes {
            print("  \(snapshot.allNodes.count) nodes, \(snapshot.allEdges.count) edges (simplified from \(totalNodes) nodes, \(totalEdges) edges)")
            print("  Use --max-nodes 0 for the full graph, or --max-nodes N to adjust")
        } else {
            print("  \(snapshot.allNodes.count) nodes, \(snapshot.allEdges.count) edges")
        }
        print("  http://localhost:\(port)")
        print("  Press Ctrl+C to stop")

        #if canImport(Network)
        // Ignore SIGPIPE so broken client connections don't kill the process
        signal(SIGPIPE, SIG_IGN)

        // Start HTTP server using Network.framework
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(integerLiteral: UInt16(port)))

        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            Self.handleConnection(connection, htmlData: htmlData, jsonData: jsonData)
        }

        let openBrowser = !self.noBrowser
        let serverPort = self.port

        // Wait for SIGINT or listener failure
        signal(SIGINT, SIG_IGN)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let awaiter = OnceContinuation(continuation)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if openBrowser {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        process.arguments = ["http://localhost:\(serverPort)"]
                        try? process.run()
                    }
                case .failed(let error):
                    FileHandle.standardError.write(Data("Server error: \(error)\n".utf8))
                    awaiter.resume()
                case .cancelled:
                    awaiter.resume()
                default:
                    break
                }
            }

            listener.start(queue: .global())

            let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            sigintSource.setEventHandler {
                print("\nShutting down...")
                listener.cancel()
                sigintSource.cancel()
                awaiter.resume()
            }
            sigintSource.resume()
        }
        #else
        print("Network.framework not available. Cannot start HTTP server.")
        throw ExitCode.failure
        #endif
    }

    #if canImport(Network)
    private static func handleConnection(_ connection: NWConnection, htmlData: Data, jsonData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
            guard let data = data, error == nil else {
                connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""
            let responseData: Data

            if request.contains("GET /api/graph") {
                responseData = Self.httpResponse(
                    status: "200 OK",
                    contentType: "application/json",
                    body: jsonData
                )
            } else if request.contains("GET /") {
                responseData = Self.httpResponse(
                    status: "200 OK",
                    contentType: "text/html; charset=utf-8",
                    body: htmlData
                )
            } else {
                responseData = Self.httpResponse(
                    status: "404 Not Found",
                    contentType: "text/plain",
                    body: Data("Not Found".utf8)
                )
            }

            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private static func httpResponse(status: String, contentType: String, body: Data) -> Data {
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r\n
        """
        var response = Data(header.utf8)
        response.append(body)
        return response
    }
    #endif
}
