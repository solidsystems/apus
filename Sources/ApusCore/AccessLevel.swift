public enum AccessLevel: String, Codable, Sendable, Comparable {
    case open
    case public_
    case package_
    case internal_
    case fileprivate_
    case private_

    public var displayName: String {
        switch self {
        case .open: "open"
        case .public_: "public"
        case .package_: "package"
        case .internal_: "internal"
        case .fileprivate_: "fileprivate"
        case .private_: "private"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .open: 0
        case .public_: 1
        case .package_: 2
        case .internal_: 3
        case .fileprivate_: 4
        case .private_: 5
        }
    }

    public static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
