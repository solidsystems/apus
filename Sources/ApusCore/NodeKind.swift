public enum NodeKind: String, Codable, Sendable, CaseIterable {
    case class_
    case struct_
    case enum_
    case protocol_
    case extension_
    case actor
    case function
    case method
    case property
    case variable
    case constructor
    case subscript_
    case operator_
    case typeAlias
    case associatedType
    case macro
    case propertyWrapper
    case resultBuilder
    case target
    case file
    case module

    public var displayName: String {
        switch self {
        case .class_: "class"
        case .struct_: "struct"
        case .enum_: "enum"
        case .protocol_: "protocol"
        case .extension_: "extension"
        case .actor: "actor"
        case .function: "function"
        case .method: "method"
        case .property: "property"
        case .variable: "variable"
        case .constructor: "init"
        case .subscript_: "subscript"
        case .operator_: "operator"
        case .typeAlias: "typealias"
        case .associatedType: "associatedtype"
        case .macro: "macro"
        case .propertyWrapper: "propertyWrapper"
        case .resultBuilder: "resultBuilder"
        case .target: "target"
        case .file: "file"
        case .module: "module"
        }
    }
}
