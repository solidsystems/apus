public enum EdgeKind: String, Codable, Sendable, CaseIterable {
    case contains
    case defines
    case imports
    case calls
    case extends
    case implements
    case memberOf
    case conformsTo
    case isolates
    case wraps
    case overrides
    case associatedWith
    case dependsOn
    case availableOn
}
