import SwiftSyntax

/// Extracts attribute names from a declaration's attribute list.
enum AttributeExtractor: Sendable {
    static func extract(from attributes: AttributeListSyntax) -> [String] {
        var result: [String] = []
        for element in attributes {
            if let attr = element.as(AttributeSyntax.self) {
                let name = "@\(attr.attributeName.trimmedDescription)"
                result.append(name)
            }
        }
        return result
    }
}
