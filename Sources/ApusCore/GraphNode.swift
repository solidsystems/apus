public struct GraphNode: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var kind: NodeKind
    public var name: String
    public var qualifiedName: String
    public var filePath: String?
    public var line: Int?
    public var accessLevel: AccessLevel?
    public var docComment: String?
    public var attributes: [String]
    public var targetName: String?

    public init(
        id: String,
        kind: NodeKind,
        name: String,
        qualifiedName: String,
        filePath: String? = nil,
        line: Int? = nil,
        accessLevel: AccessLevel? = nil,
        docComment: String? = nil,
        attributes: [String] = [],
        targetName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.qualifiedName = qualifiedName
        self.filePath = filePath
        self.line = line
        self.accessLevel = accessLevel
        self.docComment = docComment
        self.attributes = attributes
        self.targetName = targetName
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        lhs.id == rhs.id
    }
}
