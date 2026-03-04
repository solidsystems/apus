import CIndexStore
import ApusCore

/// Maps IndexStore C API symbol kinds to ApusCore.NodeKind.
public enum SymbolMapper: Sendable {
    public static func mapKind(_ kind: indexstore_symbol_kind_t) -> NodeKind? {
        switch kind {
        case INDEXSTORE_SYMBOL_KIND_CLASS:
            return .class_
        case INDEXSTORE_SYMBOL_KIND_STRUCT:
            return .struct_
        case INDEXSTORE_SYMBOL_KIND_ENUM:
            return .enum_
        case INDEXSTORE_SYMBOL_KIND_PROTOCOL:
            return .protocol_
        case INDEXSTORE_SYMBOL_KIND_EXTENSION:
            return .extension_
        case INDEXSTORE_SYMBOL_KIND_FUNCTION:
            return .function
        case INDEXSTORE_SYMBOL_KIND_INSTANCEMETHOD,
             INDEXSTORE_SYMBOL_KIND_CLASSMETHOD,
             INDEXSTORE_SYMBOL_KIND_STATICMETHOD:
            return .method
        case INDEXSTORE_SYMBOL_KIND_INSTANCEPROPERTY,
             INDEXSTORE_SYMBOL_KIND_CLASSPROPERTY,
             INDEXSTORE_SYMBOL_KIND_STATICPROPERTY:
            return .property
        case INDEXSTORE_SYMBOL_KIND_VARIABLE:
            return .variable
        case INDEXSTORE_SYMBOL_KIND_CONSTRUCTOR:
            return .constructor
        case INDEXSTORE_SYMBOL_KIND_TYPEALIAS:
            return .typeAlias
        case INDEXSTORE_SYMBOL_KIND_MACRO:
            return .macro
        case INDEXSTORE_SYMBOL_KIND_MODULE:
            return .module
        case INDEXSTORE_SYMBOL_KIND_ENUMCONSTANT:
            return .variable
        case INDEXSTORE_SYMBOL_KIND_FIELD:
            return .property
        default:
            return nil
        }
    }

    // Bit positions for Swift access control in indexstore_symbol_property_t
    private static let accessBit17: UInt64 = 1 << 17  // less-than-fileprivate / private
    private static let accessBit18: UInt64 = 1 << 18  // fileprivate
    private static let accessBit19: UInt64 = 1 << 19  // package

    /// Maps IndexStore symbol properties to an AccessLevel.
    public static func mapAccessLevel(_ properties: indexstore_symbol_property_t) -> AccessLevel? {
        let raw = properties.rawValue

        // public = bit 19 | bit 18
        if (raw & accessBit19 != 0) && (raw & accessBit18 != 0) {
            return .public_
        }
        // SPI = bit 19 | bit 17 (treat as public for our purposes)
        if (raw & accessBit19 != 0) && (raw & accessBit17 != 0) {
            return .public_
        }
        // package = bit 19 only
        if (raw & accessBit19 != 0) {
            return .package_
        }
        // internal = bit 18 | bit 17
        if (raw & accessBit18 != 0) && (raw & accessBit17 != 0) {
            return .internal_
        }
        // fileprivate = bit 18 only
        if (raw & accessBit18 != 0) {
            return .fileprivate_
        }
        // private = bit 17 only
        if (raw & accessBit17 != 0) {
            return .private_
        }

        return nil
    }
}
