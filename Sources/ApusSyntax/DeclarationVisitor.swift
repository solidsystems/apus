import SwiftSyntax
import ApusCore

/// A declaration extracted from syntax, before being converted to a GraphNode.
struct ExtractedDeclaration: Sendable {
    let name: String
    let kind: NodeKind
    let line: Int
    let accessLevel: AccessLevel?
    let docComment: String?
    let attributes: [String]
    /// Protocol/class conformances from inheritance clause.
    let conformances: [String]
    /// For extensions, the extended type name.
    let extendedType: String?
    /// Parent declaration names (for nesting context).
    let parentPath: [String]
}

/// Visits all declarations in a Swift source file and extracts metadata.
final class DeclarationVisitor: SyntaxVisitor, @unchecked Sendable {
    private(set) var declarations: [ExtractedDeclaration] = []

    /// Stack tracking the current nesting path of named types.
    private var parentStack: [String] = []

    // MARK: - Type Declarations

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        addDeclaration(
            name: node.name.trimmedDescription,
            kind: .class_,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause
        )
        parentStack.append(node.name.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        parentStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        addDeclaration(
            name: node.name.trimmedDescription,
            kind: .struct_,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause
        )
        parentStack.append(node.name.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        parentStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        addDeclaration(
            name: node.name.trimmedDescription,
            kind: .enum_,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause
        )
        parentStack.append(node.name.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        parentStack.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        addDeclaration(
            name: node.name.trimmedDescription,
            kind: .protocol_,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause
        )
        parentStack.append(node.name.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        parentStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        addDeclaration(
            name: node.name.trimmedDescription,
            kind: .actor,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause
        )
        parentStack.append(node.name.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        parentStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedType = node.extendedType.trimmedDescription
        addDeclaration(
            name: extendedType,
            kind: .extension_,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause,
            extendedType: extendedType
        )
        parentStack.append(extendedType)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        parentStack.removeLast()
    }

    // MARK: - Member Declarations

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let kind: NodeKind = parentStack.isEmpty ? .function : .method
        addDeclaration(
            name: node.name.trimmedDescription,
            kind: kind,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: nil
        )
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let kind: NodeKind = parentStack.isEmpty ? .variable : .property
        for binding in node.bindings {
            if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmedDescription {
                addDeclaration(
                    name: name,
                    kind: kind,
                    node: Syntax(node),
                    modifiers: node.modifiers,
                    attributes: node.attributes,
                    inheritanceClause: nil
                )
            }
        }
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        addDeclaration(
            name: "init",
            kind: .constructor,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: nil
        )
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        addDeclaration(
            name: "subscript",
            kind: .subscript_,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: nil
        )
        return .skipChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        addDeclaration(
            name: node.name.trimmedDescription,
            kind: .typeAlias,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: nil
        )
        return .skipChildren
    }

    override func visit(_ node: OperatorDeclSyntax) -> SyntaxVisitorContinueKind {
        let converter = SourceLocationConverter(fileName: "", tree: node.root.as(SourceFileSyntax.self)!)
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        let docComment = DocCommentExtractor.extract(from: Syntax(node).leadingTrivia)

        declarations.append(ExtractedDeclaration(
            name: node.name.trimmedDescription,
            kind: .operator_,
            line: location.line,
            accessLevel: nil,
            docComment: docComment,
            attributes: [],
            conformances: [],
            extendedType: nil,
            parentPath: parentStack
        ))
        return .skipChildren
    }

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        addDeclaration(
            name: node.name.trimmedDescription,
            kind: .macro,
            node: Syntax(node),
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: nil
        )
        return .skipChildren
    }

    // MARK: - Helpers

    private func addDeclaration(
        name: String,
        kind: NodeKind,
        node: Syntax,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax,
        inheritanceClause: InheritanceClauseSyntax?,
        extendedType: String? = nil
    ) {
        let converter = SourceLocationConverter(fileName: "", tree: node.root.as(SourceFileSyntax.self)!)
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        let line = location.line

        let accessLevel = AccessControlExtractor.extract(from: modifiers)
        let docComment = DocCommentExtractor.extract(from: node.leadingTrivia)
        let attrs = AttributeExtractor.extract(from: attributes)
        let conformances = extractConformances(from: inheritanceClause)

        declarations.append(ExtractedDeclaration(
            name: name,
            kind: kind,
            line: line,
            accessLevel: accessLevel,
            docComment: docComment,
            attributes: attrs,
            conformances: conformances,
            extendedType: extendedType,
            parentPath: parentStack
        ))
    }

    private func extractConformances(from clause: InheritanceClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.inheritedTypes.map { $0.type.trimmedDescription }
    }
}
