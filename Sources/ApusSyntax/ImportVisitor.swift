import SwiftSyntax

/// Collects module import statements from a source file.
final class ImportVisitor: SyntaxVisitor, @unchecked Sendable {
    /// The module names found by import declarations.
    private(set) var imports: [String] = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.map { $0.name.trimmedDescription }.joined(separator: ".")
        imports.append(moduleName)
        return .skipChildren
    }
}
