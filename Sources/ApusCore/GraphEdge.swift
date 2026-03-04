public struct GraphEdge: Codable, Sendable, Hashable {
    public let sourceID: String
    public let targetID: String
    public var kind: EdgeKind
    public var metadata: [String: String]

    public init(
        sourceID: String,
        targetID: String,
        kind: EdgeKind,
        metadata: [String: String] = [:]
    ) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.kind = kind
        self.metadata = metadata
    }
}
