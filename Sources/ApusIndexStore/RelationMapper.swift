import CIndexStore
import ApusCore

/// Maps IndexStore C API symbol roles (bit flags) to ApusCore.EdgeKind.
///
/// The indexstore_symbol_role_t is defined via INDEXSTORE_OPTIONS macro in C,
/// which Swift imports as an OptionSet-like struct. We use raw bit values directly
/// since the individual constants may not be available as top-level Swift names.
public enum RelationMapper: Sendable {
    // Relation role bit positions from indexstore.h
    private static let relChildOf: UInt64     = 1 << 9
    private static let relBaseOf: UInt64      = 1 << 10
    private static let relOverrideOf: UInt64  = 1 << 11
    private static let relReceivedBy: UInt64  = 1 << 12
    private static let relCalledBy: UInt64    = 1 << 13
    private static let relExtendedBy: UInt64  = 1 << 14
    private static let relAccessorOf: UInt64  = 1 << 15
    private static let relContainedBy: UInt64 = 1 << 16
    private static let relIBTypeOf: UInt64    = 1 << 17
    private static let relSpecializationOf: UInt64 = 1 << 18

    private static let allRelationMask: UInt64 =
        relChildOf | relBaseOf | relOverrideOf | relReceivedBy |
        relCalledBy | relExtendedBy | relAccessorOf | relContainedBy |
        relIBTypeOf | relSpecializationOf

    /// Extracts all applicable edge kinds from a role bitmask.
    public static func mapRoles(_ roles: indexstore_symbol_role_t) -> [EdgeKind] {
        var result: [EdgeKind] = []
        let raw = roles.rawValue

        if raw & relCalledBy != 0 {
            result.append(.calls)
        }
        if raw & relBaseOf != 0 {
            result.append(.conformsTo)
        }
        if raw & relOverrideOf != 0 {
            result.append(.overrides)
        }
        if raw & relExtendedBy != 0 {
            result.append(.extends)
        }
        if raw & relChildOf != 0 {
            result.append(.memberOf)
        }
        if raw & relContainedBy != 0 {
            result.append(.contains)
        }
        if raw & relAccessorOf != 0 {
            result.append(.associatedWith)
        }
        if raw & relSpecializationOf != 0 {
            result.append(.dependsOn)
        }

        return result
    }

    /// Determines whether a role bitmask contains any relation roles worth recording.
    public static func hasRelationRoles(_ roles: indexstore_symbol_role_t) -> Bool {
        roles.rawValue & allRelationMask != 0
    }
}
